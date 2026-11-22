# hypr-cursorfx

A Hyprland plugin throwing particles behind the mouse pointer as it moves. The **petals** and **vampire** rices use it.

| Style | Look |
|---|---|
| `petals` | petals in the Caelestia scheme colour, flung by the pointer, then drifting down with a light breeze: they flutter, spin, tumble and fade |
| `blood` | drops shaken off the pointer: they fall, stretch with speed, and splat a little below where they fell from; the splats fade |
| `image` | any PNG (`plugin:cursorfx:image`), thrown like the petals |
| `off` | nothing |

Switch live with `hyprctl eval 'hl.config({ plugin = { cursorfx = { style = "blood" } } })'`.
Flicking the mouse throws the particles further. Nothing happens while animations are off (Caelestia's game mode).

## Config

All optional, e.g. `hl.config({ plugin = { cursorfx = { style = "blood" } } })`:

| Option | Meaning | Default |
|---|---|---|
| `plugin:cursorfx:style` | `petals` \| `blood` \| `image` \| `off` | `petals` |
| `plugin:cursorfx:image` | PNG path for the image style, `~` allowed | `""` |
| `plugin:cursorfx:density` | particles per 100 px of pointer travel | `5` |
| `plugin:cursorfx:size` | particle size in logical px | `14` |
| `plugin:cursorfx:life_ms` | how long a petal / image lives | `1400` |
| `plugin:cursorfx:max_particles` | cap, the oldest go first | `400` |
| `plugin:cursorfx:color` | petal colour `0xAARRGGBB`, `0` = follow the Caelestia scheme | `0` |
| `plugin:cursorfx:blood_color` | `0xAARRGGBB` | `0xFF8A0012` |
| `plugin:cursorfx:splat_ms` | how long a blood splat stays | `1600` |

The rices set `style` (the `cursorfx` field of `config/caelestia/rices/<name>.json`).

## How it works

Hyprland's mouse-move event spawns particles along the pointer path, with part of the pointer's velocity.
Particles live in global coordinates (they cross monitors), are stepped once per frame and drawn at the end of each frame.
Every shape is drawn by one fragment shader.

## Build

`default.nix` builds it against `pkgs.hyprland`, and `nixos/modules/desktop/caelestia.nix` installs it as `/etc/hypr/plugins/cursorfx.so`,
loaded in `config/caelestia/hypr-user.lua`. Rebuild after a Hyprland update.
