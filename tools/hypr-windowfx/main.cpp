// windowfx: a Hyprland plugin animating closing windows, and opening ones (the same thing played
// backwards).
//
// Styles (plugin:windowfx:style):
//  petals  the window shatters into petals in the Caelestia scheme colour, blown away by the
//          wind; opening windows assemble from petals brought by the wind.
//  blood   blood runs down the window from the top in uneven drip streaks until it is soaked,
//          then it drains from the bottom up: the cells splash off as teardrop droplets thrown
//          every way (many upwards), slowed by the air, then falling with gravity; they stretch
//          with speed and fade. Opening windows rise from the drops, and
//          the blood runs off them upwards to uncover the window.
//  off     stock windowsIn / windowsOut animations.
//
// How it works:
//  - Hyprland snapshots a closing window into a monitor-sized framebuffer and hands it to
//    Desktop::CWindowFadeout::create for the windowsOut / fadeOut animation. That function is
//    hooked: the plugin keeps the snapshot and returns no fadeout, so the stock animation is skipped.
//  - The window's box is cut into a grid of cells. Each cell is a quad showing its own patch of the
//    snapshot. As it leaves its spot, a shader morphs it from a rectangle into a petal shape, so the
//    window cracks and peels off one petal after another (downwind side first); then they flutter,
//    spin, tumble and fade.
//  - Opening windows play the same thing backwards: a new window stays hidden (its renderWindow is
//    hooked) for open_delay_ms so the client has drawn a first frame, then it is snapshotted and a
//    close burst is simulated ahead of time with the wind reversed. The snapshot is retaken every
//    open_refresh_ms while the petals fly in, so they pick up the content the client draws late. Played backwards, the petals ride
//    the wind in, land, fuse into the window, and the real window takes their place.
//  - Petals live in global logical coordinates, so they fly across monitors. They are drawn on top
//    of everything at the end of each frame.
//
// Config (all optional, e.g. hl.config({ plugin = { windowfx = { style = "blood" } } })):
//  plugin:windowfx:style          petals | blood | off                                   (petals)
//  plugin:windowfx:max_pieces     petals cap per window, petals grow on big windows      (240)
//  plugin:windowfx:open           1 = animate opening windows too                        (1)
//  plugin:windowfx:open_duration_ms  flight time of one piece when opening               (900)
//  plugin:windowfx:open_spread_ms    delay between the first and the last piece landing  (280)
//  plugin:windowfx:open_delay_ms     wait for the client's first frame                   (60)
//  plugin:windowfx:open_refresh_ms   retake the snapshot this often while opening, 0 = never (80)
//  plugin:windowfx:open_speed        playback speed of the whole opening, 2 = twice as fast  (1.0)
// petals:
//  plugin:windowfx:size           petal size in logical px                               (44)
//  plugin:windowfx:duration_ms    flight time of one petal                               (1700)
//  plugin:windowfx:spread_ms      delay between the first and the last petal leaving     (380)
//  plugin:windowfx:wind_x         wind direction, x                                      (1.0)
//  plugin:windowfx:wind_y         wind direction, y (negative = up)                      (-0.45)
//  plugin:windowfx:wind_strength  wind speed in logical px/s                             (750)
//  plugin:windowfx:tint           how much petals take the colour, 0..1                  (0.3)
//  plugin:windowfx:color          0xAARRGGBB, 0 = follow the Caelestia scheme            (0)
// blood:
//  plugin:windowfx:blood_color        0xAARRGGBB                                         (0xFF8A0012)
//  plugin:windowfx:blood_size         cell size in logical px (droplets are 30-100% of it) (18)
//  plugin:windowfx:blood_max_drops    cap per window, cells grow on big windows          (1500)
//  plugin:windowfx:blood_duration_ms  fall time of one drop                              (1000)
//  plugin:windowfx:blood_spread_ms    pace of the blood running down and draining off    (420)
//  plugin:windowfx:blood_gravity      logical px/s²                                      (1900)
//
// Like cursortrail, nothing happens while animations are off (Caelestia's game mode).
// Assumes unrotated monitors (the snapshot is sampled in untransformed monitor pixels).

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/state/WindowFadeout.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/render/WindowRenderPresentation.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <random>
#include <regex>
#include <sstream>
#include <typeindex>
#include <vector>

using namespace Render::GL;

using Clock = std::chrono::steady_clock;

namespace {
    constexpr double MORPH_S   = 0.14; // rectangle -> petal
    constexpr double GROW      = 1.35; // petals overlap their neighbours once morphed
    constexpr double MAX_DT    = 1.0 / 20.0;
    constexpr double PI        = 3.14159265358979323846;
    constexpr double TRACK_FPS = 120.0; // precomputed open animations
    constexpr double BLOOD_GROW    = 1.2;  // drops are fatter than their cell
    constexpr double BLOOD_STRETCH = 0.9;  // extra length of a drop at full speed
    constexpr double SOAK_S        = 0.2;  // blood running down one cell

    enum eStyle {
        STYLE_OFF,
        STYLE_PETALS,
        STYLE_BLOOD,
    };

    // A piece of the window: a petal, or a blood drop
    struct SPetal {
        Vector2D home;    // cell centre, global logical
        Vector2D pos;     // current centre, global logical
        Vector2D vel;     // logical px/s
        Vector2D uv;      // cell centre in the snapshot, 0..1
        double   release; // s after the burst starts
        double   rot = 0, spin;
        double   tumble = 0, tumbleRate;
        double   flutterPhase, flutterFreq, flutterAmp;
        double   gust;    // per-petal wind (or gravity) multiplier
        double   alpha = 1, scale = 1;
        // blood
        double   soakAt  = 0; // s after the burst starts, when the blood reaches this cell
        double   soak    = 0; // 0..1, how far the blood ran down this cell
        double   stretch = 1; // drop length / width
        double   drop    = 1; // droplet size once it left the window, of its cell
    };

    struct SFrame {
        Vector2D pos;
        float    rot, tumble, alpha, scale, soak, stretch;
    };

    struct SBurst {
        eStyle                   style = STYLE_PETALS;
        SP<Render::IFramebuffer> fb; // keeps the snapshot alive
        SP<Render::ITexture>     tex;
        Vector2D                 snapSizePx; // monitor pixels of the snapshot
        double                   cell = 0;   // logical px
        Vector2D                 uvCell;     // cell size in uv
        std::vector<SPetal>      petals;
        Clock::time_point        start;
        Clock::time_point        lastStep;
        double                   duration = 1.7;
        Vector2D                 wind;      // unit direction the petals are blown to
        std::mt19937             rng;

        // opening: the close simulation, recorded and played backwards
        bool                     reverse = false;
        double                   total   = 0; // s, of the recorded simulation
        double                   speed   = 1; // playback rate of the track
        int                      frames  = 0;
        std::vector<SFrame>      track;  // frames * petals
        PHLWINDOWREF             window; // hidden until the petals have assembled it
        SP<CEventLoopTimer>      refresh; // retakes the snapshot while the petals fly in

        ~SBurst() {
            if (refresh) {
                refresh->cancel();
                g_pEventLoopManager->removeTimer(refresh);
            }
        }
    };

    struct SPending {
        PHLWINDOWREF          window;
        SP<CEventLoopTimer>   timer;
    };

    struct SState {
        HANDLE                          handle    = nullptr;
        CFunctionHook*                  createHook = nullptr;
        CFunctionHook*                  renderHook = nullptr;
        std::vector<UP<SBurst>>         bursts;
        std::vector<SPending>           pending; // opened, waiting for their first real frame
        std::vector<PHLWINDOWREF>       hidden;  // opened, not rendered until assembled
        bool                            snapshotting = false;
        CBox                            lastDrawn; // global logical

        SP<Config::Values::CStringValue> style;
        SP<Config::Values::CIntValue>    maxPetals, bloodMaxDrops, durationMs, spreadMs, open, openDurationMs, openSpreadMs, openDelayMs, openRefreshMs, bloodDurationMs, bloodSpreadMs;
        SP<Config::Values::CFloatValue>  size, windX, windY, windStrength, tint, openSpeed, bloodSize, bloodGravity;
        SP<Config::Values::CColorValue>  color, bloodColor;

        CHyprColor                      schemeColor{0xF5 / 255.0, 0xC2 / 255.0, 0xE7 / 255.0, 1.0};
        std::filesystem::file_time_type schemeMtime{};
        Clock::time_point               schemeChecked{};

        SP<CShader>                     shader;
        GLint locProj = -1, locTex = -1, locUvOrigin = -1, locUvSpan = -1, locMorph = -1, locAlpha = -1, locTint = -1, locTintAmt = -1, locBack = -1,
              locBlood = -1, locSoak = -1, locBloodColor = -1;

        CHyprSignalListener             stageListener, preChecksListener, openListener, destroyListener;
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
uniform float blood;      // 1 = blood style
uniform float soak;       // 0..1, how far the blood ran down this cell
uniform vec4 bloodColor;  // premultiplied, opaque
in vec2 v_local;
layout(location = 0) out vec4 fragColor;

// Falling drop (y down): pointed top, round bottom
float drop(vec2 q) {
    float w = mix(0.05, 1.0, smoothstep(-1.0, 0.25, q.y));
    return length(vec2(q.x / w, q.y - 0.05)) - 0.93;
}

void bloodMain(vec2 q) {
    float d = drop(q);
    float aa = max(fwidth(d), 1e-4);
    float shape = clamp(0.5 - d / aa, 0.0, 1.0);
    float mask = mix(1.0, shape, morph);
    if (mask <= 0.0)
        discard;

    vec4 c = texture(tex, uvOrigin + v_local * uvSpan);

    // The blood runs down the cell: a wavy front from its top to its bottom
    float wave = 0.07 * sin(v_local.x * 9.0 + uvOrigin.x * 57.0 + uvOrigin.y * 23.0);
    float front = soak * 1.3 - 0.15 + wave;
    float wet = smoothstep(v_local.y - 0.12, v_local.y + 0.12, front);

    // Shading: darker towards the drop's edge, a glossy highlight once it is a drop, and a darker
    // line on the front of the blood running down
    vec3 b = bloodColor.rgb;
    float edge = morph * smoothstep(-0.5, 0.0, d);
    b *= 1.0 - 0.5 * edge;
    b *= 1.0 - 0.35 * (1.0 - morph) * smoothstep(0.25, 0.0, abs(front - v_local.y)) * step(soak, 0.999);
    float hl = morph * (1.0 - smoothstep(0.05, 0.25, length(q - vec2(-0.28, 0.4))));
    b = mix(b, vec3(1.0), hl * 0.45);

    c = mix(c, vec4(b, 1.0), wet);
    fragColor = c * mask * alpha;
}

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
    if (blood > 0.5) {
        bloodMain(q);
        return;
    }
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

    eStyle style() {
        const std::string s = g->style->value();
        if (s == "petals" || s == "petal")
            return STYLE_PETALS;
        if (s == "blood")
            return STYLE_BLOOD;
        return STYLE_OFF;
    }

    bool active() {
        static auto PANIMENABLED = CConfigValue<Config::INTEGER>("animations:enabled");
        return *PANIMENABLED && style() != STYLE_OFF;
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

    // Half the diagonal of a piece's quad at full growth, to bound it whatever its rotation
    double petalRadius(const SBurst& b) {
        if (b.style == STYLE_BLOOD)
            return b.cell * BLOOD_GROW * (1.0 + BLOOD_STRETCH) * 0.7072 + 2.0;
        return b.cell * GROW * 0.7072 + 2.0;
    }

    bool step(SBurst& b, double t, double dt);

    // reverse: an opening window, simulated now and played backwards later
    SBurst* startBurst(PHLWINDOW window, SP<Render::IFramebuffer> fb, bool reverse) {
        const auto mon = window->m_monitor.lock();
        if (!mon || !fb || !fb->getTexture())
            return nullptr;

        static auto PBORDER = CConfigValue<Config::INTEGER>("general:border_size");
        const double border  = *PBORDER + 1.0;

        const Vector2D wpos = window->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT) - Vector2D{border, border};
        const Vector2D wsize = window->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT) + Vector2D{border * 2, border * 2};
        if (wsize.x < 4 || wsize.y < 4)
            return nullptr;

        auto b       = makeUnique<SBurst>();
        b->style      = style();
        const bool blood = b->style == STYLE_BLOOD;
        b->fb         = fb;
        b->tex        = fb->getTexture();
        b->snapSizePx = mon->m_transformedSize;
        b->reverse    = reverse;
        b->duration   = std::max<int64_t>((reverse ? g->openDurationMs : blood ? g->bloodDurationMs : g->durationMs)->value(), 100) / 1000.0;
        // played backwards, petals blown against the wind arrive with it
        b->wind       = reverse ? windDir() * -1.0 : windDir();
        b->start = b->lastStep = Clock::now();
        b->rng.seed(std::random_device{}());

        // Grid: about `size` px cells, grown on big windows to stay under max_pieces
        double       cell = std::max<double>((blood ? g->bloodSize : g->size)->value(), 8.0);
        const double maxN = std::max<int64_t>((blood ? g->bloodMaxDrops : g->maxPetals)->value(), 4);
        if ((wsize.x / cell) * (wsize.y / cell) > maxN)
            cell = std::sqrt(wsize.x * wsize.y / maxN);
        const int    cols = std::max(1, sc<int>(std::round(wsize.x / cell)));
        const int    rows = std::max(1, sc<int>(std::round(wsize.y / cell)));
        const double cw = wsize.x / cols, ch = wsize.y / rows;
        b->cell = std::max(cw, ch);
        // square quads (petals are drawn square), sampling a square patch of the snapshot
        b->uvCell = Vector2D{b->cell * mon->m_scale / b->snapSizePx.x, b->cell * mon->m_scale / b->snapSizePx.y};

        const Vector2D dir    = b->wind;
        const Vector2D centre = wpos + wsize / 2.0;
        const double   extent = std::abs(dir.x) * wsize.x / 2.0 + std::abs(dir.y) * wsize.y / 2.0;
        const double   spread = std::max<int64_t>((reverse ? g->openSpreadMs : blood ? g->bloodSpreadMs : g->spreadMs)->value(), 0) / 1000.0;
        const Vector2D perp   = {-dir.y, dir.x};

        auto&          rng = b->rng;

        // Blood: each column runs down with its own lag (most trail behind, a few drips run
        // ahead), so it comes down in streaks. Once the window is soaked it drains from the bottom.
        std::vector<double> colLag(cols);
        for (auto& lag : colLag)
            lag = spread * 0.35 * (frand(rng, 0, 1) < 0.2 ? frand(rng, 0.0, 0.3) : frand(rng, 0.45, 1.0));
        const double soakSpan   = spread * 0.6;                  // top to bottom
        const double drainStart = soakSpan + spread * 0.35 + SOAK_S; // every cell is soaked by then

        for (int r = 0; r < rows; r++) {
            for (int c = 0; c < cols; c++) {
                SPetal p;
                p.home = p.pos = wpos + Vector2D{(c + 0.5) * cw, (r + 0.5) * ch};
                p.uv           = Vector2D{(p.home.x - mon->m_position.x) * mon->m_scale / b->snapSizePx.x,
                                          (p.home.y - mon->m_position.y) * mon->m_scale / b->snapSizePx.y};

                if (blood) {
                    const double down = (r + 0.5) / rows; // 0 top .. 1 bottom
                    p.soakAt          = down * soakSpan + colLag[c];
                    p.release = std::max(p.soakAt + SOAK_S + 0.04, drainStart + (1.0 - down) * spread * 0.5 + colLag[c] * 0.4 + frand(rng, 0.0, 0.06));
                    // a splash: thrown every way (up a lot), out from the window's centre, then
                    // the air slows it and gravity takes over
                    const Vector2D off = p.home - centre;
                    const double   len = std::sqrt(off.x * off.x + off.y * off.y);
                    const Vector2D out = len > 1e-6 ? off / len : Vector2D{0, 0};
                    const double   ang = frand(rng, 0, 2 * PI);
                    const double   up  = frand(rng, 0, 1) < 0.45 ? frand(rng, 250, 650) : 0.0;
                    p.vel  = Vector2D{std::cos(ang), std::sin(ang)} * frand(rng, 60, 380) + out * frand(rng, 40, 220) + Vector2D{0.0, -up};
                    p.gust = frand(rng, 0.75, 1.2);
                    // mostly small droplets, a few big ones
                    p.drop = frand(rng, 0, 1) < 0.15 ? frand(rng, 0.8, 1.0) : frand(rng, 0.3, 0.65);
                    p.spin = p.tumbleRate = p.flutterPhase = p.flutterFreq = p.flutterAmp = 0;
                    b->petals.push_back(p);
                    continue;
                }

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

        if (reverse) {
            double lastRelease = 0;
            for (const auto& p : b->petals)
                lastRelease = std::max(lastRelease, p.release);
            b->total  = lastRelease + b->duration;
            b->frames = sc<int>(std::ceil(b->total * TRACK_FPS)) + 1;
            b->track.resize(sc<size_t>(b->frames) * b->petals.size());
            for (int f = 0; f < b->frames; f++) {
                if (f > 0)
                    step(*b, f / TRACK_FPS, 1.0 / TRACK_FPS);
                for (size_t i = 0; i < b->petals.size(); i++) {
                    const auto& p = b->petals[i];
                    b->track[f * b->petals.size() + i] = {p.pos,           sc<float>(p.rot),  sc<float>(p.tumble), sc<float>(p.alpha),
                                                          sc<float>(p.scale), sc<float>(p.soak), sc<float>(p.stretch)};
                }
            }
            b->speed = std::clamp<double>(g->openSpeed->value(), 0.1, 10.0);
            b->start = Clock::now(); // the simulation above took some time
        }

        g->bursts.emplace_back(std::move(b));
        return g->bursts.back().get();
    }

    // Opening windows: show the recorded close simulation, backwards. False once assembled.
    bool playBack(SBurst& b, Clock::time_point now) {
        const double t = std::chrono::duration<double>(now - b.start).count() * b.speed;
        if (t >= b.total)
            return false;
        const int f = std::clamp(sc<int>((b.total - t) * TRACK_FPS), 0, b.frames - 1);
        for (size_t i = 0; i < b.petals.size(); i++) {
            auto&       p  = b.petals[i];
            const auto& fr = b.track[f * b.petals.size() + i];
            p.pos          = fr.pos;
            p.rot          = fr.rot;
            p.tumble       = fr.tumble;
            p.alpha        = fr.alpha;
            p.scale        = fr.scale;
            p.soak         = fr.soak;
            p.stretch      = fr.stretch;
        }
        return true;
    }

    // Blood: soak the cells as the blood runs down, then drop them
    bool stepBlood(SBurst& b, double t, double dt) {
        const double gravity = g->bloodGravity->value();
        const double drag    = std::exp(-1.8 * dt);
        bool         alive   = false;

        for (auto& p : b.petals) {
            const double age = t - p.release;
            if (age < 0) {
                p.pos  = p.home;
                p.soak = std::clamp((t - p.soakAt) / SOAK_S, 0.0, 1.0);
                alive  = true;
                continue;
            }
            if (age > b.duration) {
                p.alpha = 0;
                continue;
            }
            alive  = true;
            p.soak = 1;

            p.vel = p.vel * drag;
            p.vel.y += gravity * p.gust * dt;
            p.pos = p.pos + p.vel * dt;

            // the drop leans and stretches along its fall
            const double speed = std::sqrt(p.vel.x * p.vel.x + p.vel.y * p.vel.y);
            p.rot              = speed > 1e-3 ? std::atan2(-p.vel.x, p.vel.y) : 0.0;
            p.stretch          = 1.0 + BLOOD_STRETCH * std::clamp(speed / 1800.0, 0.0, 1.0);

            const double life     = age / b.duration;
            const double fadeFrom = b.reverse ? 0.85 : 0.55;
            p.alpha               = 1.0 - std::clamp((life - fadeFrom) / (1.0 - fadeFrom), 0.0, 1.0);
            p.alpha *= p.alpha;
            p.scale = 1.0 - 0.4 * life;
        }
        return alive;
    }

    bool step(SBurst& b, Clock::time_point now) {
        if (b.reverse)
            return playBack(b, now);
        const double dt = std::clamp(std::chrono::duration<double>(now - b.lastStep).count(), 0.0, MAX_DT);
        const double t  = std::chrono::duration<double>(now - b.start).count();
        b.lastStep      = now;
        if (dt <= 0)
            return true;
        return step(b, t, dt);
    }

    // Advance the simulation to close time t; returns false once every petal is gone
    bool step(SBurst& b, double t, double dt) {
        if (b.style == STYLE_BLOOD)
            return stepBlood(b, t, dt);
        const Vector2D dir      = b.wind;
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
            // Closing petals fade out over the second half of their flight. Opening ones play this
            // backwards, so they only fade in over the first 15%: otherwise they spend most of their
            // flight faint, where the rim glow takes over and they look milky instead of see-through.
            const double fadeFrom = b.reverse ? 0.85 : 0.4;
            p.alpha               = 1.0 - std::clamp((life - fadeFrom) / (1.0 - fadeFrom), 0.0, 1.0);
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
            HyprlandAPI::addNotification(g->handle, "[windowfx] shader failed to compile", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
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
        g->locBlood     = glGetUniformLocation(prog, "blood");
        g->locSoak      = glGetUniformLocation(prog, "soak");
        g->locBloodColor = glGetUniformLocation(prog, "bloodColor");
        return true;
    }

    struct SPetalDraw {
        CBox  boxPx; // with rot
        float uvOrigin[2], uvSpan[2];
        float morph, alpha, back, soak;
    };

    struct SBurstDraw {
        SP<Render::ITexture>    tex;
        bool                    blood = false;
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
            const auto blood = g_pHyprRenderer->getConvertedColor(ctx, CHyprColor(sc<uint64_t>(g->bloodColor->value())));
            glUniform4f(g->locBloodColor, blood.r, blood.g, blood.b, 1.0F);

            g_pHyprOpenGL->blend(true);
            g_pHyprOpenGL->blendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            glActiveTexture(GL_TEXTURE0);
            glBindVertexArray(g->shader->getUniformLocation(SHADER_SHADER_VAO));

            for (const auto& burst : m_bursts) {
                glBindTexture(GL_TEXTURE_2D, burst.tex->m_texID);
                glUniform1f(g->locBlood, burst.blood ? 1.F : 0.F);
                for (const auto& p : burst.petals) {
                    const auto proj = g_pHyprRenderer->projectBoxToTarget(ctx, p.boxPx);
                    glUniformMatrix3fv(g->locProj, 1, GL_TRUE, proj.getMatrix().data());
                    glUniform2f(g->locUvOrigin, p.uvOrigin[0], p.uvOrigin[1]);
                    glUniform2f(g->locUvSpan, p.uvSpan[0], p.uvSpan[1]);
                    glUniform1f(g->locMorph, p.morph);
                    glUniform1f(g->locAlpha, p.alpha);
                    glUniform1f(g->locBack, p.back);
                    glUniform1f(g->locSoak, p.soak);
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
            return "CWindowFxPassElement";
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
            d.blood         = b->style == STYLE_BLOOD;
            const double r  = petalRadius(*b);

            for (const auto& p : b->petals) {
                if (p.alpha <= 0)
                    continue;
                if (CBox{p.pos.x - r, p.pos.y - r, 2 * r, 2 * r}.intersection(monBox).empty())
                    continue;

                if (d.blood) {
                    // a plain cell on its spot (soaking), a drop once it falls, stretched along its fall
                    const Vector2D away = p.pos - p.home;
                    const double   m    = std::clamp(std::sqrt(away.x * away.x + away.y * away.y) / (b->cell * 0.4), 0.0, 1.0);
                    const double   mm   = m * m * (3 - 2 * m);
                    const double   grow = 1.0 + (BLOOD_GROW * p.drop - 1.0) * mm; // shrinks to a droplet
                    const double   side = b->cell * grow * p.scale;
                    const double   sy   = side * p.stretch;
                    const double   sx   = side / std::sqrt(p.stretch);

                    SPetalDraw     pd;
                    const Vector2D c = (p.pos - mon->m_position) * mon->m_scale;
                    pd.boxPx         = CBox{c.x - sx * mon->m_scale / 2.0, c.y - sy * mon->m_scale / 2.0, sx * mon->m_scale, sy * mon->m_scale};
                    pd.boxPx.rot     = p.rot;
                    const double us  = b->uvCell.x * grow, vs = b->uvCell.y * grow;
                    pd.uvOrigin[0]   = sc<float>(p.uv.x - us / 2.0);
                    pd.uvOrigin[1]   = sc<float>(p.uv.y - vs / 2.0);
                    pd.uvSpan[0]     = sc<float>(us);
                    pd.uvSpan[1]     = sc<float>(vs);
                    pd.morph         = sc<float>(mm);
                    pd.alpha         = sc<float>(p.alpha);
                    pd.back          = 0.F;
                    pd.soak          = sc<float>(p.soak);
                    d.petals.push_back(pd);
                    continue;
                }

                // A petal is a plain cell on its spot and takes its shape (growing over its
                // neighbours) as it moves away: packed petals overlapping would draw a darker heart
                // pattern over see-through windows. By distance, not time, since landing petals
                // slow down and hover right above their spot.
                const Vector2D away  = p.pos - p.home;
                const double   m     = std::clamp(std::sqrt(away.x * away.x + away.y * away.y) / (b->cell * 0.6), 0.0, 1.0);
                const double mm    = m * m * (3 - 2 * m);
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
                pd.soak          = 0.F;
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

    bool isHidden(const PHLWINDOW& w);
    void unhide(const PHLWINDOWREF& ref);

    SP<Desktop::CWindowFadeout> hkCreate(PHLWINDOW window, SP<Render::IFramebuffer> snapshot, float sourceAlpha, SP<Render::IFramebuffer> workspaceSnapshot) {
        // closed while still assembling: its snapshot is empty (it was hidden), just drop the petals
        if (window && isHidden(window)) {
            const PHLWINDOWREF ref = window;
            std::erase_if(g->bursts, [&ref](const UP<SBurst>& b) { return b->reverse && b->window == ref; });
            unhide(ref);
            return nullptr;
        }
        if (active() && window && snapshot && snapshot->getTexture() && !window->backend().traits().suggestsNoBorder) {
            const auto before = g->bursts.size();
            startBurst(window, snapshot, false);
            if (g->bursts.size() > before) {
                g_pHyprRenderer->damageBox(burstsBox());
                return nullptr; // no stock fadeout: the petals replace it
            }
        }
        return (*(origCreate)g->createHook->m_original)(window, snapshot, sourceAlpha, workspaceSnapshot);
    }

    bool isHidden(const PHLWINDOW& w) {
        return std::ranges::any_of(g->hidden, [&w](const PHLWINDOWREF& h) { return h.lock() == w; });
    }

    void unhide(const PHLWINDOWREF& ref) {
        std::erase_if(g->hidden, [&ref](const PHLWINDOWREF& h) { return h.expired() || h == ref; });
        if (const auto w = ref.lock())
            g_pHyprRenderer->damageWindow(w, true);
    }

    using origRenderWindow = void (*)(void*, Render::CRenderContext&, PHLWINDOW, PHLMONITOR, const Render::SWindowRenderPresentation&, const Time::steady_tp&, bool,
                                      Render::eRenderPassMode, bool, bool);

    // Opening windows are not drawn until their petals have assembled them (except into our snapshot)
    void hkRenderWindow(void* thisptr, Render::CRenderContext& ctx, PHLWINDOW window, PHLMONITOR monitor, const Render::SWindowRenderPresentation& presentation,
                        const Time::steady_tp& now, bool decorate, Render::eRenderPassMode mode, bool ignorePosition, bool standalone) {
        if (!g->hidden.empty() && isHidden(window)) {
            if (!g->snapshotting)
                return;
            // Our snapshot of an opening window: its fade-in has barely started, which would leave
            // the petals nearly empty. Draw it fully faded in (its own opacity rules still apply).
            auto shown         = presentation;
            shown.fadeAlpha    = 1.F;
            shown.alphaVisible = true;
            (*(origRenderWindow)g->renderHook->m_original)(thisptr, ctx, window, monitor, shown, now, decorate, mode, ignorePosition, standalone);
            return;
        }
        (*(origRenderWindow)g->renderHook->m_original)(thisptr, ctx, window, monitor, presentation, now, decorate, mode, ignorePosition, standalone);
    }

    // hyprliquid (Liquid Glass on kitty) draws its glass while the surface is drawn, refracting what
    // is behind it. In our snapshot nothing is behind, so it would bake an opaque dark slab into the
    // petals. Closing windows never get it (hyprliquid drops them before Hyprland snapshots), so turn
    // it off around our snapshots too, and both look alike.
    bool* hyprliquidEnabled() {
        static const std::string NAME = "plugin:hyprliquid:enabled";
        const auto               opt  = Config::mgr()->getConfigValue(NAME);
        if (!opt.dataptr || !opt.type || std::type_index(*opt.type) != typeid(Config::BOOL))
            return nullptr; // not loaded (reading a missing option would assert)
        return CConfigValue<Config::BOOL>(NAME).ptr();
    }

    SP<Render::IFramebuffer> snapshot(PHLWINDOW w) {
        bool* const liquid = hyprliquidEnabled();
        const bool  was    = liquid && *liquid;
        if (liquid)
            *liquid = false;
        g->snapshotting = true;
        const auto fb   = g_pHyprRenderer->makeSnapshotFB(w);
        g->snapshotting = false;
        if (liquid)
            *liquid = was;
        return fb && fb->getTexture() ? fb : nullptr;
    }

    // Event loop, outside any render: the client may have drawn more since the last snapshot
    void refreshSnapshot(const PHLWINDOWREF& ref, const SP<CEventLoopTimer>& self) {
        const auto it = std::ranges::find_if(g->bursts, [&ref](const UP<SBurst>& b) { return b->reverse && b->window == ref; });
        const auto w  = ref.lock();
        if (it == g->bursts.end() || !w || !w->mapped())
            return;
        if (const auto fb = snapshot(w)) {
            (*it)->fb  = fb;
            (*it)->tex = fb->getTexture();
        }
        self->updateTimeout(std::chrono::milliseconds(std::max<int64_t>(g->openRefreshMs->value(), 16)));
    }

    // Runs from the event loop, outside any render: snapshot the new window and start assembling it
    void assemble(const PHLWINDOWREF& ref) {
        const auto w = ref.lock();
        if (!w || !w->mapped() || !active()) {
            unhide(ref);
            return;
        }

        // the petals land where the window ends up, fully opaque: skip the stock windowsIn animation
        w->finishAnimation();
        w->presentation().alpha(Desktop::View::WINDOW_ALPHA_FADE)->warp();

        const auto fb = snapshot(w);
        const auto b  = fb ? startBurst(w, fb, true) : nullptr;
        if (!b) {
            unhide(ref);
            return;
        }
        b->window = ref;

        if (const auto every = g->openRefreshMs->value(); every > 0) {
            b->refresh = makeShared<CEventLoopTimer>(
                std::chrono::milliseconds(std::max<int64_t>(every, 16)), [ref](SP<CEventLoopTimer> self, void*) { refreshSnapshot(ref, self); }, nullptr);
            g_pEventLoopManager->addTimer(b->refresh);
        }
        g_pHyprRenderer->damageBox(CBox{w->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT), w->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)});
    }

    void onOpen(PHLWINDOW w) {
        if (!w || !active() || !g->open->value() || !g->renderHook || w->backend().traits().suggestsNoBorder)
            return;

        const PHLWINDOWREF ref = w;
        g->hidden.push_back(ref);

        const auto delay = std::chrono::milliseconds(std::clamp<int64_t>(g->openDelayMs->value(), 0, 1000));
        auto       timer = makeShared<CEventLoopTimer>(
            delay,
            [ref](SP<CEventLoopTimer> self, void*) {
                std::erase_if(g->pending, [&self](const SPending& p) { return p.timer == self; });
                assemble(ref);
            },
            nullptr);
        g->pending.push_back({ref, timer});
        g_pEventLoopManager->addTimer(timer);
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(handle, "[windowfx] built for another Hyprland version, not loading", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[windowfx] version mismatch");
    }

    g         = makeUnique<SState>();
    g->handle = handle;

    using namespace Config::Values;
    g->style          = makeShared<CStringValue>("plugin:windowfx:style", "petals, blood or off", "petals");
    g->maxPetals      = makeShared<CIntValue>("plugin:windowfx:max_pieces", "Maximum pieces per window", 240);
    g->open           = makeShared<CIntValue>("plugin:windowfx:open", "Animate opening windows too", 1);
    g->openDurationMs = makeShared<CIntValue>("plugin:windowfx:open_duration_ms", "Flight time of one piece when opening, in ms", 900);
    g->openSpreadMs   = makeShared<CIntValue>("plugin:windowfx:open_spread_ms", "Delay between the first and last piece landing, in ms", 280);
    g->openDelayMs    = makeShared<CIntValue>("plugin:windowfx:open_delay_ms", "Wait for the client's first frame, in ms", 60);
    g->openRefreshMs  = makeShared<CIntValue>("plugin:windowfx:open_refresh_ms", "Retake the snapshot this often while opening, in ms (0 = never)", 80);
    g->openSpeed      = makeShared<CFloatValue>("plugin:windowfx:open_speed", "Playback speed of the opening animation, 2 is twice as fast", 1.F);
    // petals
    g->size         = makeShared<CFloatValue>("plugin:windowfx:size", "Petal size in logical px", 44.F);
    g->durationMs   = makeShared<CIntValue>("plugin:windowfx:duration_ms", "Flight time of one petal, in ms", 1700);
    g->spreadMs     = makeShared<CIntValue>("plugin:windowfx:spread_ms", "Delay between the first and last petal leaving, in ms", 380);
    g->windX        = makeShared<CFloatValue>("plugin:windowfx:wind_x", "Wind direction, x", 1.F);
    g->windY        = makeShared<CFloatValue>("plugin:windowfx:wind_y", "Wind direction, y (negative is up)", -0.45F);
    g->windStrength = makeShared<CFloatValue>("plugin:windowfx:wind_strength", "Wind speed in logical px/s", 750.F);
    g->tint         = makeShared<CFloatValue>("plugin:windowfx:tint", "How much the petals take the colour, 0..1", 0.3F);
    g->color        = makeShared<CColorValue>("plugin:windowfx:color", "Petal colour, 0 follows the Caelestia scheme primary", 0);
    // blood
    g->bloodColor      = makeShared<CColorValue>("plugin:windowfx:blood_color", "Blood colour", 0xFF8A0012);
    g->bloodSize       = makeShared<CFloatValue>("plugin:windowfx:blood_size", "Blood drop size in logical px", 18.F);
    g->bloodMaxDrops   = makeShared<CIntValue>("plugin:windowfx:blood_max_drops", "Maximum blood drops per window", 1500);
    g->bloodDurationMs = makeShared<CIntValue>("plugin:windowfx:blood_duration_ms", "Fall time of one blood drop, in ms", 1000);
    g->bloodSpreadMs   = makeShared<CIntValue>("plugin:windowfx:blood_spread_ms", "Pace of the blood running down and draining off, in ms", 420);
    g->bloodGravity    = makeShared<CFloatValue>("plugin:windowfx:blood_gravity", "Gravity on blood drops, logical px/s^2", 1900.F);
    for (const SP<IValue>& v : std::initializer_list<SP<IValue>>{
             g->style, g->maxPetals, g->open, g->openDurationMs, g->openSpreadMs, g->openDelayMs, g->openRefreshMs, g->openSpeed, g->size, g->durationMs,
             g->spreadMs, g->windX, g->windY, g->windStrength, g->tint, g->color, g->bloodColor, g->bloodSize, g->bloodMaxDrops, g->bloodDurationMs, g->bloodSpreadMs,
             g->bloodGravity})
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
        HyprlandAPI::addNotification(handle, "[windowfx] could not hook CWindowFadeout::create (" + why + "), not loading", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[windowfx] " + why);
    }

    // Optional: without it only closing windows get petals
    for (const auto& fn : HyprlandAPI::findFunctionsByName(handle, "IHyprRenderer12renderWindow")) {
        g->renderHook = HyprlandAPI::createFunctionHook(handle, fn.address, (void*)&hkRenderWindow);
        if (g->renderHook && !g->renderHook->hook()) {
            HyprlandAPI::removeFunctionHook(handle, g->renderHook);
            g->renderHook = nullptr;
        }
        break;
    }

    g->openListener    = Event::bus()->m_events.window.openLate.listen([](PHLWINDOW w) { onOpen(w); });
    g->destroyListener = Event::bus()->m_events.window.destroy.listen([](PHLWINDOWREF) { std::erase_if(g->hidden, [](const PHLWINDOWREF& h) { return h.expired(); }); });

    g->stageListener = Event::bus()->m_events.render.stage.listen([](const Event::SRenderStageEvent& ev) {
        if (ev.stage == RENDER_LAST_MOMENT && ev.context)
            addPetals(ev.context->get(), ev.monitor);
    });

    // Step the petals once per frame and keep frames coming while they fly (also erases the last one)
    g->preChecksListener = Event::bus()->m_events.render.preChecks.listen([](PHLMONITOR) {
        if (g->bursts.empty() && g->lastDrawn.empty())
            return;
        const auto now = Clock::now();
        std::erase_if(g->bursts, [now](const UP<SBurst>& b) {
            if (step(*b, now))
                return false;
            if (b->reverse)
                unhide(b->window); // assembled: the real window takes over
            return true;
        });
        const CBox current = burstsBox();
        const CBox damage  = boxUnion(current, g->lastDrawn);
        g->lastDrawn       = current;
        if (!damage.empty())
            g_pHyprRenderer->damageBox(damage);
    });

    return {"windowfx", "Closing / opening window animations: petals or blood", "Dralexgon", "1.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (!g)
        return;
    if (!g->lastDrawn.empty())
        g_pHyprRenderer->damageBox(g->lastDrawn);
    for (auto& p : g->pending) {
        p.timer->cancel();
        g_pEventLoopManager->removeTimer(p.timer);
    }
    g->pending.clear();
    for (const auto& h : std::vector<PHLWINDOWREF>(g->hidden))
        unhide(h);
    g->bursts.clear();
    if (g->shader) {
        g_pHyprOpenGL->makeEGLCurrent();
        g->shader->destroy();
    }
    g.reset();
}
