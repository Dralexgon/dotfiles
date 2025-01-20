#!/usr/bin/env bash

DOTFILES_DIR=./dotfiles

mkdir -p $DOTFILES_DIR

# Gnome

mkdir -p $DOTFILES_DIR/gnome
dconf dump /org/gnome/shell/extensions/ >$DOTFILES_DIR/gnome/gnome-shell-extensions.dconf
dconf dump /org/gnome/desktop/interface/ >$DOTFILES_DIR/gnome/gnome-settings.dconf
dconf dump /org/gnome/settings-daemon/plugins/media-keys/ >$DOTFILES_DIR/gnome/keyboard-shortcuts.dconf

cp -r ~/.config/autostart $DOTFILES_DIR/gnome/autostart
cp -r ~/.themes $DOTFILES_DIR/gnome/.themes
cp -r ~/.icons $DOTFILES_DIR/gnome/.icons

# Bashrc

mkdir -p $DOTFILES_DIR/bash
cp ~/.bashrc $DOTFILES_DIR/bash/.bashrc

# Hyprland

#mkdir -p $DOTFILES_DIR/hypr $DOTFILES_DIR/kitty $DOTFILES_DIR/rofi $DOTFILES_DIR/waybar
cp -r ~/.config/hypr $DOTFILES_DIR
cp -r ~/.config/kitty $DOTFILES_DIR
cp -r ~/.config/rofi $DOTFILES_DIR
cp -r ~/.config/waybar $DOTFILES_DIR

# Neovim

#mkdir -p $DOTFILES_DIR/nvim
cp -r ~/.config/nvim $DOTFILES_DIR

# Nixos
if grep -q nixos </etc/os-release; then
    cp -r /etc/nixos $DOTFILES_DIR/nixos
fi

echo "Configuration backed up to $DOTFILES_DIR"
