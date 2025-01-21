#!/usr/bin/env bash

DOTFILES_DIR=./dotfiles

if ! command -v stow 2>&1 >/dev/null; then
    echo "Stow not found, install GNU Stow"
    exit 1
fi

# Gnome

dconf load /org/gnome/shell/extensions/ <$DOTFILES_DIR/gnome/gnome-shell-extensions.dconf
dconf load /org/gnome/desktop/interface/ <$DOTFILES_DIR/gnome/gnome-settings.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ <$DOTFILES_DIR/gnome/keyboard-shortcuts.dconf

cd $DOTFILES_DIR/gnome || exit
stow --target="$HOME/.config" autostart
stow --target="$HOME" .themes
stow --target="$HOME" .icons

# Hyprland

cd ..
stow --target="$HOME/.config" hypr kitty rofi waybar

# Bashrc

stow --target="$HOME" bash

# Neovim

stow --target="$HOME/.config" nvim

# Nixos

if grep -q nixos </etc/os-release; then
    test -f /etc/nixos/configuration.nix && sudo mv /etc/nixos/configuration.nix /etc/nixos/configuration.nix.bak
    sudo stow --target="/etc/nixos" nixos
fi

echo "Complete"
