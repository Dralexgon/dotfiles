"""Read and edit the environment.systemPackages lists of a module file.

Module files stay Nix code: a package is one line of a list, and it is
disabled by commenting that line out, the same way you would by hand:

    environment.systemPackages = with pkgs; [
      kitty # Terminal          <- enabled
      # lutris                  <- disabled
      # Ricing                  <- a comment (capitalized or several words)
      (python3.withPackages (ps: [ ps.requests ]))   <- read-only expression
    ];
"""

import re
from dataclasses import dataclass, field

DECLARATION = re.compile(r"environment\.systemPackages\s*=")
# An item that is just an attribute path, with an optional trailing comment.
ENABLED = re.compile(r"^(\s*)([A-Za-z_][\w'.-]*)\s*(#.*)?$")
# A commented-out attribute path: lowercase, one word, "#" then at most one
# space (deeper indentation after "#" is the inside of a commented block).
DISABLED = re.compile(r"^(\s*)# ?([a-z0-9_][\w'.-]*)\s*(#.*)?$")


@dataclass
class Entry:
    line: int  # 0-based line number in the file
    name: str  # attribute path, or the first line of an expression
    enabled: bool
    editable: bool  # False for expressions (overrides, withPackages...)
    comment: str = ""


@dataclass
class Block:
    """One environment.systemPackages list."""

    close: int  # line of the closing "]"
    indent: str  # indentation of its items
    entries: list[Entry] = field(default_factory=list)


def code_part(line: str) -> str:
    """The line without its comment (a "#" outside of a string)."""
    in_string = False
    for i, char in enumerate(line):
        if char == '"':
            in_string = not in_string
        elif char == "#" and not in_string:
            return line[:i]
    return line


def depth_change(code: str) -> int:
    return sum(code.count(c) for c in "[({") - sum(code.count(c) for c in "])}")


def parse(text: str) -> list[Block]:
    lines = text.splitlines()
    blocks = []
    i = 0
    while i < len(lines):
        code = code_part(lines[i])
        match = DECLARATION.search(code)
        if not match:
            i += 1
            continue
        # The list starts at the first "[" after "=", maybe on a later line.
        rest = code[match.end():]
        while "[" not in rest and i + 1 < len(lines):
            i += 1
            rest = code_part(lines[i])
        if "[" not in rest:
            break
        depth = 1 + depth_change(rest[rest.index("[") + 1:])
        if depth <= 0:  # "[ ]" on one line: nothing to list
            i += 1
            continue
        items: list[tuple[int, str]] = []  # (line, kind) at depth 1
        i += 1
        while i < len(lines) and depth > 0:
            line = lines[i]
            code = code_part(line).strip()
            if depth == 1 and code.startswith("]"):
                break
            if depth == 1:
                items.append((i, "comment" if not code else "code"))
            depth += depth_change(code)
            i += 1
        if depth > 0 and i >= len(lines):
            break
        # A list closed at the end of an item line ("foo ]") has no line to
        # insert before: close = -1 means packages can't be added to it.
        closed_inline = depth == 0

        code_lines = [n for n, kind in items if kind == "code"]
        reference = code_lines[0] if code_lines else (items[0][0] if items else i)
        indent = re.match(r"\s*", lines[reference]).group()
        if not items and not closed_inline:
            indent = re.match(r"\s*", lines[i]).group() + "  "
        block = Block(close=-1 if closed_inline else i, indent=indent)
        for n, kind in items:
            line = lines[n]
            if kind == "code":
                if m := ENABLED.match(line):
                    block.entries.append(Entry(n, m[2], True, True, m[3] or ""))
                else:
                    block.entries.append(Entry(n, line.strip(), True, False))
            elif (m := DISABLED.match(line)) and m[1] == indent:
                block.entries.append(Entry(n, m[2], False, True, m[3] or ""))
        blocks.append(block)
        i += 1
    return blocks


def entries(text: str) -> list[Entry]:
    return [e for block in parse(text) for e in block.entries]


def _replace_line(text: str, n: int, new: str | None) -> str:
    lines = text.splitlines(keepends=True)
    if new is None:
        del lines[n]
    else:
        ending = "\n" if lines[n].endswith("\n") else ""
        lines[n] = new + ending
    return "".join(lines)


def toggle(text: str, entry: Entry) -> str:
    line = text.splitlines()[entry.line]
    indent = re.match(r"\s*", line).group()
    body = line[len(indent):]
    if entry.enabled:
        return _replace_line(text, entry.line, f"{indent}# {body}")
    return _replace_line(text, entry.line, indent + re.sub(r"^# ?", "", body))


def remove(text: str, entry: Entry) -> str:
    return _replace_line(text, entry.line, None)


def add(text: str, attr: str) -> tuple[str, int] | None:
    """Add a package line at the end of the first list.

    Returns the new text and the line of the package, or None when the
    module has no environment.systemPackages list.
    """
    blocks = [b for b in parse(text) if b.close >= 0]
    if not blocks:
        return None
    block = blocks[0]
    lines = text.splitlines(keepends=True)
    lines.insert(block.close, f"{block.indent}{attr}\n")
    return "".join(lines), block.close
