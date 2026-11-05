"""Set every Razer device to a static Caelestia primary colour.

Usage: caelestia-razer-colour [primary hex]

Without an argument, the primary is read from the current Caelestia scheme.
"""

import colorsys
import json
import os
import sys

from openrazer.client import DaemonNotFound, DeviceManager

SCHEME = os.path.expanduser("~/.local/state/caelestia/scheme.json")


def led_colour(hex_colour):
    """Keep the hue but max out saturation and brightness.

    Material You primaries are pastel in dark mode (e.g. #cfbfeb), and LEDs
    render pastels as nearly white. Grey schemes stay white.
    """
    rgb = [int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    h, s, _ = colorsys.rgb_to_hsv(*rgb)
    s = 1.0 if s >= 0.05 else 0.0
    return tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, 1.0))


def main():
    if len(sys.argv) > 1:
        primary = sys.argv[1].lstrip("#")
    else:
        with open(SCHEME) as f:
            primary = json.load(f)["colours"]["primary"].lstrip("#")
    r, g, b = led_colour(primary)

    try:
        devices = DeviceManager().devices
    except DaemonNotFound:
        sys.exit("openrazer daemon not running")

    for device in devices:
        if device.fx.has("static"):
            device.fx.static(r, g, b)
            print(f"{device.name}: #{primary} -> #{r:02x}{g:02x}{b:02x}")


if __name__ == "__main__":
    main()
