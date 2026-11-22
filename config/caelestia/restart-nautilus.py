#!/usr/bin/env python3
"""Restart Nautilus so it loads the new gtk.css, and put its windows back where they were.

Nautilus reads gtk.css only at startup, so a colour change needs a restart. To keep the layout:

- a tiled window gets a placeholder (an empty foot window) swapped into its slot before Nautilus
  quits. The new Nautilus window is then swapped with the placeholder, so it lands in the same
  slot of the same workspace with the same split ratios.
- a floating window gets its workspace, position and size back.

Tabs can not be reopened as tabs: each extra tab comes back as a window on the same workspace.
"""

import json
import os
import re
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse

NAUTILUS_CLASS = "org.gnome.Nautilus"
PLACEHOLDER_ID = f"caelestia-placeholder-{os.getpid()}"


def log(*args):
    print("restart-nautilus:", *args, flush=True)


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def dispatch(lua):
    out = run("hyprctl", "dispatch", lua).strip()
    if out != "ok":
        log(f"dispatch failed: {lua} -> {out}")
    return out == "ok"


def clients():
    try:
        return json.loads(run("hyprctl", "clients", "-j"))
    except json.JSONDecodeError:
        return []


def nautilus_clients():
    return [c for c in clients() if c["class"] == NAUTILUS_CLASS]


def nautilus_running():
    # By bus name: the process itself is called .nautilus-wrapped on NixOS
    return re.search(r"^org\.gnome\.Nautilus ", run("busctl", "--user", "list", "--acquired"), re.M)


def wait_for(condition, timeout=5.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = condition()
        if result:
            return result
        time.sleep(0.05)
    return None


def workspace_of(client):
    ws = client["workspace"]
    return str(ws["id"]) if ws.get("id", 0) > 0 else ws.get("name", "")


def open_folders():
    """Folders (URIs) of each Nautilus window, one list per window."""
    out = run(
        "busctl", "--user", "--json=short", "get-property", "org.freedesktop.FileManager1",
        "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", "OpenWindowsWithLocations",
    )
    try:
        return [uris for uris in json.loads(out)["data"].values() if uris]
    except (json.JSONDecodeError, KeyError):
        return []


def match_folders(old, folders):
    """Pair each Hyprland window with the folders of its Nautilus window, by window title."""
    home = os.path.expanduser("~")
    left = list(folders)
    pairs = {}
    for c in old:
        for uris in left:
            names = set()
            for uri in uris:
                path = unquote(urlparse(uri).path).rstrip("/")
                names.add("Home" if path == home else os.path.basename(path))
            if c["title"] in names:
                pairs[c["address"]] = uris
                left.remove(uris)
                break
    # Titles that did not match (search, Recent, translated names): pair in order
    for c in old:
        if c["address"] not in pairs and left:
            pairs[c["address"]] = left.pop(0)
    return pairs, left


def window_bg():
    try:
        css = open(os.path.expanduser("~/.config/gtk-4.0/gtk.css")).read()
        return re.search(r"window_bg_color\s+#([0-9a-fA-F]{6})", css).group(1)
    except (OSError, AttributeError):
        return "000000"


def place_placeholder(client, index, bg):
    """Open a placeholder on the window's workspace and swap it into the window's slot."""
    app_id = f"{PLACEHOLDER_ID}-{index}"
    cmd = f"foot --app-id={app_id} -o colors-dark.background={bg} sleep 60"
    dispatch(f'hl.dsp.exec_cmd("{cmd}", {{ workspace = "{workspace_of(client)} silent" }})')
    found = wait_for(lambda: [c for c in clients() if c["class"] == app_id], timeout=3)
    if not found:
        return None
    address = found[0]["address"]
    if not dispatch(f'hl.dsp.window.swap({{ window = "address:{address}", target = "address:{client["address"]}" }})'):
        return None
    return address


def silent_rule(workspace, enabled):
    """Window rule that opens Nautilus windows on a workspace without showing or focusing them.

    Without it a new window pops up on the current workspace and takes the keyboard. The rules
    are kept in a Lua global and only switched on while a window is being opened.
    """
    ws = workspace.replace("\\", "").replace("'", "")
    lua = (
        "caelestia_nautilus_rules = caelestia_nautilus_rules or {} "
        f"local r = caelestia_nautilus_rules['{ws}'] "
        f"if r then r:set_enabled({str(enabled).lower()}) "
        f"elseif {str(enabled).lower()} then caelestia_nautilus_rules['{ws}'] = hl.window_rule("
        f"{{ match = {{ class = '^org\\\\.gnome\\\\.Nautilus$' }}, workspace = '{ws} silent' }}) end"
    )
    run("hyprctl", "eval", lua)


def open_window(uri, known, workspace):
    """Open a Nautilus window on a folder, out of sight on a workspace; return its Hyprland client."""
    if urlparse(uri).scheme == "x-nautilus-search":
        uri = "file://" + os.path.expanduser("~")  # a search can not be reopened
    silent_rule(workspace, True)
    try:
        subprocess.Popen(
            ["nautilus", "--new-window", uri],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True,
        )
        new = wait_for(lambda: [c for c in nautilus_clients() if c["address"] not in known])
    finally:
        silent_rule(workspace, False)
    if not new:
        log(f"no window appeared for {uri}")
        return None
    known.add(new[0]["address"])
    return new[0]


def restore(new, old, placeholder):
    win = f'window = "address:{new["address"]}"'
    if placeholder:
        dispatch(f'hl.dsp.window.swap({{ {win}, target = "address:{placeholder}" }})')
        return
    if workspace_of(new) != workspace_of(old):
        dispatch(f'hl.dsp.window.move({{ {win}, workspace = "{workspace_of(old)}", follow = false }})')
    if old["floating"]:
        dispatch(f'hl.dsp.window.float({{ action = "on", {win} }})')
        dispatch(f'hl.dsp.window.resize({{ x = {old["size"][0]}, y = {old["size"][1]}, {win} }})')
        dispatch(f'hl.dsp.window.move({{ x = {old["at"][0]}, y = {old["at"][1]}, relative = false, {win} }})')


def main():
    if not nautilus_running():
        return
    old = sorted(nautilus_clients(), key=lambda c: (workspace_of(c), c["at"]))
    pairs, extra = match_folders(old, open_folders())
    try:
        focused = json.loads(run("hyprctl", "activewindow", "-j")).get("address")
    except json.JSONDecodeError:
        focused = None

    bg = window_bg()
    placeholders = {}
    try:
        for i, c in enumerate(old):
            if not c["floating"] and c["address"] in pairs:
                placeholders[c["address"]] = place_placeholder(c, i, bg)

        subprocess.run(["nautilus", "-q"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if not wait_for(lambda: not nautilus_running() and not nautilus_clients()):
            log("nautilus did not quit, nothing reopened")
            return

        known = set()
        refocus = None
        for c in old:
            for n, uri in enumerate(pairs.get(c["address"], [])):
                new = open_window(uri, known, workspace_of(c))
                if not new:
                    continue
                # Extra tabs have no slot of their own: they only go back to the workspace
                restore(new, c, placeholders.get(c["address"]) if n == 0 else None)
                if n == 0 and c["address"] == focused:
                    refocus = new["address"]
        active = json.loads(run("hyprctl", "activeworkspace", "-j"))
        for uris in extra:
            for uri in uris:
                open_window(uri, known, workspace_of({"workspace": active}))

        # A focused Nautilus window gets the focus back
        if refocus:
            dispatch(f'hl.dsp.focus({{ window = "address:{refocus}" }})')
        log(f"restarted, {len(known)} window(s) reopened")
    finally:
        subprocess.run(["pkill", "-f", f"foot --app-id={PLACEHOLDER_ID}"])


if __name__ == "__main__":
    sys.exit(main())
