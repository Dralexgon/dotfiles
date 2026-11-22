# hypr-cursortrail

A Hyprland plugin drawing a fading trail behind the mouse pointer. Every rice uses it, in its own colour.

- Pointer positions come from Hyprland's own mouse-move event (no polling of the Hyprland socket).
- The trail is drawn in the compositor render pass, just under the cursor, in the very frame the pointer moves, so it never lags behind.
- The whole trail is one draw call: a shader computes the distance to every segment, so joints never overlap and edges are antialiased.
- No trail while animations are off (Caelestia's game mode).

It replaces a former Quickshell overlay that polled the cursor position.

## Config

All optional, e.g. `hl.config({ plugin = { cursortrail = { width = 8 } } })`:

| Option | Meaning | Default |
|---|---|---|
| `plugin:cursortrail:width` | trail width in logical px at the pointer | `8` |
| `plugin:cursortrail:life_ms` | how long a trail point lives | `220` |
| `plugin:cursortrail:color` | `0xAARRGGBB`, `0` = follow the Caelestia scheme | `0` |

The rices set `color` (the `trail` field of `config/caelestia/rices/<name>.json`).

## Build

`default.nix` builds it against `pkgs.hyprland`, and `nixos/modules/desktop/caelestia.nix` installs it as `/etc/hypr/plugins/cursortrail.so`,
loaded in `config/caelestia/hypr-user.lua`. Rebuild after a Hyprland update.
