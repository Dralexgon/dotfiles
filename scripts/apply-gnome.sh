#!/usr/bin/env bash

gtk=true
icons=true

flavor="macchiato" # Available flavors : latte|macchiato
gtk_color='purple'
icons_color='#CBA6F7'
remove_icons_app=true

echo "" # A little bit of space
echo "Installing Catppuccin Gnome Theme. Special thanks to https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme"

cd /tmp || exit
git clone https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme
(
    cd Catppuccin-GTK-Theme || exit
    git reset --hard a89b477ab26f8b64062efbeb9cdffc24d2143f2b
    (
        if [ "$gtk" = true ]; then
            cd themes || return
            ./install.sh -l --theme "$gtk_color" --color dark --tweaks outline "$flavor" float
        fi
    )
    (
        if [ "$icons" = true ]; then
        (
            cd icons || return
            mkdir -p ~/.icons
            cp -r Catppuccin-Macchiato ~/.icons
            (
                cd ~/.icons/Catppuccin-Macchiato || return
                (
                    cd places || return
                    find . -type f -name 'folder-oomox*.svg' -exec sed -i "s/#7DC4E4/$icons_color/g" {} +
                )
                if [ "$remove_icons_app" = true ]; then
                    (
                        cd apps || return
                        find -L . ! -type d ! -name '*nautilus*.svg' ! -name '*file-manager*.svg' ! -name '*caja*.svg' -delete
                        find . -type f -exec sh -c 'cat ../places/64/folder.svg > "$1"' _ {} \;
                    )
                fi
                sed -i "s/Inherits=/Inherits=Adwaita,/g" index.theme
            )
        )
        fi
    )
)
# rm -rf Catppuccin-GTK-Theme

echo "Catppuccin Gnome Theme installed"
