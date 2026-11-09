# keybinds-viewer

Shows the keyboard (Razer BlackWidow V3 TKL, so tenkeyless) with every Hyprland shortcut on it.
Open it with **SUPER + /** (press again to close), the app launcher ("Keybinds") or `keybinds-viewer`.
It opens in its own floating window; `keybinds-viewer --browser` opens it in the browser instead.
Escape (when nothing is selected), Ctrl + W or Ctrl + Q close the window.

- Pick the modifiers at the top (or click Ctrl / Alt / Shift on the drawing, or hold them) to see
  what each key does with them. The combo chips list every modifier set in use, with their counts.
- Hover, click or press a key: the panel lists every bind on that key.
- Search (`/`) by name, key or command; the combo chips show where the matches are.
- US / FR switches the key labels. Hyprland reads binds on the first layout of `kb_layout` (US)
  since `input:resolve_binds_by_sym` is off, so the FR view shows AZERTY labels at the US places.
- A `!` on a key (or a combo chip) means several binds share that combo and all of them run.
  The **⚠ N conflicts** button next to the title lists them all, grouped by cause, with the
  variable or file to change. It shows **✓ No conflicts** when there are none.
- Colours follow the current Caelestia scheme (`~/.local/state/caelestia/scheme.json`).

## How it works

| File | Role |
|---|---|
| `keybinds_viewer.py` | reads and names the binds, writes the page, entry point |
| `index.html` | the page: keyboard drawing, panels, search (HTML/CSS/JS, no dependencies) |
| `window.py` | the window: GTK4 + WebKitGTK, single instance (app id `dev.dralexgon.KeybindsViewer`) |
| `default.nix` | the `keybinds-viewer` command + launcher entry, installed by `nixos/modules/caelestia.nix` |

The window rule (float, centered, 80 %) and the SUPER + / bind are in `config/caelestia/hypr-user.lua`.

`keybinds_viewer.py` reads `hyprctl binds -j`, names each bind, writes the data into `index.html`
and opens the result (`$XDG_RUNTIME_DIR/keybinds-viewer.html`) in the browser.
`keybinds-viewer --json` prints the data instead.

Hyprland's Lua config hides the dispatcher arguments, so names come from, in order:
1. the bind's description: `hl.bind("SUPER + X", action, { description = "Name" })`
   (used for our binds in `config/caelestia/hypr-user.lua`)
2. Caelestia's `kb*` variables (`~/.config/hypr/variables.lua` + `config/caelestia/hypr-vars.lua`),
   matched by key combo (`VARS` / `WS_VARS` in the script)
3. Caelestia's binds without a variable (`LITERALS`)
4. the dispatcher name, as a last resort ("Lua function", "Exec cmd")

A bind showing up as "Lua function" or "Exec cmd" needs a description.

The packaged command runs the copy in `~/dotfiles`, so changes here need no rebuild.

## TODO

- [x] Own window instead of a browser tab (GTK4 + WebKitGTK showing the same page).
- [ ] Fully native app: Python + GTK4 (libadwaita) widgets, or a Quickshell overlay that fits the
      Caelestia shell (opened as a layer on top of everything, closes on Escape).
- [ ] Other shortcut sets on their own tabs: kitty, Neovim (nvf), apps.
