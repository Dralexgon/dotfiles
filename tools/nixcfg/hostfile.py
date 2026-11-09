"""Read and edit the module imports of a Nix file.

A module is turned on or off the way you would by hand: by commenting its
line in `imports` out. Hosts import top-level modules and group cores:

    # nixos/hosts/<host>/configuration.nix
    imports = [
      ./hardware-configuration.nix
      ./../../core.nix

      ./../../modules/gnome.nix             <- enabled
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
