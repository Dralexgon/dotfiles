# nixcfg

A terminal UI to turn modules on and off and to add or remove packages,
for each NixOS host of this flake.

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
  file there is a module, subfolders included (`gaming.nix` → `gaming`,
  `epita/c.nix` → `epita/c`). Modules don't import each other: each one is
  turned on and off here.
- `packages`: nixpkgs attribute paths, nested ones included.

**Groups**: a folder with a `core.nix` (like `epita/`) is a group. Its core
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

## Keys

| Key | Tab | Action |
|---|---|---|
| `Space` | Modules | Turn the highlighted module on or off |
| `n` | Modules | New module: creates `nixos/modules/<name>.nix` (`<name>` can be `folder/name`) from a template, enables it and opens it in `$EDITOR` |
| `e` | Modules | Edit the highlighted module in `$EDITOR` |
| `D` | Modules | Delete the highlighted module and disable it on every host |
| `a` | Packages | Add a package (searches nixpkgs) |
| `x` / `Delete` | Packages | Remove the highlighted package |
| `h` | both | Switch host |
| `g` | both | Show `git diff` of `nixos/` |
| `b` | both | Build the host's system (no sudo, nothing is activated) |
| `r` | both | `sudo nixos-rebuild switch` (only for this machine, asks first) |
| `q` | both | Quit |

Every change is written to `state.json` right away: use `git diff` and
`git restore` to review or undo.

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
- `default.nix`: packages it with Python and Textual. It is exposed in
  `flake.nix` as `apps.x86_64-linux.nixcfg`.
