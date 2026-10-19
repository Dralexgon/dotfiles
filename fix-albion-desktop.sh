#!/usr/bin/env bash
# fix-albion-desktop.sh: change only the Exec= line of the Albion Online .desktop file
set -euo pipefail

# Install directory: first argument, otherwise ~/albiononline
INSTALL_DIR="${1:-$HOME/albiononline}"
WIDTH="${2:-3840}"
HEIGHT="${3:-2160}"
NEW_EXEC="steam-run $INSTALL_DIR/Albion-Online -screen-width $WIDTH -screen-height $HEIGHT -screen-fullscreen 1"

# Look for the file in the usual places
FILE=$(find "$HOME/.local/share/applications" "$HOME/Desktop" /run/current-system/sw/share/applications \
    -maxdepth 1 -iname '*albion*.desktop' 2>/dev/null | head -n 1)

if [[ -z "$FILE" ]]; then
    echo "No Albion .desktop file found." >&2
    exit 1
fi
echo "Found: $FILE"

# System files are read-only (Nix store): copy to the user directory first
TARGET="$HOME/.local/share/applications/$(basename "$FILE")"
if [[ "$FILE" != "$TARGET" ]]; then
    mkdir -p "$(dirname "$TARGET")"
    cp --no-preserve=mode "$FILE" "$TARGET"
    FILE="$TARGET"
fi

cp "$FILE" "$FILE.bak"                      # backup
sed -i "s|^Exec=.*|Exec=$NEW_EXEC|" "$FILE" # only the Exec line changes

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Done. New line:"
grep '^Exec=' "$FILE"
