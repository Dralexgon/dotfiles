"""Where the case's LEDs are, for the case preview in the window.

Measured by lighting blocks of LEDs through OpenRGB and looking at the case
through the webcam (from two angles). Everything is on the B550M's D_LED2
header (D_LED1 and the single-LED headers have nothing visible on them):

- the AIO pump (12 LEDs) is first in a daisy chain, then the 3 top fans,
  front to rear (12 LEDs each): LEDs 0-11, 12-23, 24-35, 36-47;
- the 4 ring fans (3 at the front, 1 at the rear) hang on a splitter, so they
  all show LEDs 0-19 (20 each, clockwise).

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
