#!/usr/bin/env bash

gtk=true
icons=true

gtk_color='purple'
icons_color='#CBA6F7'
remove_icons_app=false

echo "Installing Catppuccin Gnome Theme. Special thanks to https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme"
echo "" # A little bit of space

cd /tmp || exit
git clone https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme
(
    cd Catppuccin-GTK-Theme || exit
    (
        if [ "$gtk" = true ]; then
            cd themes || return
            ./install.sh -l --theme "$gtk_color" --color dark --tweaks outline macchiato float
        fi
    )
    (
        if [ "$icons" = true ]; then
            cd icons || return
            (
                cd Catppuccin-Macchiato || return
                if [ "$remove_icons_app" = true ]; then
                    rm -rf apps
                fi
                (
                    cd places || return
                    find . -type f -name 'folder-oomox*.svg' -exec sed -i "s/#7DC4E4/$icons_color/g" {} +
                )

            )
            mkdir -p ~/.icons
            cp -r Catppuccin-Macchiato ~/.icons
        fi
    )
)
rm -rf Catppuccin-GTK-Theme

echo "Catppuccin Gnome Theme installed"
