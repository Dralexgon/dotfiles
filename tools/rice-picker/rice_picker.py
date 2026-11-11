#!/usr/bin/env python3
"""rice-picker: a small window to switch rices (adaptive / petals / vampire).

Each card shows the rice's palette; clicking one (or pressing 1-3, or Enter on it) calls
`hyprctl eval "set_rice('<name>')"`, the same function as SUPER + SHIFT + R and `rice <name>`
(config/caelestia/hypr-user.lua, "Rices"). The window takes the colours of the current scheme
and follows it live when the scheme changes.

One instance only: launching it again while it is open closes it when it has the focus,
or brings it up otherwise. Escape, Ctrl + W and Ctrl + Q close it.

Usage: rice-picker [--list | --set NAME]
"""

import json
import os
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
DOTFILES = Path(os.environ.get("RICE_PICKER_DOTFILES", HOME / "dotfiles"))
SCHEMES = DOTFILES / "config/caelestia/schemes"
RICE_STATE = HOME / ".local/state/caelestia/rice"
SCHEME_STATE = HOME / ".local/state/caelestia/scheme.json"
APP_ID = "dev.dralexgon.RicePicker"  # also the Wayland app id, matched by the Hyprland window rule

# Keep in sync with RICES / RICE_ORDER in config/caelestia/hypr-user.lua.
# scheme: (name, flavour, mode) of the file in config/caelestia/schemes, None = from the wallpaper
RICES = [
    {"name": "adaptive", "title": "Adaptive", "icon": "🎨",
     "tagline": "Colours follow the wallpaper", "effects": "default windows · adaptive trail",
     "scheme": None},
    {"name": "petals", "title": "Petals", "icon": "🌸",
     "tagline": "Pink and soft", "effects": "petal windows · petal cursor",
     "scheme": ("petals", "soft", "dark")},
    {"name": "vampire", "title": "Vampire", "icon": "🩸",
     "tagline": "Bright red and bloody — for the Empress", "effects": "bleeding windows · blood cursor · red trail",
     "scheme": ("vampire", "hard", "dark")},
]
SWATCHES = ("primary", "secondary", "tertiary", "surfaceContainer", "background")

# used when scheme.json is missing or broken
FALLBACK = {"background": "0A0506", "onBackground": "EFE3E4", "surfaceContainer": "0D0607",
            "surfaceContainerHigh": "120809", "primary": "C8102E", "onPrimary": "FFFFFF",
            "outline": "6B4A4F", "onSurfaceVariant": "CDB6B9"}


def read_scheme_file(name, flavour, mode):
    colours = {}
    try:
        for line in (SCHEMES / name / flavour / f"{mode}.txt").read_text().splitlines():
            parts = line.split()
            if len(parts) == 2:
                colours[parts[0]] = parts[1].lstrip("#")
    except OSError:
        pass
    return colours


def current_colours():
    try:
        return {**FALLBACK, **json.loads(SCHEME_STATE.read_text())["colours"]}
    except (OSError, ValueError, KeyError):
        return dict(FALLBACK)


def current_rice():
    try:
        name = RICE_STATE.read_text().strip()
    except OSError:
        name = ""
    names = [r["name"] for r in RICES]
    return name if name in names else "vampire"  # same default as read_rice() in hypr-user.lua


def set_rice(name):
    """Asks Hyprland to switch; returns an error message or None."""
    try:
        out = subprocess.run(["hyprctl", "eval", f"set_rice('{name}')"],
                             capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired) as e:
        return str(e)
    text = (out.stdout + out.stderr).strip()
    if out.returncode != 0 or "error" in text.lower():
        return text or f"hyprctl exited with {out.returncode}"
    return None


def palette(rice):
    if rice["scheme"]:
        return read_scheme_file(*rice["scheme"])
    # adaptive: show the live colours when it is the current rice, else a rainbow (see CSS)
    return current_colours() if current_rice() == "adaptive" else {}


# ---------------------------------------------------------------- GTK window

def run_gui():
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Gdk", "4.0")
    from gi.repository import Gdk, Gio, GLib, Gtk

    class Picker(Gtk.Application):
        def __init__(self):
            super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
            self.window = None
            self.css = Gtk.CssProvider()
            self.cards = {}
            self.monitors = []
            self.status = None
            self.reload_pending = False

        # ---- lifecycle
        def do_activate(self):
            if self.window and self.window.is_active():
                self.window.close()
                return
            if not self.window:
                self.window = self.build()
                Gtk.StyleContext.add_provider_for_display(
                    Gdk.Display.get_default(), self.css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
                self.watch(SCHEME_STATE)
                self.watch(RICE_STATE)
            self.refresh()
            self.window.present()
            self.cards[current_rice()].grab_focus()

        def watch(self, path):
            mon = Gio.File.new_for_path(str(path)).monitor_file(Gio.FileMonitorFlags.NONE, None)
            mon.connect("changed", lambda *_: self.schedule_refresh())
            self.monitors.append(mon)  # keep a reference or it stops

        def schedule_refresh(self):
            # caelestia writes scheme.json in several steps: refresh once it settles
            if not self.reload_pending:
                self.reload_pending = True
                GLib.timeout_add(150, self.refresh)

        # ---- widgets
        def build(self):
            win = Gtk.ApplicationWindow(application=self, title="Rices")
            win.set_default_size(980, 380)
            win.add_css_class("rice-picker")

            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
            box.add_css_class("content")

            header = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            title = Gtk.Label(label="Choose your rice", xalign=0)
            title.add_css_class("title")
            sub = Gtk.Label(label="Click a card, or press 1 – 3.  SUPER + SHIFT + R cycles them too.", xalign=0)
            sub.add_css_class("subtitle")
            header.append(title)
            header.append(sub)
            box.append(header)

            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16, homogeneous=True, vexpand=True)
            for i, rice in enumerate(RICES, 1):
                card = self.make_card(rice, i)
                self.cards[rice["name"]] = card
                row.append(card)
            box.append(row)

            self.status = Gtk.Label(xalign=0)
            self.status.add_css_class("status")
            box.append(self.status)
            win.set_child(box)

            keys = Gtk.EventControllerKey()
            keys.connect("key-pressed", self.on_key)
            win.add_controller(keys)
            return win

        def make_card(self, rice, index):
            card = Gtk.Button()
            card.add_css_class("card")
            card.add_css_class(f"rice-{rice['name']}")
            card.connect("clicked", lambda *_: self.pick(rice["name"]))

            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            top = Gtk.Box(spacing=10)
            icon = Gtk.Label(label=rice["icon"])
            icon.add_css_class("icon")
            name = Gtk.Label(label=rice["title"], xalign=0, hexpand=True)
            name.add_css_class("name")
            badge = Gtk.Label(label="current")
            badge.add_css_class("badge")
            key = Gtk.Label(label=str(index))
            key.add_css_class("key")
            for w in (icon, name, badge, key):
                top.append(w)
            inner.append(top)

            swatches = Gtk.Box(spacing=6, homogeneous=True)
            swatches.add_css_class("swatches")
            for role in SWATCHES:
                sw = Gtk.Box(hexpand=True)
                sw.add_css_class("swatch")
                sw.add_css_class(f"sw-{rice['name']}-{role}")
                sw.set_tooltip_text(role)
                swatches.append(sw)
            inner.append(swatches)

            tagline = Gtk.Label(label=rice["tagline"], xalign=0, wrap=True)
            tagline.add_css_class("tagline")
            effects = Gtk.Label(label=rice["effects"], xalign=0, wrap=True)
            effects.add_css_class("effects")
            inner.append(tagline)
            inner.append(effects)

            card.set_child(inner)
            card.badge = badge
            return card

        # ---- actions
        def on_key(self, _ctrl, keyval, _code, state):
            name = Gdk.keyval_name(keyval) or ""
            ctrl = state & Gdk.ModifierType.CONTROL_MASK
            if name == "Escape" or (ctrl and name in ("w", "q")):
                self.window.close()
                return True
            if name in ("1", "2", "3", "KP_1", "KP_2", "KP_3"):
                i = int(name[-1]) - 1
                if i < len(RICES):
                    self.pick(RICES[i]["name"])
                return True
            return False

        def pick(self, name):
            self.status.set_text(f"Switching to {name}…")
            self.status.remove_css_class("error")
            err = set_rice(name)
            if err:
                self.status.set_text(f"Could not switch: {err}")
                self.status.add_css_class("error")
            else:
                self.status.set_text("")
            self.refresh()

        # ---- colours
        def refresh(self):
            self.reload_pending = False
            cur = current_rice()
            for name, card in self.cards.items():
                if name == cur:
                    card.add_css_class("active")
                else:
                    card.remove_css_class("active")
                card.badge.set_visible(name == cur)
            self.css.load_from_string(self.stylesheet())
            return False  # GLib.timeout_add: run once

        def stylesheet(self):
            c = current_colours()

            def col(key, fallback="888888"):
                return "#" + c.get(key, fallback)

            css = f"""
            window.rice-picker {{ background: {col('background')}; color: {col('onBackground')}; }}
            .content {{ padding: 28px; }}
            .title {{ font-size: 22pt; font-weight: 800; }}
            .subtitle, .effects {{ color: {col('onSurfaceVariant')}; }}
            .status {{ color: {col('onSurfaceVariant')}; min-height: 1.2em; }}
            .status.error {{ color: #{c.get('error', 'FF5449')}; }}
            button.card {{
                background: {col('surfaceContainer')}; color: {col('onBackground')};
                border: 2px solid transparent; border-radius: 18px; padding: 18px;
                box-shadow: none; transition: all 150ms ease;
            }}
            button.card:hover {{ background: {col('surfaceContainerHigh')}; }}
            button.card:focus-visible {{ border-color: {col('outline')}; }}
            button.card.active {{ border-color: {col('primary')}; }}
            .icon {{ font-size: 22pt; }}
            .name {{ font-size: 16pt; font-weight: 700; }}
            .badge {{
                background: {col('primary')}; color: {col('onPrimary')};
                border-radius: 999px; padding: 2px 10px; font-size: 9pt; font-weight: 700;
            }}
            .key {{
                border: 1px solid {col('outline')}; color: {col('onSurfaceVariant')};
                border-radius: 6px; padding: 0 7px; font-size: 9pt;
            }}
            .swatch {{ min-height: 64px; border-radius: 10px; border: 1px solid alpha({col('outline')}, 0.4); }}
            .tagline {{ font-weight: 600; }}
            """
            rainbow = ["#ff6b6b", "#ffd166", "#06d6a0", "#4cc9f0", "#9b5de5"]
            for rice in RICES:
                pal = palette(rice)
                for i, role in enumerate(SWATCHES):
                    if role in pal:
                        bg = "#" + pal[role]
                    else:
                        bg = f"linear-gradient(135deg, {rainbow[i]}, {rainbow[(i + 1) % 5]})"
                    css += f".sw-{rice['name']}-{role} {{ background: {bg}; }}\n"
            return css

    return Picker().run(None)


def main():
    args = sys.argv[1:]
    if args[:1] == ["--list"]:
        cur = current_rice()
        for r in RICES:
            print(("* " if r["name"] == cur else "  ") + r["name"])
        return 0
    if args[:1] == ["--set"] and len(args) == 2:
        err = set_rice(args[1])
        if err:
            print(err, file=sys.stderr)
            return 1
        return 0
    if args:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    return run_gui()


if __name__ == "__main__":
    sys.exit(main())
