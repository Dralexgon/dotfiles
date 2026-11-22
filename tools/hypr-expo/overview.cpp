#include "overview.hpp"
#include <algorithm>
#include <cmath>
// beginRender() and renderAllClientsForWorkspace() are protected
#define protected public
#include <hyprland/src/render/Renderer.hpp>
#undef protected
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/SceneResources.hpp>
#include <hyprland/src/render/scene/SceneSelection.hpp>
#include <hyprland/src/render/pass/ClearPassElement.hpp>
#include <hyprland/src/render/pass/TexPassElement.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/config/shared/animation/AnimationTree.hpp>
#include <hyprland/src/animation/AnimationManager.hpp>
#include <hyprland/src/animation/WorkspaceAnimationController.hpp>
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/helpers/time/Time.hpp>
#include <hyprland/src/helpers/varlist/VarList.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>
#include <hyprland/src/state/workspace/State.hpp>
#include <hyprland/src/state/workspace/Resolver.hpp>

using namespace Hyprutils::String;

static uint32_t numberedIDOf(const PHLWORKSPACE& ws) {
    if (!ws || ws->type() != Workspace::eWorkspaceType::NORMAL)
        return 0;
    return ws->numberedID().value_or(0);
}

static PHLWORKSPACE workspaceByID(uint32_t id) {
    if (id == 0)
        return nullptr;
    for (const auto& ref : State::Workspace::state()->workspaces()) {
        const auto WS = ref.lock();
        if (numberedIDOf(WS) == id)
            return WS;
    }
    return nullptr;
}

// "1", "r+2", "name:x"... resolved to a numbered workspace, 0 if it is not one
static uint32_t numberedFromString(const std::string& in, PHLMONITOR monitor) {
    const auto TARGET = State::Workspace::resolver()->getWorkspaceTargetFromString(in, monitor);
    if (!TARGET.valid() || !TARGET.id)
        return 0;
    const auto NUMBERED = std::get_if<Workspace::SWorkspaceNumberedID>(&*TARGET.id);
    return NUMBERED ? NUMBERED->value : 0;
}

static void damageMonitor(WP<Hyprutils::Animation::CBaseAnimatedVariable> thisptr) {
    if (g_pOverview)
        g_pOverview->damage();
}

COverview::~COverview() {
    Render::GL::g_pHyprOpenGL->makeEGLCurrent();
    images.clear(); // otherwise we get a vram leak
    Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_UNKNOWN);
    if (pMonitor)
        pMonitor->m_blurFBDirty = true;
}

// Which numbered workspaces fill the grid, row by row. 0 = empty slot.
std::vector<uint32_t> COverview::pickWorkspaceIDs(uint32_t currentID) const {
    static const CConfigValue<Config::INTEGER> PSKIP("plugin:hyprexpo:skip_empty");
    static const CConfigValue<Config::STRING>  PMETHOD("plugin:hyprexpo:workspace_method");

    const size_t                               COUNT = SIDE_LENGTH * SIDE_LENGTH;
    std::vector<uint32_t>                      ids(COUNT, 0);

    // "center current" (current workspace in the middle) or "first <workspace>" (grid starts there)
    bool     center  = true;
    uint32_t startID = currentID;
    CVarList method{*PMETHOD, 0, 's', true};
    if (method.size() < 2)
        Log::logger->log(Log::ERR, "[hyprexpo] invalid workspace_method");
    else {
        center = method[0] == "center";
        if (const auto ID = numberedFromString(method[1], pMonitor.lock()); ID != 0)
            startID = ID;
    }

    if (*PSKIP) {
        // only the workspaces that exist on this monitor
        std::vector<uint32_t> existing;
        for (const auto& ref : State::Workspace::state()->workspaces()) {
            const auto WS = ref.lock();
            if (WS && WS->m_monitor == pMonitor && numberedIDOf(WS) != 0)
                existing.push_back(numberedIDOf(WS));
        }
        if (currentID != 0)
            existing.push_back(currentID);
        std::ranges::sort(existing);
        existing.erase(std::unique(existing.begin(), existing.end()), existing.end());

        size_t first = 0;
        if (center) {
            const auto   IT    = std::ranges::find(existing, startID);
            const size_t INDEX = IT == existing.end() ? 0 : IT - existing.begin();
            first              = INDEX > (COUNT - 1) / 2 ? INDEX - (COUNT - 1) / 2 : 0;
            if (existing.size() > COUNT)
                first = std::min(first, existing.size() - COUNT);
            else
                first = 0;
        } else
            first = std::ranges::lower_bound(existing, startID) - existing.begin();

        for (size_t i = 0; i < COUNT && first + i < existing.size(); ++i)
            ids[i] = existing[first + i];
    } else {
        uint32_t first = startID;
        if (center)
            first = startID > (COUNT - 1) / 2 ? startID - (COUNT - 1) / 2 : 1;
        first = std::max<uint32_t>(first, 1);
        for (size_t i = 0; i < COUNT; ++i)
            ids[i] = first + i;
    }

    return ids;
}

COverview::COverview(PHLWORKSPACE startedOn_, bool swipe_) : startedOn(startedOn_), swipe(swipe_) {
    const auto PMONITOR = Desktop::focusState()->monitor();
    pMonitor            = PMONITOR;

    static const CConfigValue<Config::INTEGER> PCOLUMNS("plugin:hyprexpo:columns");
    static const CConfigValue<Config::INTEGER> PGAPS("plugin:hyprexpo:gap_size");
    static const CConfigValue<Config::INTEGER> PCOL("plugin:hyprexpo:bg_col");

    SIDE_LENGTH = std::clamp<int>(*PCOLUMNS, 1, 10);
    GAP_WIDTH   = std::max<int>(*PGAPS, 0);
    BG_COLOR    = CHyprColor(*PCOL);

    const auto IDS = pickWorkspaceIDs(numberedIDOf(startedOn));
    images.resize(IDS.size());

    int currentid = 0;
    for (size_t i = 0; i < images.size(); ++i) {
        images[i].workspaceID = IDS[i];
        images[i].pWorkspace  = workspaceByID(IDS[i]);
        if (images[i].pWorkspace && images[i].pWorkspace == startedOn)
            currentid = i;
    }
    openedID = currentid;

    redrawAll();

    // start zoomed on the current workspace, then zoom out to the grid
    Vector2D tileSize = pMonitor->m_size / SIDE_LENGTH;

    Animation::mgr()->createAnimation(pMonitor->m_size * pMonitor->m_size / tileSize, size, Config::animationTree()->getAnimationPropertyConfig("windowsMove"), AVARDAMAGE_NONE);
    Animation::mgr()->createAnimation((-((pMonitor->m_size / (double)SIDE_LENGTH) * Vector2D{currentid % SIDE_LENGTH, currentid / SIDE_LENGTH}) * pMonitor->m_scale) *
                                          (pMonitor->m_size / tileSize),
                                      pos, Config::animationTree()->getAnimationPropertyConfig("windowsMove"), AVARDAMAGE_NONE);

    size->setUpdateCallback(damageMonitor);
    pos->setUpdateCallback(damageMonitor);

    if (!swipe) {
        *size = pMonitor->m_size;
        *pos  = {0, 0};
    }

    Pointer::Cursor::overrideController->setOverride("left_ptr", Pointer::Cursor::CURSOR_OVERRIDE_UNKNOWN);

    lastMousePosLocal = g_pInputManager->getMouseCoordsInternal() - pMonitor->m_position;

    auto onCursorMove = [this](Event::SCallbackInfo& info) {
        if (closing)
            return;

        info.cancelled    = true;
        lastMousePosLocal = g_pInputManager->getMouseCoordsInternal() - pMonitor->m_position;
    };

    auto onCursorSelect = [this](Event::SCallbackInfo& info) {
        if (closing)
            return;

        info.cancelled = true;

        selectHoveredWorkspace();

        close();
    };

    mouseMoveHook = Event::bus()->m_events.input.mouse.move.listen([onCursorMove](Vector2D, Event::SCallbackInfo& info) { onCursorMove(info); });
    touchMoveHook = Event::bus()->m_events.input.touch.motion.listen([onCursorMove](ITouch::SMotionEvent, Event::SCallbackInfo& info) { onCursorMove(info); });

    mouseButtonHook = Event::bus()->m_events.input.mouse.button.listen([onCursorSelect](IPointer::SButtonEvent, Event::SCallbackInfo& info) { onCursorSelect(info); });
    touchDownHook   = Event::bus()->m_events.input.touch.down.listen([onCursorSelect](ITouch::SDownEvent, Event::SCallbackInfo& info) { onCursorSelect(info); });
}

void COverview::selectHoveredWorkspace() {
    if (closing)
        return;

    // get tile x,y
    int x     = std::clamp((int)(lastMousePosLocal.x / pMonitor->m_size.x * SIDE_LENGTH), 0, SIDE_LENGTH - 1);
    int y     = std::clamp((int)(lastMousePosLocal.y / pMonitor->m_size.y * SIDE_LENGTH), 0, SIDE_LENGTH - 1);
    closeOnID = std::clamp(x + y * SIDE_LENGTH, 0, SIDE_LENGTH * SIDE_LENGTH - 1);
}

// Renders one workspace, full size, into its tile framebuffer (offscreen, outside the monitor frame)
void COverview::redrawID(int id) {
    const auto MON = pMonitor.lock();
    if (!MON || !MON->m_output || MON->m_transformedSize.x <= 0 || MON->m_transformedSize.y <= 0)
        return;

    if (MON->m_activeWorkspace != startedOn && !closing) {
        // likely user changed.
        onWorkspaceChange();
    }

    auto& R = *g_pHyprRenderer;
    if (R.context().active())
        return; // can't nest renders, the next damage retries

    id          = std::clamp(id, 0, SIDE_LENGTH * SIDE_LENGTH - 1);
    auto& image = images[id];

    // refresh the workspace, it can appear (or go away) while the overview is open
    if (!image.pWorkspace)
        image.pWorkspace = workspaceByID(image.workspaceID);

    const Vector2D SIZE   = MON->m_transformedSize;
    const auto     FORMAT = MON->useFP16() ? DRM_FORMAT_ABGR16161616F : DRM_FORMAT_ABGR8888;
    const auto     DESC   = MON->workBufferImageDescription();

    Render::GL::g_pHyprOpenGL->makeEGLCurrent();

    if (!image.fb)
        image.fb = R.createFB("hyprexpo tile");
    if (image.fb->m_size != SIZE) {
        image.fb->release();
        if (!image.fb->alloc(SIZE.x, SIZE.y, FORMAT))
            return;
    }
    image.fb->setImageDescription(DESC);

    Render::SRenderOptions options;
    options.sceneResources = makeShared<Render::CSceneResources>(R.createFB("hyprexpo tile blur"), Render::SSceneBufferDescription{.format = FORMAT, .imageDescription = DESC});

    CRegion fakeDamage{0, 0, sc<int>(SIZE.x), sc<int>(SIZE.y)};

    blockOverviewRendering = true;

    if (!R.beginRender(MON, fakeDamage, Render::RENDER_MODE_FULL_FAKE, nullptr, image.fb, true, options)) {
        blockOverviewRendering = false;
        return;
    }

    auto&      ctx = R.context();
    const auto WS  = image.pWorkspace.lock();

    // the current workspace keeps its frame callbacks, so its clients keep drawing (it is the live tile)
    ctx.m_blockSurfaceFeedback = WS != startedOn;

    R.draw(ctx, CClearPassElement::SClearData{CHyprColor(0, 0, 0, 1.0)});
    R.startRenderPass(ctx);

    const auto NOW = Time::steadyNow();
    if (WS && WS->m_monitor == pMonitor)
        R.renderWorkspace(ctx, WS, NOW, Render::eSceneMode::WORKSPACE_WITH_SHELL);
    else
        R.renderAllClientsForWorkspace(ctx, MON, nullptr, NOW); // no workspace (or on another monitor): wallpaper and layers only

    R.endRender();

    blockOverviewRendering = false;
}

void COverview::redrawAll() {
    if (!pMonitor)
        return;
    for (size_t i = 0; i < (size_t)(SIDE_LENGTH * SIDE_LENGTH); ++i) {
        redrawID(i);
    }
}

void COverview::damage() {
    g_pHyprRenderer->damageMonitor(pMonitor.lock());
}

uint32_t COverview::selectedWorkspaceID() const {
    const int ID = closeOnID == -1 ? openedID : closeOnID;
    if (ID < 0 || ID >= (int)images.size())
        return 0;

    return images[ID].workspaceID;
}

void COverview::close(bool switchToSelection) {
    if (closing)
        return;

    const int   ID     = closeOnID == -1 ? openedID : closeOnID;
    const int   SAFEID = std::clamp(ID, 0, SIDE_LENGTH * SIDE_LENGTH - 1);

    const auto& TILE = images[SAFEID];

    Vector2D    tileSize = (pMonitor->m_size / SIDE_LENGTH);

    size->warp();
    pos->warp();

    // zoom back into the selected tile
    *size = pMonitor->m_size * pMonitor->m_size / tileSize;
    *pos  = (-((pMonitor->m_size / (double)SIDE_LENGTH) * Vector2D{SAFEID % SIDE_LENGTH, SAFEID / SIDE_LENGTH}) * pMonitor->m_scale) * (pMonitor->m_size / tileSize);

    closing = true;

    redrawAll();

    if (switchToSelection && (TILE.workspaceID == 0 || TILE.workspaceID != numberedIDOf(pMonitor->m_activeWorkspace))) {
        if (pMonitor->m_activeSpecialWorkspace)
            pMonitor->setSpecialWorkspace(nullptr);

        const auto OLDWS = pMonitor->m_activeWorkspace;

        // an empty tile (skip_empty) opens the next empty workspace
        (void)Config::Actions::changeWorkspace(TILE.workspaceID == 0 ? std::string{"emptynm"} : std::to_string(TILE.workspaceID));

        // no workspace slide: the zoom is the animation
        if (pMonitor->m_activeWorkspace)
            Animation::Workspace::startAnimation(pMonitor->m_activeWorkspace, Animation::Workspace::ANIMATION_TYPE_IN, true, true);
        if (OLDWS && OLDWS != pMonitor->m_activeWorkspace)
            Animation::Workspace::startAnimation(OLDWS, Animation::Workspace::ANIMATION_TYPE_OUT, false, true);

        startedOn = pMonitor->m_activeWorkspace;
    }

    size->setCallbackOnEnd([](auto) { g_pEventLoopManager->doLater([] { g_pOverview.reset(); }); });
}

// Runs before every frame of pMonitor. Frames only come when something on the monitor was damaged
// (a client of the live workspace drew, the zoom animation moved...): refresh the live tile, then
// repaint the whole grid, as the damage was reported for the normal (not overview) layout.
void COverview::onPreRender() {
    redrawID(closing ? (closeOnID == -1 ? openedID : closeOnID) : openedID);
    pMonitor->m_damage.damageEntire(); // no frame scheduling: this frame is already coming
}

void COverview::onWorkspaceChange() {
    if (!valid(startedOn))
        startedOn = pMonitor->m_activeWorkspace;

    const auto ACTIVEID = numberedIDOf(pMonitor->m_activeWorkspace);
    for (size_t i = 0; i < (size_t)(SIDE_LENGTH * SIDE_LENGTH); ++i) {
        if (images[i].workspaceID != ACTIVEID)
            continue;

        openedID = i;
        break;
    }

    closeOnID = openedID;
    if (!closing)
        close();
}

void COverview::render(Render::CRenderContext& ctx) {
    if (pMonitor->m_activeWorkspace != startedOn && !closing) {
        // likely user changed.
        onWorkspaceChange();
    }

    const auto GAPSIZE = (closing ? (1.0 - size->getPercent()) : size->getPercent()) * GAP_WIDTH;

    Vector2D   SIZE = size->value();

    Vector2D   tileRenderSize = (SIZE - Vector2D{GAPSIZE, GAPSIZE} * (SIDE_LENGTH - 1)) / SIDE_LENGTH;

    g_pHyprRenderer->addPassElement(ctx, makeUnique<CClearPassElement>(CClearPassElement::SClearData{BG_COLOR.stripA()}));

    for (size_t y = 0; y < (size_t)SIDE_LENGTH; ++y) {
        for (size_t x = 0; x < (size_t)SIDE_LENGTH; ++x) {
            auto& image = images[x + y * SIDE_LENGTH];
            if (!image.fb)
                continue;

            CBox texbox = {x * tileRenderSize.x + x * GAPSIZE, y * tileRenderSize.y + y * GAPSIZE, tileRenderSize.x, tileRenderSize.y};
            texbox.scale(pMonitor->m_scale).translate(pos->value());
            texbox.round();

            CTexPassElement::SRenderData data;
            data.tex = image.fb->getTexture();
            data.box = texbox;
            g_pHyprRenderer->addPassElement(ctx, makeUnique<CTexPassElement>(std::move(data)));
        }
    }
}

static float lerp(const float& from, const float& to, const float perc) {
    return (to - from) * perc + from;
}

static Vector2D lerp(const Vector2D& from, const Vector2D& to, const float perc) {
    return Vector2D{lerp(from.x, to.x, perc), lerp(from.y, to.y, perc)};
}

void COverview::setClosing(bool closing_) {
    closing = closing_;
}

void COverview::onSwipeUpdate(double delta) {
    m_isSwiping = true;

    static const CConfigValue<Config::INTEGER> PDISTANCE("plugin:hyprexpo:gesture_distance");

    const float PERC = closing ? std::clamp(delta / (double)*PDISTANCE, 0.0, 1.0) : 1.0 - std::clamp(delta / (double)*PDISTANCE, 0.0, 1.0);
    const auto  WORKSPACE_FOCUS_ID = closing && closeOnID != -1 ? closeOnID : openedID;

    Vector2D    tileSize = (pMonitor->m_size / SIDE_LENGTH);

    const auto  SIZEMAX = pMonitor->m_size * pMonitor->m_size / tileSize;
    const auto  POSMAX  = (-((pMonitor->m_size / (double)SIDE_LENGTH) * Vector2D{WORKSPACE_FOCUS_ID % SIDE_LENGTH, WORKSPACE_FOCUS_ID / SIDE_LENGTH}) * pMonitor->m_scale) *
        (pMonitor->m_size / tileSize);

    const auto SIZEMIN = pMonitor->m_size;
    const auto POSMIN  = Vector2D{0, 0};

    size->setValueAndWarp(lerp(SIZEMIN, SIZEMAX, PERC));
    pos->setValueAndWarp(lerp(POSMIN, POSMAX, PERC));
}

void COverview::onSwipeEnd() {
    if (closing || !m_isSwiping)
        return;

    const auto SIZEMIN = pMonitor->m_size;
    const auto SIZEMAX = pMonitor->m_size * pMonitor->m_size / (pMonitor->m_size / SIDE_LENGTH);
    const auto PERC    = (size->value() - SIZEMIN).x / (SIZEMAX - SIZEMIN).x;
    if (PERC > 0.5) {
        close();
        return;
    }
    *size = pMonitor->m_size;
    *pos  = {0, 0};

    m_isSwiping = false;
}
