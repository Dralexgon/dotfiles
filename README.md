# My dotfiles (Not finished !)

The goal of this rice is to have multiple rices that I can change dynamically, live, hot reload.
The current rices (Hyprland and Caelestia) are :
- adaptive : the colors change depending on the wallpaper
- vampire : bright red and bloody vibes
- petals : pink and soft vibes
- cyberpunk : a style similar to cyberpunk 2077

Switch between adaptive, petals and vampire with SUPER + SHIFT + R (cycles), or `rice adaptive|petals|vampire|next` in fish, or the **Rices** app in the launcher (`tools/rice-picker`).

The legacy rices were :
- a Gnome purple Catppuccin rice with cool animations
- a uwu color scheme with a gtk theme on Gnome or Hyprland
Not the priority, it could be in another repo later

## TODO

Every change to .config should change files in dotfiles. If not create a file here and create a symlink.

### install.sh

- [x] install.sh will have 2 modes : an input one : asking for user input, example : yes/no and a TUI one : where they can select their choice with the arrows (this one will be the default)
- [x] To create a new configuration.nix, ask the user what hostname and username he wants. Then ask which module he wants to install 
- [x] Ask the user if they want to caelestia install
- [x] change razer keyboard color to the caelestia colors when changing wallpapers

### Keybinds

- [ ] Add a read-only Keybinds tab to nixcfg : read the Caelestia defaults (`~/.config/hypr/variables.lua`) with my overrides from `config/caelestia/hypr-vars.lua` on top, and also list my own binds from `config/caelestia/hypr-user.lua` (`hyprctl binds` is useless here, every bind shows up as `__lua`)
- [ ] Look into a Keybinds page in the Caelestia settings (nexus) to view and edit the `kb*` variables, saving to `hypr-vars.lua` : check upstream for an existing issue/PR first, then propose it as a PR

### OneDrive

- [ ] Write `config/onedrive/sync_list` (one OneDrive path per line, `/` = from the root, `!` = exclude) and symlink it to `~/.config/onedrive/sync_list`
- [ ] First sync : `onedrive --sync --resync --dry-run` to check what gets downloaded, then without `--dry-run` (needed after every `sync_list` change)
- [ ] Restart the service with `systemctl --user restart onedrive@onedrive` : the current one started before the login and stays idle

### razerfx

- [ ] Try `FPS = 60` in `tools/razerfx/daemon.py` (smoother wave, plasma, audio visualiser) and measure the CPU cost of razerfx + openrazer-daemon
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

### Login screen (vampire style)

Currently SDDM + the custom `predatoria` QML theme (`themes/sddm/predatoria`), set in `nixos/modules/hyprland.nix` (ly and sddm-astronaut configs kept there, disabled). Try each option:

- [x] ly with a red doom fire: `services.displayManager.ly.settings` with `animation = "doom"`, `doom_top_color = "0x00300000"` (flame tips), `doom_middle_color = "0x00A00000"`, `doom_bottom_color = "0x00FF2020"` (fire base), `border_fg = "0x00B00000"`, `bigclock = "en"`
- [x] SDDM with `sddm-astronaut`, recolored through its `embeddedTheme` / `themeConfig` overrides: Predatoria art or a gothic video loop as the background, Cinzel or UnifrakturMaguntia font, palette `#0b0507` / `#8a0303` / `#ff2a2a` / bone-white text
- [x] Custom greeter in QML (SDDM QML theme, or Quickshell + greetd like Caelestia): blood drips from the top edge that splat (same idea as windowfx/cursorfx), password field bleeds and shakes on a wrong password, red eyelid vignette on login, Predatoria crest above the clock, "Speak the word, mortal…" placeholder
  - Match hyprlock with the same palette, and maybe switch Plymouth to `red_loader` / `hexagon_red`, so boot → login → lock looks like one theme
