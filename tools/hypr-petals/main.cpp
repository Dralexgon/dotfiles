// petals: a Hyprland plugin that shatters closing windows into petals blown away by the wind.
//
// How it works:
//  - Hyprland snapshots a closing window into a monitor-sized framebuffer and hands it to
//    Desktop::CWindowFadeout::create for the windowsOut / fadeOut animation. That function is
//    hooked: the plugin keeps the snapshot and returns no fadeout, so the stock animation is skipped.
//  - The window's box is cut into a grid of cells. Each cell is a quad showing its own patch of the
//    snapshot; a shader morphs it from a rectangle into a petal shape (the window "cracks"), then the
//    petals peel off one after another (downwind side first), flutter, spin, tumble and fade.
//  - Petals live in global logical coordinates, so they fly across monitors. They are drawn on top
//    of everything at the end of each frame.
//
// Config (all optional, e.g. hl.config({ plugin = { petals = { size = 42 } } })):
//  plugin:petals:enabled        1 = shatter closing windows, 0 = stock animation       (1)
//  plugin:petals:size           petal size in logical px                               (44)
//  plugin:petals:max_petals     cap per window, petals grow on big windows             (240)
//  plugin:petals:duration_ms    flight time of one petal                               (1700)
//  plugin:petals:spread_ms      delay between the first and the last petal leaving     (380)
//  plugin:petals:wind_x         wind direction, x                                      (1.0)
//  plugin:petals:wind_y         wind direction, y (negative = up)                      (-0.45)
//  plugin:petals:wind_strength  wind speed in logical px/s                             (750)
//  plugin:petals:tint           how much petals take the colour, 0..1                  (0.3)
//  plugin:petals:color          0xAARRGGBB, 0 = follow the Caelestia scheme            (0)
//
// Like cursortrail, nothing happens while animations are off (Caelestia's game mode).
// Assumes unrotated monitors (the snapshot is sampled in untransformed monitor pixels).

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/state/WindowFadeout.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <random>
#include <regex>
#include <sstream>
#include <vector>

using namespace Render::GL;

using Clock = std::chrono::steady_clock;

namespace {
    constexpr double MORPH_S   = 0.14; // rectangle -> petal
    constexpr double GROW      = 1.35; // petals overlap their neighbours once morphed
    constexpr double MAX_DT    = 1.0 / 20.0;
    constexpr double PI        = 3.14159265358979323846;

    struct SPetal {
        Vector2D home;    // cell centre, global logical
        Vector2D pos;     // current centre, global logical
        Vector2D vel;     // logical px/s
        Vector2D uv;      // cell centre in the snapshot, 0..1
        double   release; // s after the burst starts
        double   rot = 0, spin;
        double   tumble = 0, tumbleRate;
        double   flutterPhase, flutterFreq, flutterAmp;
        double   gust;    // per-petal wind multiplier
        double   alpha = 1, scale = 1;
    };

    struct SBurst {
        SP<Render::IFramebuffer> fb; // keeps the snapshot alive
        SP<Render::ITexture>     tex;
        Vector2D                 snapSizePx; // monitor pixels of the snapshot
        double                   cell = 0;   // logical px
        Vector2D                 uvCell;     // cell size in uv
        std::vector<SPetal>      petals;
        Clock::time_point        start;
        Clock::time_point        lastStep;
        double                   duration = 1.7;
        std::mt19937             rng;
    };

    struct SState {
        HANDLE                          handle    = nullptr;
        CFunctionHook*                  createHook = nullptr;
        std::vector<UP<SBurst>>         bursts;
        CBox                            lastDrawn; // global logical

        SP<Config::Values::CIntValue>   enabled, maxPetals, durationMs, spreadMs;
        SP<Config::Values::CFloatValue> size, windX, windY, windStrength, tint;
        SP<Config::Values::CColorValue> color;

        CHyprColor                      schemeColor{0xF5 / 255.0, 0xC2 / 255.0, 0xE7 / 255.0, 1.0};
        std::filesystem::file_time_type schemeMtime{};
        Clock::time_point               schemeChecked{};

        SP<CShader>                     shader;
        GLint locProj = -1, locTex = -1, locUvOrigin = -1, locUvSpan = -1, locMorph = -1, locAlpha = -1, locTint = -1, locTintAmt = -1, locBack = -1;

        CHyprSignalListener             stageListener, preChecksListener;
    };

    UP<SState> g;

    const char* VERT = R"#(#version 300 es
uniform mat3 proj;
in vec2 pos;
out vec2 v_local;
void main() {
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
    v_local = pos;
}
)#";

    // v_local: 0..1 over the petal quad (y down). The snapshot is premultiplied.
    const char* FRAG = R"#(#version 300 es
precision highp float;
uniform sampler2D tex;
uniform vec2 uvOrigin;
uniform vec2 uvSpan;
uniform float morph;
uniform float alpha;
uniform vec4 tint;
uniform float tintAmt;
uniform float back;
in vec2 v_local;
layout(location = 0) out vec4 fragColor;

// Signed-ish distance to a petal pointing up: narrow base, round body, small notch at the tip
float petal(vec2 q) {
    vec2 p = vec2(q.x, -q.y);
    float w = mix(0.22, 1.0, smoothstep(-1.05, 0.35, p.y));
    float body = length(vec2(p.x / w, p.y)) - 0.97;
    float notch = 0.24 - length(p - vec2(0.0, 1.02));
    return max(body, notch);
}

void main() {
    vec2 q = v_local * 2.0 - 1.0;
    float d = petal(q);
    float aa = max(fwidth(d), 1e-4);
    float shape = clamp(0.5 - d / aa, 0.0, 1.0);
    float mask = mix(1.0, shape, morph);
    if (mask <= 0.0)
        discard;

    vec4 c = texture(tex, uvOrigin + v_local * uvSpan);

    // Colour the petal (more on its back side), with a soft glowing rim so
    // translucent windows still leave visible petals
    float rim = morph * smoothstep(-0.35, 0.0, d);
    float t = clamp(tintAmt * morph + back * 0.45, 0.0, 1.0);
    c.rgb = mix(c.rgb, tint.rgb * c.a, t);
    float glow = clamp(rim * 0.55 + morph * tintAmt * 0.25, 0.0, 1.0) * tint.a;
    c = c + tint * glow * (1.0 - c.a);

    fragColor = c * mask * alpha;
}
)#";

    double frand(std::mt19937& rng, double a, double b) {
        return std::uniform_real_distribution<double>(a, b)(rng);
    }

    bool active() {
        static auto PANIMENABLED = CConfigValue<Config::INTEGER>("animations:enabled");
        return *PANIMENABLED && g->enabled->value();
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

    CHyprColor petalColor() {
        const auto c = g->color->value();
        if (c != 0)
            return CHyprColor(sc<uint64_t>(c));
        refreshSchemeColor();
        return g->schemeColor;
    }

    Vector2D windDir() {
        Vector2D w = {g->windX->value(), g->windY->value()};
        const double len = std::sqrt(w.x * w.x + w.y * w.y);
        return len < 1e-6 ? Vector2D{1, 0} : w / len;
    }

    // Half the diagonal of a petal quad at full growth, to bound it whatever its rotation
    double petalRadius(const SBurst& b) {
        return b.cell * GROW * 0.7072 + 2.0;
    }

    void startBurst(PHLWINDOW window, SP<Render::IFramebuffer> fb) {
        const auto mon = window->m_monitor.lock();
        if (!mon || !fb || !fb->getTexture())
            return;

        static auto PBORDER = CConfigValue<Config::INTEGER>("general:border_size");
        const double border  = *PBORDER + 1.0;

        const Vector2D wpos = window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT) - Vector2D{border, border};
        const Vector2D wsize = window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT) + Vector2D{border * 2, border * 2};
        if (wsize.x < 4 || wsize.y < 4)
            return;

        auto b       = makeUnique<SBurst>();
        b->fb         = fb;
        b->tex        = fb->getTexture();
        b->snapSizePx = mon->m_transformedSize;
        b->duration   = std::max<int64_t>(g->durationMs->value(), 100) / 1000.0;
        b->start = b->lastStep = Clock::now();
        b->rng.seed(std::random_device{}());

        // Grid: about `size` px cells, grown on big windows to stay under max_petals
        double       cell = std::max<double>(g->size->value(), 8.0);
        const double maxN = std::max<int64_t>(g->maxPetals->value(), 4);
        if ((wsize.x / cell) * (wsize.y / cell) > maxN)
            cell = std::sqrt(wsize.x * wsize.y / maxN);
        const int    cols = std::max(1, sc<int>(std::round(wsize.x / cell)));
        const int    rows = std::max(1, sc<int>(std::round(wsize.y / cell)));
        const double cw = wsize.x / cols, ch = wsize.y / rows;
        b->cell = std::max(cw, ch);
        // square quads (petals are drawn square), sampling a square patch of the snapshot
        b->uvCell = Vector2D{b->cell * mon->m_scale / b->snapSizePx.x, b->cell * mon->m_scale / b->snapSizePx.y};

        const Vector2D dir    = windDir();
        const Vector2D centre = wpos + wsize / 2.0;
        const double   extent = std::abs(dir.x) * wsize.x / 2.0 + std::abs(dir.y) * wsize.y / 2.0;
        const double   spread = std::max<int64_t>(g->spreadMs->value(), 0) / 1000.0;
        const Vector2D perp   = {-dir.y, dir.x};

        auto&          rng = b->rng;
        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                SPetal p;
                p.home = p.pos = wpos + Vector2D{(c + 0.5) * cw, (r + 0.5) * ch};
                p.uv           = Vector2D{(p.home.x - mon->m_position.x) * mon->m_scale / b->snapSizePx.x,
                                          (p.home.y - mon->m_position.y) * mon->m_scale / b->snapSizePx.y};

                // downwind side leaves first
                const Vector2D off  = p.home - centre;
                const double   proj = extent > 1e-6 ? (off.x * dir.x + off.y * dir.y) / extent : 0.0; // -1..1
                p.release           = MORPH_S + (1.0 - proj) * 0.5 * spread + frand(rng, 0.0, 0.09);

                // a small kick out of the window and upwards, then the wind takes over
                const double len = std::sqrt(off.x * off.x + off.y * off.y);
                const Vector2D out = len > 1e-6 ? off / len : Vector2D{0, 0};
                p.vel = out * frand(rng, 30, 110) + perp * frand(rng, -60, 60) + Vector2D{0.0, -frand(rng, 20, 80)};

                p.spin         = frand(rng, 1.2, 4.0) * (frand(rng, 0, 1) < 0.5 ? -1 : 1);
                p.tumbleRate   = frand(rng, 2.0, 6.5);
                p.flutterPhase = frand(rng, 0, 2 * PI);
                p.flutterFreq  = frand(rng, 2.5, 5.5);
                p.flutterAmp   = frand(rng, 90, 220);
                p.gust         = frand(rng, 0.6, 1.35);
                b->petals.push_back(p);
            }
        }

        g->bursts.emplace_back(std::move(b));
    }

    // Advance the simulation; returns false once every petal is gone
    bool step(SBurst& b, Clock::time_point now) {
        const double dt = std::clamp(std::chrono::duration<double>(now - b.lastStep).count(), 0.0, MAX_DT);
        const double t  = std::chrono::duration<double>(now - b.start).count();
        b.lastStep      = now;
        if (dt <= 0)
            return true;

        const Vector2D dir      = windDir();
        const Vector2D perp     = {-dir.y, dir.x};
        const double   strength = g->windStrength->value();
        const double   follow   = 1.0 - std::exp(-2.2 * dt);
        bool           alive    = false;

        for (auto& p : b.petals) {
            const double age = t - p.release;
            if (age < 0) {
                p.pos = p.home; // still part of the window
                alive = true;
                continue;
            }
            if (age > b.duration) {
                p.alpha = 0;
                continue;
            }
            alive = true;

            // wind ramps up after the release, with a side-to-side flutter
            const double   ramp   = std::min(age / 0.35, 1.0);
            const Vector2D target = dir * (strength * p.gust * ramp) + perp * (p.flutterAmp * std::sin(p.flutterPhase + age * p.flutterFreq));
            p.vel                 = p.vel + (target - p.vel) * follow;
            p.pos                 = p.pos + p.vel * dt;

            p.rot += p.spin * dt * ramp;
            p.tumble += p.tumbleRate * dt * ramp;

            const double life = age / b.duration;
            p.alpha           = 1.0 - std::clamp((life - 0.4) / 0.6, 0.0, 1.0);
            p.alpha *= p.alpha;
            p.scale = 1.0 - 0.45 * life;
        }
        return alive;
    }

    CBox burstsBox() {
        CBox box;
        for (const auto& b : g->bursts) {
            const double r = petalRadius(*b);
            for (const auto& p : b->petals) {
                if (p.alpha <= 0)
                    continue;
                const CBox pb{p.pos.x - r, p.pos.y - r, 2 * r, 2 * r};
                if (box.empty())
                    box = pb;
                else {
                    const double x1 = std::min(box.x, pb.x), y1 = std::min(box.y, pb.y);
                    const double x2 = std::max(box.x + box.w, pb.x + pb.w), y2 = std::max(box.y + box.h, pb.y + pb.h);
                    box = CBox{x1, y1, x2 - x1, y2 - y1};
                }
            }
        }
        return box;
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

    bool ensureShader() {
        if (g->shader)
            return g->shader->program() != 0;

        g->shader = makeShared<CShader>();
        if (!g->shader->createProgram(VERT, FRAG, true)) {
            HyprlandAPI::addNotification(g->handle, "[petals] shader failed to compile", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
            return false;
        }

        const auto prog = g->shader->program();
        g->locProj      = glGetUniformLocation(prog, "proj");
        g->locTex       = glGetUniformLocation(prog, "tex");
        g->locUvOrigin  = glGetUniformLocation(prog, "uvOrigin");
        g->locUvSpan    = glGetUniformLocation(prog, "uvSpan");
        g->locMorph     = glGetUniformLocation(prog, "morph");
        g->locAlpha     = glGetUniformLocation(prog, "alpha");
        g->locTint      = glGetUniformLocation(prog, "tint");
        g->locTintAmt   = glGetUniformLocation(prog, "tintAmt");
        g->locBack      = glGetUniformLocation(prog, "back");
        return true;
    }

    struct SPetalDraw {
        CBox  boxPx; // with rot
        float uvOrigin[2], uvSpan[2];
        float morph, alpha, back;
    };

    struct SBurstDraw {
        SP<Render::ITexture>    tex;
        std::vector<SPetalDraw> petals;
    };

    class CPetalsPassElement : public IPassElement {
      public:
        CPetalsPassElement(std::vector<SBurstDraw>&& bursts, const CBox& boxPx, const CBox& boxLogical) :
            m_bursts(std::move(bursts)), m_boxPx(boxPx), m_boxLogical(boxLogical) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            if (!ensureShader())
                return {};

            CRegion damage = ctx.m_data.damage.copy().intersect(m_boxPx);
            if (damage.empty())
                return {};

            const auto color     = petalColor();
            const auto converted = g_pHyprRenderer->getConvertedColor(ctx, CHyprColor(color.r, color.g, color.b, 1.0));

            g_pHyprOpenGL->useShader(g->shader);
            glUniform1i(g->locTex, 0);
            glUniform4f(g->locTint, converted.r, converted.g, converted.b, 1.0F);
            glUniform1f(g->locTintAmt, std::clamp<float>(g->tint->value(), 0.F, 1.F));

            g_pHyprOpenGL->blend(true);
            g_pHyprOpenGL->blendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            glActiveTexture(GL_TEXTURE0);
            glBindVertexArray(g->shader->getUniformLocation(SHADER_SHADER_VAO));

            for (const auto& burst : m_bursts) {
                glBindTexture(GL_TEXTURE_2D, burst.tex->m_texID);
                for (const auto& p : burst.petals) {
                    const auto proj = g_pHyprRenderer->projectBoxToTarget(ctx, p.boxPx);
                    glUniformMatrix3fv(g->locProj, 1, GL_TRUE, proj.getMatrix().data());
                    glUniform2f(g->locUvOrigin, p.uvOrigin[0], p.uvOrigin[1]);
                    glUniform2f(g->locUvSpan, p.uvSpan[0], p.uvSpan[1]);
                    glUniform1f(g->locMorph, p.morph);
                    glUniform1f(g->locAlpha, p.alpha);
                    glUniform1f(g->locBack, p.back);
                    damage.forEachRect([&ctx](const auto& RECT) {
                        g_pHyprOpenGL->scissor(ctx, &RECT, ctx.m_data.transformDamage);
                        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                    });
                }
            }

            glBindTexture(GL_TEXTURE_2D, 0);
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
            return "CPetalsPassElement";
        }
        ePassElementType type() override {
            return EK_CUSTOM;
        }

      private:
        std::vector<SBurstDraw> m_bursts;
        CBox                    m_boxPx, m_boxLogical;
    };

    void addPetals(Render::CRenderContext& ctx, PHLMONITOR mon) {
        if (!mon || g->bursts.empty())
            return;

        const CBox monBox = {mon->m_position, mon->m_size};
        const CBox global = burstsBox();
        if (global.empty() || global.intersection(monBox).empty())
            return;

        std::vector<SBurstDraw> draws;
        for (const auto& b : g->bursts) {
            SBurstDraw d;
            d.tex           = b->tex;
            const double t  = std::chrono::duration<double>(Clock::now() - b->start).count();
            const double m  = std::clamp(t / MORPH_S, 0.0, 1.0);
            const double mm = m * m * (3 - 2 * m);
            const double r  = petalRadius(*b);

            for (const auto& p : b->petals) {
                if (p.alpha <= 0)
                    continue;
                if (CBox{p.pos.x - r, p.pos.y - r, 2 * r, 2 * r}.intersection(monBox).empty())
                    continue;

                const double grow  = 1.0 + (GROW - 1.0) * mm;
                const double side  = b->cell * grow * p.scale;
                const double flip  = std::cos(p.tumble); // fake 3D: squash one axis
                const double sx    = side * std::max(std::abs(flip), 0.12);

                SPetalDraw   pd;
                const Vector2D c = (p.pos - mon->m_position) * mon->m_scale;
                pd.boxPx         = CBox{c.x - sx * mon->m_scale / 2.0, c.y - side * mon->m_scale / 2.0, sx * mon->m_scale, side * mon->m_scale};
                pd.boxPx.rot     = p.rot;
                // the texture patch keeps its full width, it gets squashed with the quad
                const double us  = b->uvCell.x * grow, vs = b->uvCell.y * grow;
                pd.uvOrigin[0]   = sc<float>(p.uv.x - us / 2.0);
                pd.uvOrigin[1]   = sc<float>(p.uv.y - vs / 2.0);
                pd.uvSpan[0]     = sc<float>(us);
                pd.uvSpan[1]     = sc<float>(vs);
                pd.morph         = sc<float>(mm);
                pd.alpha         = sc<float>(p.alpha);
                pd.back          = flip < 0 ? 1.F : 0.F;
                d.petals.push_back(pd);
            }
            if (!d.petals.empty())
                draws.push_back(std::move(d));
        }
        if (draws.empty())
            return;

        CBox boxLogical = global.copy().translate(-mon->m_position);
        CBox boxPx      = boxLogical.copy().scale(mon->m_scale).round();
        g_pHyprRenderer->addPassElement(ctx, makeUnique<CPetalsPassElement>(std::move(draws), boxPx, boxLogical));
    }

    using origCreate = SP<Desktop::CWindowFadeout> (*)(PHLWINDOW, SP<Render::IFramebuffer>, float, SP<Render::IFramebuffer>);

    SP<Desktop::CWindowFadeout> hkCreate(PHLWINDOW window, SP<Render::IFramebuffer> snapshot, float sourceAlpha, SP<Render::IFramebuffer> workspaceSnapshot) {
        if (active() && window && snapshot && snapshot->getTexture() && !window->backend().traits().suggestsNoBorder) {
            const auto before = g->bursts.size();
            startBurst(window, snapshot);
            if (g->bursts.size() > before) {
                g_pHyprRenderer->damageBox(burstsBox());
                return nullptr; // no stock fadeout: the petals replace it
            }
        }
        return (*(origCreate)g->createHook->m_original)(window, snapshot, sourceAlpha, workspaceSnapshot);
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(handle, "[petals] built for another Hyprland version, not loading", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[petals] version mismatch");
    }

    g         = makeUnique<SState>();
    g->handle = handle;

    g->enabled      = makeShared<Config::Values::CIntValue>("plugin:petals:enabled", "Shatter closing windows into petals", 1);
    g->size         = makeShared<Config::Values::CFloatValue>("plugin:petals:size", "Petal size in logical px", 44.F);
    g->maxPetals    = makeShared<Config::Values::CIntValue>("plugin:petals:max_petals", "Maximum petals per window", 240);
    g->durationMs   = makeShared<Config::Values::CIntValue>("plugin:petals:duration_ms", "Flight time of one petal, in ms", 1700);
    g->spreadMs     = makeShared<Config::Values::CIntValue>("plugin:petals:spread_ms", "Delay between the first and last petal leaving, in ms", 380);
    g->windX        = makeShared<Config::Values::CFloatValue>("plugin:petals:wind_x", "Wind direction, x", 1.F);
    g->windY        = makeShared<Config::Values::CFloatValue>("plugin:petals:wind_y", "Wind direction, y (negative is up)", -0.45F);
    g->windStrength = makeShared<Config::Values::CFloatValue>("plugin:petals:wind_strength", "Wind speed in logical px/s", 750.F);
    g->tint         = makeShared<Config::Values::CFloatValue>("plugin:petals:tint", "How much the petals take the colour, 0..1", 0.3F);
    g->color        = makeShared<Config::Values::CColorValue>("plugin:petals:color", "Petal colour, 0 follows the Caelestia scheme primary", 0);
    for (const auto& v : {SP<Config::Values::IValue>(g->enabled), SP<Config::Values::IValue>(g->size), SP<Config::Values::IValue>(g->maxPetals),
                          SP<Config::Values::IValue>(g->durationMs), SP<Config::Values::IValue>(g->spreadMs), SP<Config::Values::IValue>(g->windX),
                          SP<Config::Values::IValue>(g->windY), SP<Config::Values::IValue>(g->windStrength), SP<Config::Values::IValue>(g->tint),
                          SP<Config::Values::IValue>(g->color)})
        HyprlandAPI::addConfigValueV2(handle, v);

    // Searched by mangled name: the plain "create" matches far too many symbols
    std::string why = "symbol not found";
    for (const auto& fn : HyprlandAPI::findFunctionsByName(handle, "CWindowFadeout6create")) {
        g->createHook = HyprlandAPI::createFunctionHook(handle, fn.address, (void*)&hkCreate);
        if (g->createHook && !g->createHook->hook()) {
            HyprlandAPI::removeFunctionHook(handle, g->createHook);
            g->createHook = nullptr;
            why           = "hook failed";
        }
        break;
    }
    if (!g->createHook) {
        HyprlandAPI::addNotification(handle, "[petals] could not hook CWindowFadeout::create (" + why + "), not loading", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[petals] " + why);
    }

    g->stageListener = Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& ev) {
        if (ev.stage == RENDER_LAST_MOMENT && ev.context)
            addPetals(ev.context->get(), ev.monitor);
    });

    // Step the petals once per frame and keep frames coming while they fly (also erases the last one)
    g->preChecksListener = Event::bus()->m_events.render.preChecks.listen([](PHLMONITOR) {
        if (g->bursts.empty() && g->lastDrawn.empty())
            return;
        const auto now = Clock::now();
        std::erase_if(g->bursts, [now](const UP<SBurst>& b) { return !step(*b, now); });
        const CBox current = burstsBox();
        const CBox damage  = boxUnion(current, g->lastDrawn);
        g->lastDrawn       = current;
        if (!damage.empty())
            g_pHyprRenderer->damageBox(damage);
    });

    return {"petals", "Closing windows shatter into petals blown by the wind", "Dralexgon", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (!g)
        return;
    if (!g->lastDrawn.empty())
        g_pHyprRenderer->damageBox(g->lastDrawn);
    g->bursts.clear();
    if (g->shader) {
        g_pHyprOpenGL->makeEGLCurrent();
        g->shader->destroy();
    }
    g.reset();
}
