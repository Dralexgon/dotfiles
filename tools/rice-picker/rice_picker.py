#!/usr/bin/env python3
"""rice-picker: a small window to switch rices, and to edit or create them.

Rices are files in ~/.config/caelestia/rices/<name>.json (config/caelestia/rices, see its README).
Each card shows the rice's palette; clicking one (or pressing 1-9, or Enter on it) calls
`hyprctl eval "set_rice('<name>')"`, the same function as SUPER + SHIFT + R and `rice <name>`
(config/caelestia/hypr-user.lua, "Rices"). The ⚙ button on a card unfolds that rice's settings;
"New rice" copies the current one under a new name. The window takes the colours of the
current scheme and follows it live when the scheme changes.

`--apply NAME` is the shell side of a switch, run by set_rice(): the Caelestia scheme, the
wallpaper, the cursor and the fonts (set_rice() itself does the Hyprland side).

One instance only: launching it again while it is open closes it when it has the focus,
or brings it up otherwise. Escape, Ctrl + W and Ctrl + Q close it.

Usage: rice-picker [--list | --set NAME | --apply NAME]
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
DOTFILES = Path(os.environ.get("RICE_PICKER_DOTFILES", HOME / "dotfiles"))
CAELESTIA = HOME / ".config/caelestia"  # a symlink to config/caelestia
if not (CAELESTIA / "rices").is_dir():
    CAELESTIA = DOTFILES / "config/caelestia"
RICES_DIR = CAELESTIA / "rices"
SCHEMES = CAELESTIA / "schemes"
SHELL_JSON = CAELESTIA / "shell.json"
RICE_STATE = HOME / ".local/state/caelestia/rice"
SCHEME_STATE = HOME / ".local/state/caelestia/scheme.json"
APP_ID = "dev.dralexgon.RicePicker"  # also the Wayland app id, matched by the Hyprland window rule
DEFAULT_RICE = "vampire"  # same as DEFAULT_RICE in hypr-user.lua

# Key order in the files, and the values a new key gets
DEFAULTS = {
    "order": None, "title": "", "icon": "✨", "tagline": "", "effects": "",
    "scheme": None, "wallpaper": None,
    "windowfx": "off", "cursorfx": "off", "trail": None, "transition": None,
    "cursor": {"theme": "Bibata-Modern-Classic", "size": 24},
    "font": {"sans": None, "mono": None},
    "animations": {},
}
WINDOWFX = ["off", "petals", "blood", "blood-legacy"]
CURSORFX = ["off", "petals", "blood", "image"]
ANIM_LEAVES = ["windowsIn", "windowsOut"]  # always shown in the settings
SWATCHES = ("primary", "secondary", "tertiary", "surfaceContainer", "background")
FOLDED, UNFOLDED = (980, 380), (980, 880)  # window size; the folded one is the Hyprland window rule

# used when scheme.json is missing or broken
FALLBACK = {"background": "0A0506", "onBackground": "EFE3E4", "surfaceContainer": "0D0607",
            "surfaceContainerHigh": "120809", "primary": "C8102E", "onPrimary": "FFFFFF",
            "outline": "6B4A4F", "onSurfaceVariant": "CDB6B9"}


# ---------------------------------------------------------------- rice files

def load_rices():
    """{name: rice}, sorted by "order" then name. Broken files are skipped (and printed)."""
    rices = {}
    for path in sorted(RICES_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text())
        except (OSError, ValueError) as e:
            print(f"rice {path.stem}: {e}", file=sys.stderr)
            continue
        if isinstance(data, dict):
            rices[path.stem] = {**DEFAULTS, **data, "name": path.stem}
    return dict(sorted(rices.items(), key=lambda kv: (
        kv[1]["order"] if isinstance(kv[1]["order"], (int, float)) else float("inf"), kv[0])))


def save_rice(rice):
    data = {k: rice.get(k, v) for k, v in DEFAULTS.items()}
    data.update({k: v for k, v in rice.items() if k not in DEFAULTS and k != "name"})
    RICES_DIR.mkdir(parents=True, exist_ok=True)
    (RICES_DIR / f"{rice['name']}.json").write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n")


def valid_name(name):
    return re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name or "") is not None


def wallpaper_path(value):
    """The rice's wallpaper as an absolute path: "~/..." or relative to the rices folder."""
    if not value:
        return None
    path = Path(value).expanduser()
    # resolve(): RICES_DIR goes through the ~/.config/caelestia symlink, and "../" must climb the
    # real folders (config/caelestia/rices -> the dotfiles), not the symlink's
    return path if path.is_absolute() else (RICES_DIR / path).resolve()


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


def scheme_choices():
    """Every (name, flavour) Caelestia knows, dynamic first; the local schemes if it can't say."""
    try:
        out = subprocess.run(["caelestia", "scheme", "list"], capture_output=True, text=True, timeout=5)
        schemes = {n: list(f) for n, f in json.loads(out.stdout).items()}
    except (OSError, ValueError, subprocess.TimeoutExpired, AttributeError):
        schemes = {d.name: sorted(f.name for f in d.iterdir() if f.is_dir())
                   for d in SCHEMES.iterdir() if d.is_dir()} if SCHEMES.is_dir() else {}
    schemes.pop("dynamic", None)
    return [(n, f) for n in sorted(schemes) for f in schemes[n]]


def cursor_themes():
    dirs = [HOME / ".icons", HOME / ".local/share/icons", Path("/run/current-system/sw/share/icons"),
            Path("/usr/share/icons")]
    dirs += [Path(d) / "icons" for d in os.environ.get("XDG_DATA_DIRS", "").split(":") if d]
    found = set()
    for d in dirs:
        try:
            found.update(t.name for t in d.iterdir() if (t / "cursors").is_dir())
        except OSError:
            pass
    return sorted(found)


def current_colours():
    try:
        return {**FALLBACK, **json.loads(SCHEME_STATE.read_text())["colours"]}
    except (OSError, ValueError, KeyError):
        return dict(FALLBACK)


def current_rice(rices=None):
    rices = load_rices() if rices is None else rices
    try:
        name = RICE_STATE.read_text().strip()
    except OSError:
        name = ""
    if name in rices:
        return name
    return DEFAULT_RICE if DEFAULT_RICE in rices else next(iter(rices), "")


def palette(rice, current):
    scheme = rice.get("scheme")
    if scheme:
        return read_scheme_file(scheme.get("name"), scheme.get("flavour"), scheme.get("mode", "dark"))
    # from the wallpaper: show the live colours when it is the current rice, else a rainbow (see CSS)
    return current_colours() if current == rice["name"] else {}


# ---------------------------------------------------------------- switching

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


def run(*cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"{cmd[0]}: {e}"
    if out.returncode != 0:
        return f"{' '.join(cmd[:3])}: {(out.stderr or out.stdout).strip()}"
    return None


def set_fonts(font):
    """Caelestia's sans / mono fonts (appearance.font.family in shell.json); null removes the key,
    so Caelestia uses its default. The file is only rewritten when something changes."""
    try:
        data = json.loads(SHELL_JSON.read_text())
    except (OSError, ValueError) as e:
        return f"shell.json: {e}"
    before = json.dumps(data)
    appearance = data.setdefault("appearance", {})
    family = appearance.setdefault("font", {}).setdefault("family", {})
    for key in ("sans", "mono"):
        if (font or {}).get(key):
            family[key] = font[key]
        else:
            family.pop(key, None)
    if not family:
        appearance["font"].pop("family")
    if not appearance["font"]:
        appearance.pop("font")
    if json.dumps(data) != before:
        SHELL_JSON.write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n")
    return None


def apply_rice(name):
    """The shell side of a switch (set_rice() in hypr-user.lua does the Hyprland side)."""
    rice = load_rices().get(name)
    if not rice:
        return f"unknown rice {name}"
    errors = []
    scheme = rice.get("scheme")
    if scheme:
        cmd = ["caelestia", "scheme", "set", "-n", scheme["name"]]
        if scheme.get("flavour"):
            cmd += ["-f", scheme["flavour"]]
        cmd += ["-m", scheme.get("mode", "dark")]
    else:
        cmd = ["caelestia", "scheme", "set", "-n", "dynamic"]
    errors.append(run(*cmd))
    wallpaper = wallpaper_path(rice.get("wallpaper"))
    if wallpaper:
        # after the scheme, so it is no longer dynamic; -N: a bright wallpaper must not flip the mode to light
        errors.append(run("caelestia", "wallpaper", "-N", "-f", str(wallpaper)))
    cursor = rice.get("cursor") or {}
    if cursor.get("theme"):
        size = str(int(cursor.get("size") or 24))
        errors.append(run("hyprctl", "setcursor", cursor["theme"], size))
        run("gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", cursor["theme"])
        run("gsettings", "set", "org.gnome.desktop.interface", "cursor-size", size)
    errors.append(set_fonts(rice.get("font")))
    errors = [e for e in errors if e]
    title = rice.get("title") or name
    if errors:
        run("notify-send", "-a", "caelestia", "-u", "critical", f"Rice {title}", "\n".join(errors))
        return "\n".join(errors)
    run("notify-send", "-a", "caelestia", "-t", "2000", "Rice", title)
    return None


def resize_window(width, height):
    """Floating windows keep their size in Hyprland: ask it to resize this one."""
    lua = ("for _, w in ipairs(hl.get_windows() or {}) do if w.class == '" + APP_ID + "' then "
           f"hl.dispatch(hl.dsp.window.resize({{ x = {width}, y = {height}, relative = false, window = w }})) "
           "pcall(function() hl.dispatch(hl.dsp.window.center({ window = w })) end) end end")
    run("hyprctl", "eval", lua)


# ---------------------------------------------------------------- GTK window

def run_gui():
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Gdk", "4.0")
    from gi.repository import Gdk, Gio, GLib, GObject, Gtk, Pango

    def label(text, css=None, **kw):
        w = Gtk.Label(label=text, xalign=0, **kw)
        if css:
            w.add_css_class(css)
        return w

    def entry(value, placeholder=""):
        w = Gtk.Entry(text=value or "", placeholder_text=placeholder, hexpand=True)
        return w

    def dropdown(items, selected):
        w = Gtk.DropDown.new_from_strings(items)
        if selected in items:
            w.set_selected(items.index(selected))
        return w

    def spin(value, lo, hi, step, digits=0):
        w = Gtk.SpinButton.new_with_range(lo, hi, step)
        w.set_digits(digits)
        w.set_value(value)
        return w

    class Editor(Gtk.Box):
        """The settings of one rice; save() writes them back to its file."""

        def __init__(self, app, rice):
            super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            self.add_css_class("editor")
            self.app, self.rice = app, rice
            self.window = app.window

            head = Gtk.Box(spacing=10)
            head.append(label(f"{rice.get('icon', '')}  {rice.get('title') or rice['name']} settings", "section", hexpand=True))
            head.append(label(f"rices/{rice['name']}.json", "path"))
            self.append(head)

            grid = Gtk.Grid(column_spacing=12, row_spacing=8)
            self.row = 0

            def add(text, *widgets):
                grid.attach(label(text, "field"), 0, self.row, 1, 1)
                box = Gtk.Box(spacing=8, hexpand=True)
                for w in widgets:
                    box.append(w)
                grid.attach(box, 1, self.row, 1, 1)
                self.row += 1

            def heading(text):
                grid.attach(label(text, "subsection"), 0, self.row, 2, 1)
                self.row += 1

            heading("Card")
            self.title = entry(rice.get("title"))
            self.icon = entry(rice.get("icon"))
            self.icon.set_hexpand(False)
            self.icon.set_width_chars(4)
            add("Title / icon", self.title, self.icon)
            self.tagline = entry(rice.get("tagline"))
            add("Tagline", self.tagline)
            self.effects = entry(rice.get("effects"))
            add("Effects text", self.effects)
            self.order = spin(rice.get("order") or 0, 0, 999, 1)
            add("Order", self.order)

            heading("Look")
            self.schemes = [None] + scheme_choices()
            scheme = rice.get("scheme") or {}
            current = (scheme.get("name"), scheme.get("flavour")) if scheme else None
            if current and current not in self.schemes:
                self.schemes.append(current)
            names = ["From the wallpaper (dynamic)"] + [f"{n} · {f}" for n, f in self.schemes[1:]]
            self.scheme = Gtk.DropDown.new_from_strings(names)
            self.scheme.set_selected(self.schemes.index(current))
            self.mode = dropdown(["dark", "light"], scheme.get("mode", "dark"))
            add("Colour scheme", self.scheme, self.mode)

            self.wallpaper = entry(rice.get("wallpaper"), "keep the current wallpaper")
            pick = Gtk.Button(label="Choose…")
            pick.connect("clicked", lambda *_: self.choose_wallpaper())
            add("Wallpaper", self.wallpaper, pick)

            font = rice.get("font") or {}
            self.sans = entry(font.get("sans"), "Caelestia default")
            self.mono = entry(font.get("mono"), "Caelestia default")
            add("Font", self.sans, self.font_button(self.sans))
            add("Monospace font", self.mono, self.font_button(self.mono))

            cursor = rice.get("cursor") or {}
            themes = cursor_themes()
            if cursor.get("theme") and cursor["theme"] not in themes:
                themes.append(cursor["theme"])
            self.cursor_themes = [None] + themes
            self.cursor = Gtk.DropDown.new_from_strings(["keep the current cursor"] + themes)
            self.cursor.set_selected(self.cursor_themes.index(cursor.get("theme")))
            self.cursor_size = spin(cursor.get("size") or 24, 8, 128, 1)
            add("Cursor / size", self.cursor, self.cursor_size)

            heading("Effects")
            self.windowfx = dropdown(WINDOWFX, rice.get("windowfx") or "off")
            add("Window effect", self.windowfx)
            self.cursorfx = dropdown(CURSORFX, rice.get("cursorfx") or "off")
            add("Cursor effect", self.cursorfx)
            self.trail_scheme = Gtk.CheckButton(label="scheme colour", active=not rice.get("trail"))
            self.trail = Gtk.ColorDialogButton(dialog=Gtk.ColorDialog(with_alpha=False))
            rgba = Gdk.RGBA()
            rgba.parse(rice.get("trail") or "#" + current_colours().get("primary", "888888"))
            self.trail.set_rgba(rgba)
            self.trail.set_sensitive(not rice.get("trail"))
            self.trail_scheme.connect("toggled", lambda b: self.trail.set_sensitive(not b.get_active()))
            add("Cursor trail", self.trail_scheme, self.trail)
            self.transition = entry(rice.get("transition"), "none (a command, e.g. bat-swarm)")
            add("Transition", self.transition)

            heading("Window animations")
            self.anims = {}
            anims = rice.get("animations") or {}
            for leaf in ANIM_LEAVES + [l for l in anims if l not in ANIM_LEAVES]:
                a = anims.get(leaf) or {}
                on = Gtk.CheckButton(label="on", active=a.get("enabled", True) if a else False)
                speed = spin(a.get("speed", 5), 0.1, 50, 0.1, 2)
                bezier = entry(a.get("bezier"), "bezier")
                style = entry(a.get("style"), "style, e.g. popin 50%")
                for w in (speed, bezier, style):
                    on.bind_property("active", w, "sensitive", GObject.BindingFlags.SYNC_CREATE)
                self.anims[leaf] = (bool(a), on, speed, bezier, style)
                add(leaf, on, speed, bezier, style)
            self.append(grid)

            buttons = Gtk.Box(spacing=8)
            delete = Gtk.Button(label="Delete rice")
            delete.add_css_class("destructive")
            delete.set_sensitive(len(app.rices) > 1 and rice["name"] != current_rice(app.rices))
            delete.set_tooltip_text("The current rice and the last one can't be deleted")
            delete.connect("clicked", lambda *_: self.delete())
            buttons.append(delete)
            buttons.append(Gtk.Box(hexpand=True))
            save = Gtk.Button(label="Save")
            save.connect("clicked", lambda *_: self.save(apply=False))
            apply = Gtk.Button(label="Save and apply")
            apply.add_css_class("suggested")
            apply.connect("clicked", lambda *_: self.save(apply=True))
            buttons.append(save)
            buttons.append(apply)
            self.append(buttons)

        def font_button(self, target):
            button = Gtk.Button(label="…", tooltip_text="Choose a font")

            def done(dialog, result):
                try:
                    family = dialog.choose_family_finish(result)
                except GLib.Error:
                    return
                if family:
                    target.set_text(family.get_name())

            button.connect("clicked", lambda *_: Gtk.FontDialog().choose_family(self.window, None, None, done))
            return button

        def choose_wallpaper(self):
            dialog = Gtk.FileDialog(title="Wallpaper")
            filt = Gtk.FileFilter(name="Images")
            filt.add_mime_type("image/*")
            filters = Gio.ListStore.new(Gtk.FileFilter)
            filters.append(filt)
            dialog.set_filters(filters)
            current = wallpaper_path(self.wallpaper.get_text())
            if current and current.parent.is_dir():
                dialog.set_initial_folder(Gio.File.new_for_path(str(current.parent)))

            def done(d, result):
                try:
                    path = Path(d.open_finish(result).get_path())
                except GLib.Error:
                    return
                rices, dotfiles = RICES_DIR.resolve(), DOTFILES.resolve()
                if path.is_relative_to(rices) or path.is_relative_to(dotfiles):
                    # inside the dotfiles (e.g. legacy-rices/wallpapers): relative, so it works in any clone
                    text = os.path.relpath(path, rices)
                elif path.is_relative_to(HOME):
                    text = "~/" + str(path.relative_to(HOME))
                else:
                    text = str(path)
                self.wallpaper.set_text(text)

            dialog.open(self.window, None, done)

        def collect(self):
            r = dict(self.rice)
            r["title"] = self.title.get_text().strip() or r["name"]
            r["icon"] = self.icon.get_text().strip()
            r["tagline"] = self.tagline.get_text().strip()
            r["effects"] = self.effects.get_text().strip()
            r["order"] = int(self.order.get_value())
            scheme = self.schemes[self.scheme.get_selected()]
            r["scheme"] = None if scheme is None else {
                "name": scheme[0], "flavour": scheme[1], "mode": ["dark", "light"][self.mode.get_selected()]}
            r["wallpaper"] = self.wallpaper.get_text().strip() or None
            r["font"] = {"sans": self.sans.get_text().strip() or None, "mono": self.mono.get_text().strip() or None}
            theme = self.cursor_themes[self.cursor.get_selected()]
            r["cursor"] = {"theme": theme, "size": int(self.cursor_size.get_value())} if theme else None
            r["windowfx"] = WINDOWFX[self.windowfx.get_selected()]
            r["cursorfx"] = CURSORFX[self.cursorfx.get_selected()]
            if self.trail_scheme.get_active():
                r["trail"] = None
            else:
                c = self.trail.get_rgba()
                r["trail"] = "#{:02X}{:02X}{:02X}".format(*(round(v * 255) for v in (c.red, c.green, c.blue)))
            r["transition"] = self.transition.get_text().strip() or None
            anims = {}
            for leaf, (existed, on, speed, bezier, style) in self.anims.items():
                if not on.get_active() and not existed:
                    continue  # left unset: Hyprland keeps its own value
                a = {"speed": round(speed.get_value(), 2)}
                if bezier.get_text().strip():
                    a["bezier"] = bezier.get_text().strip()
                if style.get_text().strip():
                    a["style"] = style.get_text().strip()
                if not on.get_active():
                    a["enabled"] = False
                anims[leaf] = a
            r["animations"] = anims
            return r

        def save(self, apply):
            rice = self.collect()
            try:
                save_rice(rice)
            except OSError as e:
                return self.app.say(f"Could not save: {e}", error=True)
            self.app.say(f"Saved rices/{rice['name']}.json")
            self.app.reload(open_settings=rice["name"])
            if apply:
                self.app.pick(rice["name"])

        def delete(self):
            name = self.rice["name"]
            dialog = Gtk.AlertDialog(message=f"Delete the {self.rice.get('title') or name} rice?",
                                     detail=f"This removes rices/{name}.json.", buttons=["Cancel", "Delete"],
                                     cancel_button=0, default_button=0)

            def done(d, result):
                try:
                    if d.choose_finish(result) != 1:
                        return
                except GLib.Error:
                    return
                try:
                    (RICES_DIR / f"{name}.json").unlink()
                except OSError as e:
                    return self.app.say(f"Could not delete: {e}", error=True)
                self.app.say(f"Deleted {name}")
                self.app.reload()

            dialog.choose(self.window, None, done)

    class Picker(Gtk.Application):
        def __init__(self):
            super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
            self.window = None
            self.css = Gtk.CssProvider()
            self.rices = {}
            self.cards = {}
            self.monitors = []
            self.status = None
            self.reload_pending = False
            self.open_name = None

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
            card = self.cards.get(current_rice(self.rices))
            if card:
                card.pick.grab_focus()

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
            win.set_default_size(*FOLDED)
            win.add_css_class("rice-picker")

            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18)
            box.add_css_class("content")

            header = Gtk.Box(spacing=12)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, hexpand=True)
            text.append(label("Choose your rice", "title"))
            text.append(label("Click a card, or press its number. SUPER + SHIFT + R cycles them too. "
                              "⚙ shows a rice's settings.", "subtitle", wrap=True))
            header.append(text)
            self.new_name = Gtk.Entry(placeholder_text="new-rice-name", width_chars=14, valign=Gtk.Align.CENTER)
            self.new_name.connect("activate", lambda *_: self.new_rice())
            new = Gtk.Button(label="New rice", valign=Gtk.Align.CENTER,
                             tooltip_text="Copy the open rice (or the current one) under this name")
            new.connect("clicked", lambda *_: self.new_rice())
            header.append(self.new_name)
            header.append(new)
            box.append(header)

            self.row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16, homogeneous=True)
            self.row.set_size_request(-1, FOLDED[1] - 150)
            box.append(self.row)

            self.revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN, vexpand=True)
            self.scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
            self.revealer.set_child(self.scroller)
            box.append(self.revealer)

            self.status = label("", "status", wrap=True)
            box.append(self.status)
            win.set_child(box)

            keys = Gtk.EventControllerKey()
            keys.connect("key-pressed", self.on_key)
            win.add_controller(keys)
            self.reload()
            return win

        def reload(self, open_settings=None):
            """Re-reads the rice files and rebuilds the cards (and the open settings)."""
            self.rices = load_rices()
            while (child := self.row.get_first_child()):
                self.row.remove(child)
            self.cards = {}
            for i, (name, rice) in enumerate(self.rices.items(), 1):
                card = self.make_card(rice, i)
                self.cards[name] = card
                self.row.append(card)
            self.show_settings(open_settings if open_settings in self.rices else None)
            self.refresh()

        def make_card(self, rice, index):
            card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            card.add_css_class("card")
            card.add_css_class(f"rice-{rice['name']}")

            pick = Gtk.Button(vexpand=True)
            pick.add_css_class("pick")
            pick.connect("clicked", lambda *_: self.pick(rice["name"]))

            inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
            top = Gtk.Box(spacing=10)
            icon = label(rice.get("icon") or "", "icon")
            name = label(rice.get("title") or rice["name"], "name", hexpand=True, ellipsize=Pango.EllipsizeMode.END)
            badge = Gtk.Label(label="current")
            badge.add_css_class("badge")
            for w in (icon, name, badge):
                top.append(w)
            if index <= 9:
                key = Gtk.Label(label=str(index))
                key.add_css_class("key")
                top.append(key)
            inner.append(top)

            swatches = Gtk.Box(spacing=6, homogeneous=True)
            for role in SWATCHES:
                sw = Gtk.Box(hexpand=True)
                sw.add_css_class("swatch")
                sw.add_css_class(f"sw-{rice['name']}-{role}")
                sw.set_tooltip_text(role)
                swatches.append(sw)
            inner.append(swatches)
            inner.append(label(rice.get("tagline") or "", "tagline", wrap=True))
            inner.append(label(rice.get("effects") or "", "effects", wrap=True))
            pick.set_child(inner)
            card.append(pick)

            gear = Gtk.ToggleButton(label="⚙  Settings", halign=Gtk.Align.END)
            gear.add_css_class("gear")
            gear.connect("toggled", lambda b: self.on_gear(rice["name"], b.get_active()))
            card.append(gear)

            card.pick, card.gear, card.badge = pick, gear, badge
            return card

        def on_gear(self, name, active):
            if active == (self.open_name == name):
                return  # show_settings() syncing the buttons
            if active:
                self.show_settings(name)
            elif self.open_name == name:
                self.show_settings(None)

        def show_settings(self, name):
            was_open = self.open_name is not None
            self.open_name = name
            for n, card in self.cards.items():
                if card.gear.get_active() != (n == name):
                    card.gear.set_active(n == name)
            if name:
                self.scroller.set_child(Editor(self, self.rices[name]))
            self.revealer.set_reveal_child(name is not None)
            if name and not was_open:
                resize_window(*UNFOLDED)
            elif not name and was_open:
                resize_window(*FOLDED)

        # ---- actions
        def on_key(self, _ctrl, keyval, _code, state):
            name = Gdk.keyval_name(keyval) or ""
            ctrl = state & Gdk.ModifierType.CONTROL_MASK
            if name == "Escape" or (ctrl and name in ("w", "q")):
                if name == "Escape" and self.open_name:
                    self.show_settings(None)
                else:
                    self.window.close()
                return True
            focus = self.window.get_focus()
            if isinstance(focus, Gtk.Text):  # typing in a field
                return False
            digit = name[-1] if re.fullmatch(r"(KP_)?[1-9]", name) else None
            if digit:
                names = list(self.rices)
                i = int(digit) - 1
                if i < len(names):
                    self.pick(names[i])
                return True
            return False

        def say(self, text, error=False):
            self.status.set_text(text)
            (self.status.add_css_class if error else self.status.remove_css_class)("error")

        def pick(self, name):
            self.say(f"Switching to {name}…")
            err = set_rice(name)
            self.say(f"Could not switch: {err}" if err else "", error=bool(err))
            self.refresh()

        def new_rice(self):
            name = self.new_name.get_text().strip().lower()
            if not valid_name(name):
                return self.say("A rice name is lowercase letters, digits, - and _", error=True)
            if name in self.rices:
                return self.say(f"{name} already exists", error=True)
            base = self.rices.get(self.open_name or current_rice(self.rices)) or {}
            orders = [r["order"] for r in self.rices.values() if isinstance(r.get("order"), (int, float))]
            rice = {**DEFAULTS, **base, "name": name, "title": name.replace("-", " ").title(),
                    "order": int(max(orders, default=0)) + 1}
            try:
                save_rice(rice)
            except OSError as e:
                return self.say(f"Could not create it: {e}", error=True)
            self.new_name.set_text("")
            self.say(f"Created rices/{name}.json from {base.get('name', 'the defaults')}")
            self.reload(open_settings=name)

        # ---- colours
        def refresh(self):
            self.reload_pending = False
            cur = current_rice(self.rices)
            for name, card in self.cards.items():
                (card.add_css_class if name == cur else card.remove_css_class)("active")
                card.badge.set_visible(name == cur)
            self.css.load_from_string(self.stylesheet(cur))
            return False  # GLib.timeout_add: run once

        def stylesheet(self, cur):
            c = current_colours()

            def col(key, fallback="888888"):
                return "#" + c.get(key, fallback)

            css = f"""
            window.rice-picker {{ background: {col('background')}; color: {col('onBackground')}; }}
            .content {{ padding: 28px; }}
            .title {{ font-size: 22pt; font-weight: 800; }}
            .subtitle, .effects, .path {{ color: {col('onSurfaceVariant')}; }}
            .status {{ color: {col('onSurfaceVariant')}; min-height: 1.2em; }}
            .status.error {{ color: #{c.get('error', 'FF5449')}; }}
            .card {{
                background: {col('surfaceContainer')}; color: {col('onBackground')};
                border: 2px solid transparent; border-radius: 18px; padding: 6px;
                transition: all 150ms ease;
            }}
            .card:hover {{ background: {col('surfaceContainerHigh')}; }}
            .card.active {{ border-color: {col('primary')}; }}
            button.pick {{
                background: none; color: inherit; box-shadow: none; border: 2px solid transparent;
                border-radius: 14px; padding: 12px;
            }}
            button.pick:focus-visible {{ border-color: {col('outline')}; }}
            button.gear {{
                background: none; color: {col('onSurfaceVariant')}; box-shadow: none; border-radius: 10px;
                padding: 2px 10px; margin: 0 6px 4px 0; font-size: 9pt;
            }}
            button.gear:checked {{ background: {col('primary')}; color: {col('onPrimary')}; }}
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
            .editor {{
                background: {col('surfaceContainer')}; border-radius: 18px; padding: 20px; margin-top: 4px;
            }}
            .section {{ font-size: 14pt; font-weight: 700; }}
            .subsection {{ font-weight: 700; color: {col('primary')}; margin-top: 8px; }}
            .field {{ color: {col('onSurfaceVariant')}; }}
            .editor entry, .editor spinbutton, .editor dropdown > button, .editor button,
            window.rice-picker > box entry, window.rice-picker > box > box > button {{
                background: {col('surfaceContainerHigh')}; color: {col('onBackground')};
                border-radius: 10px; box-shadow: none; border: 1px solid alpha({col('outline')}, 0.4);
            }}
            .editor button.suggested {{ background: {col('primary')}; color: {col('onPrimary')}; }}
            .editor button.destructive {{ color: #{c.get('error', 'FF5449')}; }}
            """
            rainbow = ["#ff6b6b", "#ffd166", "#06d6a0", "#4cc9f0", "#9b5de5"]
            for rice in self.rices.values():
                pal = palette(rice, cur)
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
        rices = load_rices()
        cur = current_rice(rices)
        for name in rices:
            print(("* " if name == cur else "  ") + name)
        return 0
    if args[:1] in (["--set"], ["--apply"]) and len(args) == 2:
        err = (set_rice if args[0] == "--set" else apply_rice)(args[1])
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
