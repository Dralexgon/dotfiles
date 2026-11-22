#!/usr/bin/env python3
"""Check that the Rust nixcfg reads and edits the dotfiles exactly like the
legacy Python one (legacy/).

Both compute the same report: the hosts, modules and their state, every
module's packages, the Keybinds tab, and the text of every edit nixcfg can
make (toggling each module, desktop, submodule and package, removing and
adding packages). The Rust one prints it with `nixcfg --dump`; this script
computes it with the Python functions and diffs the two. Nothing is written.

    nix develop ~/dotfiles#nixcfg -c python tools/nixcfg/compare.py [--rust BIN] [--dotfiles DIR]
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def python_report() -> dict:
    sys.path.insert(0, str(HERE / "legacy"))
    import hostfile
    import keybinds
    import modfile
    import nixcfg as py

    def read(path: Path) -> str:
        try:
            return path.read_text()
        except OSError:
            return ""

    def toggled(items: list[str], item: str) -> list[str]:
        return [n for n in items if n != item] if item in items else [*items, item]

    def attempt(f):
        try:
            return f()
        except ValueError:
            return None

    hosts, modules = py.list_hosts(), py.list_modules()
    out = {"hosts": hosts, "modules": modules}
    all_names = [py.CORE]
    keys = ("state", "names", "default_session", "desktops", "add_packages_block",
            "import_edits", "desktop_edits", "default_session_edits")
    for key in keys:
        out[key] = {}
    known = [py.desktop_name(n) for n in py.list_desktops()]
    for host in hosts:
        enabled = py.load_state(host)["modules"]
        shown = sorted({py.CORE, py.host_module(host), *modules, *enabled}, key=py.display_key)
        all_names += [n for n in shown if n not in all_names]
        path = py.host_path(host)
        text = path.read_text()
        out["state"][host] = enabled
        out["names"][host] = shown
        out["default_session"][host] = hostfile.default_session(text)
        out["desktops"][host] = hostfile.desktops(text)
        out["add_packages_block"][host] = hostfile.add_packages_block(text)

        own = [n for n in enabled if not py.group_core(n)]
        out["import_edits"][host] = {
            name: attempt(lambda name=name: hostfile.update(
                text, path.parent, py.MODULES_DIR, toggled(own, name),
                lambda n: py.module_path(n).exists(), py.display_key))
            for name in shown if not py.group_core(name) and not py.is_pinned(name)
        }
        on = hostfile.desktops(text)
        edits = {d: hostfile.update_desktops(text, toggled(on, d), known) for d in known}
        edits["(none)"] = hostfile.update_desktops(text, [], known)
        out["desktop_edits"][host] = edits
        out["default_session_edits"][host] = {
            d: attempt(lambda d=d: hostfile.set_default_session(text, d)) for d in known}

    out["module_info"], out["entries"], out["package_edits"] = {}, {}, {}
    for name in all_names:
        out["module_info"][name] = {
            "display_key": list(py.display_key(name)),
            "group_core": py.group_core(name),
            "is_group": py.is_group(name),
            "is_pinned": py.is_pinned(name),
        }
        text = read(py.module_path(name))
        entries = modfile.entries(text)
        out["entries"][name] = [[e.line, e.name, e.enabled, e.editable, e.comment] for e in entries]
        edits = {}
        for e in entries:
            if e.editable:
                edits[f"toggle:{e.line}"] = modfile.toggle(text, e)
                edits[f"remove:{e.line}"] = modfile.remove(text, e)
        added = modfile.add(text, "nixcfg-test", "  # A  test  package ")
        edits["add"] = list(added) if added else None
        added = modfile.add(text, "nixcfg-test", "")
        edits["add-bare"] = list(added) if added else None
        out["package_edits"][name] = edits

    out["core_edits"] = {}
    for core in modules:
        if not py.is_group(core) or core == py.DESKTOP_CORE:
            continue
        subs = py.group_subs(core)
        out["core_edits"][core] = {
            sub: attempt(lambda sub=sub: py.core_text(core, toggled(subs, sub)))
            for sub in modules if py.group_core(sub) == core
        }

    out["keybinds"] = [{
        "combo": b.combo, "label": b.label, "action": b.action, "source": b.source,
        "path": str(b.path), "line": b.line, "var": b.var, "default": b.default,
        "section": b.section, "flags": b.flags, "conflict": b.conflict,
    } for b in keybinds.load(py.DOTFILES)]
    return out


def differences(a, b, path="") -> list[str]:
    if isinstance(a, dict) and isinstance(b, dict):
        found = []
        for key in sorted(set(a) | set(b)):
            if key not in a:
                found.append(f"{path}/{key}: only in Rust")
            elif key not in b:
                found.append(f"{path}/{key}: only in Python")
            else:
                found += differences(a[key], b[key], f"{path}/{key}")
        return found
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [f"{path}: {len(a)} items in Python, {len(b)} in Rust"]
        return [d for i, (x, y) in enumerate(zip(a, b)) for d in differences(x, y, f"{path}[{i}]")]
    if a != b:
        return [f"{path}:\n    python: {a!r:.300}\n    rust:   {b!r:.300}"]
    return []


def count(report) -> int:
    if isinstance(report, dict):
        return sum(count(v) for v in report.values())
    if isinstance(report, list):
        return sum(count(v) for v in report)
    return 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    default = next((p for p in (HERE / "target/release/nixcfg", HERE / "target/debug/nixcfg") if p.exists()),
                   shutil.which("nixcfg"))
    parser.add_argument("--rust", default=default, help="the Rust nixcfg binary")
    parser.add_argument("--dotfiles", help="the dotfiles to read (default: NIXCFG_DOTFILES or ~/dotfiles)")
    args = parser.parse_args()
    if args.dotfiles:
        os.environ["NIXCFG_DOTFILES"] = str(Path(args.dotfiles).resolve())

    rust = json.loads(subprocess.run([str(args.rust), "--dump"], check=True,
                                     capture_output=True, text=True).stdout)
    python = python_report()
    diffs = differences(python, rust)
    for d in diffs[:40]:
        print(d)
    if len(diffs) > 40:
        print(f"... and {len(diffs) - 40} more")
    print(f"{count(python)} values compared, {len(diffs)} difference(s)")
    sys.exit(1 if diffs else 0)


if __name__ == "__main__":
    main()
