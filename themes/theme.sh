WALLPAPER='default.png'
DIR="$HOME/Pictures/Wallpapers"
SHELL_THEME='Adwaita'

if [ $# != 1 ]; then
    echo "Usage: theme.sh <file.theme>"
    exit 1
fi

source "$1"

echo "Setting wallpaper to $DIR"/"$WALLPAPER"
gsettings set org.gnome.desktop.background picture-uri file://"$DIR"/"$WALLPAPER"
gsettings set org.gnome.desktop.background picture-uri-dark file://"$DIR"/"$WALLPAPER"
gsettings set org.gnome.shell.extensions.user-theme name "$SHELL_THEME"
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'

# FILE="$HOME/.config/gtk-3.0/settings.ini"
#
# # Check if the file contains a line starting with gtk-theme-name=
# if grep -q "^gtk-theme-name=" "$FILE"; then
#     # Replace existing line
#     sed -i 's/^gtk-theme-name=.*/gtk-theme-name='"$SHELL_THEME"'/' "$FILE"
# else
#     # Append if not found
#     echo 'gtk-theme-name='"$SHELL_THEME" >>"$FILE"
# fi
#
# FILE="$HOME/.config/gtk-4.0/settings.ini"
#
# # Check if the file contains a line starting with gtk-theme-name=
# if grep -q "^gtk-theme-name=" "$FILE"; then
#     # Replace existing line
#     sed -i 's/^gtk-theme-name=.*/gtk-theme-name='"$SHELL_THEME"'/' "$FILE"
# else
#     # Append if not found
#     echo 'gtk-theme-name='"$SHELL_THEME" >>"$FILE"
# fi
