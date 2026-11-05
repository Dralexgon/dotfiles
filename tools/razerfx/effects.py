"""Every effect and overlay razerfx can draw.

A frame is a float array of shape (ROWS, COLS, 3), RGB in [0, 1]. The daemon
renders the chosen effect, applies the enabled overlays on top in the order
of OVERLAYS, then the brightness, and sends it to the keyboard.

To add one: write a class with the decorator, a `name`, `title` and
`description`, and a `render(ctx)` (effect) or `apply(frame, ctx)` (overlay).
It shows up in the TUI and in `razerfx list` by itself. Then document it in
README.md.
"""

import re
import time
from dataclasses import dataclass

import numpy as np

import keymap
from keymap import COLS, ROWS
from palette import NAMED, Palette, hex_rgb, hue, parse

ROW, COL = np.mgrid[0:ROWS, 0:COLS].astype(float)

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

    def render(self, ctx):
        bands = ctx.inputs.audio.get()
        height = bands * ROWS  # in rows
        level = (ROWS - 1 - ROW)  # 0 at the bottom row
        on = np.clip(height[None, :] - level, 0, 1)
        colours = ctx.palette.primary * (1 - ROW / ROWS)[..., None] + ctx.palette.tertiary * (ROW / ROWS)[..., None]
        return colours * on[..., None] + ctx.palette.primary * 0.03


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
    description = ("While a timer runs (`razerfx pomodoro 25`, or p in the TUI), the F-row is a "
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
    """`razerfx flash [colour]`: always on, not listed (used by hooks and scripts)."""

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
