"""The case fans (and other OpenRGB devices) show the keyboard effect too.

They go through the OpenRGB SDK server (services.hardware.openrgb), in Direct
mode. Keyboards are skipped: the Razer one is drawn through openrazer.

Each LED strip (an ARGB header, so the fans on it) is laid along the width of
the keyboard: LED i of n takes the colour at column i/n, so waves and
gradients travel along the fans. A column's colour is its brightest key, so
sparse effects (ripples, sparks) still show. Single-LED zones take the average.

The zone sizes come from OpenRGB: set the real LED count of each ARGB header
in the OpenRGB GUI (Resize zone), otherwise the effect is spread over 60 LEDs
and only its start shows on the fans.
"""

import logging
import time

import numpy as np

log = logging.getLogger("rgbfx")
RETRY = 10  # seconds between connection attempts


class Fans:
    def __init__(self):
        self.client = None
        self.devices = []  # (device, [per-zone sampling positions or None])
        self.next_try = 0.0

    def _connect(self) -> None:
        from openrgb import OpenRGBClient
        from openrgb.utils import DeviceType

        self.client = OpenRGBClient("127.0.0.1", 6742, "rgbfx")
        self.devices = []
        for dev in self.client.devices:
            if dev.type == DeviceType.KEYBOARD or not dev.leds:
                continue
            dev.set_mode("direct")
            zones = [None if len(z.leds) == 1 else np.linspace(0, 1, len(z.leds), endpoint=False)
                     for z in dev.zones]
            self.devices.append((dev, zones))
            log.info("openrgb: drawing on %s (%s)", dev.name,
                     ", ".join(f"{z.name}: {len(z.leds)}" for z in dev.zones))

    def ready(self) -> bool:
        if self.client is not None:
            return True
        if time.monotonic() < self.next_try:
            return False
        self.next_try = time.monotonic() + RETRY
        try:
            self._connect()
        except Exception as e:  # noqa: BLE001 - server not up yet, refused...
            log.debug("openrgb: %s", e)
            self.client = None
        return self.client is not None

    def draw(self, frame: np.ndarray) -> None:
        """frame: the keyboard frame, ROWS x COLS x 3 uint8."""
        if not self.ready():
            return
        from openrgb.utils import RGBColor

        f = frame.astype(float)
        # Brightest key of each column -> a COLS x 3 strip
        strip = f[f.sum(axis=2).argmax(axis=0), np.arange(f.shape[1])]
        cols = np.arange(len(strip)) / len(strip)
        average = strip.mean(axis=0)
        try:
            for dev, zones in self.devices:
                colours = []
                for pos in zones:
                    if pos is None:
                        rgb = average[None, :]
                    else:
                        rgb = np.stack([np.interp(pos, cols, strip[:, ch], period=1) for ch in range(3)], axis=1)
                    colours += [RGBColor(*(int(v) for v in np.round(c))) for c in rgb]
                dev.set_colors(colours, fast=True)
        except Exception as e:  # noqa: BLE001 - server restarted, device gone...
            log.warning("openrgb: draw failed (%s), reconnecting", e)
            try:
                self.client.disconnect()
            except Exception:  # noqa: BLE001
                pass
            self.client = None
