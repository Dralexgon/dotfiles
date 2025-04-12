WALLPAPER='default.png'
DIR="$HOME/Pictures/Wallpapers"
SHELL_THEME='Adwaita'
ICON_THEME='Adwaita'
GTK_THEME='Adwaita'

if [ $# != 1 ]; then
    echo "Usage: theme.sh <file.theme>"
    exit 1
fi

source "$1"

echo "Setting wallpaper to $DIR"/"$WALLPAPER"
gsettings set org.gnome.desktop.background picture-uri file://"$DIR"/"$WALLPAPER"
gsettings set org.gnome.desktop.background picture-uri-dark file://"$DIR"/"$WALLPAPER"
gsettings set org.gnome.shell.extensions.user-theme name "$SHELL_THEME"
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME"
gsettings set org.gnome.desktop.interface icon-theme "$ICON_THEME"

FILE="$HOME/.config/gtk-3.0/settings.ini"

# Check if the file contains a line starting with gtk-theme-name=
if grep -q "^gtk-theme-name=" "$FILE"; then
    # Replace existing line
    sed -i 's/^gtk-theme-name=.*/gtk-theme-name='"$SHELL_THEME"'/' "$FILE"
else
    # Append if not found
    echo 'gtk-theme-name='"$SHELL_THEME" >>"$FILE"
fi

FILE="$HOME/.config/gtk-4.0/settings.ini"

# Check if the file contains a line starting with gtk-theme-name=
if grep -q "^gtk-theme-name=" "$FILE"; then
    # Replace existing line
    sed -i 's/^gtk-theme-name=.*/gtk-theme-name='"$SHELL_THEME"'/' "$FILE"
else
    # Append if not found
    echo 'gtk-theme-name='"$SHELL_THEME" >>"$FILE"
fi

#libadwaita # Thanks to https://github.com/Fausto-Korpsvart/Catppuccin-GTK-Theme/blob/main/themes/install.sh
rm -rf "${HOME}/.config/gtk-4.0/"{assets,gtk.css,gtk-dark.css}

[ -d "${HOME}/.themes/${GTK_THEME}" ] || exit

echo -e "\nLink '${HOME}/.themes/${GTK_THEME}/gtk-4.0' to '${HOME}/.config/gtk-4.0' for libadwaita..."
mkdir -p "${HOME}/.config/gtk-4.0"
ln -sf "${HOME}/.themes/${GTK_THEME}/gtk-4.0/assets" "${HOME}/.config/gtk-4.0/assets"
ln -sf "${HOME}/.themes/${GTK_THEME}/gtk-4.0/gtk.css" "${HOME}/.config/gtk-4.0/gtk.css"
ln -sf "${HOME}/.themes/${GTK_THEME}/gtk-4.0/gtk-dark.css" "${HOME}/.config/gtk-4.0/gtk-dark.css"
