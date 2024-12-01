#!/bin/bash

DOTFILES_DIR=./dotfiles/gnome

mkdir -p $DOTFILES_DIR

dconf dump /org/gnome/shell/extensions/ > $DOTFILES_DIR/gnome-shell-extensions.dconf
dconf dump /org/gnome/desktop/interface/ > $DOTFILES_DIR/gnome-settings.dconf
dconf dump /org/gnome/settings-daemon/plugins/media-keys/ > $DOTFILES_DIR/keyboard-shortcuts.dconf

cp -r ~/.config/autostart $DOTFILES_DIR/autostart
cp -r ~/.themes $DOTFILES_DIR/.themes
cp -r ~/.icons $DOTFILES_DIR/.icons

echo "GNOME configuration backed up to $DOTFILES_DIR"
