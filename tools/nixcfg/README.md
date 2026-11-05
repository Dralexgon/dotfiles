# nixcfg

A terminal UI to turn modules on and off and to enable, disable, add or
remove packages (in modules or per host), for each NixOS host of this flake.

```bash
nix run ~/dotfiles#nixcfg
```

It opens on the host matching this machine's hostname (or the first host
found), with two tabs: **Modules** and **Packages**.

## How it works

nixcfg never edits Nix code. Each host has a `state.json` next to its
`configuration.nix`:

```json
{
  "modules": [
    "gnome",
    "hyprland",
    "epita/core"
  ],
  "packages": [
    "gparted",
    "kdePackages.kate"
  ]
}
```

- `modules`: paths relative to `nixos/modules/`, without `.nix`. Every `.nix`
  file there is a module, subfolders included (`gnome.nix` → `gnome`,
  `epita/c.nix` → `epita/c`). Modules don't import each other: each one is
  turned on and off here.
- `packages`: nixpkgs attribute paths, nested ones included.

**Groups**: a folder with a `core.nix` (like `epita/` or `gaming/`) is a group. Its core
(`epita/core`, shown as `epita`) is the switch for the whole group, and each
submodule (`epita/c`, `epita/docker`…) is toggled on its own. A submodule is
only imported when its group is on, so turning a group off keeps your
submodule choices for when you turn it back on.

[`nixos/state.nix`](../../nixos/state.nix) turns this file into a module that
imports the listed modules and adds the packages to
`environment.systemPackages`. Each host loads it with:

```nix
imports = [
  ./hardware-configuration.nix
  ./../../core.nix
  (import ./../../state.nix ./state.json)
];
```

You can edit `state.json` by hand too: nixcfg writes it in the same format
(2-space indent, one item per line), so diffs stay clean.

## Modules tab

Three columns, like a file manager:

```
 Modules            │ gaming.nix  2/7          │ gaming.nix
 ● epita  4/10 ▸    │ ○ steam  # Steam is al…  │ 17   environment.systemPackages = with pkgs; [
 ● gaming           │ ● adwsteamgtk            │ 18     # steam # Steam is already installed…
 ● gnome            │ ● protonplus             │ 19     adwsteamgtk
 ○ jetbrains        │ ○ lutris                 │ 24     # lutris
```

- **Modules** (left): `●` enabled on this host. A group (`epita 4/10 ▸`)
  opens with `→` to show its submodules.
- **Packages** of the highlighted module (middle): `→` enters this column,
  `←` goes back. `●` means the line is active, `○` that it is commented out.
  Expressions such as `(python3.withPackages …)` or `inputs.foo.packages…`
  are shown in italics and are read-only: edit them with `e`.
- **The file** (right, read-only): follows the highlighted package. Hidden
  when the terminal is narrower than 120 columns.

| Key | Where | Action |
|---|---|---|
| `Space` / `Enter` | Modules | Turn the module on or off for this host |
| `→` / `←` | Modules | Open / close a group, or enter / leave the packages column |
| `n` | Modules | New module: creates `nixos/modules/<name>.nix` (`<name>` can be `folder/name`) from a template, enables it and opens it in `$EDITOR` |
| `D` | Modules | Delete the module and disable it on every host |
| `Space` / `Enter` | Packages column | Comment or uncomment the package's line |
| `a` | Packages column | Add a package line to the module (searches nixpkgs) |
| `x` / `Delete` | Packages column | Delete the package's line |
| `e` | both columns | Open the module in `$EDITOR`, at the package's line if one is highlighted |

## Packages tab

Every package in one list: the ones in each module (`gnome.nix`,
`gaming.nix`…) and this host's own extra packages (`this host`, from
`state.json`). `●` means it is installed on this host: its line is active and
its module is enabled.

| Key | Action |
|---|---|
| `/` | Filter by package or module name (`Enter` or `Esc` goes back to the list) |
| `Enter` | Jump to the package's line in its module |
| `a` | Add a package to this host (`state.json`) |
| `x` / `Delete` | Remove one of this host's packages |

## Everywhere

| Key | Action |
|---|---|
| `1` / `2` | Show the Modules / Packages tab |
| `h` | Switch host |
| `g` | Show `git diff` of `nixos/` and `flake.lock` |
| `u` | `nix flake update` (all hosts share `flake.lock`, asks first) |
| `b` | Build the host's system (no sudo, nothing is activated) |
| `r` | `sudo nixos-rebuild switch` (only for this machine, asks first) |
| `q` | Quit |

Every change is written right away (to `state.json` or to the module file):
use `git diff` and `git restore` to review or undo.

## Editing modules safely

nixcfg never rewrites a module: it only comments, uncomments, adds or
deletes **one line** of an `environment.systemPackages` list
([`modfile.py`](modfile.py)), so your comments and formatting stay. A line
counts as a package when it is a single attribute path (`kitty`,
`kdePackages.kate`, with an optional `# comment`). A commented line counts as
a disabled package when it is one lowercase word right after the `#`
(`# lutris`, `#nix-software-center`). Section comments like `# Ricing` or
`# Not sure if...` are ignored.

After each change, nixcfg checks the file with Nix in the background
(`checking…` next to the module name):

1. `nix-instantiate --parse` on the file (syntax),
2. an evaluation of `environment.systemPackages` for every host that uses the
   module (this catches unknown package names, about 3 s per host).

If the check fails, the change is **reverted** and the Nix error is shown.

## Details

- **Package search** runs `nix search` on the nixpkgs locked in this flake's
  `flake.lock`, so results match what a rebuild will install. The first
  search evaluates all of nixpkgs and can take a minute; later ones are
  cached. The first entry always lets you add the typed name as-is.
- **New modules** are `git add`ed and **deleted modules** are `git rm --cached`,
  because a flake only sees files tracked by git. Nothing is committed.
- **Deleting** a module removes its file (and its folder once empty) and
  disables it on every host. If another module still mentions the file, the
  confirmation warns you.
- The **Modules** tab shows groups as a tree (`epita 4/10` = 4 of its 10
  submodules on), which other hosts enable each module, and marks
  modules listed in `state.json` whose file doesn't exist as *missing file*.
- The **`default`** host imports `/etc/nixos/hardware-configuration.nix`, so
  builds and rebuilds for it run with `--impure`.
- nixcfg looks for the flake in `~/dotfiles`. Set `NIXCFG_DOTFILES` to use
  another path.

## Look

nixcfg uses the colors of your Caelestia shell (the Material You palette in
`~/.local/state/caelestia/scheme.json`, generated from the wallpaper) and
follows it live when the wallpaper changes. Without Caelestia it falls back
to Catppuccin Mocha. `Ctrl+P` → *Change theme* picks another theme for the
session.

## Files

- `nixcfg.py`: the app ([Textual](https://textual.textualize.io/)).
- `modfile.py`: reads and edits the package lists of module files.
- `default.nix`: packages it with Python and Textual. It is exposed in
  `flake.nix` as `apps.x86_64-linux.nixcfg`.

## Developing

The `nixcfg` command runs `tools/nixcfg/nixcfg.py` from the dotfiles
checkout (`$NIXCFG_DOTFILES`, or `~/dotfiles`), and only falls back to its
Nix store copy when there is none. Edits show up on the next launch, with no
rebuild. Rebuild only when `default.nix` changes (new Python packages, the
desktop entry...).

For live CSS reload and the Textual console:

```bash
nix develop ~/dotfiles#nixcfg
textual run --dev tools/nixcfg/nixcfg.py   # in one terminal
textual console                            # in another, for print() and logs
```
