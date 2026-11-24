"""Where the case's LEDs are, for the case preview in the window.

Measured by lighting blocks of LEDs through OpenRGB and looking at the case
through the webcam (from two angles). Everything is on the B550M's D_LED2
header (D_LED1 and the single-LED headers have nothing visible on them):

- the AIO pump (12 LEDs) is first in a daisy chain, then the 3 top fans,
  front to rear (12 LEDs each): LEDs 0-11, 12-23, 24-35, 36-47;
- the 4 ring fans (3 at the front, 1 at the rear) hang on a splitter, so they
  all show LEDs 0-19 (20 each, clockwise).

So LEDs 0-19 light several fans at once: to fix by moving a cable to the
empty D_LED1 header (see "To fix: the fans share LEDs" in README.md), then
measure again.

Drawn the way the case is seen through its glass side: the front on the
right, the top fans along the top, the pump and the rear fan at the back.
"""

from dataclasses import dataclass

ASPECT = 0.9  # width / height of the drawing


@dataclass
class Ring:
    name: str
    zone: str  # OpenRGB zone name
    first: int  # its first LED in the zone
    count: int
    x: float  # centre, in 0..1 of the case width / height
    y: float
    r: float  # radius, in 0..1 of the case height
    start: float = 0.0  # angle of LED 0, degrees clockwise from 12 o'clock
    kind: str = "fan"  # fan | pump


RINGS = [
    *[Ring(f"Top fan {i + 1}", "D_LED2", 12 + 12 * i, 12, 0.74 - i * 0.25, 0.12, 0.085) for i in range(3)],
    *[Ring(f"Front fan {i + 1}", "D_LED2", 0, 20, 0.84, 0.36 + i * 0.22, 0.085, start=15) for i in range(3)],
    Ring("Rear fan", "D_LED2", 0, 20, 0.14, 0.36, 0.085, start=15),
    Ring("Pump", "D_LED2", 0, 12, 0.42, 0.36, 0.06, kind="pump"),
]

# Shapes drawn faintly for context: (x, y, w, h) in 0..1
BOARD = (0.25, 0.24, 0.45, 0.5)
GPU = (0.22, 0.56, 0.5, 0.07)


def shared() -> list[tuple[Ring, Ring]]:
    """Pairs of rings driven by some of the same LEDs, but not all (so they can't show
    different things). Exact copies are fine: the fans on a splitter are meant to match.
    The window warns about them until the wiring is fixed (see README.md)."""
    return [(a, b) for i, a in enumerate(RINGS) for b in RINGS[i + 1:]
            if a.zone == b.zone and a.first < b.first + b.count and b.first < a.first + a.count
            and (a.first, a.count) != (b.first, b.count)]


# Shown by the window while shared() isn't empty
WIRING_HELP = """Everything is on the D_LED2 header: the ring fans' splitter (LEDs 0-19)
and the pump + top fans chain (pump 0-11, top fans 12-47). So LEDs 0-11
light the ring fans and the pump, and LEDs 12-19 light the ring fans and
top fan 1 (the front one): the top fans can't be in sync with the rest.

Fix: move the ring fans' splitter (or the cable to the pump, the top fans
follow it) to the empty D_LED1 header, then measure the fans again and
update case.py.

Gigabyte B550M GAMING X WIFI6 (manual Rev. 1001, pages 4 and 17),
seen as in the manual, rear I/O on the left:

 ┌─────────────────────────────────────────────┐
 │ I/O            CPU            RAM  LED_C2 ◄─┼── D_LED2 (top right edge)
 │                                             │
 │      PCIe x16 (GPU)                         │
 │      PCIe x4                                │
 │ F_AUDIO  LED_C1  D_LED1  TPM  COM ...       │
 └──────────────────▲──────────────────────────┘
                    └── D_LED1 (bottom edge)

D_LED1 is below the PCIe slots, probably under the graphics card.
3-pin 5 V: 1 = 5V, 2 = data, 3 = no pin, 4 = ground. The arrow on the
plug is 5V and goes to pin 1 (the wrong way can damage the LEDs).
Turn the PC off and unplug it first.

More in tools/rgbfx/README.md, "To fix: the fans share LEDs"."""
