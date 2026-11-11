#!/usr/bin/env bash

DOTFILES_DIR=./dotfiles

# TODO: rework

# if ! command -v stow 2>&1 >/dev/null; then
#     echo "Stow not found, install GNU Stow"
#     exit 1
# fi

# # Gnome

# dconf load /org/gnome/shell/extensions/ <$DOTFILES_DIR/gnome/gnome-shell-extensions.dconf
# dconf load /org/gnome/desktop/interface/ <$DOTFILES_DIR/gnome/gnome-settings.dconf
# dconf load /org/gnome/settings-daemon/plugins/media-keys/ <$DOTFILES_DIR/gnome/keyboard-shortcuts.dconf

# cd $DOTFILES_DIR/gnome || exit
# mkdir -p "$HOME/.config/autostart" &
# stow --target="$HOME/.config/autostart" autostart
# mkdir -p "$HOME/.themes" &
# stow --target="$HOME/.themes" .themes
# mkdir -p "$HOME/.icons" &
# stow --target="$HOME/.icons" .icons

# # Hyprland

# cd ..
# mkdir -p "$HOME/.config/hypr" &
# stow --adopt --target="$HOME/.config/hypr" hypr
# mkdir -p "$HOME/.config/kitty" &
# stow --target="$HOME/.config/kitty" kitty
# mkdir -p "$HOME/.config/rofi" &
# stow --target="$HOME/.config/rofi" rofi
# mkdir -p "$HOME/.config/waybar" &
# stow --target="$HOME/.config/waybar" waybar

# # Bashrc

# stow --target="$HOME" bash

# # Neovim

# mkdir -p "$HOME/.config/nvim" &
# stow --target="$HOME/.config/nvim" nvim

# # Nixos

# if grep -q nixos </etc/os-release; then
#     test -f /etc/nixos/configuration.nix && sudo mv /etc/nixos/configuration.nix /etc/nixos/configuration.nix.bak
#     # sudo stow --ignore="hardware-configuration.nix" --target="/etc/nixos" nixos
#     # sudo stow --adopt --target="/etc/nixos" nixos
#     sudo stow --adopt --target="/etc/nixos" nixos
# fi

# echo "Complete"
