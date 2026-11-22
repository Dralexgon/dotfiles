// cursorfx: a Hyprland plugin throwing particles behind the mouse pointer as it moves.
//
// Styles (plugin:cursorfx:style):
//  petals  petals in the Caelestia scheme colour, flung by the pointer, then drifting down with a
//          light breeze: they flutter, spin, tumble (fake 3D squash) and fade.
//  blood   drops shaken off the pointer: they fall with gravity, stretch with speed, and splat on
//          an imaginary floor a little below where they fell from; the splats fade after splat_ms.
//  image   any PNG (plugin:cursorfx:image) thrown like the petals.
//  off     nothing.
//
// How it works:
//  - Hyprland's mouse-move event spawns particles along the pointer path (density per 100 px),
//    with part of the pointer velocity, so flicking the mouse throws them further.
//  - Particles live in global logical coordinates (they cross monitors). They are stepped once per
//    frame (render preChecks) and drawn at the end of each frame. Every shape is computed in one
//    fragment shader: the quad is mapped to the shape's own frame (rotation, tumble, stretch).
//
// Config (all optional, e.g. hl.config({ plugin = { cursorfx = { style = "blood" } } })):
//  plugin:cursorfx:style          petals | blood | image | off                             (petals)
//  plugin:cursorfx:image          PNG path for the image style, ~ allowed                  ("")
//  plugin:cursorfx:density        particles per 100 px of pointer travel                   (5)
//  plugin:cursorfx:size           particle size in logical px                              (14)
//  plugin:cursorfx:life_ms        how long a petal / image lives                           (1400)
//  plugin:cursorfx:max_particles  cap, the oldest go first                                 (400)
//  plugin:cursorfx:color          petal colour 0xAARRGGBB, 0 = follow the Caelestia scheme (0)
//  plugin:cursorfx:blood_color    0xAARRGGBB                                               (0xFF8A0012)
//  plugin:cursorfx:splat_ms       how long a blood splat stays                             (1600)
//
// Like cursortrail and petals, nothing happens while animations are off (Caelestia's game mode).

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>

#include <cairo/cairo.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <deque>
#include <filesystem>
#include <fstream>
#include <random>
#include <regex>
#include <sstream>

using namespace Render::GL;

using Clock = std::chrono::steady_clock;

namespace {
    constexpr double PI         = 3.14159265358979323846;
    constexpr double MAX_DT     = 1.0 / 20.0;
    constexpr double MAX_JUMP   = 400.0; // logical px in one move event: a warp, not a throw
    constexpr int    MAX_PER_EV = 10;    // spawned per move event

    enum eKind : int {
        KIND_PETAL = 0,
        KIND_DROP  = 1,
        KIND_SPLAT = 2,
        KIND_IMAGE = 3,
    };

    enum eStyle {
        STYLE_OFF,
        STYLE_PETALS,
        STYLE_BLOOD,
        STYLE_IMAGE,
    };

    struct SParticle {
        eKind    kind;
        Vector2D pos, vel; // global logical, px/s
        double   age = 0, life;
        double   size;     // logical px, full height of the shape
        double   rot = 0, spin = 0;
        double   tumble = 0, tumbleRate = 0;
        double   flutterPhase = 0, flutterFreq = 0, flutterAmp = 0;
        double   floorY = 0; // drops splat when they reach it
        float    seed;
        float    shade;      // per-particle colour variation
        float    whiten = 0; // petals: mix toward white
    };

    struct SState {
        HANDLE                           handle = nullptr;
        std::deque<SParticle>            particles;
        std::mt19937                     rng{std::random_device{}()};
        CBox                             lastDrawn; // global logical
        Clock::time_point                lastStep{};

        Vector2D                         lastPos;
        Clock::time_point                lastMove{};
        bool                             havePos = false;
        Vector2D                         cursorVel; // smoothed, logical px/s
        double                           travel = 0; // since the last spawn

        SP<Config::Values::CStringValue> style, image;
        SP<Config::Values::CFloatValue>  density, size;
        SP<Config::Values::CIntValue>    lifeMs, maxParticles, splatMs;
        SP<Config::Values::CColorValue>  color, bloodColor;

        CHyprColor                       schemeColor{0xF5 / 255.0, 0xC2 / 255.0, 0xE7 / 255.0, 1.0};
        std::filesystem::file_time_type  schemeMtime{};
        Clock::time_point                schemeChecked{};

        SP<Render::ITexture>             imageTex;
        std::string                      imageLoaded; // path the texture comes from
        bool                             imageFailed = false;

        SP<CShader>                      shader;
        GLint locProj = -1, locKind = -1, locFrame = -1, locColor = -1, locAlpha = -1, locBack = -1, locSeed = -1, locTex = -1;

        CHyprSignalListener              moveListener, stageListener, preChecksListener;
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

    // v_local: 0..1 over the (axis aligned) quad, y down. frame maps the quad, as -1..1, to the
    // shape's own -1..1 frame: rotation, tumble squash and stretch all live in it.
    const char* FRAG = R"#(#version 300 es
precision highp float;
uniform int kind;
uniform vec4 frame;
uniform vec4 color; // premultiplied
uniform float alpha;
uniform float back;
uniform float seed;
uniform sampler2D tex;
in vec2 v_local;
layout(location = 0) out vec4 fragColor;

// Petal pointing up (-y): narrow base, round body, small notch at the tip
float petal(vec2 q) {
    vec2 p = vec2(q.x, -q.y);
    float w = mix(0.22, 1.0, smoothstep(-1.05, 0.35, p.y));
    float body = length(vec2(p.x / w, p.y)) - 0.97;
    float notch = 0.24 - length(p - vec2(0.0, 1.02));
    return max(body, notch);
}

// Falling drop, head towards +y, thin tail towards -y
float drop(vec2 q) {
    float y = clamp(q.y, -1.0, 1.0);
    float w = sqrt(max(1.0 - y * y, 0.0)) * smoothstep(-1.1, 0.55, y) * 0.95;
    return max(abs(q.x) - w, abs(q.y) - 1.0);
}

// Irregular splat with a few droplets around it
float splat(vec2 q) {
    float a = atan(q.y, q.x);
    float r = 0.58 + 0.08 * sin(3.0 * a + seed) + 0.06 * sin(5.0 * a + seed * 2.3) + 0.035 * sin(9.0 * a + seed * 4.1);
    float d = length(q) - r;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float ang = seed * 1.7 + fi * 1.27 + 0.6 * sin(seed + fi * 3.1);
        float dist = 0.72 + 0.14 * fract(sin(seed * 12.9 + fi * 78.2) * 437.5);
        float rad = 0.03 + 0.07 * fract(sin(seed * 39.3 + fi * 11.7) * 917.3);
        d = min(d, length(q - dist * vec2(cos(ang), sin(ang))) - rad);
    }
    return d;
}

void main() {
    vec2 c = v_local * 2.0 - 1.0;
    vec2 q = vec2(dot(frame.xy, c), dot(frame.zw, c));

    if (kind == 3) {
        if (abs(q.x) > 1.0 || abs(q.y) > 1.0)
            discard;
        vec4 t = texture(tex, q * 0.5 + 0.5);
        t.rgb *= mix(1.0, 0.7, back);
        fragColor = t * alpha;
        return;
    }

    float d = kind == 0 ? petal(q) : kind == 1 ? drop(q) : splat(q);
    float aa = max(fwidth(d), 1e-4);
    float mask = clamp(0.5 - d / aa, 0.0, 1.0);
    if (mask <= 0.0)
        discard;

    vec3 rgb = color.rgb;
    if (kind == 0) {
        // lighter towards the tip, a faint vein, softer rim, darker back side
        float along = clamp((1.0 - q.y) * 0.5, 0.0, 1.0);
        rgb *= mix(0.78, 1.12, along);
        rgb *= 1.0 - 0.18 * smoothstep(0.07, 0.0, abs(q.x)) * smoothstep(-1.0, 0.3, q.y);
        rgb = mix(rgb, vec3(color.a), 0.18 * smoothstep(-0.18, 0.0, d));
        rgb *= mix(1.0, 0.78, back);
    } else if (kind == 1) {
        // round, glossy: darker edges, small highlight near the head
        rgb *= mix(0.55, 1.08, clamp(-d / 0.45, 0.0, 1.0));
        float h = smoothstep(0.22, 0.0, length(q - vec2(-0.32, 0.45)));
        rgb = mix(rgb, vec3(color.a), h * 0.6);
    } else {
        // pooled: darker ring where it dries, a dull sheen in the middle
        rgb *= mix(1.0, 0.62, smoothstep(-0.16, 0.0, d));
        float h = smoothstep(0.35, 0.0, length(q - vec2(-0.18, -0.2)));
        rgb = mix(rgb, vec3(color.a), h * 0.18);
    }
    fragColor = vec4(rgb, color.a) * mask * alpha;
}
)#";

    double frand(double a, double b) {
        return std::uniform_real_distribution<double>(a, b)(g->rng);
    }

    bool animationsOn() {
        static auto PANIMENABLED = CConfigValue<Config::INTEGER>("animations:enabled");
        return *PANIMENABLED;
    }

    eStyle style() {
        const std::string s = g->style->value();
        if (s == "petals" || s == "petal")
            return STYLE_PETALS;
        if (s == "blood")
            return STYLE_BLOOD;
        if (s == "image") {
            const std::string img = g->image->value();
            return img.empty() || img == "[[EMPTY]]" ? STYLE_PETALS : STYLE_IMAGE; // nothing to throw yet
        }
        return STYLE_OFF;
    }

    bool active() {
        return animationsOn() && style() != STYLE_OFF;
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

    double baseSize() {
        return std::clamp<double>(g->size->value(), 2.0, 200.0);
    }

    // Half extent of the square that holds the particle whatever its rotation, logical px
    double extent(const SParticle& p) {
        switch (p.kind) {
            case KIND_DROP: {
                const double speed = std::sqrt(p.vel.x * p.vel.x + p.vel.y * p.vel.y);
                return p.size * 0.5 * std::max(1.0, 1.0 + speed / 700.0) * 1.05;
            }
            case KIND_SPLAT: return p.size * 0.5 * 1.05;
            default: return p.size * 0.5 * 1.42;
        }
    }

    CBox particlesBox() {
        if (g->particles.empty())
            return {};
        double x1 = 1e18, y1 = 1e18, x2 = -1e18, y2 = -1e18;
        for (const auto& p : g->particles) {
            const double e = extent(p) + 2.0;
            x1 = std::min(x1, p.pos.x - e);
            y1 = std::min(y1, p.pos.y - e);
            x2 = std::max(x2, p.pos.x + e);
            y2 = std::max(y2, p.pos.y + e);
        }
        return CBox{x1, y1, x2 - x1, y2 - y1};
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

    void spawn(eStyle s, const Vector2D& at) {
        SParticle p;
        p.pos  = at;
        p.seed = sc<float>(frand(0.0, 100.0));
        const double sz = baseSize();

        if (s == STYLE_BLOOD) {
            p.kind   = KIND_DROP;
            p.size   = sz * frand(0.55, 1.1);
            p.vel    = g->cursorVel * frand(0.08, 0.22) + Vector2D{frand(-50, 50), frand(-60, 30)};
            p.life   = 4.0; // safety net, they splat long before
            p.floorY = at.y + frand(35, 240);
            p.shade  = sc<float>(frand(0.78, 1.05));
        } else {
            p.kind         = s == STYLE_IMAGE ? KIND_IMAGE : KIND_PETAL;
            p.size         = sz * frand(0.75, 1.25);
            p.vel          = g->cursorVel * frand(0.15, 0.35) + Vector2D{frand(-70, 70), frand(-90, 20)};
            p.life         = std::max<int64_t>(g->lifeMs->value(), 50) / 1000.0 * frand(0.75, 1.2);
            p.rot          = frand(0, 2 * PI);
            p.spin         = frand(-4.0, 4.0);
            p.tumble       = frand(0, 2 * PI);
            p.tumbleRate   = frand(-6.0, 6.0);
            p.flutterPhase = frand(0, 2 * PI);
            p.flutterFreq  = frand(2.0, 4.5);
            p.flutterAmp   = frand(60, 160);
            p.shade        = sc<float>(frand(0.85, 1.12));
            p.whiten       = sc<float>(frand(0.0, 0.35));
        }

        if (g->particles.empty())
            g->lastStep = Clock::now(); // idle until now: do not step over the pause
        g->particles.push_back(p);
        const auto cap = sc<size_t>(std::max<int64_t>(g->maxParticles->value(), 1));
        while (g->particles.size() > cap)
            g->particles.pop_front();
    }

    void onMouseMove() {
        const auto now = Clock::now();
        const auto pos = Pointer::mgr()->position();

        if (!active() || !g->havePos) {
            g->havePos  = true;
            g->lastPos  = pos;
            g->lastMove = now;
            g->travel   = 0;
            return;
        }

        const Vector2D delta = pos - g->lastPos;
        const double   dist  = std::sqrt(delta.x * delta.x + delta.y * delta.y);
        const double   dt    = std::max(std::chrono::duration<double>(now - g->lastMove).count(), 1e-3);
        const Vector2D from  = g->lastPos;
        g->lastPos           = pos;
        g->lastMove          = now;

        if (dist > MAX_JUMP) { // warped, not moved
            g->cursorVel = {};
            g->travel    = 0;
            return;
        }

        // smoothed pointer velocity; a long pause resets it
        const Vector2D v = dt > 0.1 ? Vector2D{} : delta / dt;
        const double   k = std::clamp(dt / 0.04, 0.0, 1.0);
        g->cursorVel     = g->cursorVel * (1.0 - k) + v * k;

        const eStyle   s       = style();
        const double   density = std::max<double>(g->density->value(), 0.01);
        const double   spacing = 100.0 / density * (s == STYLE_BLOOD ? 1.6 : 1.0);
        g->travel += dist;

        int n = 0;
        while (g->travel >= spacing && n < MAX_PER_EV) {
            g->travel -= spacing;
            // spread along the segment this event covered
            const double t = dist > 0 ? std::clamp(1.0 - g->travel / dist, 0.0, 1.0) : 1.0;
            spawn(s, from + delta * t + Vector2D{frand(-3, 3), frand(-3, 3)});
            n++;
        }
        if (n == MAX_PER_EV)
            g->travel = 0;

        if (n > 0 && !g->lastDrawn.empty())
            g_pHyprRenderer->damageBox(boxUnion(particlesBox(), g->lastDrawn));
        else if (n > 0)
            g_pHyprRenderer->damageBox(particlesBox());
    }

    // Advance every particle by dt; false = it is gone
    bool step(SParticle& p, double dt) {
        p.age += dt;

        switch (p.kind) {
            case KIND_PETAL:
            case KIND_IMAGE: {
                const double drag = std::exp(-1.8 * dt);
                p.vel = p.vel * drag;
                p.vel.y += 140.0 * dt; // light: they float down
                p.vel.x += 35.0 * dt;  // a breeze
                p.flutterPhase += p.flutterFreq * dt;
                p.pos = p.pos + p.vel * dt + Vector2D{std::sin(p.flutterPhase) * p.flutterAmp * dt, 0.0};
                p.rot += p.spin * dt;
                p.tumble += p.tumbleRate * dt;
                break;
            }
            case KIND_DROP: {
                p.vel = p.vel * std::exp(-0.4 * dt);
                p.vel.y += 1500.0 * dt;
                p.pos = p.pos + p.vel * dt;
                if (p.pos.y >= p.floorY && p.vel.y > 0) {
                    p.kind  = KIND_SPLAT;
                    p.pos.y = p.floorY;
                    p.vel   = {};
                    p.age   = 0;
                    p.life  = std::max<int64_t>(g->splatMs->value(), 50) / 1000.0;
                    p.size *= frand(1.3, 2.1);
                    p.rot   = frand(0, 2 * PI);
                }
                break;
            }
            case KIND_SPLAT: break;
        }
        return p.age < p.life;
    }

    void stepAll(Clock::time_point now) {
        const double dt = std::clamp(std::chrono::duration<double>(now - g->lastStep).count(), 0.0, MAX_DT);
        g->lastStep     = now;
        if (dt <= 0)
            return;
        std::erase_if(g->particles, [dt](SParticle& p) { return !step(p, dt); });
    }

    double alphaOf(const SParticle& p) {
        const double t = std::clamp(p.age / p.life, 0.0, 1.0);
        switch (p.kind) {
            case KIND_DROP: return std::clamp(p.age / 0.05, 0.0, 1.0);          // drips in
            case KIND_SPLAT: return 1.0 - std::pow(std::max(0.0, (t - 0.55) / 0.45), 1.5); // dries off late
            default: return std::clamp(t / 0.06, 0.0, 1.0) * (1.0 - std::pow(std::max(0.0, (t - 0.6) / 0.4), 1.4));
        }
    }

    // Load (or reload when the path changes) the PNG of the image style. Needs the EGL context.
    SP<Render::ITexture> imageTexture() {
        std::string path = g->image->value();
        if (path.starts_with("~/")) {
            if (const char* home = getenv("HOME"))
                path = std::string(home) + path.substr(1);
        }
        if (path == g->imageLoaded)
            return g->imageTex;

        g->imageLoaded = path;
        g->imageTex.reset();
        if (path.empty() || path == "[[EMPTY]]")
            return nullptr;

        cairo_surface_t* surface = cairo_image_surface_create_from_png(path.c_str());
        if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
            cairo_surface_destroy(surface);
            HyprlandAPI::addNotification(g->handle, "[cursorfx] cannot load PNG " + path, CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
            return nullptr;
        }
        g->imageTex = g_pHyprRenderer->createTexture(surface);
        cairo_surface_destroy(surface);
        return g->imageTex;
    }

    bool ensureShader() {
        if (g->shader)
            return g->shader->program() != 0;

        g->shader = makeShared<CShader>();
        if (!g->shader->createProgram(VERT, FRAG, true)) {
            HyprlandAPI::addNotification(g->handle, "[cursorfx] shader failed to compile", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
            return false;
        }

        const auto prog = g->shader->program();
        g->locProj      = glGetUniformLocation(prog, "proj");
        g->locKind      = glGetUniformLocation(prog, "kind");
        g->locFrame     = glGetUniformLocation(prog, "frame");
        g->locColor     = glGetUniformLocation(prog, "color");
        g->locAlpha     = glGetUniformLocation(prog, "alpha");
        g->locBack      = glGetUniformLocation(prog, "back");
        g->locSeed      = glGetUniformLocation(prog, "seed");
        g->locTex       = glGetUniformLocation(prog, "tex");
        return true;
    }

    struct SDraw {
        CBox       boxPx; // axis aligned square holding the shape
        float      frame[4];
        CHyprColor color; // straight alpha, before conversion
        float      alpha, back, seed;
        int        kind;
    };

    class CFxPassElement : public IPassElement {
      public:
        CFxPassElement(std::vector<SDraw>&& draws, const CBox& boxPx, const CBox& boxLogical) : m_draws(std::move(draws)), m_boxPx(boxPx), m_boxLogical(boxLogical) {}

        std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx) override {
            if (!ensureShader())
                return {};

            CRegion damage = ctx.m_data.damage.copy().intersect(m_boxPx);
            if (damage.empty())
                return {};

            SP<Render::ITexture> tex;
            if (std::ranges::any_of(m_draws, [](const SDraw& d) { return d.kind == KIND_IMAGE; })) {
                tex = imageTexture();
                if (!tex)
                    return {};
            }

            g_pHyprOpenGL->useShader(g->shader);
            glUniform1i(g->locTex, 0);
            g_pHyprOpenGL->blend(true);
            g_pHyprOpenGL->blendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            if (tex) {
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, tex->m_texID);
            }
            glBindVertexArray(g->shader->getUniformLocation(SHADER_SHADER_VAO));

            for (const auto& d : m_draws) {
                const auto c    = g_pHyprRenderer->getConvertedColor(ctx, CHyprColor(d.color.r * d.color.a, d.color.g * d.color.a, d.color.b * d.color.a, d.color.a));
                const auto proj = g_pHyprRenderer->projectBoxToTarget(ctx, d.boxPx);
                glUniformMatrix3fv(g->locProj, 1, GL_TRUE, proj.getMatrix().data());
                glUniform1i(g->locKind, d.kind);
                glUniform4f(g->locFrame, d.frame[0], d.frame[1], d.frame[2], d.frame[3]);
                glUniform4f(g->locColor, c.r, c.g, c.b, c.a);
                glUniform1f(g->locAlpha, d.alpha);
                glUniform1f(g->locBack, d.back);
                glUniform1f(g->locSeed, d.seed);

                CRegion here = damage.copy().intersect(d.boxPx);
                here.forEachRect([&ctx](const auto& RECT) {
                    g_pHyprOpenGL->scissor(ctx, &RECT, ctx.m_data.transformDamage);
                    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                });
            }

            if (tex)
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
            return "CFxPassElement";
        }
        ePassElementType type() override {
            return EK_CUSTOM;
        }

      private:
        std::vector<SDraw> m_draws;
        CBox               m_boxPx, m_boxLogical;
    };

    // Frame mapping the quad (-1..1, half side H) to the shape's -1..1 frame: its y axis points
    // along u, and it measures hx by hy (all in logical px)
    void setFrame(SDraw& d, const Vector2D& u, double H, double hx, double hy) {
        const Vector2D v{-u.y, u.x};
        d.frame[0] = sc<float>(v.x * H / hx);
        d.frame[1] = sc<float>(v.y * H / hx);
        d.frame[2] = sc<float>(u.x * H / hy);
        d.frame[3] = sc<float>(u.y * H / hy);
    }

    void addParticles(Render::CRenderContext& ctx, PHLMONITOR mon) {
        if (!mon || g->particles.empty())
            return;

        const CBox monBox = {mon->m_position, mon->m_size};
        const CBox global = particlesBox();
        if (global.empty() || global.intersection(monBox).empty())
            return;

        const CHyprColor petal = petalColor();
        const CHyprColor blood = CHyprColor(sc<uint64_t>(g->bloodColor->value()));
        double           imgAspect = 1.0; // width / height
        if (g->imageTex && g->imageTex->m_size.y > 0)
            imgAspect = g->imageTex->m_size.x / g->imageTex->m_size.y;

        std::vector<SDraw> splats, others;
        for (const auto& p : g->particles) {
            const double H = extent(p);
            if (CBox{p.pos.x - H, p.pos.y - H, 2 * H, 2 * H}.intersection(monBox).empty())
                continue;
            const double a = alphaOf(p);
            if (a <= 0.0)
                continue;

            SDraw d;
            d.kind  = p.kind;
            d.alpha = sc<float>(a);
            d.seed  = p.seed;
            d.back  = 0;

            switch (p.kind) {
                case KIND_PETAL:
                case KIND_IMAGE: {
                    const double flip = std::cos(p.tumble); // fake 3D: squash one axis
                    const double half = p.size * 0.5;
                    double       hx = half, hy = half;
                    if (p.kind == KIND_IMAGE) {
                        hx = imgAspect >= 1 ? half : half * imgAspect;
                        hy = imgAspect >= 1 ? half / imgAspect : half;
                    } else
                        hx = half * 0.72; // slimmer than tall
                    hx *= std::max(std::abs(flip), 0.12);
                    setFrame(d, {std::sin(p.rot), -std::cos(p.rot)}, H, hx, hy);
                    d.back = flip < 0 ? 1.F : 0.F;
                    if (p.kind == KIND_PETAL) {
                        const double s = p.shade, w = p.whiten;
                        d.color = CHyprColor(std::clamp((petal.r * s) * (1 - w) + w, 0.0, 1.0), std::clamp((petal.g * s) * (1 - w) + w, 0.0, 1.0),
                                             std::clamp((petal.b * s) * (1 - w) + w, 0.0, 1.0), petal.a);
                    } else
                        d.color = CHyprColor(1, 1, 1, 1);
                    break;
                }
                case KIND_DROP: {
                    const double speed  = std::sqrt(p.vel.x * p.vel.x + p.vel.y * p.vel.y);
                    const Vector2D u    = speed > 1 ? p.vel / speed : Vector2D{0, 1};
                    const double grow   = std::clamp(p.age / 0.08, 0.35, 1.0); // swells as it drips off
                    const double half   = p.size * 0.5 * grow;
                    const double stretch = std::max(1.0, 1.0 + speed / 700.0);
                    setFrame(d, u, H, half * 0.62, half * stretch);
                    break;
                }
                case KIND_SPLAT: {
                    const double half = p.size * 0.5;
                    // seen at a slant: flatter than wide, slightly tilted
                    const Vector2D u{std::sin(p.rot) * 0.25, 1.0};
                    const double   l = std::sqrt(u.x * u.x + u.y * u.y);
                    setFrame(d, u / l, H, half, half * 0.8);
                    break;
                }
            }
            if (p.kind == KIND_DROP || p.kind == KIND_SPLAT)
                d.color = CHyprColor(std::clamp(blood.r * p.shade, 0.0, 1.0), std::clamp(blood.g * p.shade, 0.0, 1.0), std::clamp(blood.b * p.shade, 0.0, 1.0), blood.a);

            const Vector2D c = (p.pos - mon->m_position) * mon->m_scale;
            const double   s = H * mon->m_scale;
            d.boxPx          = CBox{c.x - s, c.y - s, 2 * s, 2 * s};
            (p.kind == KIND_SPLAT ? splats : others).push_back(d);
        }

        // splats lie under the drops still falling
        splats.insert(splats.end(), others.begin(), others.end());
        if (splats.empty())
            return;

        CBox boxLogical = global.copy().translate(-mon->m_position);
        CBox boxPx      = boxLogical.copy().scale(mon->m_scale).round();
        g_pHyprRenderer->addPassElement(ctx, makeUnique<CFxPassElement>(std::move(splats), boxPx, boxLogical));
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(handle, "[cursorfx] built for another Hyprland version, not loading", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[cursorfx] version mismatch");
    }

    g         = makeUnique<SState>();
    g->handle = handle;

    g->style        = makeShared<Config::Values::CStringValue>("plugin:cursorfx:style", "petals, blood, image or off", "petals");
    g->image        = makeShared<Config::Values::CStringValue>("plugin:cursorfx:image", "PNG thrown by the image style", "");
    g->density      = makeShared<Config::Values::CFloatValue>("plugin:cursorfx:density", "Particles per 100 px of pointer travel", 5.F);
    g->size         = makeShared<Config::Values::CFloatValue>("plugin:cursorfx:size", "Particle size in logical px", 14.F);
    g->lifeMs       = makeShared<Config::Values::CIntValue>("plugin:cursorfx:life_ms", "How long a petal or image lives, in ms", 1400);
    g->maxParticles = makeShared<Config::Values::CIntValue>("plugin:cursorfx:max_particles", "Particle cap, the oldest go first", 400);
    g->color        = makeShared<Config::Values::CColorValue>("plugin:cursorfx:color", "Petal colour, 0 follows the Caelestia scheme primary", 0);
    g->bloodColor   = makeShared<Config::Values::CColorValue>("plugin:cursorfx:blood_color", "Blood colour", 0xFF8A0012);
    g->splatMs      = makeShared<Config::Values::CIntValue>("plugin:cursorfx:splat_ms", "How long a blood splat stays, in ms", 1600);
    for (const auto& v : std::initializer_list<SP<Config::Values::IValue>>{g->style, g->image, g->density, g->size, g->lifeMs, g->maxParticles, g->color, g->bloodColor, g->splatMs})
        HyprlandAPI::addConfigValueV2(handle, v);

    g->moveListener = Event::bus()->m_events.input.mouse.move.listen([](Vector2D, Event::SCallbackInfo&) { onMouseMove(); });

    g->stageListener = Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& ev) {
        if (ev.stage == RENDER_LAST_MOMENT && ev.context)
            addParticles(ev.context->get(), ev.monitor);
    });

    // Step the particles once per frame and keep frames coming while they live (also erases the last ones)
    g->preChecksListener = Event::bus()->m_events.render.preChecks.listen([](PHLMONITOR) {
        if (!animationsOn())
            g->particles.clear();
        if (g->particles.empty() && g->lastDrawn.empty())
            return;
        stepAll(Clock::now());
        const CBox current = particlesBox();
        const CBox damage  = boxUnion(current, g->lastDrawn);
        g->lastDrawn       = current;
        if (!damage.empty())
            g_pHyprRenderer->damageBox(damage);
    });
    g->lastStep = Clock::now();

    return {"cursorfx", "Petals, blood or images thrown behind the mouse pointer", "Dralexgon", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (!g)
        return;
    if (!g->lastDrawn.empty())
        g_pHyprRenderer->damageBox(g->lastDrawn);
    g->particles.clear();
    g_pHyprOpenGL->makeEGLCurrent();
    g->imageTex.reset();
    if (g->shader)
        g->shader->destroy();
    g.reset();
}
