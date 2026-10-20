#!/usr/bin/env bash
set -Eeuo pipefail

LAUNCHER="$HOME/dotfiles/fix-albion-desktop.sh"
USER_APPS="$HOME/.local/share/applications"

if [[ ! -x "$LAUNCHER" ]]; then
    printf 'Launcher not found or not executable: %s\n' "$LAUNCHER" >&2
    exit 1
fi

mkdir -p "$USER_APPS"

source_file=""
for candidate in \
    "$USER_APPS/sandbox-interactive_com-albiononline_1.desktop" \
    "$HOME/Desktop/sandbox-interactive_com-albiononline_1.desktop" \
    /run/current-system/sw/share/applications/sandbox-interactive_com-albiononline_1.desktop; do
    if [[ -f "$candidate" ]]; then
        source_file="$candidate"
        break
    fi
done

if [[ -z "$source_file" ]]; then
    printf 'Albion desktop file not found. Reinstall Albion first.\n' >&2
    exit 1
fi

target="$USER_APPS/sandbox-interactive_com-albiononline_1.desktop"
if [[ "$source_file" != "$target" ]]; then
    cp --no-preserve=mode "$source_file" "$target"
fi

backup="$target.original"
if [[ ! -e "$backup" ]]; then
    cp "$target" "$backup"
fi

sed -i "s|^Exec=.*|Exec=$LAUNCHER|" "$target"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$USER_APPS" >/dev/null 2>&1 || true
fi

printf 'Installed Albion game-mode launcher:\n%s\n' "$target"
grep '^Exec=' "$target"
