#pragma once

#define WLR_USE_UNSTABLE

#include "globals.hpp"
#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/render/Framebuffer.hpp>
#include <hyprland/src/helpers/AnimatedVariable.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <vector>

namespace Render {
    class CRenderContext;
}

// The workspace grid shown by hyprexpo:expo. One overview at a time, on the focused monitor.
class COverview {
  public:
    COverview(PHLWORKSPACE startedOn_, bool swipe = false);
    ~COverview();

    // Called instead of Hyprland's renderWorkspace for pMonitor: queues the grid in the frame's pass
    void render(Render::CRenderContext& ctx);
    void damage();
    void onPreRender();

    void setClosing(bool closing);

    void onSwipeUpdate(double delta);
    void onSwipeEnd();

    // switchToSelection = false closes without changing workspace
    void     close(bool switchToSelection = true);
    void     selectHoveredWorkspace();
    uint32_t selectedWorkspaceID() const; // 0 = an empty tile

    bool          blockOverviewRendering = false;

    PHLMONITORREF pMonitor;
    bool          m_isSwiping = false;

    struct STile {
        SP<Render::IFramebuffer> fb;
        uint32_t                 workspaceID = 0; // numbered workspace, 0 = empty slot (opens the next empty workspace)
        PHLWORKSPACEREF          pWorkspace;
    };

  private:
    void               redrawID(int id);
    void               redrawAll();
    void               onWorkspaceChange();
    std::vector<uint32_t> pickWorkspaceIDs(uint32_t currentID) const;

    int                SIDE_LENGTH = 3;
    int                GAP_WIDTH   = 5;
    CHyprColor         BG_COLOR    = CHyprColor{0.1, 0.1, 0.1, 1.0};

    Vector2D           lastMousePosLocal = Vector2D{};

    int                openedID  = -1;
    int                closeOnID = -1;

    std::vector<STile> images;

    PHLWORKSPACE       startedOn;

    PHLANIMVAR<Vector2D> size;
    PHLANIMVAR<Vector2D> pos;

    bool               closing = false;

    CHyprSignalListener mouseMoveHook;
    CHyprSignalListener mouseButtonHook;
    CHyprSignalListener touchMoveHook;
    CHyprSignalListener touchDownHook;

    bool               swipe = false;
};

inline std::unique_ptr<COverview> g_pOverview;
