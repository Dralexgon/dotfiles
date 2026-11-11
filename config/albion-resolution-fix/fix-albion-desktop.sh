#!/usr/bin/env bash
set -Eeuo pipefail

# Monitor to rescale: $ALBION_MONITOR if set, else the focused one (names change with ports/cables).
MONITOR="${ALBION_MONITOR:-$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)}"
GAME_WIDTH="3840"
GAME_HEIGHT="1620" # even larger : 1620
GAME_DIR="${ALBION_DIR:-$HOME/games/albiononline}"
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

original_sensitivity=$(hyprctl getoption input:sensitivity 2>/dev/null \
    | sed -E 's/.*([+-]?[0-9]+(\.[0-9]+)?).*/\1/' \
    || printf '0\n')

set_monitor_scale() {
    local target_scale="$1"

    hyprctl eval \
        "hl.monitor({ output = \"$MONITOR\", mode = \"preferred\", position = \"0x0\", scale = $target_scale })" \
        >/dev/null

    local adjusted_sensitivity
    adjusted_sensitivity=$(awk -v orig_sensitivity="$original_sensitivity" \
        -v original_monitor_scale="$original_scale" \
        -v target_monitor_scale="$target_scale" '
        BEGIN {
            if (original_monitor_scale <= 0 || target_monitor_scale <= 0) {
                print orig_sensitivity
                exit
            }

            value = orig_sensitivity * (original_monitor_scale / target_monitor_scale)

            if (value < -1) value = -1
            if (value > 1) value = 1

            printf "%.4f", value
        }')

    hyprctl keyword "input:sensitivity" "$adjusted_sensitivity" >/dev/null || true
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
