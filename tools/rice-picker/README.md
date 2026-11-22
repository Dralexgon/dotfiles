# rice-picker

The **Rices** window: switch, edit and create rices. Open it from the app launcher ("Rices") or with `rice-picker`.
Launching it again while it is open closes it (if it has the focus) or brings it up.

- Each card shows a rice's palette. Click it, press `1`-`9`, or press Enter on it to switch.
  This calls `set_rice('<name>')` in `config/caelestia/hypr-user.lua`, the same function as `SUPER + SHIFT + R` and `rice <name>`.
- The **⚙** button on a card unfolds that rice's settings: scheme, wallpaper, fonts, cursor, window and cursor effects, animations.
  They are saved to `config/caelestia/rices/<name>.json` (see [its README](../../config/caelestia/rices/README.md)).
- **New rice** copies the current rice under a new name.
- The window takes the current scheme's colours and follows it live.
- Escape, Ctrl + W or Ctrl + Q close it.

## Command line

```
rice-picker              open the window
rice-picker --list       list the rices
rice-picker --set NAME   switch to a rice (same as clicking its card)
rice-picker --apply NAME the shell side of a switch: Caelestia scheme, wallpaper, cursor, fonts
```

`--apply` is run by `set_rice()`, which does the Hyprland side itself (plugins, animations).

## Files

| File | Role |
|---|---|
| `rice_picker.py` | the window (GTK4) and the command line, app id `dev.dralexgon.RicePicker` |
| `default.nix` | the `rice-picker` command + launcher entry, installed by `nixos/modules/desktop/caelestia.nix` |

The command runs `rice_picker.py` from the dotfiles checkout (`$RICE_PICKER_DOTFILES`, default `~/dotfiles`) when there is one,
so editing it needs no rebuild. The copy in the Nix store is only a fallback.
