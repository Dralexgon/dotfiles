"""Voice Changer tray: runs Applio (github:Dralexgon/nix-voice-changer) in the
background and shows a tray icon while it runs.

  Open web UI   the Applio page (http://127.0.0.1:6969)
  Show logs     Applio's output, live, in kitty
  Quit          stops Applio, the icon goes away

Starting it again while it runs only opens the web UI.
"""

import fcntl
import os
import signal
import subprocess
import sys
import urllib.request
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import AyatanaAppIndicator3 as AppIndicator  # noqa: E402
from gi.repository import GLib, Gtk  # noqa: E402

URL = "http://127.0.0.1:6969"
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "voice-changer"
LOG = STATE / "applio.log"
LOCK = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "voice-changer-tray.lock"
APPLIO_DIR = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "applio"

ICON_STARTING = "microphone-sensitivity-low-symbolic"
ICON_READY = "audio-input-microphone-symbolic"


def notify(body):
    subprocess.Popen(["notify-send", "-a", "Voice Changer", "-i", "audio-input-microphone", "Voice Changer", body])


def open_ui(*_):
    subprocess.Popen(["xdg-open", URL])


def show_logs(*_):
    subprocess.Popen(["kitty", "--class", "voice-changer-logs", "--title", "Voice Changer logs",
                      "tail", "-n", "+1", "-F", str(LOG)])


def ui_up():
    try:
        urllib.request.urlopen(URL, timeout=1)
        return True
    except Exception:
        return False


class Tray:
    def __init__(self):
        STATE.mkdir(parents=True, exist_ok=True)
        first_run = not (APPLIO_DIR / ".venv").exists()
        log = open(LOG, "w")
        # Own process group, so Quit stops Applio and everything it started.
        self.proc = subprocess.Popen(["applio", "run"], stdout=log, stderr=subprocess.STDOUT,
                                     stdin=subprocess.DEVNULL, start_new_session=True)
        self.quitting = False

        self.ind = AppIndicator.Indicator.new("voice-changer", ICON_STARTING,
                                              AppIndicator.IndicatorCategory.APPLICATION_STATUS)
        self.ind.set_title("Voice Changer")
        self.ind.set_status(AppIndicator.IndicatorStatus.ACTIVE)

        menu = Gtk.Menu()
        self.status = Gtk.MenuItem(label="Starting…")
        self.status.set_sensitive(False)
        for item in (self.status, Gtk.SeparatorMenuItem()):
            menu.append(item)
        for label, cb in (("Open web UI", open_ui), ("Show logs", show_logs)):
            item = Gtk.MenuItem(label=label)
            item.connect("activate", cb)
            menu.append(item)
        menu.append(Gtk.SeparatorMenuItem())
        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", self.quit)
        menu.append(quit_item)
        menu.show_all()
        self.ind.set_menu(menu)
        self.ind.set_secondary_activate_target(menu.get_children()[2])  # middle click: web UI

        if first_run:
            notify("First start: installing Applio, this takes a few minutes")
            show_logs()
        else:
            notify("Starting…")

        GLib.timeout_add_seconds(2, self.poll)
        try:
            gi.require_version("GLibUnix", "2.0")
            from gi.repository import GLibUnix
            signal_add = GLibUnix.signal_add
        except (ValueError, ImportError):
            signal_add = GLib.unix_signal_add
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal_add(GLib.PRIORITY_DEFAULT, sig, self.quit)

    def poll(self):
        if self.proc.poll() is not None:
            if not self.quitting:
                notify(f"Applio stopped (exit code {self.proc.returncode}), see {LOG}")
            Gtk.main_quit()
            return False
        if self.status.get_label() != "Running" and ui_up():
            self.status.set_label("Running")
            self.ind.set_icon_full(ICON_READY, "Voice Changer running")
        return True

    def quit(self, *_):
        self.quitting = True
        self.status.set_label("Stopping…")
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        GLib.timeout_add_seconds(8, self.kill)
        return True

    def kill(self):
        if self.proc.poll() is None:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        return False


def main():
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        # Already running: just show it.
        if ui_up():
            open_ui()
        else:
            notify("Still starting, the web UI opens when it is ready")
        return
    Tray()
    Gtk.main()


if __name__ == "__main__":
    sys.exit(main())
