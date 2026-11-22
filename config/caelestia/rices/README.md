# Rices

One JSON file per rice. `set_rice()` (`../hypr-user.lua`), `rice <name>` and the Rices app
(`tools/rice-picker`) all read them, so a new file here is a new rice: no list to update.
The Rices app can edit them (the ⚙ button on a card) and create new ones.

| Key | What | `null` means |
|---|---|---|
| `order` | position in the picker and in the SUPER + SHIFT + R cycle | last |
| `title`, `icon`, `tagline`, `effects` | text on the picker card | |
| `scheme` | `{name, flavour, mode}` of a scheme in `../schemes/` | colours from the wallpaper (`caelestia scheme set -n dynamic`) |
| `wallpaper` | image path (`~/` or relative to this folder) | keep the current wallpaper |
| `windowfx` | window open/close effect: `petals`, `blood`, `blood-legacy`, `off` | |
| `cursorfx` | particles behind the pointer: `petals`, `blood`, `image`, `off` | |
| `trail` | pointer trail colour, `#RRGGBB` | the scheme's colour |
| `transition` | command played when switching to it (e.g. `bat-swarm`) | none |
| `cursor` | `{theme, size}` | keep the current cursor |
| `font` | `{sans, mono}`: Caelestia's fonts (`appearance.font.family` in `../shell.json`) | Caelestia's default |
| `animations` | Hyprland animations by leaf, e.g. `{"windowsIn": {"speed": 4.5, "bezier": "windowPop", "style": "popin 50%"}}` | a leaf left out keeps its current value |

Hyprland-side settings (windowfx, cursorfx, trail, animations, transition) are applied by
`set_rice()`; the rest (scheme, wallpaper, cursor, fonts) by `rice-picker --apply <name>`, which
`set_rice()` runs.

## Wallpapers

One wallpaper per rice in `wallpapers/`. The `adaptive` rice has none: it keeps the current
wallpaper and takes its colours from it.

| Rice | File | Author | Source |
|---|---|---|---|
| petals | `wallpapers/petals.png` | Unknown | Unknown |
| vampire | `wallpapers/vampire.png` | rinfiora (Krul Tepes, *Owari no Seraph*) | Konachan post 228944, upscaled 4x with Upscayl |

The wallpapers belong to their authors. If you are one of them and want yours credited differently
or removed, open an issue.
