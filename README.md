# My dotfiles (Not finished !)

I'm currently working on another rice with Hyprland and Caelestia

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

### Cursor trail

- [ ] Make the mouse pointer trail (`config/caelestia/cursor-trail.qml`) a Hyprland plugin : draw it in the compositor render pass, so it stays in sync with the pointer and no longer polls `cursorpos` over the socket
