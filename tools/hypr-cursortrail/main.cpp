// cursortrail: a Hyprland plugin drawing a fading trail behind the mouse pointer.
//
// It replaces the former Quickshell overlay (cursor-trail.qml, polling the Hyprland socket):
//  - pointer positions come from Hyprland's own mouse-move event (no socket polling),
//  - the trail is drawn in the compositor render pass, just under the cursor, so it is
//    rendered in the very frame the pointer moves and never lags behind it,
//  - the whole trail is one draw call: a shader computes the distance to every segment
//    (union of tapered capsules), so joints never overlap and edges are antialiased.
//
// Config (all optional, e.g. hl.config({ plugin = { cursortrail = { width = 8 } } })):
//  plugin:cursortrail:width     trail width in logical px at the pointer      (8)
//  plugin:cursortrail:life_ms   how long a trail point lives                  (220)
//  plugin:cursortrail:color     0xAARRGGBB, 0 = follow the Caelestia scheme   (0)
//
// No trail while animations are off: that is what Caelestia's game mode turns off.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <deque>
#include <filesystem>
#include <fstream>
#include <regex>
#include <sstream>

using namespace Render::GL;

using Clock = std::chrono::steady_clock;

namespace {
    constexpr int    MAX_POINTS   = 128;   // must match the shader array size
    constexpr double MIN_SPACING  = 1.5;   // logical px between stored points
    constexpr auto   MIN_INTERVAL = std::chrono::microseconds(2000);
    constexpr double AA_PAD       = 2.0;   // px around the trail for antialiasing

    struct SPoint {
        Vector2D          pos; // global logical coords
        Clock::time_point t;
    };

    struct SState {
        HANDLE                           handle = nullptr;
        std::deque<SPoint>               points;
        CBox                             lastDrawn; // global logical, what is on screen now
        CFunctionHook*                   cursorHook = nullptr;

        SP<Config::Values::CFloatValue>  width;
        SP<Config::Values::CIntValue>    lifeMs;
        SP<Config::Values::CColorValue>  color;

        CHyprColor                       schemeColor{0xF5 / 255.0, 0xC2 / 255.0, 0xE7 / 255.0, 1.0};
        std::filesystem::file_time_type  schemeMtime{};
        Clock::time_point                schemeChecked{};

        SP<CShader>                      shader;
        GLint                            locProj = -1, locTopLeft = -1, locFullSize = -1, locColor = -1, locCount = -1, locPts = -1;

        CHyprSignalListener              moveListener, preChecksListener, lastMomentListener;
    };

    UP<SState> g;

    const char* VERT = R"#(#version 300 es
uniform mat3 proj;
uniform vec2 topLeft;
uniform vec2 fullSize;
in vec2 pos;
out vec2 v_px;
void main() {
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
    v_px = topLeft + pos * fullSize;
}
)#";

    // pts[i] = (x, y, radius, alpha) in monitor pixels, oldest first
    const char* FRAG = R"#(#version 300 es
precision highp float;
uniform vec4 color;
uniform int count;
uniform vec4 pts[128];
in vec2 v_px;
layout(location = 0) out vec4 fragColor;
void main() {
    float cov = 0.0;
    for (int i = 0; i < count - 1; i++) {
        vec4 a = pts[i];
        vec4 b = pts[i + 1];
        vec2 ab = b.xy - a.xy;
        vec2 ap = v_px - a.xy;
        float h = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
        float d = length(ap - ab * h);
        float r = mix(a.z, b.z, h);
        cov = max(cov, clamp(r - d + 0.5, 0.0, 1.0) * mix(a.w, b.w, h));
    }
    if (cov <= 0.0)
        discard;
    fragColor = color * cov;
}
)#";

    Clock::duration lifetime() {
        return std::chrono::milliseconds(std::max<int64_t>(g->lifeMs->value(), 1));
    }

    double halfWidth() {
        return std::max<double>(g->width->value(), 0.5) / 2.0;
    }

    // Caelestia writes the scheme to ~/.local/state/caelestia/scheme.json; reread it when it changes
    void refreshSchemeColor() {
        const auto now = Clock::now();
        if (now - g->schemeChecked < std::chrono::milliseconds(500))
            return;
        g->schemeChecked = now;

        const char* home = getenv("HOME");
        if (!home)
            return;
        const std::filesystem::path path = std::filesystem::path(home) / ".local/state/caelestia/scheme.json";

        std::error_code             ec;
        const auto                  mtime = std::filesystem::last_write_time(path, ec);
        if (ec || mtime == g->schemeMtime)
            return;
        g->schemeMtime = mtime;

        std::ifstream     file(path);
        std::stringstream ss;
        ss << file.rdbuf();
        static const std::regex RE(R"#("primary"\s*:\s*"([0-9a-fA-F]{6})")#");
        std::smatch             m;
        const std::string       text = ss.str();
        if (!std::regex_search(text, m, RE))
            return;
        const auto rgb = std::stoul(m[1].str(), nullptr, 16);
        g->schemeColor = CHyprColor(((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, 1.0);
    }

    CHyprColor trailColor() {
        const auto c = g->color->value();
        if (c != 0)
            return CHyprColor(sc<uint64_t>(c));
        refreshSchemeColor();
        return g->schemeColor;
    }

    void expire(Clock::time_point now) {
        const auto life = lifetime();
        while (!g->points.empty() && now - g->points.front().t > life)
            g->points.pop_front();
    }

    // Bounding box of the live trail (stored points + the pointer), global logical coords
    CBox trailBox() {
        if (g->points.empty())
            return {};
        Vector2D mn = Pointer::mgr()->position(), mx = mn;
        for (const auto& p : g->points) {
            mn = {std::min(mn.x, p.pos.x), std::min(mn.y, p.pos.y)};
            mx = {std::max(mx.x, p.pos.x), std::max(mx.y, p.pos.y)};
        }
        const double pad = halfWidth() + AA_PAD;
        return CBox{mn.x - pad, mn.y - pad, mx.x - mn.x + 2 * pad, mx.y - mn.y + 2 * pad};
    }

    CBox boxUnion(const CBox& a, const CBox& b) {
        if (a.empty())
            return b;
        if (b.empty())
            return a;
        const double x1 = std::min(a.x, b.x), y1 = std::min(a.y, b.y);
        const double x2 = std::max(a.x + a.w, b.x + b.w), y2 = std::max(a.y + a.h, b.y + b.h);
        return CBox{x1, y1, x2 - x1, y2 - y1};
    }

    // Damage where the trail is now and where it was last drawn, which also schedules a frame
    void damageTrail() {
        const CBox box = boxUnion(trailBox(), g->lastDrawn);
        if (!box.empty())
            g_pHyprRenderer->damageBox(box);
    }

    // Caelestia's game mode sets animations:enabled = 0 (and a reload restores it)
    bool active() {
        static auto PANIMENABLED = CConfigValue<Config::INTEGER>("animations:enabled");
        return *PANIMENABLED;
    }

    void onMouseMove() {
        if (!active()) {
            g->points.clear();
            if (!g->lastDrawn.empty())
                damageTrail(); // schedules the frame that erases it (see preChecks)
            return;
        }

        const auto now = Clock::now();
        const auto pos = Pointer::mgr()->position();
        expire(now);

        if (!g->points.empty()) {
            const auto& last = g->points.back();
            if (last.pos.distance(pos) < MIN_SPACING || now - last.t < MIN_INTERVAL) {
                damageTrail(); // the head follows the pointer even between stored points
                return;
            }
        }

        g->points.push_back({pos, now});
        while (g->points.size() > MAX_POINTS - 1) // keep a slot for the live pointer
            g->points.pop_front();

        damageTrail();
    }

    bool ensureShader() {
        if (g->shader)
            return g->shader->program() != 0;

        g->shader = makeShared<CShader>();
        if (!g->shader->createProgram(VERT, FRAG, true)) {
            HyprlandAPI::addNotification(g->handle, "[cursortrail] shader failed to compile", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
            return false;
        }

        const auto prog = g->shader->program();
        g->locProj      = glGetUniformLocation(prog, "proj");
        g->locTopLeft   = glGetUniformLocation(prog, "topLeft");
        g->locFullSize  = glGetUniformLocation(prog, "fullSize");
        g->locColor     = glGetUniformLocation(prog, "color");
        g->locCount     = glGetUniformLocation(prog, "count");
        g->locPts       = glGetUniformLocation(prog, "pts");
        return true;
    }

    class CTrailPassElement : public IPassElement {
      public:
        CTrailPassElement(std::vector<float>&& pts, const CBox& boxPx, const CBox& boxLogical) : m_pts(std::move(pts)), m_boxPx(boxPx), m_boxLogical(boxLogical) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            if (!ensureShader())
                return {};

            CRegion damage = ctx.m_data.damage.copy().intersect(m_boxPx);
            if (damage.empty())
                return {};

            const auto color     = trailColor();
            const auto premult   = CHyprColor(color.r * color.a, color.g * color.a, color.b * color.a, color.a);
            const auto converted = g_pHyprRenderer->getConvertedColor(ctx, premult);
            const auto proj      = g_pHyprRenderer->projectBoxToTarget(ctx, m_boxPx);

            g_pHyprOpenGL->useShader(g->shader);
            glUniformMatrix3fv(g->locProj, 1, GL_TRUE, proj.getMatrix().data());
            glUniform2f(g->locTopLeft, m_boxPx.x, m_boxPx.y);
            glUniform2f(g->locFullSize, m_boxPx.w, m_boxPx.h);
            glUniform4f(g->locColor, converted.r, converted.g, converted.b, converted.a);
            glUniform1i(g->locCount, sc<GLint>(m_pts.size() / 4));
            glUniform4fv(g->locPts, sc<GLsizei>(m_pts.size() / 4), m_pts.data());

            g_pHyprOpenGL->blend(true);
            g_pHyprOpenGL->blendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

            glBindVertexArray(g->shader->getUniformLocation(SHADER_SHADER_VAO));
            damage.forEachRect([&ctx](const auto& RECT) {
                g_pHyprOpenGL->scissor(ctx, &RECT, ctx.m_data.transformDamage);
                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            });
            glBindVertexArray(0);
            g_pHyprOpenGL->disableScissor();
            return {};
        }

        bool needsLiveBlur(Render::CRenderContext&) override {
            return false;
        }
        bool needsPrecomputeBlur(Render::CRenderContext&) override {
            return false;
        }
        std::optional<CBox> boundingBox(Render::CRenderContext&) override {
            return m_boxLogical;
        }
        CRegion opaqueRegion(Render::CRenderContext&) override {
            return {};
        }
        const char* passName() override {
            return "CTrailPassElement";
        }
        ePassElementType type() override {
            return EK_CUSTOM;
        }

      private:
        std::vector<float> m_pts;
        CBox               m_boxPx, m_boxLogical;
    };

    // Queue the trail for this monitor's frame, in the current render pass
    void addTrail(Render::CRenderContext& ctx, PHLMONITOR mon) {
        const auto now = Clock::now();
        expire(now);

        if (!active())
            g->points.clear();

        const CBox global = trailBox();
        g->lastDrawn      = global;
        if (global.empty() || !mon)
            return;

        const CBox monBox = {mon->m_position, mon->m_size};
        if (global.intersection(monBox).empty())
            return;

        const double       lifeS = std::chrono::duration<double>(lifetime()).count();
        const double       r     = halfWidth() * mon->m_scale;

        std::vector<float> pts;
        pts.reserve((g->points.size() + 1) * 4);
        auto push = [&](const Vector2D& p, double life) {
            const Vector2D px = (p - mon->m_position) * mon->m_scale;
            life              = std::clamp(life, 0.0, 1.0);
            pts.insert(pts.end(), {sc<float>(px.x), sc<float>(px.y), sc<float>(std::max(r * life, 0.5)), sc<float>(life)});
        };
        for (const auto& p : g->points)
            push(p.pos, 1.0 - std::chrono::duration<double>(now - p.t).count() / lifeS);
        push(Pointer::mgr()->position(), 1.0); // the head sits on the pointer itself

        if (pts.size() < 8)
            return;

        CBox boxLogical = global.copy().translate(-mon->m_position);
        CBox boxPx      = boxLogical.copy().scale(mon->m_scale).round();
        g_pHyprRenderer->addPassElement(ctx, makeUnique<CTrailPassElement>(std::move(pts), boxPx, boxLogical));
    }

    // Hooked so the trail lands in the pass right before the (software) cursor, staying under it
    using origRenderSWCursors = void (*)(void*, Render::CRenderContext&, PHLMONITOR, const Time::steady_tp&, CRegion&, std::optional<Vector2D>, bool, bool);

    void hkRenderSoftwareCursorsFor(void* thisptr, Render::CRenderContext& ctx, PHLMONITOR pMonitor, const Time::steady_tp& now, CRegion& damage,
                                    std::optional<Vector2D> overridePos, bool screencopy, bool forceRender) {
        if (!screencopy)
            addTrail(ctx, pMonitor);
        (*(origRenderSWCursors)g->cursorHook->m_original)(thisptr, ctx, pMonitor, now, damage, overridePos, screencopy, forceRender);
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(handle, "[cursortrail] built for another Hyprland version, not loading", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[cursortrail] version mismatch");
    }

    g         = makeUnique<SState>();
    g->handle = handle;

    g->width  = makeShared<Config::Values::CFloatValue>("plugin:cursortrail:width", "Trail width in logical px at the pointer", 8.F);
    g->lifeMs = makeShared<Config::Values::CIntValue>("plugin:cursortrail:life_ms", "How long a trail point lives, in ms", 220);
    g->color  = makeShared<Config::Values::CColorValue>("plugin:cursortrail:color", "Trail colour, 0 follows the Caelestia scheme primary", 0);
    HyprlandAPI::addConfigValueV2(handle, g->width);
    HyprlandAPI::addConfigValueV2(handle, g->lifeMs);
    HyprlandAPI::addConfigValueV2(handle, g->color);

    for (const auto& fn : HyprlandAPI::findFunctionsByName(handle, "renderSoftwareCursorsFor")) {
        if (!fn.demangled.contains("CPointerManager::renderSoftwareCursorsFor"))
            continue;
        g->cursorHook = HyprlandAPI::createFunctionHook(handle, fn.address, (void*)&hkRenderSoftwareCursorsFor);
        if (g->cursorHook && !g->cursorHook->hook()) {
            HyprlandAPI::removeFunctionHook(handle, g->cursorHook);
            g->cursorHook = nullptr;
        }
        break;
    }

    // Fallback without the hook: draw at the end of the frame (above the cursor)
    if (!g->cursorHook)
        g->lastMomentListener = Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& ev) {
            if (ev.stage == RENDER_LAST_MOMENT && ev.context)
                addTrail(ev.context->get(), ev.monitor);
        });

    g->moveListener = Event::bus()->m_events.input.mouse.move.listen([](Vector2D, Event::SCallbackInfo&) { onMouseMove(); });

    // Keep frames coming while the trail fades out (also erases it once it is gone)
    g->preChecksListener = Event::bus()->m_events.render.preChecks.listen([](PHLMONITOR) {
        expire(Clock::now());
        if (g->points.empty() && g->lastDrawn.empty())
            return;
        damageTrail();
        if (g->points.empty())
            g->lastDrawn = {}; // this frame erases the trail, nothing left to track
    });

    return {"cursortrail", "Fading trail behind the mouse pointer", "Dralexgon", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (!g)
        return;
    if (!g->lastDrawn.empty())
        g_pHyprRenderer->damageBox(g->lastDrawn);
    if (g->shader) {
        g_pHyprOpenGL->makeEGLCurrent();
        g->shader->destroy();
    }
    g.reset();
}
