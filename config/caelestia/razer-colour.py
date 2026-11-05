"""Set every Razer device to a static Caelestia primary colour.

Usage: caelestia-razer-colour [primary hex]

Without an argument, the primary is read from the current Caelestia scheme.
"""

import json
import os
import sys

from openrazer.client import DaemonNotFound, DeviceManager

SCHEME = os.path.expanduser("~/.local/state/caelestia/scheme.json")


def main():
    if len(sys.argv) > 1:
        primary = sys.argv[1].lstrip("#")
    else:
        with open(SCHEME) as f:
            primary = json.load(f)["colours"]["primary"].lstrip("#")
    r, g, b = (int(primary[i:i + 2], 16) for i in (0, 2, 4))

    try:
        devices = DeviceManager().devices
    except DaemonNotFound:
        sys.exit("openrazer daemon not running")

    for device in devices:
        if device.fx.has("static"):
            device.fx.static(r, g, b)
            print(f"{device.name}: #{primary}")


if __name__ == "__main__":
    main()
