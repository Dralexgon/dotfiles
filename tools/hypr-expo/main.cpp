// hyprexpo: workspace overview, ported to Hyprland 0.57 (Lua config) from hyprwm/hyprland-plugins,
// which dropped it as unmaintained. See README.md for the config and the Lua functions.

#define WLR_USE_UNSTABLE

#include <unistd.h>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/helpers/time/Time.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/managers/input/trackpad/GestureTypes.hpp>
#include <hyprland/src/managers/input/trackpad/TrackpadGestures.hpp>
#include <hyprland/src/event/EventBus.hpp>

#include <lua.hpp>

#include "globals.hpp"
#include "overview.hpp"
#include "ExpoGesture.hpp"

inline CFunctionHook* g_pRenderWorkspaceHook = nullptr;
typedef void (*origRenderWorkspace)(void*, Render::CRenderContext&, PHLMONITOR, PHLWORKSPACE, const Time::steady_tp&, const CBox&);

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

// The monitor scene draws its workspace through this: while the overview is open, draw the grid instead
static void hkRenderWorkspace(void* thisptr, Render::CRenderContext& ctx, PHLMONITOR pMonitor, PHLWORKSPACE pWorkspace, const Time::steady_tp& now, const CBox& geometry) {
    if (!g_pOverview || g_pOverview->blockOverviewRendering || g_pOverview->pMonitor != pMonitor)
        ((origRenderWorkspace)(g_pRenderWorkspaceHook->m_original))(thisptr, ctx, pMonitor, pWorkspace, now, geometry);
    else
        g_pOverview->render(ctx);
}

static void openOverview() {
    const auto MONITOR = Desktop::focusState()->monitor();
    if (!MONITOR || !MONITOR->m_activeWorkspace)
        return;
    g_pOverview = std::make_unique<COverview>(MONITOR->m_activeWorkspace);
}

static SDispatchResult onExpoDispatcher(std::string arg) {
    if (g_pOverview && g_pOverview->m_isSwiping)
        return {.success = false, .error = "already swiping"};

    if (arg == "select") {
        if (g_pOverview) {
            g_pOverview->selectHoveredWorkspace();
            g_pOverview->close();
        }
        return {};
    }

    if (arg == "toggle") {
        if (g_pOverview)
            g_pOverview->close();
        else
            openOverview();
        return {};
    }

    if (arg == "off" || arg == "close" || arg == "disable") {
        if (g_pOverview)
            g_pOverview->close();
        return {};
    }

    // "on", "open", "enable"...
    if (!g_pOverview)
        openOverview();
    return {};
}

// hl.plugin.hyprexpo.expo("toggle" | "on" | "off" | "select")
static int luaExpo(lua_State* L) {
    const auto RESULT = onExpoDispatcher(luaL_optstring(L, 1, "toggle"));
    if (!RESULT.success)
        return luaL_error(L, "%s", RESULT.error.c_str());
    return 0;
}

struct SRegisteredGesture {
    size_t                    fingers;
    eTrackpadGestureDirection direction;
};
static std::vector<SRegisteredGesture> g_gestures;

// hl.plugin.hyprexpo.gesture(fingers, direction): swipe to open/close the overview, following the fingers.
// Gestures are cleared on config reload and re-added by the config.
static int luaGesture(lua_State* L) {
    const auto FINGERS = luaL_checkinteger(L, 1);
    const auto DIRSTR  = std::string{luaL_checkstring(L, 2)};

    if (FINGERS <= 1 || FINGERS >= 10)
        return luaL_error(L, "hyprexpo.gesture: invalid finger count %d", (int)FINGERS);

    const auto DIRECTION = g_pTrackpadGestures->dirForString(DIRSTR);
    if (DIRECTION == TRACKPAD_GESTURE_DIR_NONE)
        return luaL_error(L, "hyprexpo.gesture: invalid direction %s", DIRSTR.c_str());

    const auto RESULT = g_pTrackpadGestures->addGesture(makeUnique<CExpoGesture>(), FINGERS, DIRECTION, Input::HL_MODIFIER_NONE, 1.F, false);
    if (!RESULT)
        return luaL_error(L, "hyprexpo.gesture: %s", RESULT.error().c_str());

    g_gestures.push_back({(size_t)FINGERS, DIRECTION});
    return 0;
}

static void failNotif(const std::string& reason) {
    HyprlandAPI::addNotification(PHANDLE, "[hyprexpo] Failure in initialization: " + reason, CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
}

// Finds a member function by its demangled name and an argument it takes, e.g. ("Render::IHyprRenderer::renderWorkspace(", "CBox const&")
static CFunctionHook* hookFunction(const std::string& name, const std::string& qualified, const std::string& argument, void* destination) {
    for (const auto& fn : HyprlandAPI::findFunctionsByName(PHANDLE, name)) {
        if (!fn.demangled.starts_with(qualified) || !fn.demangled.contains(argument) || !fn.demangled.ends_with(")")) // not the [clone .cold] parts
            continue;
        const auto HOOK = HyprlandAPI::createFunctionHook(PHANDLE, fn.address, destination);
        if (!HOOK || !HOOK->hook()) {
            failNotif("could not hook " + qualified + argument);
            throw std::runtime_error("[hyprexpo] could not hook " + qualified + argument);
        }
        return HOOK;
    }
    failNotif("no function " + qualified + argument);
    throw std::runtime_error("[hyprexpo] no function " + qualified + argument);
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        failNotif("Version mismatch (headers ver is not equal to running hyprland ver)");
        throw std::runtime_error("[hyprexpo] Version mismatch");
    }

    g_pRenderWorkspaceHook = hookFunction("renderWorkspace", "Render::IHyprRenderer::renderWorkspace(", "CBox const&", (void*)hkRenderWorkspace);

    // A frame is coming for the overview's monitor (something on it changed, or the zoom moved)
    static auto P = Event::bus()->m_events.render.pre.listen([](PHLMONITOR monitor) {
        if (g_pOverview && g_pOverview->pMonitor == monitor)
            g_pOverview->onPreRender();
    });

    HyprlandAPI::addDispatcherV2(PHANDLE, "hyprexpo:expo", ::onExpoDispatcher);
    HyprlandAPI::addLuaFunction(PHANDLE, "hyprexpo", "expo", ::luaExpo);
    HyprlandAPI::addLuaFunction(PHANDLE, "hyprexpo", "gesture", ::luaGesture);

    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<Config::Values::CIntValue>("plugin:hyprexpo:columns", "columns", 3));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<Config::Values::CIntValue>("plugin:hyprexpo:gap_size", "gap size", 5));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<Config::Values::CColorValue>("plugin:hyprexpo:bg_col", "background color", 0xFF111111));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<Config::Values::CStringValue>("plugin:hyprexpo:workspace_method", "workspace method", "center current"));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<Config::Values::CIntValue>("plugin:hyprexpo:skip_empty", "skip empty workspaces", 0));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<Config::Values::CIntValue>("plugin:hyprexpo:gesture_distance", "gesture distance", 200));

    return {"hyprexpo", "A plugin for an overview", "Vaxry, ported by Dralexgon", "1.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_pOverview.reset();

    // the gestures point into this plugin's code
    for (const auto& g : g_gestures)
        (void)g_pTrackpadGestures->removeGesture(g.fingers, g.direction, Input::HL_MODIFIER_NONE, 1.F, false);
    g_gestures.clear();
}
