#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER="$SCRIPT_DIR/fix-albion-desktop.sh"
USER_APPS="$HOME/.local/share/applications"
NORMAL_DESKTOP="sandbox-interactive_com-albiononline_1.desktop"
BIGGER_DESKTOP="sandbox-interactive_com-albiononline_1-bigger-resolution.desktop"
DEFAULT_ALBION_LAUNCHER="${ALBION_DIR:-$HOME/games/albiononline}/Albion-Online"

is_wrapper_exec() {
    grep -Eq '^Exec=.*fix-albion-desktop\.sh([[:space:]]|$)' "$1"
}

if [[ ! -x "$LAUNCHER" ]]; then
    printf 'Launcher not found or not executable: %s\n' "$LAUNCHER" >&2
    exit 1
fi

mkdir -p "$USER_APPS"

source_file=""
for candidate in \
    "$HOME/Desktop/$NORMAL_DESKTOP" \
    "/run/current-system/sw/share/applications/$NORMAL_DESKTOP" \
    "$USER_APPS/$NORMAL_DESKTOP.original" \
    "$USER_APPS/$NORMAL_DESKTOP"; do
    if [[ -f "$candidate" ]]; then
        source_file="$candidate"
        break
    fi
done

if [[ -z "$source_file" ]]; then
    printf 'Albion desktop file not found. Reinstall Albion first.\n' >&2
    exit 1
fi

normal_target="$USER_APPS/$NORMAL_DESKTOP"
if [[ "$source_file" != "$normal_target" ]]; then
    cp --no-preserve=mode "$source_file" "$normal_target"
fi

if is_wrapper_exec "$normal_target"; then
    if [[ -x "$DEFAULT_ALBION_LAUNCHER" ]]; then
        sed -i "s|^Exec=.*|Exec=$DEFAULT_ALBION_LAUNCHER|" "$normal_target"
    else
        printf 'Normal launcher Exec is broken and default launcher not found: %s\n' "$DEFAULT_ALBION_LAUNCHER" >&2
        exit 1
    fi
fi

backup="$normal_target.original"
if [[ ! -e "$backup" ]]; then
    cp "$normal_target" "$backup"
elif is_wrapper_exec "$backup"; then
    cp "$normal_target" "$backup"
fi

bigger_target="$USER_APPS/$BIGGER_DESKTOP"
cp --no-preserve=mode "$normal_target" "$bigger_target"

if grep -q '^Name=' "$bigger_target"; then
    sed -i 's|^Name=.*|Name=Albion (bigger resolution)|' "$bigger_target"
else
    printf 'Name=Albion (bigger resolution)\n' >>"$bigger_target"
fi

if grep -q '^Exec=' "$bigger_target"; then
    sed -i "s|^Exec=.*|Exec=$LAUNCHER|" "$bigger_target"
else
    printf 'Exec=%s\n' "$LAUNCHER" >>"$bigger_target"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$USER_APPS" >/dev/null 2>&1 || true
fi

printf 'Installed Albion launchers:\n- Normal: %s\n- Bigger resolution: %s\n' \
    "$normal_target" \
    "$bigger_target"
grep '^Name=\|^Exec=' "$bigger_target"
