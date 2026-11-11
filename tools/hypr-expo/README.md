# hypr-expo

Workspace overview for Hyprland: a grid of live workspace previews, with a zoom in and out of the current one.

This is **hyprexpo** from [hyprwm/hyprland-plugins](https://github.com/hyprwm/hyprland-plugins) (BSD-3, see `LICENSE`), which upstream dropped as unmaintained in May 2026 ("all: drop unmaintained plugins"). It is ported here to Hyprland 0.57 and its Lua config.

It is built against `pkgs.hyprland` and installed to `/etc/hypr/plugins/hyprexpo.so` by `nixos/modules/desktop/caelestia.nix`, then loaded by `config/caelestia/hypr-user.lua`. Like any plugin, it refuses to load into another Hyprland version, and a Hyprland update can break the build.

## Usage

```lua
hl.plugin.load("/etc/hypr/plugins/hyprexpo.so")
hl.bind("SUPER + Tab", function() hl.plugin.hyprexpo.expo("toggle") end)
hl.plugin.hyprexpo.gesture(4, "up") -- trackpad swipe, follows the fingers
```

`hl.plugin.hyprexpo.expo(arg)`, where `arg` is:

| arg | effect |
|---|---|
| `toggle` (default) | open, or close and go to the hovered workspace |
| `on` | open |
| `off` | close, back to the workspace it was opened on |
| `select` | close and go to the hovered workspace |

In the overview, a click (or tap) goes to that workspace.

## Config

```lua
hl.config({ plugin = { hyprexpo = {
    columns = 3,                         -- grid is columns x columns
    gap_size = 5,                        -- logical px between tiles
    bg_col = 0xff111111,                 -- behind the tiles
    workspace_method = "center current", -- or "first <workspace>", e.g. "first 1"
    skip_empty = 0,                      -- 1: only workspaces that exist (empty slots open a new one)
    gesture_distance = 200,              -- swipe length for a full open
} } })
```

## Changes from upstream

- Rendering uses Hyprland 0.57's workspace scenes: each tile is drawn offscreen with `renderWorkspace(ctx, workspace, now, WORKSPACE_WITH_SHELL)`, so the plugin no longer swaps the monitor's active workspace for every tile.
- The grid is drawn with Hyprland's own clear and texture pass elements, replacing the custom pass element.
- No more hooks on `CMonitor::addDamage`: before each frame of the overview's monitor, the plugin redraws the current workspace's live tile and repaints the whole grid.
- The workspace grid is computed from numbered workspace IDs (Hyprland 0.57 workspace IDs are no longer plain integers). Named workspaces are not shown.
- The `hyprexpo-gesture` config keyword is replaced by `hl.plugin.hyprexpo.gesture(fingers, direction)`, and the `bring` dispatcher is dropped.
