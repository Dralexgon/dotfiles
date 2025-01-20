#!/usr/bin/env bash

DOTFILES_DIR=./dotfiles

# Gnome

dconf load /org/gnome/shell/extensions/ <$DOTFILES_DIR/gnome/gnome-shell-extensions.dconf
dconf load /org/gnome/desktop/interface/ <$DOTFILES_DIR/gnome/gnome-settings.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ <$DOTFILES_DIR/gnome/keyboard-shortcuts.dconf

cp -r $DOTFILES_DIR/gnome/autostart ~/.config/autostart
cp -r $DOTFILES_DIR/gnome/.themes ~/.themes
cp -r $DOTFILES_DIR/gnome/.icons ~/.icons

# Bashrc

cp $DOTFILES_DIR/bash/.bashrc ~/.bashrc

# Hyprland

cp -r $DOTFILES_DIR/hypr ~/.config/hypr
cp -r $DOTFILES_DIR/kitty ~/.config/kitty
cp -r $DOTFILES_DIR/rofi ~/.config/rofi
cp -r $DOTFILES_DIR/waybar ~/.config/waybar

# Neovim

cp -r $DOTFILES_DIR/nvim ~/.config/nvim

# Nixos

cp -r $DOTFILES_DIR/nixos /etc/nixos

echo "Complete"
