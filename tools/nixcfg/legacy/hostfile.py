"""Read and edit the module imports of a Nix file.

A module is turned on or off the way you would by hand: by commenting its
line in `imports` out. Hosts import top-level modules and group cores:

    # nixos/hosts/<host>/configuration.nix
    imports = [
      ./hardware-configuration.nix
      ./../../core.nix

      ./../../modules/flatpak.nix           <- enabled
      # ./../../modules/jetbrains.nix       <- disabled
      ./../../modules/epita/core.nix        <- the epita group
    ];

and a group's core.nix (a folder with a core.nix is a group) imports its
submodules, for every host that turns the group on:

    # nixos/modules/epita/core.nix
    imports = [
      ./c.nix
      # ./java.nix
    ];

The host's own packages are a plain environment.systemPackages list in its
configuration.nix, edited with modfile.
"""

import os
import re
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

# An import line: "#"s (commented out), a relative path to a .nix file, and
# an optional trailing comment.
IMPORT = re.compile(
    r"^(?P<indent>\s*)(?P<hashes>(?:#\s*)*)"
    r"(?P<path>\.{1,2}/[\w./-]*\.nix)"
    r"(?P<comment>\s+#.*)?\s*$"
)
IMPORTS = re.compile(r"^\s*imports\s*=\s*\[\s*$")

PACKAGES_BLOCK = """
  # Packages for this host only
  environment.systemPackages = with pkgs; [
  ];
"""


@dataclass
class Import:
    line: int  # 0-based
    name: str  # module name: path under nixos/modules without .nix
    enabled: bool
    indent: str
    path: str
    comment: str


def imports_block(lines: list[str]) -> tuple[int, int] | None:
    """The lines of "imports = [" and of its closing "]"."""
    for start, line in enumerate(lines):
        if IMPORTS.match(line):
            for end in range(start + 1, len(lines)):
                if lines[end].strip().startswith("]"):
                    return start, end
    return None


def module_name(path: str, here: Path, modules_dir: Path) -> str | None:
    """The module a path in a file of folder `here` points to, if any."""
    target = Path(os.path.normpath(here / path))
    try:
        return target.relative_to(modules_dir).with_suffix("").as_posix()
    except ValueError:
        return None


def parse(text: str, here: Path, modules_dir: Path) -> list[Import]:
    """The module imports of a file in folder `here` (others are ignored)."""
    lines = text.splitlines()
    block = imports_block(lines)
    if not block:
        return []
    found = []
    for n in range(block[0] + 1, block[1]):
        if (m := IMPORT.match(lines[n])) and (
                name := module_name(m["path"], here, modules_dir)):
            found.append(Import(n, name, not m["hashes"], m["indent"],
                                m["path"], m["comment"] or ""))
    return found


def enabled(text: str, here: Path, modules_dir: Path) -> list[str]:
    """The modules imported (not commented out), in file order."""
    return [i.name for i in parse(text, here, modules_dir) if i.enabled]


def line_for(indent: str, on: bool, path: str, comment: str = "") -> str:
    return f"{indent}{'' if on else '# '}{path}{comment}"


def update(text: str, here: Path, modules_dir: Path, chosen: list[str],
           exists: Callable[[str], bool], sort_key: Callable[[str], tuple]) -> str:
    """Comment and uncomment import lines so that exactly `chosen` are on.

    Existing lines keep their place, path and comment; a chosen module
    without a line gets one, next to the modules of its folder or at the end
    of the list. Commented lines of modules whose file is gone are dropped.
    """
    if not text.endswith("\n"):
        text += "\n"
    lines = text.splitlines()
    block = imports_block(lines)
    if not block:
        text = add_imports_block(text)
        lines = text.splitlines()
        block = imports_block(lines)
        if not block:
            raise ValueError("no `imports = [` list, and no place to add one")

    found = parse(text, here, modules_dir)
    have = {i.name for i in found}
    drop = set()
    for i in found:
        on = i.name in chosen
        if not on and not exists(i.name):
            drop.add(i.line)
        elif on != i.enabled:
            # Remove every "#" level, or comment the line once.
            lines[i.line] = line_for(i.indent, on, i.path, i.comment)

    indent = found[0].indent if found else re.match(r"\s*", lines[block[0]]).group() + "  "
    inserts: dict[int, list[str]] = {}
    for name in sorted((n for n in chosen if n not in have), key=sort_key):
        path = os.path.relpath(modules_dir / f"{name}.nix", here)
        path = path if path.startswith("../") else f"./{path}"
        if found and found[0].path.startswith("./../"):
            path = f"./{path}"  # the "./../../modules/" style of host files
        folder = name.rpartition("/")[0]
        same = [i.line for i in found if i.name.rpartition("/")[0] == folder]
        at = max(same) + 1 if same else block[1]
        inserts.setdefault(at, []).append(line_for(indent, True, path))

    out = []
    for n, line in enumerate(lines):
        out.extend(inserts.get(n, []))
        if n not in drop:
            out.append(line)
    return "\n".join(out) + "\n"


def add_imports_block(text: str) -> str:
    """Add an empty imports list at the top of the module's attribute set."""
    lines = text.splitlines()
    for n, line in enumerate(lines):
        if line.strip() == "{" or (line.strip().endswith(": {") and n == 0):
            lines[n + 1:n + 1] = ["  imports = [", "  ];", ""]
            break
    return "\n".join(lines) + "\n"


def add_packages_block(text: str) -> str:
    """Add an empty environment.systemPackages list before the last "}"."""
    lines = text.rstrip("\n").splitlines()
    for n in range(len(lines) - 1, -1, -1):
        if lines[n].strip() == "}":
            lines[n:n] = PACKAGES_BLOCK.rstrip("\n").splitlines()
            break
    return "\n".join(lines) + "\n"


# Desktops (nixos/modules/desktop) are chosen per host by a list of names,
# with a commented line for each one that is off, and an optional default:
#
#     desktop.enabled = [
#       "caelestia"
#       # "kde"
#     ];
#     desktop.defaultSession = "caelestia";
DESKTOPS = re.compile(r"^(?P<indent>\s*)desktop\.enabled\s*=\s*\[\s*$")
DESKTOP = re.compile(
    r'^(?P<indent>\s*)(?P<hashes>(?:#\s*)*)"(?P<name>[\w-]+)"'
    r"(?P<comment>\s+#.*)?\s*$"
)
DEFAULT_SESSION = re.compile(
    r'^(?P<head>\s*desktop\.defaultSession\s*=\s*)(?:"(?P<name>[\w-]*)"|null)(?P<tail>\s*;.*)$'
)


@dataclass
class Desktop:
    line: int  # 0-based
    name: str
    enabled: bool
    indent: str
    comment: str


def desktops_block(lines: list[str]) -> tuple[int, int] | None:
    """The lines of "desktop.enabled = [" and of its closing "]"."""
    for start, line in enumerate(lines):
        if DESKTOPS.match(line):
            for end in range(start + 1, len(lines)):
                if lines[end].strip().startswith("]"):
                    return start, end
    return None


def parse_desktops(text: str) -> list[Desktop]:
    lines = text.splitlines()
    block = desktops_block(lines)
    if not block:
        return []
    return [Desktop(n, m["name"], not m["hashes"], m["indent"], m["comment"] or "")
            for n in range(block[0] + 1, block[1]) if (m := DESKTOP.match(lines[n]))]


def desktops(text: str) -> list[str]:
    """The desktops the host turns on, in file order."""
    return [d.name for d in parse_desktops(text) if d.enabled]


def default_session(text: str) -> str | None:
    """desktop.defaultSession if set, else the first desktop (Nix's default)."""
    for line in text.splitlines():
        if m := DEFAULT_SESSION.match(line):
            return m["name"]
    on = desktops(text)
    return on[0] if on else None


def update_desktops(text: str, chosen: list[str], known: list[str]) -> str:
    """Comment and uncomment the lines of desktop.enabled so that exactly
    `chosen` are on. A desktop of `known` without a line gets one (commented
    when off), and the list is added if missing. If the default session is
    turned off, it moves to the first desktop left on (or null)."""
    if not text.endswith("\n"):
        text += "\n"
    lines = text.splitlines()
    if not desktops_block(lines):
        if not chosen:
            return text
        lines = add_desktops_block(text).splitlines()
    start, end = desktops_block(lines)
    found = parse_desktops("\n".join(lines))
    for d in found:
        on = d.name in chosen
        if on != d.enabled:
            lines[d.line] = f'{d.indent}{"" if on else "# "}"{d.name}"{d.comment}'
    have = {d.name for d in found}
    indent = found[0].indent if found else DESKTOPS.match(lines[start])["indent"] + "  "
    missing = [f'{indent}{"" if n in chosen else "# "}"{n}"'
               for n in sorted(set(known) - have)]
    lines[end:end] = missing

    for n, line in enumerate(lines):
        if (m := DEFAULT_SESSION.match(line)) and m["name"] not in chosen:
            on = desktops("\n".join(lines))
            value = f'"{on[0]}"' if on else "null"
            lines[n] = f"{m['head']}{value}{m['tail']}"
    return "\n".join(lines) + "\n"


def set_default_session(text: str, name: str) -> str:
    """Set desktop.defaultSession, adding the line after the list if needed."""
    lines = text.splitlines()
    for n, line in enumerate(lines):
        if m := DEFAULT_SESSION.match(line):
            lines[n] = f'{m["head"]}"{name}"{m["tail"]}'
            return "\n".join(lines) + "\n"
    block = desktops_block(lines)
    if not block:
        raise ValueError("no `desktop.enabled = [` list")
    indent = DESKTOPS.match(lines[block[0]])["indent"]
    lines.insert(block[1] + 1, f'{indent}desktop.defaultSession = "{name}";')
    return "\n".join(lines) + "\n"


def add_desktops_block(text: str) -> str:
    """Add an empty desktop.enabled list after the imports (or before the last "}")."""
    lines = text.rstrip("\n").splitlines()
    block = imports_block(lines)
    new = ["", "  # Desktops: all selectable on the login screen (or use `nixcfg`)",
           "  desktop.enabled = [", "  ];"]
    if block:
        at = block[1] + 1
    else:
        at = max(n for n, line in enumerate(lines) if line.strip() == "}")
    lines[at:at] = new
    return "\n".join(lines) + "\n"
