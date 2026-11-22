# hypr-windowfx

A Hyprland plugin animating closing windows, and opening ones (the same animation played backwards). The **petals** and **vampire** rices use it.

| Style | Closing window | Opening window |
|---|---|---|
| `petals` | shatters into petals in the scheme colour, blown away by the wind | assembles from petals brought by the wind |
| `blood` | shrinks fast to its centre and bursts into blood droplets that fly, fall and splat | pops in with a small overshoot, then a few drops drip off its edges |
| `blood-legacy` | blood runs down it until it is soaked, then drains off as droplets | rises from the drops, the blood runs off upwards |
| `off` | Hyprland's own `windowsIn` / `windowsOut` animations | |

Switch live with `hyprctl eval 'hl.config({ plugin = { windowfx = { style = "petals" } } })'`.
Nothing happens while animations are off (Caelestia's game mode). It assumes unrotated monitors.

## Config

All optional, e.g. `hl.config({ plugin = { windowfx = { style = "blood" } } })`. The main ones:

| Option | Meaning | Default |
|---|---|---|
| `plugin:windowfx:style` | `petals` \| `blood` \| `blood-legacy` \| `off` | `petals` |
| `plugin:windowfx:open` | `1` = animate opening windows too | `1` |
| `plugin:windowfx:open_speed` | playback speed of the whole opening, `2` = twice as fast | `1.0` |
| `plugin:windowfx:max_pieces` | petals cap per window | `240` |
| `plugin:windowfx:size` | petal size in logical px | `44` |
| `plugin:windowfx:duration_ms` | flight time of one petal | `1700` |
| `plugin:windowfx:wind_x`, `wind_y`, `wind_strength` | wind direction and speed (px/s) | `1.0`, `-0.45`, `750` |
| `plugin:windowfx:color` | petal colour `0xAARRGGBB`, `0` = follow the Caelestia scheme | `0` |
| `plugin:windowfx:blood_color` | `0xAARRGGBB` | `0xFF8A0012` |
| `plugin:windowfx:blood_drops` | drops bursting out of a closing window | `40` |

The full list (opening timings, blood and blood-legacy options) is at the top of [`main.cpp`](main.cpp).
The rices set `style` (the `windowfx` field of `config/caelestia/rices/<name>.json`).

## How it works

- Hyprland snapshots a closing window for its fade-out animation. The plugin hooks that, keeps the snapshot and skips the stock animation.
- The window is cut into a grid of cells, each showing its own patch of the snapshot. A shader morphs each cell into a petal (or a drop) as it leaves its spot.
- An opening window stays hidden until it has drawn a first frame, then it is snapshotted and a close is simulated backwards (wind reversed).

## Build

`default.nix` builds it against `pkgs.hyprland`, and `nixos/modules/desktop/caelestia.nix` installs it as `/etc/hypr/plugins/windowfx.so`,
loaded in `config/caelestia/hypr-user.lua`. Rebuild after a Hyprland update.
