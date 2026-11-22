# installer-gui

[`install.sh`](../../install.sh) in a window (GTK4 + libadwaita). Start it with:

```bash
./install.sh --gui
```

It uses `installer-gui` when it is installed, else `nix run ~/dotfiles#installer-gui` (fine on a fresh NixOS).
The questions are the same as in the terminal: user, Caelestia, new NixOS host (hostname, desktops, modules, tools), configs to link.
The output of the script is in **Details** at the bottom, and sudo asks for your password in a small window.

## How it works

The install logic stays in `install.sh`: the window runs `install.sh --gui-backend` and shows each question as a page.
A question is one line on the script's stdout, `\x1e` then a JSON object, and the answer goes back on its stdin as one line:

| Question | Answer |
|---|---|
| `{"type": "text", "prompt", "default", "pattern"}` | the text |
| `{"type": "password", "prompt"}` | the password (asked twice in the window) |
| `{"type": "yesno", "prompt", "default": "y" \| "n"}` | `y` or `n` |
| `{"type": "one", "title", "default", "options"}` | the index of the option |
| `{"type": "many", "title", "options", "checked"}` | one `0` / `1` per option, space separated |

Every other line goes to the log, and the lines printed since the last question are shown above the next one (warnings, "already installed"...).
sudo asks through `installer-gui --askpass` (`SUDO_ASKPASS`).

## Files

| File | Role |
|---|---|
| `installer_gui.py` | the window and the askpass dialog, app id `dev.dralexgon.Installer` |
| `default.nix` | the `installer-gui` and `installer-gui-askpass` commands, the `installer-gui` app in `flake.nix` |
