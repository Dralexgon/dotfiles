# Dralexgon's dotfiles

My NixOS config (a flake) and a Hyprland + [Caelestia](https://github.com/caelestia-dots/shell) desktop with several **rices** you can switch live, without logging out.

> Still a work in progress. It's made for my machines first, but the installer can set it up on yours.

## Rices

| Rice | Look | Effects |
|---|---|---|
| **adaptive** | colours taken from the wallpaper | Hyprland's own animations, cursor trail |
| **petals** 🌸 | pink and soft | windows open and close in petals, petals behind the cursor |
| **vampire** 🩸 | bright red and bloody | windows bleed away, blood behind the cursor, red trail, bats fly across the screen when you switch to it |

A **cyberpunk** rice (Cyberpunk 2077 style) is planned.

Switch rices with any of:
- `SUPER + SHIFT + R` (cycles adaptive → petals → vampire)
- `rice adaptive|petals|vampire|next` in fish
- the **Rices** app in the launcher

Each rice is one file in [`config/caelestia/rices/`](config/caelestia/rices): colour scheme, wallpaper, fonts, cursor, window and cursor effects, animations. Edit them from the **⚙ Settings** button on a card in the Rices app, or create your own with **New rice**. Their wallpapers are in [`config/caelestia/rices/wallpapers/`](config/caelestia/rices/wallpapers) (authors credited in [its README](config/caelestia/rices/README.md#wallpapers)).

The keyboard and case fan lights (`rgbfx`) follow the current colours.

### Legacy rices

Before Caelestia, this repo had GNOME rices (Catppuccin purple, uwu, with their GTK themes, icons and cursors) and an early hand-made Hyprland setup ([demo video](https://youtu.be/rfYjSGmUcBk)). They now live in [Dralexgon/legacy-rices](https://github.com/Dralexgon/legacy-rices), with their history. They are not maintained, but you can still borrow from them.

## Install

You need NixOS with flakes enabled.

```bash
git clone https://github.com/Dralexgon/dotfiles ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installer (arrow-key menus by default, `./install.sh --input` to type the answers instead, `./install.sh --gui` for a window) asks:

1. **Which user**: the current one, or a new user, to try the dotfiles without touching yours (it prints how to delete it at the end).
2. **Caelestia**: whether to install the Caelestia desktop.
3. **Projects**: whether to clone the apps that live in their own repos, like [Nova](#tools) (into `~/dev/ai/nova`, where the shortcuts expect it).
4. **NixOS host**: a hostname, the desktops, modules and tools you want. It creates `nixos/hosts/<hostname>/` and generates its `hardware-configuration.nix`.
5. **Dotfiles**: which configs from `config/` to symlink into your home (existing files can be backed up first).

My own personal files (git identity...) are in a private repo that only I can clone. If you aren't logged in to GitHub, the installer asks whether to set it up (right after the projects): just answer no. My git config isn't in `config/`, so set your own name and email with `git config --global`.

Then apply it:

```bash
sudo nixos-rebuild switch --flake ~/dotfiles#<hostname>
```

`./install.sh --help` lists every option.

To update, use `u` in nixcfg. With plain Nix, name the inputs (`nix flake update nixpkgs caelestia-shell ...`): a bare `nix flake update` fails on `private`, my private repo, which only exists on my machines.

## Changing the config

**nixcfg** is a terminal UI to turn modules and packages on and off for each host, and to see the Hyprland shortcuts:

```bash
nix run ~/dotfiles#nixcfg   # or SUPER + I once installed
```

You can also edit `nixos/hosts/<hostname>/configuration.nix` by hand: every module is one import line, comment it out to disable it.

## Useful shortcuts

| Keys | Action |
|---|---|
| `SUPER + /` | Keyboard with every shortcut on it |
| `SUPER + I` | nixcfg |
| `SUPER + SHIFT + R` | Next rice |
| `SUPER + Tab` | Workspace overview |
| `SUPER + Space` | Next keyboard layout |
| `SUPER + A` | Open [Nova](#tools), then switch her between full screen and the mini orb |
| `F8` | Talk to Nova from anywhere (tap or hold) |

The rest are Caelestia's defaults, with my changes in `config/caelestia/hypr-vars.lua` and `config/caelestia/hypr-user.lua`.

## What's in here

| Path | What |
|---|---|
| `flake.nix` | Builds one NixOS config per folder in `nixos/hosts/` |
| `nixos/core.nix` | Base config shared by every host |
| `nixos/hosts/` | One folder per machine (`default` is a generic install) |
| `nixos/modules/` | Optional modules: desktops, dev, gaming, drivers, ricing... |
| `config/` | Dotfiles (kitty, fish, Caelestia, Neovim...) |
| `tools/` | My own apps and Hyprland plugins, see below |
| `themes/`, `icons/` | GRUB, Plymouth, SDDM and GTK themes |
| `recover.sh` | Notes to repair the boot from a live USB (`nixos-enter`, reinstall the bootloader) |

### Tools

| Tool | What |
|---|---|
| [`nixcfg`](tools/nixcfg/README.md) | TUI to toggle modules and packages per host |
| [`rice-picker`](tools/rice-picker/README.md) | The **Rices** window |
| [`rgbfx`](tools/rgbfx/README.md) | Razer keyboard and case fan lighting that follows the colour scheme |
| [`keybinds-viewer`](tools/keybinds-viewer/README.md) | Your keyboard with every Hyprland shortcut on it |
| [`hypr-windowfx`](tools/hypr-windowfx/README.md) | Hyprland plugin: windows open and close in petals or blood |
| [`hypr-cursorfx`](tools/hypr-cursorfx/README.md) | Hyprland plugin: petals or blood behind the cursor |
| [`hypr-cursortrail`](tools/hypr-cursortrail/README.md) | Hyprland plugin: cursor trail |
| [`hypr-expo`](tools/hypr-expo/README.md) | Hyprland plugin: workspace overview (hyprexpo, ported to Hyprland 0.57) |
| [`hypr-liquid`](tools/hypr-liquid/README.md) | Hyprland plugin: Liquid Glass windows ([hyprliquid](https://github.com/zaregototsukai/hyprliquid)) |
| [`bat-swarm`](tools/bat-swarm/README.md) | Bats flying across the screen (vampire rice transition) |
| [`zen-sidebar`](tools/zen-sidebar/README.md) | Save and restore the Zen browser sidebar |
| [`installer-gui`](tools/installer-gui/README.md) | `install.sh` in a window (`./install.sh --gui`) |
| [`voice-changer-tray`](tools/voice-changer-tray/README.md) | Tray icon for the [voice changer](https://github.com/Dralexgon/nix-voice-changer) |
| [Nova](https://github.com/Dralexgon/nova) | Voice AI companion with a shader orb face (`SUPER + A`, `F8`). In its own repo: the installer clones it into `~/dev/ai/nova` |

## License

[GPL-3.0](LICENSE)
