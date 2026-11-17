"""Read the Hyprland keybinds of the Caelestia config, for the Keybinds tab.

`hyprctl binds` is no help with Hyprland's Lua config: every bind's
dispatcher shows up as `__lua`. So the binds are read from the Lua files
themselves, without running them:

- Caelestia's defaults: the `kb*` variables of ~/.config/hypr/variables.lua,
  bound by the `create_bind(vars.kbX, action, flags)` calls of
  ~/.config/hypr/hyprland/keybinds.lua (which also binds a few keys
  literally, like the brightness keys);
- the overrides of config/caelestia/hypr-vars.lua, applied on top (the way
  hyprland.lua merges them: a key replaces the default, "" removes the bind);
- the user's own `hl.bind(key, action, { description = ... })` calls of
  config/caelestia/hypr-user.lua.

The parser is a small Lua tokenizer: strings ("", '', [[ ]]), comments
(-- and --[[ ]]) and nesting (brackets and function/do/then ... end) are
handled, anything else is kept as source text.
"""

import re
from dataclasses import dataclass, field
from pathlib import Path

# Caelestia's files (installed by the caelestia module, not in the dotfiles)
HYPR = Path.home() / ".config/hypr"
DEFAULT_VARS = HYPR / "variables.lua"
DEFAULT_BINDS = HYPR / "hyprland/keybinds.lua"

# Names of Caelestia's kb* variables. A variable missing here is named from
# its own name (kbFooBar -> "Foo bar").
LABELS = {
    "kbGoToWs": "Go to workspace",
    "kbGoToWsGroup": "Go to workspace group",
    "kbMoveWinToWs": "Move window to workspace",
    "kbMoveWinToWsSilent": "Send window to workspace (stay)",
    "kbMoveWinToWsGroup": "Move window to workspace group",
    "kbMoveWinToWsSpecial": "Move window to the scratchpad",
    "kbMoveWinFromWsSpecial": "Move window out of the scratchpad",
    "kbMoveWinToWsNext": "Move window to the next workspace",
    "kbMoveWinToWsPrev": "Move window to the previous workspace",
    "kbNextWs": "Next workspace",
    "kbPrevWs": "Previous workspace",
    "kbNextWsGroup": "Next workspace group",
    "kbPrevWsGroup": "Previous workspace group",
    "kbWindowCycleNext": "Next window",
    "kbWindowCyclePrev": "Previous window",
    "kbWindowGroupCycleNext": "Next window in the group",
    "kbWindowGroupCyclePrev": "Previous window in the group",
    "kbUngroup": "Take the window out of its group",
    "kbToggleGroup": "Group / ungroup windows",
    "kbGroupLockActive": "Lock the window group",
    "kbWindowDecreaseWidth": "Narrower window",
    "kbWindowIncreaseWidth": "Wider window",
    "kbWindowDecreaseHeight": "Shorter window",
    "kbWindowIncreaseHeight": "Taller window",
    "kbMoveWindow": "Drag the window (hold)",
    "kbResizeWindow": "Resize the window (hold)",
    "kbCenterWindow": "Center the window",
    "kbNormalizeWindow": "Normal size, centered",
    "kbWindowPip": "Picture in picture",
    "kbPinWindow": "Pin the window (every workspace)",
    "kbWindowFullscreen": "Fullscreen",
    "kbWindowBorderedFullscreen": "Maximize",
    "kbToggleWindowFloating": "Float / tile the window",
    "kbCloseWindow": "Close the window",
    "kbSpecialWs": "Scratchpad",
    "kbSystemMonitorWs": "System monitor",
    "kbMusicWs": "Music",
    "kbCommunicationWs": "Communication (Discord...)",
    "kbTodoWs": "Todo",
    "kbTerminal": "Terminal",
    "kbBrowser": "Browser",
    "kbEditor": "Editor",
    "kbFileExplorer": "Files",
    "kbAudioSettings": "Audio settings",
    "kbScreenshot": "Screenshot",
    "kbScreenshotFreeze": "Screenshot a region (frozen)",
    "kbScreenshotRegion": "Screenshot a region",
    "kbRecord": "Record the screen",
    "kbRecordSound": "Record the screen with sound",
    "kbRecordRegion": "Record a region",
    "kbColorPicker": "Color picker",
    "kbMediaToggle": "Play / pause",
    "kbMediaNext": "Next track",
    "kbMediaPrev": "Previous track",
    "kbMediaStop": "Stop the media",
    "kbVolumeMute": "Mute",
    "kbLauncher": "App launcher",
    "kbSession": "Session menu",
    "kbShowSidebar": "Sidebar",
    "kbClearNotifs": "Clear notifications",
    "kbShowPanels": "Show all panels",
    "kbLock": "Lock the screen",
    "kbRestoreLock": "Restore the lock screen",
    "kbSleep": "Sleep",
    "kbClipboard": "Clipboard history",
    "kbClipboardDel": "Delete from the clipboard history",
    "kbClipboardPasteLatest": "Type the latest clipboard entry",
    "kbEmoji": "Emoji picker",
}

# Names of the binds keybinds.lua writes literally, without a variable. The
# extra keys of a variable (`{ vars.kbMediaToggle, "XF86AudioPlay" }`) are
# named after it instead.
LITERAL_LABELS = {
    "CTRL + SUPER + SHIFT + R": "Kill the shell",
    "CTRL + SUPER + ALT + R": "Restart the shell",
    "XF86MonBrightnessUp": "Brightness up",
    "XF86MonBrightnessDown": "Brightness down",
    "XF86AudioMicMute": "Mute the microphone",
    "XF86AudioRaiseVolume": "Volume up",
    "XF86AudioLowerVolume": "Volume down",
    "SUPER + ALT + F12": "Test notification",
}
# Binds made in a `for _, dir in ipairs({...})` loop, by action ({} is the loop value)
LOOP_LABELS = {
    "focus({ direction = dir })": "Focus the window {}",
    "window.move({ direction = dir })": "Move the window {}",
}

# Modifier names as Hyprland reads them, to compare combos
MODIFIERS = {"SHIFT": "SHIFT", "CAPS": "CAPS", "CTRL": "CTRL", "CONTROL": "CTRL",
             "ALT": "ALT", "MOD2": "MOD2", "MOD3": "MOD3", "SUPER": "SUPER", "WIN": "SUPER",
             "LOGO": "SUPER", "MOD4": "SUPER", "MOD5": "MOD5"}

# The bind flags of hl.bind's options table
FLAGS = ("locked", "release", "repeating", "mouse", "non_consuming", "long_press")

# Keys bound by the "modifier only" variables (kbGoToWs...): modifier + 1..9, 0
WS_KEYS = "1-9, 0"


@dataclass
class Bind:
    combo: str  # as written, "SUPER + Q"; "" when the bind is removed
    label: str  # what it does, in words
    action: str  # the Lua action, shortened ("exec kitty", "caelestia:launcher")
    source: str  # "default", "override" or "user"
    path: Path  # the file to change it in
    line: int  # its line in that file (1-based)
    var: str = ""  # the kb* variable, for Caelestia's binds
    default: str = ""  # an override: the default combo it replaces
    section: str = ""  # Caelestia's comment heading in keybinds.lua, or "Your binds"
    flags: list[str] = field(default_factory=list)
    conflict: bool = False  # another bind with a different action on the same combo

    @property
    def disabled(self) -> bool:
        return not self.combo


# Tokenizer


@dataclass
class Token:
    kind: str  # "str", "name", "num" or "op"
    value: str  # a string's contents, or the token's text
    start: int  # offsets in the source
    end: int
    line: int  # 1-based


LONG_BRACKET = re.compile(r"\[(=*)\[")
NAME = re.compile(r"[A-Za-z_]\w*")
NUMBER = re.compile(r"0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+")
OPERATORS = ("...", "..", "==", "~=", "<=", ">=", "//", "::", "<<", ">>")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def tokenize(text: str) -> tuple[list[Token], dict[int, str]]:
    """The tokens of a Lua file, and its whole-line comments by line."""
    tokens: list[Token] = []
    comments: dict[int, str] = {}
    i, line, n = 0, 1, len(text)
    line_has_code = False
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            line_has_code = False
            i += 1
            continue
        if c.isspace():
            i += 1
            continue
        if text.startswith("--", i):
            long = LONG_BRACKET.match(text, i + 2)
            if long:
                close = text.find("]" + long.group(1) + "]", long.end())
                close = n if close < 0 else close + len(long.group(0))
                line += text.count("\n", i, close)
                i = close
                continue
            end = text.find("\n", i)
            end = n if end < 0 else end
            if not line_has_code:
                comments[line] = text[i + 2:end].strip()
            i = end
            continue
        line_has_code = True
        start, start_line = i, line
        long = LONG_BRACKET.match(text, i) if c == "[" else None
        if long:
            close = text.find("]" + long.group(1) + "]", long.end())
            close = n if close < 0 else close
            value = text[long.end():close].removeprefix("\n")
            i = min(n, close + len(long.group(0)))
            line += text.count("\n", start, i)
            tokens.append(Token("str", value, start, i, start_line))
        elif c in "\"'":
            i += 1
            chars = []
            while i < n and text[i] != c:
                if text[i] == "\\" and i + 1 < n:
                    chars.append(ESCAPES.get(text[i + 1], text[i + 1]))
                    i += 2
                    continue
                if text[i] == "\n":  # unfinished string
                    break
                chars.append(text[i])
                i += 1
            i += 1
            tokens.append(Token("str", "".join(chars), start, i, start_line))
        elif m := NAME.match(text, i):
            i = m.end()
            tokens.append(Token("name", m.group(0), start, i, start_line))
        elif m := NUMBER.match(text, i):
            i = m.end()
            tokens.append(Token("num", m.group(0), start, i, start_line))
        else:
            op = next((o for o in OPERATORS if text.startswith(o, i)), c)
            i += len(op)
            tokens.append(Token("op", op, start, i, start_line))
    return tokens, comments


OPEN = {"(", "{", "["}
CLOSE = {")", "}", "]"}
BLOCK_OPEN = {"function", "do", "then", "repeat"}
BLOCK_CLOSE = {"end", "until"}


def nesting(token: Token) -> int:
    """+1 when a token opens a bracket or a block, -1 when it closes one."""
    if token.kind == "op":
        return (token.value in OPEN) - (token.value in CLOSE)
    if token.kind == "name":
        # "if ... then ... end" and "for/while ... do ... end": then and do open the block,
        # and "elseif ... then" closes the previous branch before its then opens the next one
        return (token.value in BLOCK_OPEN) - (token.value in BLOCK_CLOSE) - (token.value == "elseif")
    return 0


def split_args(tokens: list[Token], open_index: int) -> tuple[list[list[Token]], int]:
    """The comma-separated items after an opening bracket, and the index of its closing one."""
    items: list[list[Token]] = [[]]
    depth = 0
    i = open_index + 1
    while i < len(tokens):
        t = tokens[i]
        if depth == 0 and t.kind == "op":
            if t.value in CLOSE:
                break
            if t.value in (",", ";"):
                items.append([])
                i += 1
                continue
        depth += nesting(t)
        items[-1].append(t)
        i += 1
    return [item for item in items if item], i


def calls(tokens: list[Token], name: str) -> list[tuple[int, list[list[Token]]]]:
    """The (line, arguments) of every call to a function, like "hl.bind"."""
    parts = name.split(".")
    pattern = [p for part in parts for p in (part, ".")][:-1]
    found = []
    for i in range(len(tokens) - len(pattern)):
        if i and tokens[i - 1].kind == "op" and tokens[i - 1].value in (".", ":"):
            continue  # x.hl.bind or "function foo.create_bind" are not calls of it
        if i and tokens[i - 1].kind == "name" and tokens[i - 1].value == "function":
            continue  # its definition
        if all(tokens[i + k].value == p for k, p in enumerate(pattern)):
            after = i + len(pattern)
            if after < len(tokens) and tokens[after].value == "(":
                args, _ = split_args(tokens, after)
                found.append((tokens[i].line, args))
    return found


# Values


def literal(item: list[Token]):
    """A plain string, or a table of plain strings (as a list); None for anything else."""
    if len(item) == 1 and item[0].kind == "str":
        return item[0].value
    if item and item[0].value == "{" and item[-1].value == "}":
        values, _ = split_args(item, 0)
        strings = [literal(v) for v in values]
        if all(isinstance(s, str) for s in strings):
            return strings
    return None


def table_fields(tokens: list[Token], open_index: int) -> dict[str, tuple[object, int, list[Token]]]:
    """The `name = value` fields of a table: name -> (literal value or None, line, tokens)."""
    fields = {}
    items, _ = split_args(tokens, open_index)
    for item in items:
        if len(item) >= 3 and item[0].kind == "name" and item[1].value == "=":
            fields[item[0].value] = (literal(item[2:]), item[0].line, item[2:])
    return fields


def read_vars(path: Path) -> dict[str, tuple[object, int]]:
    """The fields of the table a variables file returns: name -> (value, line).

    Values that are not plain strings (numbers, "a" .. b) are None.
    """
    try:
        tokens, _ = tokenize(path.read_text())
    except OSError:
        return {}
    for i, t in enumerate(tokens[:-1]):
        if t.kind == "name" and t.value == "return" and tokens[i + 1].value == "{":
            return {k: (v, line) for k, (v, line, _) in table_fields(tokens, i + 1).items()}
    return {}


def source_text(text: str, item: list[Token]) -> str:
    return " ".join(text[item[0].start:item[-1].end].split()) if item else ""


def var_ref(item: list[Token]) -> str | None:
    """"kbX" for `vars.kbX`."""
    if len(item) == 3 and item[0].value == "vars" and item[1].value == "." and item[2].kind == "name":
        return item[2].value
    return None


def shorten(text: str, width: int = 60) -> str:
    return text if len(text) <= width else text[: width - 1] + "…"


def describe_action(text: str, item: list[Token], resolve) -> str:
    """A short name for a bind's Lua action."""
    if not item:
        return ""
    first = item[0].value
    if first == "function":
        commands = [t.value for k, t in enumerate(item[2:], 2)
                    if t.kind == "str" and item[k - 2].value == "exec_cmd"]
        if commands:
            return shorten("lua: " + " / ".join(commands))
        return "lua function"
    source = source_text(text, item)
    m = re.fullmatch(r"hl\.dsp\.exec_cmd\((.*)\)", source)
    if m:
        args, _ = split_args(item, item.index(next(t for t in item if t.value == "(")))
        command = literal(args[0]) if args else None
        if command is None and args and var_ref(args[0]):
            command = resolve(args[0][2].value)
        return shorten(f"exec {command if isinstance(command, str) else m.group(1).strip()}")
    m = re.fullmatch(r'hl\.dsp\.global\("([^"]*)"\)', source)
    if m:
        return m.group(1)
    m = re.fullmatch(r'fn\.toggle\("([^"]*)"\)', source)
    if m:
        return f"toggle special:{m.group(1)}"
    m = re.fullmatch(r'fn\.wsaction\("(\w+)", "(\w*)", \w+\)', source)
    if m:
        return f"{m.group(1)} {'group' if m.group(2) else 'workspace'} n"
    return shorten(source.removeprefix("hl.dsp."))


def humanize(var: str) -> str:
    words = re.sub(r"(?<!^)(?=[A-Z])", " ", var.removeprefix("kb")).lower()
    return words[:1].upper() + words[1:]


def combo_key(combo: str) -> tuple:
    """Two combos Hyprland treats the same give the same key."""
    mods, key = set(), ""
    for part in (p.strip() for p in combo.split("+")):
        if part.upper() in MODIFIERS:
            mods.add(MODIFIERS[part.upper()])
        elif part:
            key = part.lower()
    return tuple(sorted(mods)), key


def flag_tables(tokens: list[Token]) -> dict[str, list[str]]:
    """`local locked = { locked = true }` -> {"locked": ["locked"]}."""
    tables = {}
    for i in range(len(tokens) - 3):
        if (tokens[i].value == "local" and tokens[i + 1].kind == "name"
                and tokens[i + 2].value == "=" and tokens[i + 3].value == "{"):
            fields = table_fields(tokens, i + 3)
            if fields and all(len(v[2]) == 1 and v[2][0].value == "true" for v in fields.values()):
                tables[tokens[i + 1].value] = [k for k in fields if k in FLAGS]
    return tables


def loop_values(tokens: list[Token]) -> dict[str, list[str]]:
    """`for _, dir in ipairs({ "left", "right" }) do` -> {"dir": ["left", "right"]}."""
    loops = {}
    for i in range(len(tokens) - 6):
        if tokens[i].value == "for" and tokens[i + 3].kind == "name" and tokens[i + 4].value == "in" \
                and tokens[i + 5].value == "ipairs" and tokens[i + 6].value == "(":
            args, _ = split_args(tokens, i + 6)
            values = literal(args[0]) if args else None
            if isinstance(values, list):
                loops[tokens[i + 3].value] = values
    return loops


def section_of(comments: dict[int, str], line: int) -> str:
    """The nearest short heading comment above a line ("-- Window actions")."""
    for n in range(line - 1, 0, -1):
        comment = comments.get(n)
        if comment and len(comment) <= 40 and not comment.endswith((".", ":")):
            return comment
    return ""


# Binds


def caelestia_binds(defaults: dict, overrides: dict, vars_path: Path, binds_path: Path,
                    user_vars: Path) -> list[Bind]:
    """Caelestia's binds, in keybinds.lua's order, with the overrides applied."""
    try:
        text = binds_path.read_text()
    except OSError:
        return []
    tokens, comments = tokenize(text)
    flags_by_name = flag_tables(tokens)
    loops = loop_values(tokens)

    def value(name: str):
        return (overrides.get(name) or defaults.get(name) or (None, 0))[0]

    binds: list[Bind] = []
    used: set[str] = set()
    for line, args in calls(tokens, "create_bind"):
        if len(args) < 2:
            continue
        keys, action = args[0], args[1]
        flags = []
        if len(args) > 2 and len(args[2]) == 1:
            flags = flags_by_name.get(args[2][0].value, [])
        section = section_of(comments, line)
        what = describe_action(text, action, value)

        def add(combo: str, label: str, var: str = "", ws: bool = False, action: str = "") -> None:
            what_here = action or what
            if var and var in overrides:
                new, new_line = overrides[var]
                old = defaults.get(var, (None, 0))[0]
                olds = old if isinstance(old, list) else [old] if isinstance(old, str) else []
                news = new if isinstance(new, list) else [new] if isinstance(new, str) else []
                news = [c for c in news if c.strip()]
                if combo != (olds[0] if olds else ""):
                    return  # the override's combos are all added with the first default one
                for c in news or [""]:
                    binds.append(Bind(f"{c} + {WS_KEYS}" if ws and c else c, label, what_here,
                                      "override", user_vars, new_line, var,
                                      " · ".join(f"{o} + {WS_KEYS}" if ws else o for o in olds),
                                      section, flags))
                return
            path, at = (vars_path, defaults[var][1]) if var in defaults else (binds_path, line)
            binds.append(Bind(f"{combo} + {WS_KEYS}" if ws else combo, label, what_here, "default",
                              path, at, var, "", section, flags))

        def add_key(item: list[Token], sibling: str = "") -> None:
            var = var_ref(item)
            if var:
                used.add(var)
                default = defaults.get(var, (None, 0))[0]
                combos = default if isinstance(default, list) else [default] if isinstance(default, str) else []
                combos = [c for c in combos if c.strip()]
                if var in overrides and not combos:
                    combos = [""]  # a variable with no default, set in hypr-vars.lua
                for combo in combos:
                    add(combo, LABELS.get(var, humanize(var)), var)
                return
            plain = literal(item)
            if isinstance(plain, str):
                add(plain, sibling or LITERAL_LABELS.get(plain, what))
            elif isinstance(plain, list):
                for c in plain:
                    add(c, sibling or LITERAL_LABELS.get(c, what))
            elif item and item[0].value == "{":
                subs = split_args(item, 0)[0]
                # literal keys next to a variable do the same thing: named after it
                named = next((var_ref(s) for s in subs if var_ref(s)), None)
                for sub in subs:
                    add_key(sub, LABELS.get(named, humanize(named)) if named else "")
            elif len(item) >= 4 and item[0].value == "extend_keybind" and item[1].value == "(":
                inner = split_args(item, 1)[0]
                var = var_ref(inner[0]) if inner else None
                if var:
                    used.add(var)
                    mod = defaults.get(var, (None, 0))[0]
                    if isinstance(mod, str) and mod.strip() or var in overrides:
                        add(mod if isinstance(mod, str) else "", LABELS.get(var, humanize(var)), var, ws=True)
            elif len(item) == 3 and item[0].kind == "str" and item[1].value == ".." \
                    and item[2].value in loops:
                loop_var = item[2].value
                for v in loops[loop_var]:
                    template = LOOP_LABELS.get(what)
                    label = template.format(v) if template else f"{what} {v}"
                    add(item[0].value + v, label, action=re.sub(rf"\b{loop_var}\b", f'"{v}"', what))

        add_key(keys)

    # Overrides of variables keybinds.lua does not use (a typo, or a removed bind)
    for var, (new, line) in overrides.items():
        if var.startswith("kb") and var not in used:
            combos = new if isinstance(new, list) else [new] if isinstance(new, str) else [""]
            for c in combos:
                binds.append(Bind(c, f"{humanize(var)} (not used by Caelestia)", "", "override",
                                  user_vars, line, var, "", "Unknown variables"))
    return binds


def user_binds(path: Path) -> list[Bind]:
    """The hl.bind calls of hypr-user.lua."""
    try:
        text = path.read_text()
    except OSError:
        return []
    tokens, _ = tokenize(text)
    binds = []
    for line, args in calls(tokens, "hl.bind"):
        if len(args) < 2:
            continue
        combo = literal(args[0])
        if not isinstance(combo, str):
            combo = source_text(text, args[0])
        what = describe_action(text, args[1], lambda _: None)
        label, flags = "", []
        if len(args) > 2 and args[2] and args[2][0].value == "{":
            options = table_fields(args[2], 0)
            description = options.get("description", (None,))[0]
            label = description if isinstance(description, str) else ""
            flags = [k for k, v in options.items() if k in FLAGS and source_text(text, v[2]) == "true"]
        if not label and "release" in flags:
            # the release half of a press / release pair (F8 for Nova)
            pressed = next((b for b in reversed(binds) if combo_key(b.combo) == combo_key(combo)), None)
            label = f"{pressed.label} (released)" if pressed else ""
        binds.append(Bind(combo, label or what, what, "user", path, line,
                          section="Your binds", flags=flags))
    return binds


def load(dotfiles: Path) -> list[Bind]:
    """Every bind: Caelestia's (with the overrides), then the user's."""
    user_vars = dotfiles / "config/caelestia/hypr-vars.lua"
    defaults = read_vars(DEFAULT_VARS)
    overrides = read_vars(user_vars)
    binds = caelestia_binds(defaults, overrides, DEFAULT_VARS, DEFAULT_BINDS, user_vars)
    binds += user_binds(dotfiles / "config/caelestia/hypr-user.lua")

    # The same combo bound twice to the same action is harmless (Caelestia binds
    # SUPER + mouse:273 both literally and as kbResizeWindow): shown once
    seen, unique = set(), []
    for b in binds:
        sig = (combo_key(b.combo), b.action, "release" in b.flags) if b.combo else id(b)
        if sig not in seen:
            seen.add(sig)
            unique.append(b)

    # Several actions on one combo all run on the same key press
    actions: dict[tuple, set[str]] = {}
    for b in unique:
        if b.combo:
            actions.setdefault((combo_key(b.combo), "release" in b.flags), set()).add(b.action)
    for b in unique:
        b.conflict = bool(b.combo) and len(actions[(combo_key(b.combo), "release" in b.flags)]) > 1
    return unique


if __name__ == "__main__":
    import os
    import sys

    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        os.environ.get("NIXCFG_DOTFILES", Path.home() / "dotfiles"))
    for b in load(root):
        mark = "!" if b.conflict else " "
        combo = b.combo or f"(removed, was {b.default})"
        extra = f"  was {b.default}" if b.source == "override" and b.combo else ""
        print(f"{mark} {combo:<36} {b.label:<38} {b.action:<40} {b.source}{extra}"
              f"  [{b.path.name}:{b.line}] {' '.join(b.flags)}")
