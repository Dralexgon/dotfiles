"""Colours: the Caelestia scheme, made LED-friendly, as float RGB arrays."""

import colorsys
import json
from pathlib import Path

import numpy as np

SCHEME = Path.home() / ".local/state/caelestia/scheme.json"

# Used when there is no Caelestia scheme (a purple, like the default one)
FALLBACK = {"primary": "cfbfeb", "secondary": "cdc2db", "tertiary": "f0b8c6", "error": "ffb4ab"}


def hex_rgb(hex_colour: str) -> np.ndarray:
    h = hex_colour.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def led(rgb: np.ndarray) -> np.ndarray:
    """Keep the hue but max out saturation and brightness.

    Material You colours are pastel in dark mode (e.g. #cfbfeb), and LEDs
    render pastels as nearly white. Grey colours stay white.
    """
    h, s, _ = colorsys.rgb_to_hsv(*rgb)
    return np.array(colorsys.hsv_to_rgb(h, 1.0 if s >= 0.05 else 0.0, 1.0))


class Palette:
    """The scheme colours effects draw with, reloaded when Caelestia changes it."""

    def __init__(self):
        self.mtime = None
        self.load()

    def load(self) -> None:
        try:
            colours = json.loads(SCHEME.read_text())["colours"]
        except (OSError, KeyError, ValueError):
            colours = {}
        get = lambda name: led(hex_rgb(colours.get(name, FALLBACK[name])))  # noqa: E731
        self.primary = get("primary")
        self.secondary = get("secondary")
        self.tertiary = get("tertiary")
        self.error = get("error")
        # Secondary and tertiary are often close to primary once saturated:
        # shift the hue a bit so gradients stay visible.
        self.secondary = _spread(self.primary, self.secondary, 0.08)
        self.tertiary = _spread(self.primary, self.tertiary, 0.16)
        self.white = np.ones(3)

    def reload_if_changed(self) -> bool:
        try:
            mtime = SCHEME.stat().st_mtime
        except OSError:
            mtime = None
        if mtime == self.mtime:
            return False
        self.mtime = mtime
        self.load()
        return True

    def gradient(self, x) -> np.ndarray:
        """primary -> secondary -> tertiary -> primary, x in [0, 1) wrapping."""
        stops = np.array([self.primary, self.secondary, self.tertiary, self.primary])
        x = np.asarray(x, dtype=float) % 1.0 * 3
        i = np.minimum(x.astype(int), 2)
        f = (x - i)[..., None]
        return stops[i] * (1 - f) + stops[i + 1] * f


def _spread(base: np.ndarray, other: np.ndarray, min_hue: float) -> np.ndarray:
    h1, _, _ = colorsys.rgb_to_hsv(*base)
    h2, s2, v2 = colorsys.rgb_to_hsv(*other)
    d = (h2 - h1 + 0.5) % 1.0 - 0.5
    if s2 == 0 or abs(d) >= min_hue:
        return other
    h2 = h1 + (min_hue if d >= 0 else -min_hue)
    return np.array(colorsys.hsv_to_rgb(h2 % 1.0, s2, v2))


def hue(h) -> np.ndarray:
    """Fully saturated colour(s) of hue h in [0, 1)."""
    h = np.asarray(h, dtype=float) % 1.0
    k = (np.array([5, 3, 1]) + h[..., None] * 6) % 6
    return 1 - np.clip(np.minimum(k, 4 - k), 0, 1)


NAMED = {
    "red": "ff0000", "green": "00ff00", "blue": "0000ff", "white": "ffffff",
    "yellow": "ffcc00", "orange": "ff5500", "purple": "8800ff", "pink": "ff0080",
    "cyan": "00ffff", "discord": "5865f2", "blood": "b00010",
}


def parse(colour: str | None, palette: Palette) -> np.ndarray:
    """A colour from the command line: a scheme name, a named colour or #hex."""
    if not colour:
        return palette.primary
    if colour in ("primary", "secondary", "tertiary", "error"):
        return getattr(palette, colour)
    return hex_rgb(NAMED.get(colour.lower(), colour))
