"""Read and edit the module imports of a host's configuration.nix.

A host turns a module on or off the way you would by hand: by commenting
its line in `imports` out.

    imports = [
      ./hardware-configuration.nix
      ./../../core.nix

      ./../../modules/gnome.nix             <- enabled
      # ./../../modules/jetbrains.nix       <- disabled

      # ./../../modules/epita/core.nix      <- group off...
      # ./../../modules/epita/c.nix         <- ...c is still chosen
      # # ./../../modules/epita/java.nix    <- ...java is not
    ];

A folder with a core.nix is a group, and its submodules are commented one
level deeper than their core: turning the group off comments the whole
block out, like an editor would, so each submodule keeps its own choice for
when the group is turned back on.

The host's own packages are a plain environment.systemPackages list in the
same file, edited with modfile.
"""

import re
from collections.abc import Callable
from dataclasses import dataclass

# A module import: "# " repeated (commenting depth), a path ending in
# modules/<name>.nix, and an optional trailing comment.
IMPORT = re.compile(
    r"^(?P<indent>\s*)(?P<hashes>(?:#\s*)*)"
    r"(?P<path>(?:\./)?(?:\.\./)+modules/(?P<name>[\w/-]+)\.nix)"
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
    name: str
    depth: int  # how many times the line is commented out
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


def parse(text: str) -> list[Import]:
    lines = text.splitlines()
    block = imports_block(lines)
    if not block:
        return []
    found = []
    for n in range(block[0] + 1, block[1]):
        if m := IMPORT.match(lines[n]):
            found.append(Import(n, m["name"], m["hashes"].count("#"), m["indent"],
                                m["path"], m["comment"] or ""))
    return found


def enabled(text: str, core_of: Callable[[str], str | None]) -> list[str]:
    """The modules chosen on this host, in file order.

    A submodule is chosen when it is commented as deep as its core (so the
    choice is kept while the group is off).
    """
    found = parse(text)
    depths = {i.name: i.depth for i in found}
    chosen = []
    for i in found:
        core = core_of(i.name)
        limit = 0 if core is None else depths.get(core, 1)
        if i.depth <= limit and i.name not in chosen:
            chosen.append(i.name)
    return chosen


def module_line(indent: str, depth: int, path: str, comment: str = "") -> str:
    return f"{indent}{'# ' * depth}{path}{comment}"


def update(text: str, chosen: list[str], core_of: Callable[[str], str | None],
           exists: Callable[[str], bool], sort_key: Callable[[str], tuple]) -> str:
    """Comment and uncomment import lines so that `chosen` are enabled.

    Existing lines keep their place, path and comment; a module without a
    line gets one, next to its group or at the end of the list. Commented
    lines of modules whose file is gone are dropped.
    """
    lines = text.splitlines()
    block = imports_block(lines)
    if not block:
        raise ValueError("no `imports = [` list found")

    def depth(name: str) -> int:
        core = core_of(name)
        own = 0 if name in chosen else 1
        if core is None:
            return own
        return (0 if core in chosen else 1) + own

    found = parse(text)
    have = {i.name for i in found}
    drop = set()
    for i in found:
        if i.name not in chosen and not exists(i.name):
            drop.add(i.line)
        elif i.depth != depth(i.name):
            lines[i.line] = module_line(i.indent, depth(i.name), i.path, i.comment)

    # Modules that need a line: the chosen ones, and the core of a group
    # with chosen submodules (commented out when the group is off).
    needed = [n for n in chosen if n not in have]
    needed += [core_of(n) for n in chosen
               if core_of(n) and core_of(n) not in have and core_of(n) not in needed]
    indent = found[0].indent if found else re.match(r"\s*", lines[block[0]]).group() + "  "
    prefix = path_prefix(found)
    inserts: dict[int, list[str]] = {}
    for name in sorted(needed, key=sort_key):
        new = module_line(indent, depth(name), f"{prefix}{name}.nix")
        # After the last line of the same group, or at the end of the list.
        folder = name.rpartition("/")[0]
        same = [i.line for i in found if folder and i.name.rpartition("/")[0] == folder]
        at = max(same) + 1 if same else block[1]
        inserts.setdefault(at, []).append(new)

    out = []
    for n, line in enumerate(lines):
        out.extend(inserts.get(n, []))
        if n not in drop:
            out.append(line)
    out.extend(inserts.get(len(lines), []))
    return "\n".join(out) + "\n"


def path_prefix(found: list[Import]) -> str:
    """How this file writes paths to nixos/modules ("./../../modules/")."""
    if found:
        return found[0].path[: -len(f"{found[0].name}.nix")]
    return "./../../modules/"


def add_packages_block(text: str) -> str:
    """Add an empty environment.systemPackages list before the last "}"."""
    lines = text.rstrip("\n").splitlines()
    for n in range(len(lines) - 1, -1, -1):
        if lines[n].strip() == "}":
            lines[n:n] = PACKAGES_BLOCK.rstrip("\n").splitlines()
            break
    return "\n".join(lines) + "\n"
