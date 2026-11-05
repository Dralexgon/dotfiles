"""The settings the daemon follows: ~/.local/state/razerfx/state.json.

The TUI and the CLI write it, the daemon reloads it when it changes. Writes
are atomic (temp file + rename), so the daemon never reads half a file.
"""

import json
import os
import time
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "razerfx"
STATE = STATE_DIR / "state.json"

DEFAULTS = {
    "effect": "static",
    "overlays": ["super-hints", "caps-lock"],
    "brightness": 1.0,  # 0..1, applied on top of every effect
    "speed": 1.0,  # animation speed multiplier
    "pomodoro": None,  # {"start": unix time, "minutes": 25}
    "flash": None,  # {"at": unix time, "colour": "#5865f2" or a name}
}


def load() -> dict:
    try:
        data = json.loads(STATE.read_text())
    except (OSError, ValueError):
        data = {}
    return {**DEFAULTS, **{k: v for k, v in data.items() if k in DEFAULTS}}


def save(data: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    tmp.replace(STATE)


def update(**changes) -> dict:
    data = load()
    data.update(changes)
    save(data)
    return data


def mtime() -> float | None:
    try:
        return STATE.stat().st_mtime_ns
    except OSError:
        return None


def flash(colour: str | None = None) -> None:
    update(flash={"at": time.time(), "colour": colour})
