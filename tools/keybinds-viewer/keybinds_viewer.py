#!/usr/bin/env python3
"""keybinds-viewer: draws the keyboard with every Hyprland keybind on it.

Reads the live binds from `hyprctl binds -j`, names them, puts them into
index.html (next to this file) and shows the page.

Where the names come from, first match wins:
  1. the bind's own description (hl.bind(key, action, { description = "..." }))
  2. Caelestia's keybind variables (~/.config/hypr/variables.lua, overridden by
     ~/.config/caelestia/hypr-vars.lua): the bind is matched by its key combo
  3. the few binds Caelestia writes without a variable (LITERALS below)
  4. the dispatcher name (Hyprland's Lua config hides the arguments)

Usage: keybinds-viewer [--browser] [--json] [--no-open] [-o FILE]
Opens in its own window (window.py, GTK4 + WebKitGTK), or the browser with --browser.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict, deque
from pathlib import Path

HOME = Path.home()
HYPR_VARS = HOME / ".config/hypr/variables.lua"
USER_VARS = HOME / ".config/caelestia/hypr-vars.lua"
SCHEME = HOME / ".local/state/caelestia/scheme.json"
TEMPLATE = Path(os.environ.get("KEYBINDS_VIEWER_TEMPLATE", Path(__file__).with_name("index.html")))

# Hyprland's modmask bits
MODS = {"SHIFT": 1, "CAPS": 2, "CTRL": 4, "CONTROL": 4, "ALT": 8, "MOD2": 16,
        "MOD3": 32, "SUPER": 64, "WIN": 64, "LOGO": 64, "MOD4": 64, "MOD5": 128}

# xkb keycodes of binds made with code:NN (they come without a key name)
KEYCODES = {66: "caps_lock", 9: "escape", 23: "tab", 36: "return", 65: "space"}

# Caelestia's keybind variables, in the order hyprland/keybinds.lua creates them
# (binds sharing a combo are matched in that order). name: (label, category, extra combos)
VARS = {
    "kbLauncher": ("App launcher (tap)", "shell", []),
    "kbSession": ("Session menu", "shell", []),
    "kbShowSidebar": ("Sidebar", "shell", []),
    "kbClearNotifs": ("Clear notifications", "shell", []),
    "kbShowPanels": ("Show all panels", "shell", []),
    "kbLock": ("Lock screen", "system", []),
    "kbRestoreLock": ("Restore lock screen", "system", []),
    "kbPrevWs": ("Previous workspace", "workspaces", []),
    "kbNextWs": ("Next workspace", "workspaces", []),
    "kbPrevWsGroup": ("Previous workspace group", "workspaces", []),
    "kbNextWsGroup": ("Next workspace group", "workspaces", []),
    "kbMoveWinToWsNext": ("Move window to next workspace", "workspaces", []),
    "kbMoveWinToWsPrev": ("Move window to previous workspace", "workspaces", []),
    "kbMoveWinToWsSpecial": ("Move window to scratchpad", "workspaces", []),
    "kbMoveWinFromWsSpecial": ("Move window out of scratchpad", "workspaces", []),
    "kbWindowCycleNext": ("Next window", "windows", []),
    "kbWindowCyclePrev": ("Previous window", "windows", []),
    "kbWindowGroupCycleNext": ("Next window in group", "windows", []),
    "kbWindowGroupCyclePrev": ("Previous window in group", "windows", []),
    "kbToggleGroup": ("Toggle window group", "windows", []),
    "kbUngroup": ("Take window out of group", "windows", []),
    "kbGroupLockActive": ("Lock window group", "windows", []),
    "kbWindowDecreaseWidth": ("Narrower window", "windows", []),
    "kbWindowIncreaseWidth": ("Wider window", "windows", []),
    "kbWindowDecreaseHeight": ("Shorter window", "windows", []),
    "kbWindowIncreaseHeight": ("Taller window", "windows", []),
    "kbMoveWindow": ("Drag window (hold)", "windows", ["SUPER + mouse:272"]),
    "kbResizeWindow": ("Resize window (hold)", "windows", ["SUPER + mouse:273"]),
    "kbCenterWindow": ("Center window", "windows", []),
    "kbNormalizeWindow": ("Normal size + center", "windows", []),
    "kbWindowPip": ("Picture in picture", "windows", []),
    "kbPinWindow": ("Pin window (all workspaces)", "windows", []),
    "kbWindowFullscreen": ("Fullscreen", "windows", []),
    "kbWindowBorderedFullscreen": ("Maximize", "windows", []),
    "kbToggleWindowFloating": ("Float / tile window", "windows", []),
    "kbCloseWindow": ("Close window", "windows", []),
    "kbSpecialWs": ("Scratchpad", "workspaces", []),
    "kbSystemMonitorWs": ("System monitor", "workspaces", []),
    "kbMusicWs": ("Music workspace", "workspaces", []),
    "kbCommunicationWs": ("Communication workspace", "workspaces", []),
    "kbTodoWs": ("Todo workspace", "workspaces", []),
    "kbTerminal": ("Terminal", "apps", []),
    "kbBrowser": ("Browser", "apps", []),
    "kbEditor": ("Editor", "apps", []),
    "kbFileExplorer": ("Files", "apps", []),
    "kbAudioSettings": ("Audio settings", "apps", []),
    "kbScreenshot": ("Screenshot", "utilities", []),
    "kbScreenshotFreeze": ("Screenshot region (frozen)", "utilities", []),
    "kbScreenshotRegion": ("Screenshot region", "utilities", []),
    "kbRecord": ("Record screen", "utilities", []),
    "kbRecordSound": ("Record screen + sound", "utilities", []),
    "kbRecordRegion": ("Record region", "utilities", []),
    "kbColorPicker": ("Color picker", "utilities", []),
    "kbMediaToggle": ("Play / pause", "media", ["XF86AudioPlay", "XF86AudioPause"]),
    "kbMediaNext": ("Next track", "media", ["XF86AudioNext"]),
    "kbMediaPrev": ("Previous track", "media", ["XF86AudioPrev"]),
    "kbMediaStop": ("Stop media", "media", ["XF86AudioStop"]),
    "kbVolumeMute": ("Mute", "media", ["XF86AudioMute"]),
    "kbSleep": ("Sleep", "system", []),
    "kbClipboard": ("Clipboard history", "utilities", []),
    "kbClipboardDel": ("Delete from clipboard", "utilities", []),
    "kbEmoji": ("Emoji picker", "utilities", []),
    "kbClipboardPasteLatest": ("Type latest clipboard", "utilities", []),
}

# Modifier-only variables: the binds are modifier + 1..9, 0 (workspace 10)
WS_VARS = {
    "kbGoToWs": ("Workspace {n}", "workspaces"),
    "kbMoveWinToWs": ("Move window to workspace {n}", "workspaces"),
    "kbGoToWsGroup": ("Workspace group {n}", "workspaces"),
    "kbMoveWinToWsGroup": ("Move window to workspace group {n}", "workspaces"),
    "kbMoveWinToWsSilent": ("Send window to workspace {n} (stay)", "workspaces"),
}

# Binds Caelestia writes without a variable: (combos, label, category)
LITERALS = [
    (["CTRL + SUPER + SHIFT + R"], "Kill the shell", "shell"),
    (["CTRL + SUPER + ALT + R"], "Restart the shell", "shell"),
    *[([f"SUPER + {d}"], f"Focus window {d}", "windows") for d in ("left", "right", "up", "down")],
    *[([f"SUPER + SHIFT + {d}"], f"Move window {d}", "windows") for d in ("left", "right", "up", "down")],
    (["XF86MonBrightnessUp"], "Brightness up", "media"),
    (["XF86MonBrightnessDown"], "Brightness down", "media"),
    (["XF86AudioMicMute"], "Mute microphone", "media"),
    (["XF86AudioRaiseVolume"], "Volume up", "media"),
    (["XF86AudioLowerVolume"], "Volume down", "media"),
    (["SUPER + ALT + F12"], "Test notification", "shell"),
]

# The shell's own helpers (refresh the Caps / Num Lock indicator), not shortcuts: left out
INTERNAL = {(0, "caps_lock"), (0, "num_lock")}

# Commands shown next to the app binds
APP_CMDS = {"kbTerminal": "terminal", "kbBrowser": "browser", "kbEditor": "editor",
            "kbFileExplorer": "fileExplorer", "kbAudioSettings": "audioSettings"}

LUA_VALUE = re.compile(r'^\s*(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|\[\[.*?\]\]|\{[^}]*\})', re.M | re.S)
LUA_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"|\[\[(.*?)\]\]', re.S)


def read_lua_vars(path):
    """Plain string (or list of strings) values of a Lua table file, good enough for variables.lua."""
    try:
        text = path.read_text()
    except OSError:
        return {}
    text = re.sub(r"--(?!\[\[).*", "", text)  # comments (keeps [[ ]] strings)
    values = {}
    for name, raw in LUA_VALUE.findall(text):
        strings = [a or b for a, b in LUA_STRING.findall(raw)]
        values[name] = strings if raw.startswith("{") else (strings[0] if strings else "")
    return values


def combo_id(combo):
    """'CTRL + SUPER + R' -> (68, 'r'); a modifier-only combo -> (mask, '')."""
    mask, key = 0, ""
    for part in (p.strip() for p in combo.split("+")):
        if part.upper() in MODS:
            mask |= MODS[part.upper()]
        elif part:
            key = part
    if key.lower().startswith("code:"):
        key = KEYCODES.get(int(key[5:]), key)
    return mask, key.lower()


def mods_of(mask):
    return [m for m, bit in (("SUPER", 64), ("CTRL", 4), ("ALT", 8), ("SHIFT", 1)) if mask & bit]


def known_binds(vars_):
    """Combo -> queue of (label, category, source, detail), in creation order."""
    known = defaultdict(deque)

    def add(combos, label, cat, source, detail=""):
        for c in combos if isinstance(combos, list) else [combos]:
            if isinstance(c, str) and c.strip():
                known[combo_id(c)].append((label, cat, source, detail))

    add(vars_.get("kbLauncher", []), *VARS["kbLauncher"][:2], "kbLauncher")
    for name in ("kbSession", "kbShowSidebar", "kbClearNotifs", "kbShowPanels", "kbLock", "kbRestoreLock"):
        add(vars_.get(name, []), *VARS[name][:2], name)
    for combos, label, cat in LITERALS[:2]:
        add(combos, label, cat, "caelestia")
    for i in range(1, 11):
        for name, (label, cat) in WS_VARS.items():
            mod = vars_.get(name)
            if isinstance(mod, str) and mod.strip():
                add(f"{mod} + {i % 10}", label.format(n=i), cat, name)
    for name, (label, cat, extra) in VARS.items():
        if name in ("kbLauncher", "kbSession", "kbShowSidebar", "kbClearNotifs", "kbShowPanels", "kbLock", "kbRestoreLock"):
            continue
        detail = vars_.get(APP_CMDS[name], "") if name in APP_CMDS else ""
        val = vars_.get(name, [])
        add((val if isinstance(val, list) else [val]) + extra, label, cat, name, detail)
        if name == "kbGroupLockActive":  # the arrow binds come right after the groups
            for combos, l, c in LITERALS[2:10]:
                add(combos, l, c, "caelestia")
    for combos, label, cat in LITERALS[10:]:
        add(combos, label, cat, "caelestia")
    return known


def dispatcher_name(d):
    m = re.match(r"HL\.Dispatcher\((\w+)\)", d)
    if m:
        return m.group(1)
    return "lua function" if d.startswith("function") else d


# xkb options that switch the layout with a key combo (input:kb_options). xkb handles them itself, so they
# are not in `hyprctl binds`, but they still fire with the binds on the same combo.
# Each one is a list of (combo, label).
XKB_OPTIONS = {
    "grp:win_space_toggle": [("SUPER + space", "Next keyboard layout")],
    "grp:alt_space_toggle": [("ALT + space", "Next keyboard layout")],
    "grp:ctrl_space_toggle": [("CTRL + space", "Next keyboard layout")],
    "grp:shift_space_toggle": [("SHIFT + space", "Next keyboard layout")],
    "grp:alt_shift_toggle": [("ALT + shift_l", "Next keyboard layout"), ("SHIFT + alt_l", "Next keyboard layout")],
    "grp:ctrl_shift_toggle": [("CTRL + shift_l", "Next keyboard layout"), ("SHIFT + control_l", "Next keyboard layout")],
    "grp:ctrl_alt_toggle": [("CTRL + alt_l", "Next keyboard layout"), ("ALT + control_l", "Next keyboard layout")],
    "grp:alt_caps_toggle": [("ALT + caps_lock", "Next keyboard layout")],
    "grp:caps_toggle": [("caps_lock", "Next keyboard layout")],
    "grp:win_switch": [("super_l", "Other layout while held")],
    "grp:menu_toggle": [("menu", "Next keyboard layout")],
    "grp:lalt_toggle": [("alt_l", "Next keyboard layout")],
    "grp:rctrl_toggle": [("control_r", "Next keyboard layout")],
}


def xkb_binds():
    """Pseudo-binds for the xkb layout switching options."""
    try:
        options = subprocess.run(["hyprctl", "getoption", "input:kb_options", "-j"],
                                 capture_output=True, text=True, check=True).stdout
        options = json.loads(options).get("str", "")
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []
    found = []
    for option in (o.strip() for o in options.split(",")):
        for combo, label in XKB_OPTIONS.get(option, []):
            mask, key = combo_id(combo)
            found.append({
                "mods": mods_of(mask), "key": key, "dispatcher": "xkb", "flags": [],
                "label": label, "category": "system", "source": "xkb",
                "detail": f"input:kb_options = {option}",
            })
    return found


def hyprctl(*args):
    out = subprocess.run(["hyprctl", *args, "-j"], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def collect():
    binds = hyprctl("binds")
    vars_ = read_lua_vars(HYPR_VARS)
    vars_.update(read_lua_vars(USER_VARS))
    known = known_binds(vars_)

    result = []
    for b in binds:
        key = b["key"].lower() or KEYCODES.get(b.get("keycode", 0), "")
        if not key:
            continue
        cid = (b["modmask"], key)
        if cid in INTERNAL and b.get("non_consuming"):
            continue
        disp = dispatcher_name(b["dispatcher"])
        entry = {
            "mods": mods_of(b["modmask"]),
            "key": key,
            "dispatcher": disp,
            "flags": [f for f in ("locked", "release", "repeat", "mouse", "non_consuming") if b.get(f)],
        }
        guess = known[cid].popleft() if known.get(cid) else None
        if b.get("description"):
            entry.update(label=b["description"], category=(guess[1] if guess else "custom"),
                         source="description", detail="")
        elif guess:
            label, cat, source, detail = guess
            entry.update(label=label, category=cat, source=source, detail=detail)
        else:
            entry.update(label=disp.replace("_", " ").capitalize(), category="other",
                         source="dispatcher", detail="")
        result.append(entry)

    result += xkb_binds()

    # a bind made twice (Caelestia binds SUPER + mouse:273 both as kbResizeWindow and literally) shows once
    seen, unique = set(), []
    for e in result:
        sig = (tuple(e["mods"]), e["key"], e["label"])
        if sig not in seen:
            seen.add(sig)
            unique.append(e)
    result = unique

    # several binds on one combo all run on the same key press (a doubled identical bind is harmless)
    labels = defaultdict(set)
    for e in result:
        labels[(tuple(e["mods"]), e["key"])].add(e["label"])
    for e in result:
        e["conflict"] = len(labels[(tuple(e["mods"]), e["key"])]) > 1

    layout = "us"
    try:
        main = next((k for k in hyprctl("devices")["keyboards"] if k.get("main")), None)
        if main and "french" in main.get("active_keymap", "").lower():
            layout = "fr"
    except (subprocess.CalledProcessError, StopIteration, KeyError, json.JSONDecodeError):
        pass

    try:
        scheme = json.loads(SCHEME.read_text())
        colours, scheme_name = scheme.get("colours", {}), scheme.get("name", "")
    except (OSError, json.JSONDecodeError):
        colours, scheme_name = {}, ""

    return {"binds": result, "layout": layout, "colours": colours, "scheme": scheme_name}


def write_page(output=None):
    data = collect()
    payload = json.dumps(data).replace("</", "<\\/")
    page = TEMPLATE.read_text().replace("/*__DATA__*/null", payload)
    out = output or Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "keybinds-viewer.html"
    out.write_text(page)
    return out


def open_in_browser(out):
    subprocess.Popen(["xdg-open", out.as_uri()], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--json", action="store_true", help="print the collected binds and exit")
    ap.add_argument("--browser", action="store_true", help="open in the web browser instead of its own window")
    ap.add_argument("--no-open", action="store_true", help="write the page without opening it")
    ap.add_argument("-o", "--output", type=Path, help="where to write the page")
    args = ap.parse_args()

    try:
        if args.json:
            json.dump(collect(), sys.stdout, indent=2)
            print()
            return
        if args.no_open or args.browser:
            out = write_page(args.output)
            print(out) if args.no_open else open_in_browser(out)
            return
    except (FileNotFoundError, subprocess.CalledProcessError) as e:
        sys.exit(f"keybinds-viewer: cannot read the binds from hyprctl ({e}). Is Hyprland running?")

    try:
        import window
    except (ImportError, ValueError) as e:  # no PyGObject / WebKitGTK: python3 run by hand
        print(f"keybinds-viewer: no GTK window ({e}), using the browser", file=sys.stderr)
        open_in_browser(write_page(args.output))
        return
    sys.exit(window.run(lambda: write_page(args.output)))


if __name__ == "__main__":
    main()
