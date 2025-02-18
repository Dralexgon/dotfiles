#!/usr/bin/env bash

SYMLINKS=false
REMOVE_TARGET=true # Will remove folder in .config if it already exists
NIXOS=true         # Will be disabled if not on NixOS, set it to false only if you are on NixOS AND don't want to apply the NixOS configuration

DOTFILES_DIR=./config

# Gnome

# dconf load /org/gnome/shell/extensions/ <$DOTFILES_DIR/gnome/gnome-shell-extensions.dconf
# dconf load /org/gnome/desktop/interface/ <$DOTFILES_DIR/gnome/gnome-settings.dconf
# dconf load /org/gnome/settings-daemon/plugins/media-keys/ <$DOTFILES_DIR/gnome/keyboard-shortcuts.dconf

# if $SYMLINKS; then
#     ln -s $DOTFILES_DIR/gnome/autostart ~/.config/autostart
#     ln -s $DOTFILES_DIR/gnome/.themes ~/.themes
#     ln -s $DOTFILES_DIR/gnome/.icons ~/.icons
# else
#     cp -r $DOTFILES_DIR/gnome/autostart ~/.config/autostart
#     cp -r $DOTFILES_DIR/gnome/.themes ~/.themes
#     cp -r $DOTFILES_DIR/gnome/.icons ~/.icons
# fi

# GTK theme

cd /tmp
git clone https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme
cd Catppuccin-GTK-Theme/themes
nix-shell -p sassc
./install.sh -l --theme purple --color dark
cd ..
mkdir -p ~/.icons
cp -r icons/Catppuccin-Macchiato ~/.icons
find . -type f -name 'folder-oomox*.svg' -exec sed -i 's/7DC4E4/CBA6F7/g' {} +

# Bashrc

if $SYMLINKS; then
    ln -s $DOTFILES_DIR/bash/bashrc ~/.bashrc
else
    cp $DOTFILES_DIR/bash/bashrc ~/.bashrc
fi

# Hyprland

for var in hypr kitty rofi waybar nvim; do
    if [ ! -d $DOTFILES_DIR/$var ]; then
        echo "Error: $DOTFILES_DIR/$var does not exist"
        exit 1
    fi
    if [ -e ~/.config/$var ]; then
        if $REMOVE_TARGET; then
            rm -r ~/.config/$var
        else
            echo "Error: ~/.config/$var already exists"
            exit 1
        fi
    fi
    if $SYMLINKS; then
        ln -s $DOTFILES_DIR/$var ~/.config
    else
        cp -r $DOTFILES_DIR/$var ~/.config
    fi
done

# Nixos

# if $NIXOS && grep -q nixos </etc/os-release; then
#     if $SYMLINKS; then
#         sudo ln -s nixos /etc
#     else
#         sudo cp -r nixos /etc
#     fi
# fi

echo "Completed"
