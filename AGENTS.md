# AGENTS.md

Notes for coding agents (and me) working in this repo. The user-facing docs are in `README.md`.
Who I am and how to address me: `~/AGENTS.md`.

## Layout

- `flake.nix`: one `nixosConfiguration` per directory in `nixos/hosts/` (new host dirs must be git-added). Extra per-host modules go in `hostModules`. Also the `nixcfg` / `rgbfx` apps and dev shells.
- `nixos/core.nix`: shared base config, imported by every host.
- `nixos/hosts/<host>/configuration.nix`: per-host config. Modules are toggled by commenting their import line out (that's also what `nixcfg` edits, so keep that format).
- `nixos/modules/`: optional modules (`desktop/`, `dev/`, `gaming/`, `epita/` are groups).
- `nixos/home/`: user config (nvf Neovim).
- `config/`: dotfiles, symlinked into `$HOME` by `install.sh` (`bash` -> `~/.bashrc`, `git` -> `~/.gitconfig*`, `ssh` -> `~/.ssh/config`, `clang-format` -> `~/.clang-format`, the rest -> `~/.config/<name>`).
- `config/caelestia/`: the Caelestia + Hyprland setup. `hypr-user.lua` holds my binds, window rules, plugin loading and the **Rices** (`RICES` / `RICE_ORDER` / `set_rice`). `hypr-vars.lua` overrides Caelestia's `kb*` variables. `schemes/` holds the fixed colour schemes.
- `tools/`: my own programs and Hyprland plugins (each has a `default.nix`, most have a README).
- `themes/`, `icons/`: GRUB / Plymouth / SDDM / GTK themes and assets.
- `legacy-rices/`: git submodule with the old rices and one wallpaper per rice (credits in its README).
- `recover.sh`: boot-repair notes (mount, `nixos-enter`, reinstall the bootloader). The old GNOME rices and scripts moved to [Dralexgon/legacy-rices](https://github.com/Dralexgon/legacy-rices).

## Conventions

- Every change to `~/.config` should live in this repo: if a file isn't here yet, add it under `config/` and symlink it.
- Prefer the declarative NixOS way. Rebuild with `sudo nixos-rebuild switch --flake ~/dotfiles#<hostname>` (current machine: `nixos-tower-RX9070XT-4Tssd`).
- Python tools (rice-picker, bat-swarm, keybinds-viewer, rgbfx...) run from the checkout when there is one, so editing them needs no rebuild; only `default.nix` changes do.
- Hyprland plugins in `tools/hypr-*` are built against `pkgs.hyprland`: rebuild after a Hyprland update.
- Rices are one JSON file each in `config/caelestia/rices/` (see its README): `set_rice()` in `hypr-user.lua` does the Hyprland side, `rice-picker --apply` the rest. The rices' wallpapers come from the `legacy-rices/` git submodule ([Dralexgon/legacy-rices](https://github.com/Dralexgon/legacy-rices), shallow), referenced relative to the rices folder (`../../../legacy-rices/wallpapers/<rice>.png`); to add one, commit it there, then bump the submodule here.
- Nothing personal goes in this public repo (real name, work/school email...): put it in the private `~/dotfiles-private` (install.sh links from it when it's there). Git identity here is `Dralexgon <dral3xgon@gmail.com>`, the only public email.
- `username = "alex"` is hardcoded in `flake.nix` `specialArgs`.
- Commits: conventional style, e.g. `feat(rgbfx): ...`, `docs(todo): ...`. Mark a TODO item `[x]` with a short note of what was done.

## TODO

Every change to .config should change files in dotfiles. If not create a file here and create a symlink.

### IMPORTANT

- [x] Done: `flake.nix` now generates `nixosConfigurations` from every directory in `nixos/hosts/` (extra per-host modules go in `hostModules`), and install.sh git-adds the new host dir instead of patching flake.nix

Was: make this abstract or add it in the install script :
```
nixosConfigurations."nixos-tower-RX9070XT" = nixpkgs.lib.nixosSystem {
  # Main pc POWERFUL RX 9070 XT !!!
  inherit specialArgs;
  modules = [
    ./nixos/hosts/nixos-tower-RX9070XT/configuration.nix
    # inputs.boot-animation.nixosModules.default
  ];
};
```

### install.sh

- [x] install.sh will have 2 modes : an input one : asking for user input, example : yes/no and a TUI one : where they can select their choice with the arrows (this one will be the default)
- [x] To create a new configuration.nix, ask the user what hostname and username he wants. Then ask which module he wants to install 
- [x] Ask the user if they want to caelestia install
- [x] change razer keyboard color to the caelestia colors when changing wallpapers

### Keybinds

- [x] Add a read-only Keybinds tab to nixcfg : read the Caelestia defaults (`~/.config/hypr/variables.lua`) with my overrides from `config/caelestia/hypr-vars.lua` on top, and also list my own binds from `config/caelestia/hypr-user.lua` (`hyprctl binds` is useless here, every bind shows up as `__lua`)
- [ ] Look into a Keybinds page in the Caelestia settings (nexus) to view and edit the `kb*` variables, saving to `hypr-vars.lua` : check upstream for an existing issue/PR first, then propose it as a PR
  - Researched: shell#1679 (read-only page, closed unmerged), shell#1868 + caelestia#503 (cheatsheet, open), shell#1568 (maintainer: cheatsheet planned as an official plugin). Nothing upstream edits `kb*`. Next: ask in caelestia#501 / shell#1568 whether it belongs in core or the plugin before writing the PR
- [x] Fix `Super + D` : it only toggles Vesktop when it's already running, it should launch Vesktop if it isn't open yet (`chat` toggle in `config/caelestia/cli.json`: matches discord or vesktop windows, launches discord if installed, else vesktop)

### OneDrive

- [ ] Write `config/onedrive/sync_list` (one OneDrive path per line, `/` = from the root, `!` = exclude) and symlink it to `~/.config/onedrive/sync_list`
- [ ] First sync : `onedrive --sync --resync --dry-run` to check what gets downloaded, then without `--dry-run` (needed after every `sync_list` change)
- [ ] Restart the service with `systemctl --user restart onedrive@onedrive` : the current one started before the login and stays idle

### rgbfx

- [ ] Try `FPS = 60` in `tools/rgbfx/daemon.py` (smoother wave, plasma, audio visualiser) and measure the CPU cost of rgbfx + openrazer-daemon
- [ ] Draw frames straight through the kernel driver (`/sys/.../matrix_custom_frame` then `matrix_effect_custom`) instead of D-Bus through openrazer-daemon : less CPU, a few ms less latency, makes 60 fps cheap (the USB link caps it around ~100 fps anyway). Write a whole row at once instead of the per-key Python loop. Watch out for openrazer-daemon / Polychromatic overriding it
- [ ] Rust rewrite : only if the above isn't enough (would save ~2% CPU and ~45 MB RAM, but loses the run-from-checkout setup and the Textual TUI)

### Cursor trail

- [x] Make the mouse pointer trail a Hyprland plugin (`tools/hypr-cursortrail`) : drawn in the compositor render pass, so it stays in sync with the pointer and no longer polls `cursorpos` over the socket

### Hyprland plugins

- [x] Try hyprliquid (for example on the kitty terminal): `tools/hypr-liquid`, Liquid Glass on kitty in `config/caelestia/hypr-user.lua`
  - The glass only bends the background near the edges, in a band as wide as the corner rounding (15 px by default, so it barely shows). For a stronger glass look, add `["hyprliquid:rounding_lua"] = 64` to the kitty rule: the normal `rounding` rule is capped at 20 in Lua
  - Keep `no_blur = true`: with Hyprland's blur it looks frosted, not like glass
- [ ] Add the hyprfocus plugin
- [ ] Try hyprtasking (workspace overview where windows can be dragged between workspaces): SUPER + Tab already switches to it from hyprexpo as soon as `pkgs.hyprlandPlugins.hyprtasking` builds (it fails on 0.57.1), then tune its config and gestures
- [ ] Try the imgborders plugin
- [ ] Try the `csgo-vulkan-fix` plugin for Albion instead of the current way of changing the resolution
- [ ] try to use HyprCapture instead for screenshots
- [ ] Try hy3 (i3-style tiling), with i3 as the default layout
- [ ] Try a parallax wallpaper effect: no Hyprland plugin for it, but `hyprlax` (daemon, in nixpkgs) does workspace parallax and `shiftpaper` (experimental) does cursor-driven depth parallax. Caelestia draws its own wallpaper, so it would need to be turned off

### Rice switching

- [x] Vampire: bats fly across the screen when switching to the vampire rice
- [ ] Petals: make a rice switching animation (falling petals) when switching to the petals rice
- [ ] Petals: use a cute catgirl cursor with cute animations for the petals rice (vampire and adaptive keep bibata)
- [ ] add sound effects for the rices (windows opening/closing, workspace switch, notifications, etc...)

### Nix config cleanup

- [x] Use bibata-cursors everywhere, in its own nix file
- [x] Move fonts into their own nix file
- [ ] Think about how nixcfg could let the user switch a package between `pkgs` (unstable) and `pkgs-stable`, e.g. a toggle per package (today it's hand-written, like `pkgs-stable.vscode` in `nixos/core.nix`)
- [ ] When updating the flake, test whether each `pkgs-stable.*` package now builds from unstable, so it can be moved back (e.g. `nix build` each one against the new unstable and report which ones pass)

### Useable repo

The repo is already public I want to make it easy to use for other people (example : nixcfg, install.sh)

- [x] make a AGENTS.md in this project to store the todo and other infos instead of this README then make a clear and readable README (`AGENTS.md` holds the notes and this TODO, `CLAUDE.md` imports it, `README.md` is rewritten for users)
- [x] add a GUI to install.sh (maybe gtk ? or quickshell ?) (GTK4 + libadwaita in `tools/installer-gui`, started by `./install.sh --gui`: install.sh `--gui-backend` sends each question as a JSON line and the window shows it as a page, sudo asks through an askpass window)
- [x] add a setting for the differents rices (petals, vampire) so we can tweaks the settings like the wallpaper, fonts, cursors, animations settings, etc... and create a new rice (one JSON file per rice in `config/caelestia/rices/`, read by `set_rice()` and rice-picker; the ⚙ button on a card unfolds its settings, "New rice" copies one under a new name, `rice-picker --apply` sets scheme / wallpaper / cursor / fonts)
- [x] move the old rices to another repo (`legacy/` is now [Dralexgon/legacy-rices](https://github.com/Dralexgon/legacy-rices), history kept; `recover.sh` stays here at the root)
- [x] add the wallpapers for the rices in that repo (`wallpapers/petals.png`, `wallpapers/vampire.png`, authors credited in its README, unknown when not found)
- [x] create a dotfiles-private wich store all privates informations about me (true name etc...) which could be in this repo and which save the git history. Once done, clear the history of this repo (private [Dralexgon/dotfiles-private](https://github.com/Dralexgon/dotfiles-private) at `~/dotfiles-private`: `AGENTS.md` (symlinked to `~/AGENTS.md`), `git/gitconfig-work`, and the old 423-commit history on its `dotfiles-history` branch; this repo was squashed into one commit)

### Notif grouper

- [x] clone the notif grouper repo, fix bugs if there are some and ask me to plug my phone so I can test it (merged in notifgrouper `main`: bug fixes, full-colour logos through helper apps, new app picker with search; tested on the Galaxy A16)
