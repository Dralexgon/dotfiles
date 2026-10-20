#!/usr/bin/env bash
set -Eeuo pipefail

MONITOR="DP-2"
GAME_WIDTH="3840"
GAME_HEIGHT="1620"
GAME_DIR="${ALBION_DIR:-$HOME/albiononline}"
GAME_BIN="$GAME_DIR/game_x64/Albion-Online"

command -v hyprctl >/dev/null
command -v jq >/dev/null
command -v gamescope >/dev/null

if [[ ! -x "$GAME_BIN" ]]; then
    printf 'Albion executable not found: %s\n' "$GAME_BIN" >&2
    exit 1
fi

original_scale=$(hyprctl monitors -j | jq -er \
    --arg monitor "$MONITOR" \
    '.[] | select(.name == $monitor) | .scale')

set_monitor_scale() {
    hyprctl eval \
        "hl.monitor({ output = \"$MONITOR\", mode = \"preferred\", position = \"0x0\", scale = $1 })" \
        >/dev/null
}

cleanup() {
    local exit_status=$?

    trap - EXIT INT TERM

    set_monitor_scale "$original_scale" || true

    exit "$exit_status"
}

trap cleanup EXIT INT TERM

set_monitor_scale 1

(cd "$GAME_DIR" && gamescope \
    --output-width "$GAME_WIDTH" \
    --output-height "$GAME_HEIGHT" \
    --nested-width "$GAME_WIDTH" \
    --nested-height "$GAME_HEIGHT" \
    --force-grab-cursor \
    -- "$GAME_BIN" \
    -screen-width "$GAME_WIDTH" \
    -screen-height "$GAME_HEIGHT" \
    -screen-fullscreen 0) &
gamescope_pid=$!

wait "$gamescope_pid"
