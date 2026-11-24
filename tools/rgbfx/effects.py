"""Every effect and overlay rgbfx can draw.

A frame is a float array of shape (ROWS, COLS, 3), RGB in [0, 1]. The daemon
renders the chosen effect, applies the enabled overlays on top in the order
of OVERLAYS, then the brightness, and sends it to the keyboard.

To add one: write a class with the decorator, a `name`, `title` and
`description`, and a `render(ctx)` (effect) or `apply(frame, ctx)` (overlay).
It shows up in the window and in `rgbfx list` by itself. Then document it in
README.md.
"""

import re
import time
from dataclasses import dataclass

import numpy as np

import case
import keymap
from keymap import COLS, ROWS
from palette import NAMED, Palette, hex_rgb, hue, parse

ROW, COL = np.mgrid[0:ROWS, 0:COLS].astype(float)

# Matrix cells that have an LED (the TKL matrix has holes, column 0 is empty)
LIT = np.zeros((ROWS, COLS), bool)
for _r, _c in [*keymap.POS.values(), keymap.FN_POS]:
    LIT[_r, _c] = True

EFFECTS: dict[str, type] = {}
OVERLAYS: dict[str, type] = {}


def effect(cls):
    EFFECTS[cls.name] = cls
    return cls


def overlay(cls):
    OVERLAYS[cls.name] = cls
    return cls


@dataclass
class Context:
    t: float  # animation time in seconds, scaled by the speed setting
    dt: float  # animation time since last frame
    now: float  # time.monotonic(), unscaled (for key presses)
    last: float  # `now` of the previous frame
    speed: float
    palette: Palette
    inputs: object  # inputs.Inputs
    state: dict

    def presses(self):
        """Keys pressed since the previous frame, with their position."""
        for code, t in self.inputs.keyboard.presses_since(self.last):
            if code in keymap.POS:
                yield code, keymap.POS[code], t


def fill(colour) -> np.ndarray:
    return np.broadcast_to(np.asarray(colour, float), (ROWS, COLS, 3)).copy()


def put(frame, code, colour, mix=1.0):
    """Colour one key (blending with what's under it when mix < 1)."""
    if code in keymap.POS:
        r, c = keymap.POS[code]
        frame[r, c] = frame[r, c] * (1 - mix) + np.asarray(colour) * mix


def splat(buf, y, x, colour, amount=1.0):
    """Light a point between keys: spread it over the 4 nearest ones (keeps motion smooth)."""
    r0, c0 = int(np.floor(y)), int(np.floor(x))
    fy, fx = y - r0, x - c0
    for r, c, w in ((r0, c0, (1 - fy) * (1 - fx)), (r0, c0 + 1, (1 - fy) * fx),
                    (r0 + 1, c0, fy * (1 - fx)), (r0 + 1, c0 + 1, fy * fx)):
        if 0 <= r < ROWS and 0 <= c < COLS:
            buf[r, c] = np.maximum(buf[r, c], np.asarray(colour) * w * amount)


class Base:
    name = ""
    title = ""
    description = ""
    category = ""
    needs: tuple = ()  # inputs to start: "keyboard", "audio", "hypr", "system", "notifications"

    def __init__(self):
        self.rng = np.random.default_rng()


# ---------------------------------------------------------------------------
# Effects: one at a time
# ---------------------------------------------------------------------------

# Classic effects, like the keyboard's built-in ones but in the scheme colours.
# They are drawn in software so overlays work on top of them.


@effect
class Off(Base):
    name, title, category = "off", "Off", "Classic"
    description = "All LEDs off (overlays still show up, like the Super key hints)."

    def render(self, ctx):
        return fill(0)


@effect
class Static(Base):
    name, title, category = "static", "Static", "Classic"
    description = "The whole keyboard in the Caelestia primary colour. Follows the wallpaper."

    def render(self, ctx):
        return fill(ctx.palette.primary)


@effect
class Breathing(Base):
    name, title, category = "breathing", "Breathing", "Classic"
    description = "Breathes in the primary colour, then in the tertiary one (like breath_dual)."

    def render(self, ctx):
        phase = ctx.t / 3.0
        colour = ctx.palette.primary if int(phase) % 2 == 0 else ctx.palette.tertiary
        return fill(colour * np.sin(np.pi * (phase % 1)) ** 2)


@effect
class Starlight(Base):
    name, title, category = "starlight", "Starlight", "Classic"
    description = "Random keys twinkle in the primary and secondary colours (like starlight_dual)."

    def __init__(self):
        super().__init__()
        self.stars = np.zeros((ROWS, COLS))
        self.which = np.zeros((ROWS, COLS), bool)

    def render(self, ctx):
        self.stars *= np.exp(-ctx.dt * 1.5)
        born = self.rng.random((ROWS, COLS)) < ctx.dt * 0.25
        self.stars[born] = 1
        self.which[born] = self.rng.random(born.sum()) < 0.5
        colours = np.where(self.which[..., None], ctx.palette.primary, ctx.palette.secondary)
        return colours * self.stars[..., None]


@effect
class Reactive(Base):
    name, title, category = "reactive", "Reactive", "Classic"
    description = "Keys light up in the primary colour when pressed and fade out (like reactive)."
    needs = ("keyboard",)

    def __init__(self):
        super().__init__()
        self.glow = np.zeros((ROWS, COLS))

    def render(self, ctx):
        self.glow = np.maximum(self.glow - ctx.dt / 1.2, 0)
        for _, (r, c), _ in ctx.presses():
            self.glow[r, c] = 1
        return ctx.palette.primary * self.glow[..., None] + ctx.palette.primary * 0.04


@effect
class Wave(Base):
    name, title, category = "wave", "Wave", "Classic"
    description = "A primary → secondary → tertiary gradient scrolling across the keys."

    def render(self, ctx):
        return ctx.palette.gradient(COL / COLS * 0.6 - ctx.t * 0.2)


@effect
class Spectrum(Base):
    name, title, category = "spectrum", "Rainbow", "Classic"
    description = "The full rainbow scrolling across the keys (ignores the scheme)."

    def render(self, ctx):
        return hue(COL / COLS * 0.5 + ROW * 0.02 - ctx.t * 0.1)


# Per-key effects


@effect
class AudioVisualiser(Base):
    name, title, category = "audio", "Audio visualiser", "Per-key"
    description = ("What's playing, as a spectrum: one column per frequency band, bass on the left. "
                   "Bars go from primary at the bottom to tertiary at the top.")
    needs = ("audio",)

    source = "audio"  # Inputs attribute to listen to
    bottom, top = "primary", "tertiary"  # bar colours

    def render(self, ctx):
        bands = getattr(ctx.inputs, self.source).get()
        height = bands * ROWS  # in rows
        level = (ROWS - 1 - ROW)  # 0 at the bottom row
        on = np.clip(height[None, :] - level, 0, 1)
        bottom, top = getattr(ctx.palette, self.bottom), getattr(ctx.palette, self.top)
        colours = bottom * (1 - ROW / ROWS)[..., None] + top * (ROW / ROWS)[..., None]
        return colours * on[..., None] + bottom * 0.03


@effect
class MicVisualiser(AudioVisualiser):
    name, title, category = "mic", "Mic visualiser", "Per-key"
    description = ("Your microphone, as a spectrum: one column per frequency band of the voice "
                   "range (80 Hz to 8 kHz). Bars go from secondary at the bottom to tertiary at the top.")
    needs = ("mic",)
    source = "mic"
    bottom = "secondary"


@effect
class ScreenMirror(Base):
    name, title, category = "screen", "Screen mirror", "Per-key"
    description = ("The keyboard mimics the screen, like an ambilight: each key takes the colour of "
                   "the part of the focused monitor it sits under. Colours are boosted for the LEDs.")
    needs = ("screen",)

    def __init__(self):
        super().__init__()
        self.shown = np.zeros((ROWS, COLS, 3))

    def render(self, ctx):
        target = ctx.inputs.screen.get()
        # Screens are mostly muted colours: saturate them, and use the gamma
        # curve so dark greys stay dark instead of lighting up grey-white
        grey = target.mean(axis=-1, keepdims=True)
        target = np.clip(grey + (target - grey) * 1.6, 0, 1) ** 2.2
        # Ease toward the latest capture so motion looks smooth
        self.shown += (target - self.shown) * min(1.0, ctx.dt / ctx.speed * 8)
        return self.shown


@effect
class Ripples(Base):
    name, title, category = "ripple", "Typing ripples", "Per-key"
    description = "Each key press sends a ring outward from that key, cycling through the scheme colours."
    needs = ("keyboard",)

    def __init__(self):
        super().__init__()
        self.ripples = []  # (row, col, start, colour)
        self.count = 0

    def render(self, ctx):
        for _, (r, c), t in ctx.presses():
            self.ripples.append((r, c, t, ctx.palette.gradient(self.count * 0.13)))
            self.count += 1
        frame = fill(ctx.palette.primary * 0.04)
        alive = []
        for r, c, start, colour in self.ripples:
            age = (ctx.now - start) * ctx.speed
            if age > 1.6:
                continue
            alive.append((r, c, start, colour))
            dist = np.hypot(ROW - r, (COL - c) * 0.9)
            ring = np.exp(-(((dist - age * 9) / 0.9) ** 2)) * (1 - age / 1.6)
            frame += colour * ring[..., None]
        self.ripples = alive[-24:]
        return frame


@effect
class Status(Base):
    name, title, category = "status", "Live status", "Per-key"
    description = ("Number keys 1-0 show Hyprland workspaces (bright: current, dim: has windows). "
                   "The F-row is a CPU load bar, green to red with the CPU temperature.")
    needs = ("hypr", "system")

    def render(self, ctx):
        hypr, system = ctx.inputs.hypr, ctx.inputs.system
        frame = fill(ctx.palette.primary * 0.05)
        for i, code in enumerate(keymap.NUMBERS):
            ws = i + 1
            if ws == hypr.active_workspace:
                put(frame, code, ctx.palette.primary)
            elif hypr.workspaces.get(ws, 0) > 0:
                put(frame, code, ctx.palette.secondary * 0.35)
            elif ws in hypr.workspaces:
                put(frame, code, ctx.palette.secondary * 0.12)
        heat = np.clip((system.temp - 45) / 40, 0, 1)
        bar = np.array([heat, 1 - heat, 0.0])
        lit = system.cpu * len(keymap.F_ROW)
        for i, code in enumerate(keymap.F_ROW):
            put(frame, code, bar * (0.15 + 0.85 * np.clip(lit - i, 0, 1)))
        return frame


@effect
class Heatmap(Base):
    name, title, category = "heatmap", "Typing heatmap", "Per-key"
    description = ("Keys glow from cold blue to hot red with how much you've typed them lately "
                   "(a key cools down by half every 5 minutes). See your most used keys.")
    needs = ("keyboard",)

    HALF_LIFE = 300.0  # seconds, real time (not the speed setting)
    # cold -> hot: blue, cyan, green, yellow, red
    STOPS = np.array([[0, 0, 0.25], [0, 0.6, 1], [0, 1, 0.2], [1, 0.85, 0], [1, 0, 0]])

    def __init__(self):
        super().__init__()
        self.heat = np.zeros((ROWS, COLS))

    def render(self, ctx):
        self.heat *= 0.5 ** ((ctx.now - ctx.last) / self.HALF_LIFE)
        for _, (r, c), _ in ctx.presses():
            self.heat[r, c] += 1
        level = np.sqrt(self.heat / max(self.heat.max(), 5))  # sqrt: rarely used keys still show
        x = np.clip(level, 0, 1) * (len(self.STOPS) - 1)
        i = np.minimum(x.astype(int), len(self.STOPS) - 2)
        f = (x - i)[..., None]
        return (self.STOPS[i] * (1 - f) + self.STOPS[i + 1] * f) * LIT[..., None]


# Themed effects


@effect
class Predatoria(Base):
    name, title, category = "predatoria", "Predatoria 🩸", "Themed"
    description = ("For the Empress of Vampires: a deep crimson heartbeat (lub-dub) with blood "
                   "drips falling down the rows. Pressing a key makes it bleed.")
    needs = ("keyboard",)

    BLOOD = np.array([1.0, 0.0, 0.03])

    def __init__(self):
        super().__init__()
        self.drops = []  # [col, y, vy, forming time left]
        self.stain = np.zeros((ROWS, COLS))

    def render(self, ctx):
        # Heartbeat: a strong beat, then a weaker one shortly after, ~60 bpm
        phase = ctx.t % 1.0
        pulse = np.exp(-((phase - 0.05) / 0.05) ** 2) + 0.6 * np.exp(-((phase - 0.25) / 0.05) ** 2)
        frame = fill(self.BLOOD * (0.06 + 0.3 * pulse))

        if self.rng.random() < ctx.dt * 1.2:
            self.drops.append([int(self.rng.integers(COLS)), 0.0, 0.0, 0.6])
        for _, (r, c), _ in ctx.presses():
            self.drops.append([c, float(r), 0.0, 0.3])

        self.stain *= np.exp(-ctx.dt * 0.8)
        alive = []
        for drop in self.drops:
            col, y, vy, forming = drop
            if forming > 0:  # the drop swells before it falls
                drop[3] -= ctx.dt
                self.stain[int(y), col] = max(self.stain[int(y), col], 1 - drop[3])
            else:
                drop[2] = vy + 9 * ctx.dt
                drop[1] = y + drop[2] * ctx.dt
                if drop[1] >= ROWS:
                    continue
                self.stain[int(drop[1]), col] = 1
            alive.append(drop)
        self.drops = alive[-40:]
        return np.maximum(frame, self.BLOOD * self.stain[..., None] ** 1.5)


@effect
class Fire(Base):
    name, title, category = "fire", "Fire", "Themed"
    description = "Flames rising from the space bar row (the demoscene fire). Typing stokes them."
    needs = ("keyboard",)

    def __init__(self):
        super().__init__()
        self.heat = np.zeros((ROWS + 1, COLS))
        self.acc = 0.0

    def render(self, ctx):
        self.acc += ctx.dt * 18
        while self.acc >= 1:
            self.acc -= 1
            h = self.heat
            h[-1] = self.rng.uniform(0.5, 1.0, COLS)
            spread = (np.roll(h[1:], 1, axis=1) + h[1:] * 2 + np.roll(h[1:], -1, axis=1)) / 4
            h[:-1] = np.clip(spread - self.rng.uniform(0.08, 0.22, (ROWS, COLS)), 0, 1)
        for _, (r, c), _ in ctx.presses():
            self.heat[r:, c] = 1
        h = self.heat[:-1]
        return np.stack([np.clip(h * 2.2, 0, 1), np.clip(h * 2.2 - 1, 0, 1) * 0.55,
                         np.clip(h * 3 - 2.4, 0, 1) * 0.3], axis=-1)


@effect
class Plasma(Base):
    name, title, category = "plasma", "Plasma", "Themed"
    description = "Smooth flowing blobs, in the scheme colours (the demoscene plasma)."

    def render(self, ctx):
        t = ctx.t
        v = (np.sin(COL * 0.45 + t) + np.sin(ROW * 0.6 + t * 0.8)
             + np.sin((COL + ROW) * 0.3 + t * 1.3)
             + np.sin(np.hypot(COL - 9 + 6 * np.sin(t * 0.3), ROW - 3 + 3 * np.cos(t * 0.4)) * 0.8))
        return ctx.palette.gradient(v / 8 + 0.5 + t * 0.03)


@effect
class Life(Base):
    name, title, category = "life", "Game of Life", "Themed"
    description = ("Conway's Game of Life on the keys: newborn cells in tertiary, older ones in "
                   "primary. Pressing a key brings cells to life around it.")
    needs = ("keyboard",)

    def __init__(self):
        super().__init__()
        self.alive = self.rng.random((ROWS, COLS)) < 0.35
        self.age = np.zeros((ROWS, COLS))
        self.ghost = np.zeros((ROWS, COLS))
        self.acc = 0.0
        self.history = []

    def render(self, ctx):
        for _, (r, c), _ in ctx.presses():
            for dr, dc in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
                if self.rng.random() < 0.7 or (dr, dc) == (0, 0):
                    self.alive[(r + dr) % ROWS, (c + dc) % COLS] = True
        self.acc += ctx.dt / 0.35
        while self.acc >= 1:
            self.acc -= 1
            self.step()
        self.ghost *= np.exp(-ctx.dt * 4)
        young = (self.age < 2)[..., None]
        colours = np.where(young, ctx.palette.tertiary, ctx.palette.primary)
        frame = colours * self.alive[..., None]
        return np.maximum(frame, ctx.palette.secondary * 0.4 * self.ghost[..., None])

    def step(self):
        a = self.alive
        n = sum(np.roll(np.roll(a, dr, 0), dc, 1)
                for dr in (-1, 0, 1) for dc in (-1, 0, 1) if (dr, dc) != (0, 0))
        new = (n == 3) | (a & (n == 2))
        self.ghost[a & ~new] = 1
        self.age = np.where(new, self.age + 1, 0)
        self.alive = new
        # Reseed when it dies out or loops
        key = new.tobytes()
        self.history = (self.history + [key])[-12:]
        if not new.any() or self.history.count(key) > 2:
            self.alive = self.rng.random((ROWS, COLS)) < 0.35
            self.history = []


@effect
class Storm(Base):
    name, title, category = "storm", "Thunderstorm", "Themed"
    description = ("Rain streaks falling down the keys, and every few seconds a lightning bolt "
                   "forks down from the F-row with a flash. Enter calls one down.")
    needs = ("keyboard",)

    RAIN = np.array([0.15, 0.35, 1.0])
    BOLT = np.array([0.85, 0.9, 1.0])

    def __init__(self):
        super().__init__()
        self.rain = np.zeros((ROWS, COLS))
        self.drops = []  # [col, y, speed]
        self.bolt = np.zeros((ROWS, COLS))
        self.flash = 0.0
        self.next = 1.5

    def strike(self):
        c = int(self.rng.integers(2, COLS - 1))
        for r in range(ROWS):
            self.bolt[r, c] = 1
            if self.rng.random() < 0.3 and r < ROWS - 1:  # a fork
                self.bolt[r + 1, min(COLS - 1, c + 1)] = 0.6
            c = int(np.clip(c + self.rng.integers(-1, 2), 1, COLS - 1))
        self.flash = 1.0

    def render(self, ctx):
        if self.rng.random() < ctx.dt * 14:
            self.drops.append([int(self.rng.integers(COLS)), -0.5, self.rng.uniform(10, 16)])
        self.rain *= np.exp(-ctx.dt * 9)
        alive = []
        for d in self.drops:
            d[1] += d[2] * ctx.dt
            if d[1] < ROWS:
                if d[1] >= 0:
                    self.rain[int(d[1]), d[0]] = 1
                alive.append(d)
        self.drops = alive[-60:]

        self.next -= ctx.dt
        if self.next <= 0 or any(code == keymap.ENTER for code, _, _ in ctx.presses()):
            self.strike()
            self.next = self.rng.uniform(2.5, 7)
        self.bolt *= np.exp(-ctx.dt * 5)
        self.flash *= np.exp(-ctx.dt * 7)
        # The flash flickers: lightning is a few strokes, not one
        flicker = self.flash * (0.6 + 0.4 * np.sin(self.flash * 40) ** 2)

        frame = fill(self.RAIN * 0.03 + self.BOLT * 0.35 * flicker)
        frame = np.maximum(frame, self.RAIN * 0.8 * self.rain[..., None])
        return np.maximum(frame, self.BOLT * self.bolt[..., None])


@effect
class Fireworks(Base):
    name, title, category = "fireworks", "Fireworks", "Themed"
    description = ("Rockets climb from the bottom row and burst into sparks in the scheme colours. "
                   "Press a key to launch one that bursts right on it.")
    needs = ("keyboard",)

    def __init__(self):
        super().__init__()
        self.glow = np.zeros((ROWS, COLS, 3))
        self.rockets = []  # [x, y, burst_y, colour]
        self.sparks = []  # [x, y, vx, vy, life, colour]

    def launch(self, ctx, col, burst_y):
        colour = ctx.palette.gradient(self.rng.random())
        self.rockets.append([float(col), float(ROWS - 1), burst_y, colour])

    def render(self, ctx):
        if self.rng.random() < ctx.dt * 0.9:
            self.launch(ctx, self.rng.integers(2, COLS - 1), self.rng.uniform(0.5, 2.5))
        for _, (r, c), _ in ctx.presses():
            self.launch(ctx, c, float(r))
        self.glow *= np.exp(-ctx.dt * 4.5)

        flying = []
        for rk in self.rockets:
            rk[1] -= ctx.dt * 9
            if rk[1] <= rk[2]:
                for a in self.rng.uniform(0, 2 * np.pi, 14):
                    v = self.rng.uniform(3, 7)
                    self.sparks.append([rk[0], rk[2], np.cos(a) * v * 1.4, np.sin(a) * v, 1.0, rk[3]])
            else:
                splat(self.glow, rk[1], rk[0], np.ones(3) * 0.7)
                flying.append(rk)
        self.rockets = flying[-8:]

        burning = []
        for s in self.sparks:
            s[3] += 7 * ctx.dt  # gravity
            s[0] += s[2] * ctx.dt
            s[1] += s[3] * ctx.dt
            s[4] -= ctx.dt / 1.1
            if s[4] > 0:
                splat(self.glow, s[1], s[0], s[5], s[4])
                burning.append(s)
        self.sparks = burning[-150:]
        return self.glow.copy()


@effect
class Aurora(Base):
    name, title, category = "aurora", "Aurora", "Ambient"
    description = ("Northern lights: slow curtains of light rippling across the top of the "
                   "keyboard, in the scheme colours, over a starry night.")

    def __init__(self):
        super().__init__()
        self.stars = np.zeros((ROWS, COLS))

    def render(self, ctx):
        t, x = ctx.t, COL / COLS
        # Where the curtain's lower edge hangs, and how bright each fold is
        edge = 2.6 + 1.2 * np.sin(x * 4 + t * 0.35) + 0.7 * np.sin(x * 11 - t * 0.6)
        folds = (0.5 + 0.5 * np.sin(x * 7 + t * 0.5 + 2 * np.sin(x * 3 - t * 0.25))) ** 2
        curtain = np.clip(1.2 - np.abs(ROW - edge * 0.6) / (edge * 0.6 + 0.5), 0, 1) * (0.25 + 0.75 * folds)
        colour = ctx.palette.gradient(x * 0.35 + ROW * 0.07 + t * 0.015)

        self.stars *= np.exp(-ctx.dt * 1.2)
        self.stars[self.rng.random((ROWS, COLS)) < ctx.dt * 0.05] = 1
        night = np.array([0.0, 0.01, 0.04])
        frame = night + colour * curtain[..., None] ** 1.5
        return np.maximum(frame, 0.5 * self.stars[..., None] * (curtain < 0.2)[..., None])


@effect
class Rain(Base):
    name, title, category = "matrix", "Digital rain", "Ambient"
    description = ("Falling streams of light, like the code rain from the films, in the primary "
                   "colour with bright heads. Typing sends a stream down from the key.")
    needs = ("keyboard",)

    def __init__(self):
        super().__init__()
        self.trail = np.zeros((ROWS, COLS))
        self.heads = np.zeros((ROWS, COLS))
        self.streams = []  # [col, y, speed]

    def render(self, ctx):
        for c in np.nonzero(self.rng.random(COLS) < ctx.dt * 0.7)[0]:
            self.streams.append([int(c), -1.0, self.rng.uniform(4, 9)])
        for _, (r, c), _ in ctx.presses():
            self.streams.append([c, float(r), 8.0])
        self.trail *= np.exp(-ctx.dt * 2.5)
        self.heads[:] = 0
        alive = []
        for s in self.streams:
            prev = int(s[1])
            s[1] += s[2] * ctx.dt
            for r in range(max(prev, 0), min(int(s[1]), ROWS - 1) + 1):
                self.trail[r, s[0]] = 1
            if s[1] < ROWS:
                if s[1] >= 0:
                    self.heads[int(s[1]), s[0]] = 1
                alive.append(s)
        self.streams = alive[-50:]
        # A bit of flicker, like changing glyphs
        flicker = 0.75 + 0.25 * self.rng.random((ROWS, COLS))
        frame = ctx.palette.primary * (self.trail * flicker)[..., None] ** 2
        white = ctx.palette.primary * 0.3 + 0.7
        return np.maximum(frame, white * self.heads[..., None])


@effect
class Meteors(Base):
    name, title, category = "meteors", "Meteor shower", "Ambient"
    description = "Shooting stars streak diagonally across the keys, leaving trails that cool down."

    def __init__(self):
        super().__init__()
        self.glow = np.zeros((ROWS, COLS, 3))
        self.meteors = []  # [x, y, vx, vy, colour]

    def render(self, ctx):
        if self.rng.random() < ctx.dt * 1.8:
            x = self.rng.uniform(-2, COLS * 0.8)
            v = self.rng.uniform(10, 18)
            colour = ctx.palette.gradient(self.rng.random()) * 0.5 + 0.5 * ctx.palette.tertiary
            self.meteors.append([x, -1.0, v, v * self.rng.uniform(0.25, 0.45), colour])
        self.glow *= np.exp(-ctx.dt * 6)
        alive = []
        for m in self.meteors:
            steps = max(1, int(np.hypot(m[2], m[3]) * ctx.dt * 3))  # no gaps in the trail
            for _ in range(steps):
                m[0] += m[2] * ctx.dt / steps
                m[1] += m[3] * ctx.dt / steps
                splat(self.glow, m[1], m[0], m[4])
            if m[0] < COLS + 1 and m[1] < ROWS + 1:
                splat(self.glow, m[1], m[0], np.ones(3))  # white-hot head
                alive.append(m)
        self.meteors = alive[-12:]
        return self.glow.copy()


@effect
class LavaLamp(Base):
    name, title, category = "lava", "Lava lamp", "Ambient"
    description = "Soft blobs of colour slowly rise, sink and merge (metaballs), in the scheme colours."

    BLOBS = [(2.5, 0.31, 0.0, 1.8), (6.5, 0.23, 1.7, 1.5), (10.5, 0.27, 3.1, 2.0),
             (14.5, 0.19, 4.4, 1.6), (8.5, 0.35, 5.5, 1.3)]  # centre col, speed, phase, size

    def render(self, ctx):
        t = ctx.t
        field = np.zeros((ROWS, COLS))
        tint = np.zeros((ROWS, COLS))
        for i, (cx, w, ph, size) in enumerate(self.BLOBS):
            x = cx + 2.2 * np.sin(t * w * 0.6 + ph * 2)
            y = 2.5 + 3.2 * np.sin(t * w + ph)
            f = size ** 2 / ((COL - x) ** 2 * 0.45 + (ROW - y) ** 2 + 0.3)
            field += f
            tint += f * i / len(self.BLOBS)
        tint /= field
        level = np.clip((field - 0.9) * 1.5, 0, 1)
        colour = ctx.palette.gradient(tint + t * 0.01)
        return ctx.palette.primary * 0.03 + colour * level[..., None]


# Games: they play themselves


@effect
class Snake(Base):
    name, title, category = "snake", "Snake", "Games"
    description = ("A snake that plays by itself: it hunts the pulsing food and grows. Press a key "
                   "to drop the food there. It turns red and starts over when it traps itself.")
    needs = ("keyboard",)

    CELLS = [tuple(p) for p in np.argwhere(LIT)]

    def __init__(self):
        super().__init__()
        self.reset()

    def reset(self):
        start = (3, 5)
        self.body = [start, (3, 4), (3, 3)]
        self.food = self.place_food()
        self.acc = 0.0
        self.dead = 0.0

    def place_food(self):
        free = [c for c in self.CELLS if c not in self.body]
        return free[self.rng.integers(len(free))] if free else None

    def neighbours(self, cell):
        r, c = cell
        for n in ((r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)):
            if 0 <= n[0] < ROWS and 0 <= n[1] < COLS and LIT[n]:
                yield n

    def path(self, goal, blocked):
        """First step of a shortest path from the head to goal (BFS), or None."""
        head = self.body[0]
        first = {}
        queue = []
        for n in self.neighbours(head):
            if n not in blocked:
                first[n] = n
                queue.append(n)
        while queue:
            cell = queue.pop(0)
            if cell == goal:
                return first[cell]
            for n in self.neighbours(cell):
                if n not in first and n not in blocked and n != head:
                    first[n] = first[cell]
                    queue.append(n)
        return None

    def step(self):
        blocked = set(self.body[:-1])  # the tail moves out of the way
        move = self.path(self.food, blocked) if self.food else None
        if move is None:  # no way to the food: go wherever there is the most room
            options = [n for n in self.neighbours(self.body[0]) if n not in blocked]
            if not options:
                self.dead = 1.0
                return
            move = max(options, key=lambda n: sum(1 for m in self.neighbours(n) if m not in blocked))
        self.body.insert(0, move)
        if move == self.food:
            self.food = self.place_food()
        else:
            self.body.pop()

    def render(self, ctx):
        for _, pos, _ in ctx.presses():
            if pos not in self.body:
                self.food = pos
        frame = fill(ctx.palette.primary * 0.03)
        if self.dead > 0:
            self.dead -= ctx.dt / 1.5
            for cell in self.body:
                frame[cell] = np.array([1.0, 0, 0]) * max(self.dead, 0)
            if self.dead <= 0:
                self.reset()
            return frame
        self.acc += ctx.dt / 0.13
        while self.acc >= 1 and self.dead <= 0:
            self.acc -= 1
            self.step()
        n = len(self.body)
        for i, cell in enumerate(self.body):
            frame[cell] = ctx.palette.gradient(i / max(n, 8) * 0.66) * (1 - 0.5 * i / n)
        frame[self.body[0]] = ctx.palette.primary * 0.4 + 0.6
        if self.food:
            frame[self.food] = ctx.palette.tertiary * (0.55 + 0.45 * np.sin(ctx.t * 8))
        return frame


# Test patterns


@effect
class RowScan(Base):
    name, title, category = "row-scan", "Row scan", "Test"
    description = "One row lit in the primary colour, sweeping top to bottom (one row every 0.5 s)."

    def render(self, ctx):
        frame = fill(0)
        frame[int(ctx.t / 0.5) % ROWS, :] = ctx.palette.primary
        return frame


@effect
class ColumnScan(Base):
    name, title, category = "column-scan", "Column scan", "Test"
    description = "One column lit in the primary colour, sweeping left to right (one column every 0.2 s)."

    def render(self, ctx):
        frame = fill(0)
        frame[:, int(ctx.t / 0.2) % COLS] = ctx.palette.primary
        return frame


@effect
class RainbowColumns(Base):
    name, title, category = "rainbow-columns", "Rainbow columns", "Test"
    description = ("The rainbow column by column: each key column is one solid colour, and the "
                   "whole rainbow moves one column to the right every 0.2 s.")

    def render(self, ctx):
        step = int(ctx.t / 0.2)
        return hue((np.arange(COLS) - step) / COLS)[None, :, :].repeat(ROWS, axis=0)


@effect
class FanSpin(Base):
    name, title, category = "fan-spin", "Fan spin", "Test"
    description = ("A light goes around every fan at the same time, top fans included (each fan is "
                   "drawn from its place in case.py), while a column sweeps the keyboard in step.")
    PERIOD = 3.6  # seconds per turn, like the column scan (18 columns x 0.2 s)
    TAIL = 0.2  # turns

    def turn(self, ctx):
        return (ctx.t / self.PERIOD) % 1

    def render(self, ctx):
        frame = fill(0)
        frame[:, int(self.turn(ctx) * COLS) % COLS] = ctx.palette.primary
        return frame

    def render_fans(self, ctx, sizes):
        head = self.turn(ctx)
        zones = {z: np.zeros((n, 3)) for z, n in sizes.items()}
        # The pump (LEDs 0-11) and the start of the top fans' chain (12-19) sit on the same
        # LEDs as the ring fans (0-19): the pump is skipped (it just follows the ring fans) and
        # the ring fans go last, so top fan 1's first 8 LEDs follow them too
        for ring in sorted(case.RINGS, key=lambda r: r.name.startswith("Top"), reverse=True):
            if ring.zone not in zones or ring.kind == "pump":
                continue
            angle = ring.start / 360 + np.arange(ring.count) / ring.count
            behind = (head - angle) % 1  # how far the head has gone past each LED
            k = np.clip(1 - behind / self.TAIL, 0, 1) ** 2
            leds = zones[ring.zone][ring.first:ring.first + ring.count]
            leds[:] = ctx.palette.primary * k[: len(leds), None]
        return zones


# ---------------------------------------------------------------------------
# Overlays: any number, drawn on top of the effect (in this order)
# ---------------------------------------------------------------------------


@overlay
class Context_(Base):
    name, title = "context", "App context"
    description = ("Highlights the keys that matter in the focused window: hjkl, Esc, :, / ... "
                   "in Neovim; WASD, Space, Shift... in games. The rest is dimmed.")
    needs = ("hypr",)

    # (window class regex, window title regex, {role: [keysyms]})
    RULES = [
        ("^(nvim|neovide)$|^kitty$|^foot$|^Alacritty$", r"\bn?vim\b", {
            "primary": ["h", "j", "k", "l"],
            "secondary": ["escape", "semicolon", "slash", "i", "v"],
            "tertiary": ["w", "b", "e", "u", "p", "y", "d"],
        }),
        (r"^steam_app_\d+$|^Albion-Online$|^Minecraft|^gamescope$|\.exe$", "", {
            "primary": ["w", "a", "s", "d"],
            "secondary": ["space", "shift_l", "control_l", "e", "q", "r", "f"],
            "tertiary": ["1", "2", "3", "4", "5", "tab", "escape"],
        }),
    ]

    def apply(self, frame, ctx):
        hypr = ctx.inputs.hypr
        for cls_re, title_re, roles in self.RULES:
            if re.search(cls_re, hypr.window_class) and (not title_re or re.search(title_re, hypr.window_title)):
                frame = frame * 0.2
                for role, keys in roles.items():
                    for k in keys:
                        put(frame, keymap.key(k), getattr(ctx.palette, role))
                return frame
        return frame


@overlay
class Pomodoro(Base):
    name, title = "pomodoro", "Pomodoro timer"
    description = ("While a timer runs (rgbfx pomodoro 25, or the window), the F-row is a "
                   "bar that drains from F12 to F1. It blinks green when time's up.")

    def apply(self, frame, ctx):
        pomo = ctx.state.get("pomodoro")
        if not pomo:
            return frame
        elapsed = time.time() - pomo["start"]
        total = pomo["minutes"] * 60
        n = len(keymap.F_ROW)
        if elapsed < total:
            left = (1 - elapsed / total) * n
            for i, code in enumerate(keymap.F_ROW):
                put(frame, code, ctx.palette.tertiary * (0.08 + 0.92 * np.clip(left - i, 0, 1)))
        elif elapsed < total + 8:
            on = int((elapsed - total) * 3) % 2 == 0
            for code in keymap.F_ROW:
                put(frame, code, np.array([0.0, 1.0, 0.2]) * on)
        return frame


@overlay
class CapsLock(Base):
    name, title = "caps-lock", "Caps Lock glow"
    description = "Caps Lock pulses white while it is on."
    needs = ("keyboard",)

    def apply(self, frame, ctx):
        if ctx.inputs.keyboard.caps_lock:
            put(frame, keymap.CAPS_LOCK, ctx.palette.white * (0.6 + 0.4 * np.sin(ctx.now * 4)))
        return frame


@overlay
class MicMute(Base):
    name, title = "mic-mute", "Mic muted"
    description = "Esc glows red while the default microphone is muted (wpctl)."
    needs = ("system",)

    def apply(self, frame, ctx):
        if ctx.inputs.system.mic_muted:
            put(frame, keymap.ESC, np.array([1.0, 0, 0]) * (0.6 + 0.4 * np.sin(ctx.now * 3)))
        return frame


@overlay
class Notify(Base):
    name, title = "notifications", "Notification flash"
    description = ("The keyboard pulses twice on each desktop notification: Discord blurple for "
                   "Discord/Vesktop, the primary colour otherwise.")
    needs = ("notifications",)

    def apply(self, frame, ctx):
        for app, t in list(ctx.inputs.notifications.events):
            age = ctx.now - t
            if age < 0.8:
                discord = re.search("discord|vesktop|webcord", app, re.I)
                colour = hex_rgb(NAMED["discord"]) if discord else ctx.palette.primary
                frame = _pulse(frame, colour, age)
        return frame


def _pulse(frame, colour, age):
    """Two quick flashes over 0.8 s."""
    k = np.sin(np.pi * age / 0.4) ** 2 if age < 0.8 else 0
    return frame * (1 - k) + np.asarray(colour) * k


@overlay
class SuperHints(Base):
    name, title = "super-hints", "Super key hints"
    description = ("Hold Super (the Windows key) and the keys that have a Hyprland shortcut light "
                   "up in primary. Add Shift, Ctrl or Alt and it follows: modifiers that unlock "
                   "more shortcuts glow in tertiary, keys bound to a longer combo are dim secondary.")
    needs = ("keyboard", "hypr")
    DELAY = 0.12  # seconds Super must be held, so quick shortcuts don't flash the keyboard

    def apply(self, frame, ctx):
        kb = ctx.inputs.keyboard
        held = kb.held_keys()
        since = [held[k] for k in (keymap.LSUPER, keymap.RSUPER) if k in held]
        if not since or ctx.now - min(since) < self.DELAY:
            return frame
        mask = kb.modmask()
        out = frame * 0.05
        exact, longer, unlock = set(), set(), 0
        for bind in ctx.inputs.hypr.get_binds():
            if bind.get("submap") or bind.get("mouse") or bind.get("key", "").startswith("mouse"):
                continue
            mods = bind.get("modmask", 0) & ~(2 | 16)  # ignore Caps Lock and Num Lock
            code = keymap.code_of(bind.get("key", ""), bind.get("keycode", 0))
            if code is None or code in keymap.MOD_BITS:
                continue
            if mods == mask:
                exact.add(code)
            elif mods & mask == mask:
                longer.add(code)
                unlock |= mods & ~mask
        for code in longer - exact:
            put(out, code, ctx.palette.secondary * 0.25)
        for code in exact:
            put(out, code, ctx.palette.primary)
        for bit, codes in keymap.MOD_KEYS.items():
            for code in codes:
                if mask & bit:
                    put(out, code, ctx.palette.white)
                elif unlock & bit:
                    put(out, code, ctx.palette.tertiary)
        return out


class Flash(Base):
    """`rgbfx flash [colour]`: always on, not listed (used by hooks and scripts)."""

    def apply(self, frame, ctx):
        flash = ctx.state.get("flash")
        if flash:
            age = time.time() - flash["at"]
            if 0 <= age < 0.8:
                frame = _pulse(frame, parse(flash.get("colour"), ctx.palette), age)
        return frame


# Overlays draw in this order: the Super hints stay on top of everything
ORDER = ["context", "pomodoro", "caps-lock", "mic-mute", "notifications", "super-hints"]
assert sorted(ORDER) == sorted(OVERLAYS), "add new overlays to ORDER"
