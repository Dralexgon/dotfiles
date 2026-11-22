"""Where each key sits in the LED matrix of a Razer TKL keyboard.

The BlackWidow V3 Tenkeyless has a 6x18 matrix. Positions are (row, col),
indexed by evdev key code (the numbers in linux/input-event-codes.h). They
come from Polychromatic's Huntsman TE map, which uses the same TKL matrix.
"""

ROWS, COLS = 6, 18

# evdev code -> (row, col)
POS = {
    # Row 0: Esc, F-row, Print/Scroll/Pause
    1: (0, 1), 59: (0, 3), 60: (0, 4), 61: (0, 5), 62: (0, 6), 63: (0, 7),
    64: (0, 8), 65: (0, 9), 66: (0, 10), 67: (0, 11), 68: (0, 12),
    87: (0, 13), 88: (0, 14), 99: (0, 15), 70: (0, 16), 119: (0, 17),
    # Row 1: number row, Ins/Home/PgUp
    41: (1, 1), 2: (1, 2), 3: (1, 3), 4: (1, 4), 5: (1, 5), 6: (1, 6),
    7: (1, 7), 8: (1, 8), 9: (1, 9), 10: (1, 10), 11: (1, 11), 12: (1, 12),
    13: (1, 13), 14: (1, 14), 110: (1, 15), 102: (1, 16), 104: (1, 17),
    # Row 2: Tab row, Del/End/PgDn
    15: (2, 1), 16: (2, 2), 17: (2, 3), 18: (2, 4), 19: (2, 5), 20: (2, 6),
    21: (2, 7), 22: (2, 8), 23: (2, 9), 24: (2, 10), 25: (2, 11), 26: (2, 12),
    27: (2, 13), 43: (2, 14), 111: (2, 15), 107: (2, 16), 109: (2, 17),
    # Row 3: Caps row
    58: (3, 1), 30: (3, 2), 31: (3, 3), 32: (3, 4), 33: (3, 5), 34: (3, 6),
    35: (3, 7), 36: (3, 8), 37: (3, 9), 38: (3, 10), 39: (3, 11), 40: (3, 12),
    28: (3, 14),
    # Row 4: Shift row, Up
    42: (4, 1), 44: (4, 3), 45: (4, 4), 46: (4, 5), 47: (4, 6), 48: (4, 7),
    49: (4, 8), 50: (4, 9), 51: (4, 10), 52: (4, 11), 53: (4, 12), 54: (4, 14),
    103: (4, 16),
    # Row 5: bottom row (Fn has no evdev code: (5, 12))
    29: (5, 1), 125: (5, 2), 56: (5, 3), 57: (5, 7), 100: (5, 11),
    127: (5, 13), 97: (5, 14), 105: (5, 15), 108: (5, 16), 106: (5, 17),
}

# Named keys, used by effects and overlays
ESC = 1
F_ROW = [59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88]  # F1..F12
NUMBERS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]  # 1..9, 0 (workspaces 1..10)
CAPS_LOCK = 58
PAUSE = 119
LSHIFT, RSHIFT, LCTRL, RCTRL, LALT, RALT, LSUPER, RSUPER = 42, 54, 29, 97, 56, 100, 125, 126
SPACE = 57

# Hyprland modmask bits for each modifier key
MOD_BITS = {
    LSHIFT: 1, RSHIFT: 1,
    LCTRL: 4, RCTRL: 4,
    LALT: 8, RALT: 8,
    LSUPER: 64, RSUPER: 64,
}
SHIFT, CTRL, ALT, SUPER = 1, 4, 8, 64
MOD_KEYS = {SHIFT: [LSHIFT, RSHIFT], CTRL: [LCTRL, RCTRL], ALT: [LALT, RALT], SUPER: [LSUPER]}

# Physical key under a keysym name, as Hyprland prints them in `hyprctl binds`
# (lowercased). This assumes the US layout, which is how the keys are printed.
_KEYSYMS = {
    "escape": 1, "minus": 12, "equal": 13, "backspace": 14, "tab": 15,
    "bracketleft": 26, "bracketright": 27, "return": 28, "enter": 28,
    "semicolon": 39, "apostrophe": 40, "grave": 41, "backslash": 43,
    "comma": 51, "period": 52, "slash": 53, "space": 57, "caps_lock": 58,
    "print": 99, "scroll_lock": 70, "pause": 119,
    "insert": 110, "home": 102, "prior": 104, "page_up": 104,
    "delete": 111, "end": 107, "next": 109, "page_down": 109,
    "up": 103, "left": 105, "down": 108, "right": 106, "menu": 127,
    "shift_l": LSHIFT, "shift_r": RSHIFT, "control_l": LCTRL, "control_r": RCTRL,
    "alt_l": LALT, "alt_r": RALT, "super_l": LSUPER, "super_r": RSUPER,
}
_KEYSYMS.update({str(n): code for n, code in zip("1234567890", NUMBERS)})
_KEYSYMS.update({f"f{i + 1}": code for i, code in enumerate(F_ROW)})
_KEYSYMS.update({c: code for c, code in zip(
    "qwertyuiopasdfghjklzxcvbnm",
    [16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 38,
     44, 45, 46, 47, 48, 49, 50],
)})


def code_of(keysym: str, keycode: int = 0) -> int | None:
    """evdev code of a Hyprland bind key, or None (mouse binds, media keys...)."""
    if keycode:
        return keycode - 8  # xkb keycodes are evdev codes + 8
    name = keysym.lower()
    if name.startswith("code:"):
        try:
            return int(name[5:]) - 8
        except ValueError:
            return None
    return _KEYSYMS.get(name)


def key(name: str) -> int:
    """evdev code of a keysym name that must exist ("h", "f1", "escape")."""
    return _KEYSYMS[name.lower()]
