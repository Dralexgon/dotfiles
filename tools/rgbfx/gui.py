"""The rgbfx window (GTK4 + libadwaita): pick an effect, toggle overlays, tune brightness and speed.

Like the CLI it only edits state.json; the daemon picks changes up within a frame.
The keyboard and the case at the top are a live preview: while the window is open,
the daemon writes every frame it sends to $XDG_RUNTIME_DIR/rgbfx (see state.py).
The case layout (which LED is where) is in case.py.
The colours come from Caelestia's GTK theme (~/.config/gtk-4.0/gtk.css).
"""

import json
import math
import subprocess
import sys
import time

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, GLib, Gtk  # noqa: E402

import case  # noqa: E402
import effects  # noqa: E402
import keymap  # noqa: E402
import state  # noqa: E402
from keymap import COLS, ROWS  # noqa: E402

APP_ID = "dev.dralexgon.rgbfx"

# What's printed on each key of the preview
LABELS = {code: name.upper() for name, code in keymap._KEYSYMS.items() if len(name) <= 3}
LABELS.update({
    1: "Esc", 14: "⌫", 15: "Tab", 28: "⏎", 57: "", 58: "Caps", 42: "Shift", 54: "Shift",
    29: "Ctrl", 97: "Ctrl", 56: "Alt", 100: "Alt", 125: "Super", 127: "Menu", 99: "Prt",
    70: "Scr", 119: "Pse", 110: "Ins", 102: "Home", 104: "PgUp", 111: "Del", 107: "End",
    109: "PgDn", 103: "↑", 105: "←", 108: "↓", 106: "→", 12: "-", 13: "=", 26: "[", 27: "]",
    39: ";", 40: "'", 41: "`", 43: "\\", 51: ",", 52: ".", 53: "/",
})
LABEL_AT = {pos: LABELS.get(code, "") for code, pos in keymap.POS.items()}
LABEL_AT[keymap.FN_POS] = "Fn"


def daemon_status() -> str:
    try:
        return subprocess.run(["systemctl", "--user", "is-active", "rgbfx"],
                              capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "unknown"


class Preview(Gtk.DrawingArea):
    """The keyboard, drawn from the daemon's last frame."""

    def __init__(self):
        super().__init__(content_height=200, hexpand=True)
        self.frame = None  # bytes, ROWS*COLS*3
        self.mtime = None
        self.fresh = False
        self.case = CaseView(self)
        self.fans = {}  # zone name -> bytes (RGB per LED)
        self.fans_mtime = None
        self.set_draw_func(self.draw)

    def poll(self) -> None:
        try:
            st = state.PREVIEW_FRAME.stat()
        except OSError:
            self.fresh = False
            return
        self.fresh = time.time() - st.st_mtime < 2
        if st.st_mtime_ns != self.mtime:
            self.mtime = st.st_mtime_ns
            try:
                data = state.PREVIEW_FRAME.read_bytes()
            except OSError:
                return
            if len(data) == ROWS * COLS * 3:
                self.frame = data
        try:
            st = state.PREVIEW_FANS.stat()
            if st.st_mtime_ns != self.fans_mtime:
                self.fans_mtime = st.st_mtime_ns
                self.fans = {z: bytes.fromhex(h) for z, h in json.loads(state.PREVIEW_FANS.read_text()).items()}
        except (OSError, ValueError, AttributeError):
            pass
        self.queue_draw()
        self.case.queue_draw()

    def draw(self, _area, cr, width, height):
        used = range(1, COLS)  # column 0 has no keys
        cell = min(width / len(used), height / ROWS)
        x0 = (width - cell * len(used)) / 2
        y0 = (height - cell * ROWS) / 2
        pad, radius = cell * 0.08, cell * 0.18
        live = self.frame is not None and self.fresh
        cr.select_font_face("sans")
        for r in range(ROWS):
            for c in used:
                if not effects.LIT[r, c]:
                    continue
                if live:
                    i = (r * COLS + c) * 3
                    rgb = [v / 255 for v in self.frame[i:i + 3]]
                else:
                    rgb = [0.0, 0.0, 0.0]
                x, y = x0 + (c - 1) * cell + pad, y0 + r * cell + pad
                size = cell - 2 * pad
                lum = max(rgb)
                # The glow around a lit key
                if lum > 0.05:
                    cr.set_source_rgba(*rgb, 0.25 * lum)
                    _rounded(cr, x - pad * 0.8, y - pad * 0.8, size + pad * 1.6, radius * 1.5)
                    cr.fill()
                # The key cap: dark plastic, with the LED colour shining through
                base = 0.13
                cr.set_source_rgb(*[base + (1 - base) * v for v in rgb])
                _rounded(cr, x, y, size, radius)
                cr.fill()
                label = LABEL_AT.get((r, c), "")
                if label:
                    dark = 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2] > 0.55
                    cr.set_source_rgba(*((0, 0, 0, 0.7) if dark else (1, 1, 1, 0.55)))
                    cr.set_font_size(size * (0.3 if len(label) <= 2 else 0.2))
                    ext = cr.text_extents(label)
                    cr.move_to(x + (size - ext.width) / 2 - ext.x_bearing,
                               y + (size - ext.height) / 2 - ext.y_bearing)
                    cr.show_text(label)
        if not live:
            text = "No live preview: is the daemon running?"
            cr.set_source_rgba(1, 1, 1, 0.8)
            cr.set_font_size(max(12, cell * 0.28))
            ext = cr.text_extents(text)
            cr.move_to((width - ext.width) / 2 - ext.x_bearing, (height - ext.height) / 2 - ext.y_bearing)
            cr.show_text(text)


class CaseView(Gtk.DrawingArea):
    """The PC case, seen through its glass side, with each fan's LEDs (layout in case.py)."""

    def __init__(self, preview):
        super().__init__(content_width=int(200 * case.ASPECT), content_height=200)
        self.preview = preview
        self.set_draw_func(self.draw)

    def led(self, zone, i):
        data = self.preview.fans.get(zone, b"") if self.preview.fresh else b""
        if len(data) < (i + 1) * 3:
            return (0.0, 0.0, 0.0)
        return tuple(v / 255 for v in data[i * 3:i * 3 + 3])

    def draw(self, _area, cr, width, height):
        h = min(height, width / case.ASPECT) - 4
        w = h * case.ASPECT
        ox, oy = (width - w) / 2, (height - h) / 2

        # The case and what's inside, faintly
        cr.set_source_rgba(1, 1, 1, 0.12)
        cr.set_line_width(2)
        _rect(cr, ox, oy, w, h, h * 0.04)
        cr.stroke()
        for x, y, bw, bh in (case.BOARD, case.GPU):
            cr.set_source_rgba(1, 1, 1, 0.05)
            _rect(cr, ox + x * w, oy + y * h, bw * w, bh * h, h * 0.015)
            cr.fill()

        for ring in case.RINGS:
            cx, cy, r = ox + ring.x * w, oy + ring.y * h, ring.r * h
            colours = [self.led(ring.zone, ring.first + i) for i in range(ring.count)]
            # The fan's frame and blades area
            cr.set_source_rgba(1, 1, 1, 0.06)
            cr.arc(cx, cy, r * (1.25 if ring.kind == "fan" else 1.15), 0, 2 * math.pi)
            cr.fill()
            # A soft glow of the average colour
            avg = [sum(c[k] for c in colours) / len(colours) for k in range(3)]
            if max(avg) > 0.03:
                cr.set_source_rgba(*avg, 0.18 * max(avg))
                cr.arc(cx, cy, r * 1.7, 0, 2 * math.pi)
                cr.fill()
            # Each LED as an arc of the ring
            step = 2 * math.pi / ring.count
            cr.set_line_width(r * (0.32 if ring.kind == "fan" else 0.45))
            for i, rgb in enumerate(colours):
                a = math.radians(ring.start) - math.pi / 2 + i * step
                cr.set_source_rgb(*[0.12 + 0.88 * v for v in rgb])
                cr.arc(cx, cy, r, a, a + step * 1.02)
                cr.stroke()
            # Hub
            cr.set_source_rgba(0, 0, 0, 0.35)
            cr.arc(cx, cy, r * 0.38, 0, 2 * math.pi)
            cr.fill()


def _rect(cr, x, y, w, h, r):
    cr.new_sub_path()
    cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


def _rounded(cr, x, y, size, r):
    cr.new_sub_path()
    cr.arc(x + size - r, y + r, r, -math.pi / 2, 0)
    cr.arc(x + size - r, y + size - r, r, 0, math.pi / 2)
    cr.arc(x + r, y + size - r, r, math.pi / 2, math.pi)
    cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
    cr.close_path()


class Window(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="rgbfx", default_width=1100, default_height=780)
        self.settings = state.load()
        self.mtime = None
        self.syncing = False

        # Header: daemon status, flash and restart
        self.title = Adw.WindowTitle(title="rgbfx")
        header = Adw.HeaderBar(title_widget=self.title)
        flash = Gtk.Button(icon_name="weather-clear-symbolic", tooltip_text="Test flash")
        flash.connect("clicked", lambda *_: state.flash())
        restart = Gtk.Button(icon_name="view-refresh-symbolic",
                             tooltip_text="Restart the daemon (after editing the code)")
        restart.connect("clicked", self.on_restart)
        header.pack_start(flash)
        header.pack_end(restart)

        # The preview, in a card
        self.preview = Preview()
        card = Gtk.Box(margin_top=12, margin_start=18, margin_end=18)
        card.add_css_class("card")
        self.preview.set_margin_top(12)
        self.preview.set_margin_bottom(12)
        self.preview.set_margin_start(12)
        self.preview.set_margin_end(12)
        card.append(self.preview)
        self.preview.case.set_margin_top(12)
        self.preview.case.set_margin_bottom(12)
        self.preview.case.set_margin_end(12)
        card.append(self.preview.case)

        # Left: effects, by category
        left = Adw.PreferencesPage(hexpand=True)
        self.effect_checks = {}
        group_by_cat, first = {}, None
        for name, cls in effects.EFFECTS.items():
            if cls.category not in group_by_cat:
                group_by_cat[cls.category] = Adw.PreferencesGroup(title=cls.category)
                left.add(group_by_cat[cls.category])
            check = Gtk.CheckButton(valign=Gtk.Align.CENTER)
            if first:
                check.set_group(first)
            first = first or check
            check.connect("toggled", self.on_effect, name)
            row = Adw.ActionRow(title=GLib.markup_escape_text(cls.title),
                                subtitle=GLib.markup_escape_text(cls.description), activatable_widget=check)
            row.add_prefix(check)
            group_by_cat[cls.category].add(row)
            self.effect_checks[name] = check

        # Right: settings, then overlays
        right = Adw.PreferencesPage(hexpand=True)
        settings = Adw.PreferencesGroup(title="Settings")
        right.add(settings)

        self.brightness = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 5)
        self.brightness.set_hexpand(True)
        self.brightness.set_draw_value(True)
        self.brightness.set_value_pos(Gtk.PositionType.LEFT)
        self.brightness.set_format_value_func(lambda _s, v: f"{v:.0f} %")
        self.brightness.connect("value-changed", self.on_brightness)
        row = Adw.ActionRow(title="Brightness")
        row.add_suffix(self.brightness)
        settings.add(row)

        self.speed = Adw.SpinRow(title="Animation speed", subtitle="Multiplier (1 = normal)", digits=2,
                                 adjustment=Gtk.Adjustment(lower=0.1, upper=5, step_increment=0.1,
                                                           page_increment=0.5, value=1))
        self.speed.connect("notify::value", self.on_speed)
        settings.add(self.speed)

        self.pomo = Adw.SpinRow(title="Pomodoro", subtitle="Minutes, shown on the F-row", digits=0,
                                adjustment=Gtk.Adjustment(lower=1, upper=180, step_increment=5,
                                                          page_increment=15, value=25))
        self.pomo_button = Gtk.Button(label="Start", valign=Gtk.Align.CENTER)
        self.pomo_button.connect("clicked", self.on_pomodoro)
        self.pomo.add_suffix(self.pomo_button)
        settings.add(self.pomo)

        overlays = Adw.PreferencesGroup(title="Overlays", description="Drawn on top of the effect")
        right.add(overlays)
        self.overlay_rows = {}
        for name in effects.ORDER:
            cls = effects.OVERLAYS[name]
            row = Adw.SwitchRow(title=GLib.markup_escape_text(cls.title),
                                subtitle=GLib.markup_escape_text(cls.description))
            row.connect("notify::active", self.on_overlay)
            overlays.add(row)
            self.overlay_rows[name] = row

        panes = Gtk.Box(homogeneous=True, vexpand=True)
        panes.append(left)
        panes.append(right)
        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        body.append(card)
        body.append(panes)

        self.toasts = Adw.ToastOverlay(child=body)
        view = Adw.ToolbarView(content=self.toasts)
        view.add_top_bar(header)
        self.set_content(view)

        self.reload()
        self.check_daemon()
        self.want_preview()
        GLib.timeout_add(33, self.tick_preview)
        GLib.timeout_add(500, self.tick_state)
        GLib.timeout_add_seconds(1, self.want_preview)
        GLib.timeout_add_seconds(3, self.check_daemon)

    # Timers

    def tick_preview(self):
        self.preview.poll()
        return True

    def tick_state(self):
        self.reload()
        self.show_pomodoro()
        return True

    def want_preview(self):
        try:
            state.RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
            state.PREVIEW_WANTED.touch()
        except OSError:
            pass
        return True

    def check_daemon(self):
        status = daemon_status()
        self.title.set_subtitle(f"daemon {status}")
        return True

    # State -> widgets

    def reload(self) -> None:
        if state.mtime() == self.mtime:
            return
        self.mtime = state.mtime()
        s = self.settings = state.load()
        self.syncing = True
        if s["effect"] in self.effect_checks:
            self.effect_checks[s["effect"]].set_active(True)
        for name, row in self.overlay_rows.items():
            row.set_active(name in s["overlays"])
        if round(self.brightness.get_value()) != round(s["brightness"] * 100):
            self.brightness.set_value(s["brightness"] * 100)
        if abs(self.speed.get_value() - s["speed"]) > 0.005:
            self.speed.set_value(s["speed"])
        self.syncing = False
        self.show_pomodoro()

    def pomodoro_left(self):
        pomo = self.settings.get("pomodoro")
        if not pomo:
            return None
        return pomo["start"] + pomo["minutes"] * 60 - time.time()

    def show_pomodoro(self) -> None:
        left = self.pomodoro_left()
        if left is not None and left > 0:
            self.pomo.set_subtitle(f"{int(left // 60)}:{int(left % 60):02d} left")
            self.pomo_button.set_label("Stop")
            self.pomo_button.add_css_class("destructive-action")
        else:
            self.pomo.set_subtitle("Done!" if left is not None and left > -8 else "Minutes, shown on the F-row")
            self.pomo_button.set_label("Start")
            self.pomo_button.remove_css_class("destructive-action")

    # Widgets -> state

    def on_effect(self, check, name):
        if check.get_active() and not self.syncing:
            state.update(effect=name)

    def on_overlay(self, *_):
        if not self.syncing:
            state.update(overlays=[n for n in effects.ORDER if self.overlay_rows[n].get_active()])

    def on_brightness(self, scale):
        if not self.syncing:
            state.update(brightness=round(scale.get_value() / 100, 2))

    def on_speed(self, *_):
        if not self.syncing:
            state.update(speed=round(self.speed.get_value(), 2))

    def on_pomodoro(self, *_):
        left = self.pomodoro_left()
        if left is not None and left > 0:
            state.update(pomodoro=None)
            self.toast("Pomodoro stopped")
        else:
            minutes = self.pomo.get_value()
            enabled = state.load()["overlays"]
            state.update(pomodoro={"start": time.time(), "minutes": minutes},
                         overlays=enabled + ["pomodoro"] * ("pomodoro" not in enabled))
            self.toast(f"Pomodoro: {minutes:.0f} minutes")
        self.reload()

    def on_restart(self, *_):
        subprocess.run(["systemctl", "--user", "restart", "rgbfx"])
        self.check_daemon()
        self.toast(f"Daemon {daemon_status()}")

    def toast(self, text):
        self.toasts.add_toast(Adw.Toast(title=text, timeout=2))


def main():
    app = Adw.Application(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def activate(app):
        win = app.get_active_window() or Window(app)
        win.present()

    app.connect("activate", activate)
    quit_action = Gio.SimpleAction(name="quit")
    quit_action.connect("activate", lambda *_: app.quit())
    app.add_action(quit_action)
    app.set_accels_for_action("app.quit", ["<Control>q", "<Control>w"])
    return app.run(sys.argv[:1])
