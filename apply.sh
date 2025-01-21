#!/usr/bin/env bash

SYMLINKS=true
DOTFILES_DIR=./dotfiles

# Gnome

dconf load /org/gnome/shell/extensions/ <$DOTFILES_DIR/gnome/gnome-shell-extensions.dconf
dconf load /org/gnome/desktop/interface/ <$DOTFILES_DIR/gnome/gnome-settings.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ <$DOTFILES_DIR/gnome/keyboard-shortcuts.dconf

if $SYMLINKS; then
    ln -s $DOTFILES_DIR/gnome/autostart ~/.config/autostart
    ln -s $DOTFILES_DIR/gnome/.themes ~/.themes
    ln -s $DOTFILES_DIR/gnome/.icons ~/.icons
else
    cp -r $DOTFILES_DIR/gnome/autostart ~/.config/autostart
    cp -r $DOTFILES_DIR/gnome/.themes ~/.themes
    cp -r $DOTFILES_DIR/gnome/.icons ~/.icons
fi

# Bashrc

if $SYMLINKS; then
    ln -s $DOTFILES_DIR/bash/.bashrc ~/.bashrc
else
    cp $DOTFILES_DIR/bash/.bashrc ~/.bashrc
fi

# Hyprland

if $SYMLINKS; then
    ln -s $DOTFILES_DIR/hypr ~/.config/hypr
    ln -s $DOTFILES_DIR/kitty ~/.config/kitty
    ln -s $DOTFILES_DIR/rofi ~/.config/rofi
    ln -s $DOTFILES_DIR/waybar ~/.config/waybar
else
    cp -r $DOTFILES_DIR/hypr ~/.config/hypr
    cp -r $DOTFILES_DIR/kitty ~/.config/kitty
    cp -r $DOTFILES_DIR/rofi ~/.config/rofi
    cp -r $DOTFILES_DIR/waybar ~/.config/waybar
fi

# Neovim

if $SYMLINKS; then
    ln -s $DOTFILES_DIR/nvim ~/.config/nvim
else
    cp -r $DOTFILES_DIR/nvim ~/.config/nvim
fi

# Nixos

if $SYMLINKS && grep -q nixos </etc/os-release; then
    ln -s $DOTFILES_DIR/nixos /etc/nixos
else
    cp -r $DOTFILES_DIR/nixos /etc/nixos
fi

echo "Complete"
