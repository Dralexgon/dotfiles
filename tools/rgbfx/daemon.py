"""The render loop: draws the chosen effect and overlays ~30 times a second.

It follows state.json and the Caelestia scheme as they change, and only
sends a frame to the keyboard when it differs from the last one, so a
static effect costs (almost) nothing.

The case fans (OpenRGB, see fans.py) get the same effect, without the
per-key overlays: only the notification pulses and flashes reach them.

While Caelestia's game mode is on, effects and overlays pause: the keyboard
and fans stay in the static primary colour and the loop only wakes twice a second.
Turn `game_mode_pause` off (`rgbfx gamemode run`) to keep them running.
"""

import logging
import signal
import time

import numpy as np

import effects
import state
from fans import Fans
from inputs import Inputs
from keymap import COLS, ROWS
from palette import Palette

log = logging.getLogger("rgbfx")
FPS = 30
# Overlays that are about the whole keyboard rather than some keys, so they also reach the fans
FAN_OVERLAYS = {"notifications"}


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
    inputs.game_mode.start()
    palette = Palette()
    flash = effects.Flash()
    fans = Fans()

    settings, settings_mtime = None, object()
    current, overlays = None, {}
    last_frame = last_fan_frame = None
    t = 0.0
    last = time.monotonic()
    preview, preview_checked = False, 0.0

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
                    if need not in ("audio", "mic", "screen"):  # these start on first use, stop when unused
                        getattr(inputs, need).start()
        if palette.reload_if_changed():
            last_frame = last_fan_frame = None

        speed = float(settings["speed"])
        game_mode = inputs.game_mode.enabled and settings["game_mode_pause"]
        fan_zones = {}
        if game_mode:
            # Nothing renders, so the audio and screen captures stop by themselves
            frame = fan_frame = effects.fill(palette.primary)
        else:
            ctx = effects.Context(t=t, dt=dt_real * speed, now=now, last=last, speed=speed,
                                  palette=palette, inputs=inputs, state=settings)
            frame = current.render(ctx)
            fan_frame = frame.copy()  # overlays may draw in place
            for name, part in overlays.items():
                frame = part.apply(frame, ctx)
                if name in FAN_OVERLAYS:
                    fan_frame = part.apply(fan_frame, ctx)
            frame = flash.apply(frame, ctx)
            fan_frame = flash.apply(fan_frame, ctx)
            if hasattr(current, "render_fans"):  # the effect draws the fans itself
                fan_zones = current.render_fans(ctx, fans.zone_sizes())
                for name, part in overlays.items():
                    if name in FAN_OVERLAYS:
                        fan_zones = {z: part.apply(c, ctx) for z, c in fan_zones.items()}
                fan_zones = {z: flash.apply(c, ctx) for z, c in fan_zones.items()}
        brightness = float(settings["brightness"])
        out = np.round(np.clip(frame * brightness, 0, 1) * 255).astype(np.uint8)
        fan_out = np.round(np.clip(fan_frame * brightness, 0, 1) * 255).astype(np.uint8)
        zones_out = {z: np.round(np.clip(c * brightness, 0, 1) * 255).astype(np.uint8)
                     for z, c in fan_zones.items()}
        fan_key = np.concatenate([fan_out.reshape(-1, 3), *zones_out.values()])  # for change detection

        if last_fan_frame is None or not np.array_equal(fan_key, last_fan_frame):
            fans.draw(fan_out, zones_out)
            last_fan_frame = fan_key if fans.client else None

        if last_frame is None or not np.array_equal(out, last_frame):
            if keyboards.draw(out):
                last_frame = out
            else:
                time.sleep(2)
                keyboards.connect()
                last_frame = None

        if now - preview_checked > 1:  # is the GUI open?
            preview, preview_checked = state.preview_wanted(), now
        if preview:
            state.write_preview(out.tobytes(), {z: c.tobytes() for z, c in fans.shown.items()})

        t += dt_real * speed
        last = now
        time.sleep(max(0, (0.5 if game_mode else 1 / FPS) - (time.monotonic() - now)))
