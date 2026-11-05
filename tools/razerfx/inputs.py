"""What the effects react to, each read in its own background thread.

- Keyboard: key presses from evdev (the Razer devices belong to the openrazer group).
- Audio: what's playing, as frequency bands (pw-record on the default sink).
- Hyprland: workspaces, focused window and keybinds (its IPC sockets).
- System: CPU load and temperature, microphone mute.
- Notifications: desktop notifications, seen by monitoring D-Bus.

Threads start lazily, when an effect or overlay first asks for their data,
and never crash the daemon: on errors they log, wait and retry.
"""

import asyncio
import glob
import json
import logging
import os
import socket
import subprocess
import threading
import time
from collections import deque
from pathlib import Path

import numpy as np

import keymap

log = logging.getLogger("razerfx")


def _thread(target, name):
    t = threading.Thread(target=target, name=name, daemon=True)
    t.start()
    return t


# Keyboard


class Keyboard:
    """Held keys and recent presses of the Razer keyboard."""

    def __init__(self):
        self.held: dict[int, float] = {}  # code -> time pressed
        self.presses: deque = deque(maxlen=256)  # (code, time)
        self.caps_lock = False
        self.lock = threading.Lock()
        self.ok = False
        self._started = False

    def start(self):
        if not self._started:
            self._started = True
            _thread(self._run, "keyboard")

    def _devices(self):
        import evdev

        paths = sorted(glob.glob("/dev/input/by-id/*Razer*-event-kbd"))
        devices = []
        for path in paths:
            try:
                devices.append(evdev.InputDevice(path))
            except PermissionError:
                raise
            except OSError:
                pass
        return devices

    def _run(self):
        import select

        import evdev

        warned = False
        while True:
            try:
                devices = self._devices()
            except PermissionError:
                if not warned:
                    log.warning("can't read the Razer /dev/input devices: are you in the "
                                "openrazer group (razer.nix)?")
                    warned = True
                time.sleep(10)
                continue
            if not devices:
                time.sleep(5)
                continue
            self.ok = True
            fds = {d.fd: d for d in devices}
            try:
                while True:
                    r, _, _ = select.select(fds, [], [], 0.25)
                    for fd in r:
                        for ev in fds[fd].read():
                            if ev.type == evdev.ecodes.EV_KEY:
                                self._key(ev.code, ev.value, ev.timestamp())
                    leds = set()
                    for d in devices:
                        leds.update(d.leds())
                    self.caps_lock = evdev.ecodes.LED_CAPSL in leds
            except OSError:
                log.info("keyboard disconnected, waiting for it")
                self.ok = False
                with self.lock:
                    self.held.clear()
                time.sleep(2)

    def _key(self, code, value, t):
        now = time.monotonic()
        with self.lock:
            if value == 1:
                self.held[code] = now
                self.presses.append((code, now))
            elif value == 0:
                self.held.pop(code, None)

    def presses_since(self, since: float) -> list:
        with self.lock:
            return [(c, t) for c, t in self.presses if t > since]

    def held_keys(self) -> dict:
        with self.lock:
            return dict(self.held)

    def modmask(self) -> int:
        mask = 0
        for code in self.held_keys():
            mask |= keymap.MOD_BITS.get(code, 0)
        return mask


# Audio


class Audio:
    """Loudness of 18 log-spaced bands (one per column) of what's playing, in [0, 1].

    Levels are in dB, so quiet and loud parts both move the bars. Each band
    is scaled to its own recent peak (mixed with the loudest band's), which
    keeps the highs moving even though the bass carries most of the energy.
    """

    RATE = 44100
    HOP = 512  # new samples per analysis: ~86 updates a second
    FFT = 2048
    BANDS = keymap.COLS
    RANGE_DB = 24  # dB between an empty and a full bar: smaller = jumpier
    FALL_DB = 8  # dB per second the reference peaks forget a loud moment
    FALL = 5.0  # bar heights per second a bar falls back

    def __init__(self):
        self.bands = np.zeros(self.BANDS)
        self.last_used = 0.0
        self._running = False
        edges = np.geomspace(40, 16000, self.BANDS + 1)
        freqs = np.fft.rfftfreq(self.FFT, 1 / self.RATE)
        # FFT bins of each band (the nearest one when a bass band falls between bins)
        self._bins = []
        for lo, hi in zip(edges, edges[1:]):
            idx = np.nonzero((freqs >= lo) & (freqs < hi))[0]
            self._bins.append(idx if len(idx) else [np.abs(freqs - np.sqrt(lo * hi)).argmin()])
        # Music loses energy with frequency (about -3 dB per octave): give it back
        centres = np.sqrt(edges[:-1] * edges[1:])
        self._tilt = 3 * np.log2(centres / centres[0])
        self._window = np.hanning(self.FFT)
        self.reset()

    def reset(self):
        self._buf = np.zeros(self.FFT)
        self._band_peak = np.full(self.BANDS, -60.0)
        self._peak = -60.0
        self._avg = np.zeros(self.BANDS)

    def get(self) -> np.ndarray:
        self.last_used = time.monotonic()
        if not self._running:
            self._running = True
            _thread(self._run, "audio")
        return self.bands

    def analyse(self, samples: np.ndarray) -> np.ndarray:
        """Feed HOP new samples (floats in [-1, 1]), update and return the bands."""
        dt = len(samples) / self.RATE
        self._buf = np.concatenate([self._buf[len(samples):], samples])
        power = np.abs(np.fft.rfft(self._buf * self._window)) ** 2
        db = np.array([10 * np.log10(power[b].mean() + 1e-12) for b in self._bins]) + self._tilt

        # Reference peaks jump up at once and slowly come down. They never go
        # below 0 dB (about -50 dBFS), so silence stays dark instead of
        # showing amplified noise.
        self._band_peak = np.maximum(np.maximum(self._band_peak - self.FALL_DB * dt, db), 0)
        self._peak = max(self._peak - self.FALL_DB * dt, db.max(), 0)
        ref = 0.6 * self._band_peak + 0.4 * self._peak
        level = np.clip((db - (ref - self.RANGE_DB)) / self.RANGE_DB, 0, 1)

        # Punch: a band jumping above its recent average (a beat, a note) gets a boost
        onset = np.clip(level - self._avg, 0, 1)
        self._avg += (level - self._avg) * min(1, dt * 6)
        level = np.clip(level ** 1.5 + onset * 0.8, 0, 1)

        # Instant rise, quick linear fall
        self.bands = np.maximum(level, self.bands - self.FALL * dt)
        return self.bands

    def _run(self):
        # Capture the default output (sink monitor), mono 16-bit, low latency
        cmd = ["pw-record", "-P", "{ stream.capture.sink=true }", "--latency", "10ms",
               "--rate", str(self.RATE), "--channels", "1", "--format", "s16", "-"]
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except OSError as e:
            log.warning("audio capture failed: %s", e)
            time.sleep(10)
            self._running = False
            return
        self.reset()
        try:
            while time.monotonic() - self.last_used < 5:  # stop when unused
                data = proc.stdout.read(self.HOP * 2)
                if len(data) < self.HOP * 2:
                    break
                self.analyse(np.frombuffer(data, dtype="<i2") / 32768)
        finally:
            proc.terminate()
            self.bands = np.zeros(self.BANDS)
            self._running = False


# Hyprland


def _hypr_dir() -> Path | None:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hypr"
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if sig and (runtime / sig / ".socket.sock").exists():
        return runtime / sig
    # Under systemd the variable may be missing or stale: take the newest instance
    dirs = sorted(runtime.glob("*/.socket.sock"), key=lambda p: p.stat().st_mtime, reverse=True)
    return dirs[0].parent if dirs else None


def hyprctl(command: str):
    """Send a request to Hyprland (like `hyprctl -j <command>`), parsed JSON or None."""
    d = _hypr_dir()
    if not d:
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(2)
            s.connect(str(d / ".socket.sock"))
            s.sendall(f"j/{command}".encode())
            chunks = []
            while chunk := s.recv(65536):
                chunks.append(chunk)
        return json.loads(b"".join(chunks))
    except (OSError, ValueError):
        return None


class Hyprland:
    """Workspaces, focused window and keybinds, kept up to date from socket2 events."""

    def __init__(self):
        self.active_workspace = 0
        self.workspaces: dict[int, int] = {}  # id -> window count
        self.window_class = ""
        self.window_title = ""
        self.binds: list[dict] = []
        self._binds_time = 0.0
        self._started = False

    def start(self):
        if not self._started:
            self._started = True
            _thread(self._run, "hyprland")

    def refresh(self):
        ws = hyprctl("workspaces")
        if ws is not None:
            self.workspaces = {w["id"]: w.get("windows", 0) for w in ws}
        active = hyprctl("activeworkspace")
        if active:
            self.active_workspace = active.get("id", 0)
        win = hyprctl("activewindow")
        if win is not None:
            self.window_class = win.get("class", "") if win else ""
            self.window_title = win.get("title", "") if win else ""

    def get_binds(self) -> list[dict]:
        """Keybinds, refreshed in the background when older than 5 s."""
        self.start()
        if time.monotonic() - self._binds_time > 5:
            self._binds_time = time.monotonic()
            _thread(self._load_binds, "hypr-binds")
        return self.binds

    def _load_binds(self):
        binds = hyprctl("binds")
        if binds is not None:
            self.binds = binds

    def _run(self):
        while True:
            d = _hypr_dir()
            if not d:
                time.sleep(5)
                continue
            self.refresh()
            self._load_binds()
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                    s.connect(str(d / ".socket2.sock"))
                    buf = b""
                    while chunk := s.recv(4096):
                        buf += chunk
                        *lines, buf = buf.split(b"\n")
                        for line in lines:
                            self._event(line.decode(errors="replace"))
            except OSError:
                pass
            time.sleep(2)

    def _event(self, line: str):
        name, _, data = line.partition(">>")
        if name == "activewindow":
            self.window_class, _, self.window_title = data.partition(",")
        elif name in ("workspace", "workspacev2", "createworkspace", "destroyworkspace",
                      "openwindow", "closewindow", "movewindow", "focusedmon"):
            _thread(self.refresh, "hypr-refresh")
        elif name == "configreloaded":
            self._binds_time = 0.0


# System


class System:
    """CPU load (0..1), CPU temperature (°C) and microphone mute, polled each second."""

    def __init__(self):
        self.cpu = 0.0
        self.temp = 0.0
        self.mic_muted = False
        self._started = False

    def start(self):
        if not self._started:
            self._started = True
            _thread(self._run, "system")

    @staticmethod
    def _temp_file() -> Path | None:
        for hwmon in Path("/sys/class/hwmon").glob("hwmon*"):
            try:
                name = (hwmon / "name").read_text().strip()
            except OSError:
                continue
            if name in ("k10temp", "coretemp", "zenpower"):
                return hwmon / "temp1_input"
        return None

    def _run(self):
        temp_file = self._temp_file()
        prev = None
        while True:
            try:
                fields = [int(x) for x in Path("/proc/stat").read_text().split("\n")[0].split()[1:]]
                idle, total = fields[3] + fields[4], sum(fields)
                if prev:
                    dt = total - prev[1]
                    self.cpu = 1 - (idle - prev[0]) / dt if dt else self.cpu
                prev = (idle, total)
                if temp_file:
                    self.temp = int(temp_file.read_text()) / 1000
            except (OSError, ValueError, IndexError):
                pass
            try:
                out = subprocess.run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"],
                                     capture_output=True, text=True, timeout=2).stdout
                self.mic_muted = "MUTED" in out
            except (OSError, subprocess.SubprocessError):
                pass
            time.sleep(1)


# Notifications


class Notifications:
    """Desktop notifications (app name, time), seen by monitoring the session bus."""

    def __init__(self):
        self.events: deque = deque(maxlen=32)
        self._started = False

    def start(self):
        if not self._started:
            self._started = True
            _thread(lambda: asyncio.run(self._run()), "notifications")

    async def _run(self):
        from dbus_fast import Message, MessageType
        from dbus_fast.aio import MessageBus

        rule = "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"
        while True:
            try:
                bus = await MessageBus().connect()
                reply = await bus.call(Message(
                    destination="org.freedesktop.DBus",
                    path="/org/freedesktop/DBus",
                    interface="org.freedesktop.DBus.Monitoring",
                    member="BecomeMonitor",
                    signature="asu",
                    body=[[rule], 0],
                ))
                if reply.message_type == MessageType.ERROR:
                    log.warning("can't monitor notifications: %s", reply.body)
                    return

                def handler(msg):
                    if msg.member == "Notify" and msg.body:
                        self.events.append((str(msg.body[0]), time.monotonic()))
                    return None

                bus.add_message_handler(handler)
                await bus.wait_for_disconnect()
            except Exception as e:  # noqa: BLE001 - keep retrying whatever happens
                log.warning("notification monitor: %s", e)
            await asyncio.sleep(5)


class Inputs:
    def __init__(self):
        self.keyboard = Keyboard()
        self.audio = Audio()
        self.hypr = Hyprland()
        self.system = System()
        self.notifications = Notifications()
