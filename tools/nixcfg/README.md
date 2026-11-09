# nixcfg

A terminal UI to turn modules on and off and to enable, disable, add or
remove packages (in modules or per host), for each NixOS host of this flake.

```bash
nix run ~/dotfiles#nixcfg
```

It opens on the host matching this machine's hostname (or the first host
found), with two tabs: **Modules** and **Packages**.

## How it works

nixcfg never rewrites Nix code: like you would by hand, it comments and
uncomments lines. Each host lists its modules in the `imports` of its
`configuration.nix`, and a disabled one is commented out:

```nix
imports = [
  ./hardware-configuration.nix
  ./../../core.nix

  # Modules: comment a line out to disable it (or use `nixcfg`)
  ./../../modules/caelestia.nix
  ./../../modules/epita/core.nix
  ./../../modules/gnome.nix
  # ./../../modules/jetbrains.nix
];

# Packages for this host only
environment.systemPackages = with pkgs; [
  gparted
  # usbutils
];
```

- Every `.nix` file in `nixos/modules/` is a module, subfolders included
  (`gnome.nix` → `gnome`, `epita/c.nix` → `epita/c`). A module with no
  line is off; nixcfg adds its line when you turn it on.
- The host's own packages are a normal `environment.systemPackages` list,
  edited like the ones in modules (see [Editing modules safely](#editing-modules-safely)).

**Groups**: a folder with a `core.nix` (like `epita/` or `gaming/`) is a
group. Hosts import its core (`epita/core`, shown as `epita`), and the core
imports its submodules, the same way:

```nix
# nixos/modules/epita/core.nix
imports = [
  ./c.nix
  ./criterion.nix
  # ./java.nix
];
```

So the submodule choices are **shared by every host** that turns the group
on. Toggling a submodule in nixcfg edits the core's `imports` (and is
checked with Nix, like a package change); toggling the group edits the host.

Lines keep their place, so you can reorder them, add comments after them or
edit the files by hand; [`hostfile.py`](hostfile.py) only comments or
uncomments a line, adds a missing line next to the ones of its folder, or
drops the commented line of a module whose file was deleted.

## Modules tab

Three columns, like a file manager:

```
 Modules            │ gaming.nix  2/7          │ gaming.nix
 ● epita  4/10 ▸    │ ○ steam  # Steam is al…  │ 17   environment.systemPackages = with pkgs; [
 ● gaming           │ ● adwsteamgtk            │ 18     # steam # Steam is already installed…
 ● gnome            │ ● protonplus             │ 19     adwsteamgtk
 ○ jetbrains        │ ○ lutris                 │ 24     # lutris
```

- **Modules** (left): `●` enabled on this host. The first row, `core`, is
  [`nixos/core.nix`](../../nixos/core.nix): every host imports it, so it
  can't be turned off (or deleted), but its packages are toggled like any
  module's, for every host. For per-host control, move a block of it into a
  module (like `useful-apps.nix`). A group (`epita 4/10 ▸`)
  opens with `→` to show its submodules.
- **Packages** of the highlighted module (middle): `→` enters this column,
  `←` goes back. `●` means the line is active, `○` that it is commented out.
  Expressions such as `(python3.withPackages …)` or `inputs.foo.packages…`
  are shown in italics and are read-only: edit them with `e`.
- **The file** (right, read-only): follows the highlighted package. Hidden
  when the terminal is narrower than 120 columns.

| Key | Where | Action |
|---|---|---|
| `Space` / `Enter` | Modules | Turn the module on or off for this host (a submodule: in its group's `core.nix`, for every host) |
| `→` / `←` | Modules | Open / close a group, or enter / leave the packages column |
| `n` | Modules | New module: creates `nixos/modules/<name>.nix` (`<name>` can be `folder/name`) from a template, enables it and opens it in `$EDITOR` |
| `D` | Modules | Delete the module and disable it on every host |
| `Space` / `Enter` | Packages column | Comment or uncomment the package's line |
| `a` | Packages column | Add a package line to the module (searches nixpkgs) |
| `x` / `Delete` | Packages column | Delete the package's line |
| `e` | both columns | Open the module in `$EDITOR`, at the package's line if one is highlighted |

## Packages tab

Every package in one list: the ones in each module (`gnome.nix`,
`gaming.nix`…) and this host's own packages (`this host`, from its
`configuration.nix`). `●` means it is installed on this host: its line is active and
its module is enabled. This host's packages can be commented out too.

| Key | Action |
|---|---|
| `/` | Filter by package or module name (`Enter` or `Esc` goes back to the list) |
| `Enter` | Jump to the package's line in its module, or comment / uncomment one of this host's packages |
| `a` | Add a package to this host (`configuration.nix`) |
| `x` / `Delete` | Remove one of this host's packages |

## Everywhere

| Key | Action |
|---|---|
| `1` / `2` | Show the Modules / Packages tab |
| `h` | Switch host |
| `g` | Show `git diff` of `nixos/` and `flake.lock` |
| `u` | Update `flake.lock` (shared by all hosts, asks first). With `nh`, on this machine: `nh os switch --update` (update, then switch) |
| `b` | Build the host's system (no sudo, nothing is activated): `nh os build`, or `nix build` |
| `r` | `nh os switch`, or `sudo nixos-rebuild switch` without `nh` (only for this machine, asks first) |
| `c` | Delete old system generations of this machine (see below) |
| `t` | Toggle between nixcfg's colors and the terminal's |
| `q` | Quit (really stops nixcfg, unlike closing its window) |

Every change is written right away (to the host's `configuration.nix` or to the module file):
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

## Generations

`c` lists this machine's system generations (number, date, NixOS version,
kernel), newest first. `Space` selects one, `o` selects every generation older
than the highlighted one, `d` deletes the selection (asks first). The current
generation (the one the next boot uses) can't be selected; the running one is
marked `running`.

Deleting runs, in a terminal (sudo may ask for your password):

1. `sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations …`
2. `sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot`, which
   rewrites the boot menu without them,
3. `nix-collect-garbage`, which frees the store paths nothing uses anymore.

`nix.gc` in `core.nix` already deletes generations older than 14 days every
week; this is for cleaning up sooner.

## Running in the background

Like Discord, closing the nixcfg window does not stop it: nixcfg runs in its
own hidden tmux session (socket `nixcfg`, separate from your own tmux), so an
update, build or rebuild keeps going. Launching nixcfg again (`SUPER + I`,
the app launcher or `nixcfg`) reattaches to it, right where it was. When a
command finishes, a desktop notification tells whether it worked. Press `q`
to really quit.

While it runs, a ❄ icon shows in the bar's tray ([`tray.py`](tray.py), a
StatusNotifierItem): click it to open or focus the window. Hovering it in
Caelestia shows its menu, with what is running and **Quit nixcfg** (disabled
while an update or rebuild runs).

- `nixcfg --foreground` runs it in the current terminal, without tmux.
- `tmux -L nixcfg kill-server` stops a nixcfg left in the background.

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
  modules imported by the host whose file doesn't exist as *missing file*.
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

The output of an update, build or switch is shown in the same colors: the
terminal's palette is changed while the command runs (OSC 4/10/11), then put
back. `t` switches nixcfg to the terminal's own colors instead, for both.

## Files

- `nixcfg.py`: the app ([Textual](https://textual.textualize.io/)).
- `modfile.py`: reads and edits the package lists of module files.
- `hostfile.py`: reads and edits the module imports of host files.
- `tray.py`: the tray icon (D-Bus, with `dbus-fast`).
- `default.nix`: packages it with Python, Textual and dbus-fast. It is exposed in
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
