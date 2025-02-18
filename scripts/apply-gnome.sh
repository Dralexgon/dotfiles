#!/usr/bin/env bash

cd /tmp
git clone https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme
cd Catppuccin-GTK-Theme
(
    cd themes
    ./install.sh -l --theme purple --color dark --tweaks outline macchiato float
)
(
    cd icons/Catppuccin-Macchiato/places
    find . -type f -name 'folder-oomox*.svg' -exec sed -i 's/7DC4E4/CBA6F7/g' {} +
)
mkdir -p ~/.icons
cp -r icons/Catppuccin-Macchiato ~/.icons
