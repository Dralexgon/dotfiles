#!/bin/bash

DOTFILES_DIR=./dotfiles/gnome

dconf load /org/gnome/shell/extensions/ < $DOTFILES_DIR/gnome-shell-extensions.dconf
dconf load /org/gnome/desktop/interface/ < $DOTFILES_DIR/gnome-settings.dconf
dconf load /org/gnome/settings-daemon/plugins/media-keys/ < $DOTFILES_DIR/keyboard-shortcuts.dconf

cp -r $DOTFILES_DIR/autostart ~/.config/autostart
cp -r $DOTFILES_DIR/.themes ~/.themes
cp -r $DOTFILES_DIR/.icons ~/.icons

echo "GNOME configuration restored from $DOTFILES_DIR"
