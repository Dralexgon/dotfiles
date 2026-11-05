"""The render loop: draws the chosen effect and overlays ~30 times a second.

It follows state.json and the Caelestia scheme as they change, and only
sends a frame to the keyboard when it differs from the last one, so a
static effect costs (almost) nothing.
"""

import logging
import signal
import time

import numpy as np

import effects
import state
from inputs import Inputs
from keymap import COLS, ROWS
from palette import Palette

log = logging.getLogger("razerfx")
FPS = 30


class Keyboards:
    """The openrazer devices with a per-key matrix (found again if the daemon restarts)."""

    def __init__(self):
        self.devices = []

    def connect(self) -> bool:
        from openrazer.client import DaemonNotFound, DeviceManager

        try:
            manager = DeviceManager()
            manager.sync_effects = False
            self.devices = [d for d in manager.devices
                            if d.fx.advanced and d.fx.advanced.rows >= ROWS and d.fx.advanced.cols >= COLS]
        except (DaemonNotFound, Exception) as e:  # noqa: BLE001 - dbus errors vary
            log.warning("openrazer: %s", e)
            self.devices = []
        for d in self.devices:
            log.info("drawing on %s (%dx%d)", d.name, d.fx.advanced.rows, d.fx.advanced.cols)
        return bool(self.devices)

    def draw(self, frame: np.ndarray) -> bool:
        try:
            for d in self.devices:
                m = d.fx.advanced.matrix
                for r in range(ROWS):
                    for c in range(COLS):
                        m[r, c] = tuple(int(v) for v in frame[r, c])
                d.fx.advanced.draw()
            return True
        except Exception as e:  # noqa: BLE001 - device unplugged, daemon restarted...
            log.warning("draw failed: %s", e)
            return False


def run():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    stop = []
    signal.signal(signal.SIGTERM, lambda *_: stop.append(1))
    signal.signal(signal.SIGINT, lambda *_: stop.append(1))

    keyboards = Keyboards()
    while not keyboards.connect():
        if stop:
            return
        time.sleep(3)

    inputs = Inputs()
    inputs.keyboard.start()
    palette = Palette()
    flash = effects.Flash()

    settings, settings_mtime = None, object()
    current, overlays = None, {}
    last_frame = None
    t = 0.0
    last = time.monotonic()

    while not stop:
        now = time.monotonic()
        dt_real = min(now - last, 0.2)

        mtime = state.mtime()
        if mtime != settings_mtime:
            settings_mtime, settings = mtime, state.load()
            name = settings["effect"] if settings["effect"] in effects.EFFECTS else "static"
            if current is None or current.name != name:
                current = effects.EFFECTS[name]()
                log.info("effect: %s", name)
            overlays = {n: overlays.get(n) or effects.OVERLAYS[n]()
                        for n in effects.ORDER if n in settings["overlays"]}
            for part in [current, *overlays.values()]:
                for need in part.needs:
                    if need not in ("audio", "mic"):  # these start on first use, stop when unused
                        getattr(inputs, need).start()
        if palette.reload_if_changed():
            last_frame = None

        speed = float(settings["speed"])
        ctx = effects.Context(t=t, dt=dt_real * speed, now=now, last=last, speed=speed,
                              palette=palette, inputs=inputs, state=settings)
        frame = current.render(ctx)
        for part in overlays.values():
            frame = part.apply(frame, ctx)
        frame = flash.apply(frame, ctx)
        frame = np.clip(frame * float(settings["brightness"]), 0, 1)
        out = np.round(frame * 255).astype(np.uint8)

        if last_frame is None or not np.array_equal(out, last_frame):
            if keyboards.draw(out):
                last_frame = out
            else:
                time.sleep(2)
                keyboards.connect()
                last_frame = None

        t += dt_real * speed
        last = now
        time.sleep(max(0, 1 / FPS - (time.monotonic() - now)))
