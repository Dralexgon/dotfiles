# nixcfg

A terminal UI to turn modules on and off and to enable, disable, add or
remove packages (in modules or per host), for each NixOS host of this flake.

```bash
nix run ~/dotfiles#nixcfg
```

It opens on the host matching this machine's hostname (or the first host
found), with three tabs: **Modules**, **Packages** and **Keybinds**
(read-only, the Hyprland shortcuts of the Caelestia desktop).

## How it works

nixcfg never rewrites Nix code: like you would by hand, it comments and
uncomments lines. Each host lists its modules in the `imports` of its
`configuration.nix`, and a disabled one is commented out:

```nix
imports = [
  ./hardware-configuration.nix
  ./../../core.nix

  # Modules: comment a line out to disable it (or use `nixcfg`)
  ./../../modules/boot-animation.nix
  ./../../modules/epita/core.nix
  ./../../modules/flatpak.nix
  # ./../../modules/jetbrains.nix
];

# Packages for this host only
environment.systemPackages = with pkgs; [
  gparted
  # usbutils
];
```

- Every `.nix` file in `nixos/modules/` is a module, subfolders included
  (`flatpak.nix` → `flatpak`, `epita/c.nix` → `epita/c`). A module with no
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

**Desktops**: `nixos/modules/desktop/` (GNOME, KDE, Hyprland, Caelestia,
Wayfire) is shown as the `desktop` group, but it works per host: core.nix
imports it for every host, and each host picks its desktops in a list of its
own `configuration.nix`, toggled like imports:

```nix
desktop.enabled = [
  "caelestia"
  "gnome"
  # "kde"
];
desktop.defaultSession = "caelestia"; # preselected on the login screen
```

`s` on a desktop makes it this host's default (`★ login default`). Turning the
default off moves it to the first desktop left on. Desktops can't be created
or deleted from nixcfg: each one also has its session in
`desktop/default.nix`.

Lines keep their place, so you can reorder them, add comments after them or
edit the files by hand; [`hostfile.rs`](src/hostfile.rs) only comments or
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
  module (like `useful-apps.nix`). The second row, `configuration`, is the
  host's own `nixos/hosts/<host>/configuration.nix`: always on too, so you
  can browse it, edit it with `e` and toggle its packages. A group (`epita 4/10 ▸`)
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
| `s` | Modules | On a desktop: make it this host's default on the login screen (turns it on) |
| `Space` / `Enter` | Packages column | Comment or uncomment the package's line |
| `a` | Modules / Packages column | Add a package line to the highlighted module (searches nixpkgs, then asks for an optional description written as `# comment`) |
| `x` / `Delete` | Packages column | Delete the package's line |
| `e` | both columns | Open the module in `$EDITOR`, at the package's line if one is highlighted |

## Packages tab

Every package in one list: the ones in each module (`flatpak.nix`,
`gaming.nix`…) and this host's own packages (`this host`, from its
`configuration.nix`). `●` means it is installed on this host: its line is active and
its module is enabled. This host's packages can be commented out too.

| Key | Action |
|---|---|
| `/` | Filter by package or module name (`Enter` or `Esc` goes back to the list) |
| `Enter` | Jump to the package's line in its module, or comment / uncomment one of this host's packages |
| `a` | Add a package to this host (`configuration.nix`), with an optional description |
| `x` / `Delete` | Remove one of this host's packages |

## Keybinds tab

Every Hyprland shortcut of the Caelestia desktop, read-only. `hyprctl binds`
cannot name them (with the Lua config, every bind's dispatcher is `__lua`), so
[`keybinds.rs`](src/keybinds.rs) reads the Lua files instead, without running them:

- **default**: Caelestia's `kb*` variables (`~/.config/hypr/variables.lua`),
  in the order and under the headings of `~/.config/hypr/hyprland/keybinds.lua`,
  which also gives each one its action. The few binds it writes without a
  variable (brightness keys, `SUPER + arrows`…) are listed too.
- **override**: a variable set in `config/caelestia/hypr-vars.lua`, which
  replaces the default (`was SUPER + T`). Set to `""`, the bind is **removed**
  (struck through). A `kb*` variable Caelestia does not use (a typo) shows up
  under *Unknown variables*.
- **user**: the `hl.bind(...)` calls of `config/caelestia/hypr-user.lua`,
  named by their `description`.

A red `!` marks a conflict: several actions on the same combo, which all run
on the same key press (the line under the list says with what). The tab
title counts the binds and the conflicts. The files are read again each time
the tab is shown.

| Key | Action |
|---|---|
| `/` | Filter by combo, name, action, variable or source (`override`, `user`, `conflict`…) |
| `e` | Open the file to change the bind in, in `$EDITOR`: `hypr-vars.lua` for Caelestia's variables (at the override's line), `hypr-user.lua` for your binds, Caelestia's `keybinds.lua` for the rest |

`python3 tools/nixcfg/legacy/keybinds.py` prints the same list in the terminal
(`nixcfg --dump` has it too, as JSON).

## Everywhere

| Key | Action |
|---|---|
| `1` / `2` / `3` | Show the Modules / Packages / Keybinds tab |
| `h` | Switch host |
| `g` | Show `git diff` of `nixos/` and `flake.lock` |
| `u` | Update `flake.lock` (shared by all hosts, asks first). With `nh`, on this machine: `nh os switch --update` (update, then switch) |
| `b` | Build the host's system (no sudo, nothing is activated): `nh os build`, or `nix build` |
| `r` | `nh os switch`, or `sudo nixos-rebuild switch` without `nh` (only for this machine, asks first) |
| `c` | Delete old system generations of this machine (see below) |
| `t` | Toggle between nixcfg's colors and the terminal's |
| `q` | Quit (really stops nixcfg, unlike hiding or closing its window) |
| `Esc` | Hide the window (in a list, under Hyprland: see [Running in the background](#running-in-the-background)) |

Every change is written right away (to the host's `configuration.nix` or to the module file):
use `git diff` and `git restore` to review or undo.

## Editing modules safely

nixcfg never rewrites a module: it only comments, uncomments, adds or
deletes **one line** of an `environment.systemPackages` list
([`modfile.rs`](src/modfile.rs)), so your comments and formatting stay. A line
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

Under Hyprland, its window is not even closed: a window rule in
[`hypr-user.lua`](../../config/caelestia/hypr-user.lua) puts it on its own
special workspace, `special:nixcfg`, like Caelestia's music or communication
workspaces. `SUPER + I` shows it, and hides it again; `Esc` in nixcfg hides it
too. Showing it is a workspace switch, with no new kitty or nixcfg to start.
Closing it still works, it just reopens a bit slower (a new kitty window).

While it runs, a ❄ icon shows in the bar's tray ([`tray.rs`](src/tray.rs), a
StatusNotifierItem): click it to show or focus the window. Hovering it in
Caelestia shows its menu, with what is running and **Quit nixcfg** (disabled
while an update or rebuild runs).

- `nixcfg --foreground` runs it in the current terminal, without tmux.
- `tmux -L nixcfg kill-server` stops a nixcfg left in the background.

### Startup speed

nixcfg was rewritten in Rust (Ratatui) for slow machines: on the gray laptop
it shows its first screen in about **65 ms**, against **1.3 s** for the Python
(Textual) version, and uses 9 MB of memory instead of 57 MB. With its window
hidden instead of closed, opening it again is instant.

If it still feels slow, what is left:

1. **The first kitty window.** Opening nixcfg the first time after logging in
   starts a kitty window (about 0.2–0.4 s on the laptop). It could be started
   hidden at login (an `exec-once` of `kitty --class nixcfg nixcfg`, which the
   window rule sends to its special workspace), at the cost of keeping kitty
   and nixcfg in memory all the time (about 100 MB).
2. **`kitty --single-instance`** is not worth it anymore: it only saves
   starting a kitty process, which hiding the window already avoids.
3. **The Nix check** after each change (`checking…`) still takes about 3 s per
   host that uses the module: that is Nix evaluating the config, not nixcfg.

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
to Catppuccin Mocha.

The output of an update, build or switch is shown in the same colors: the
terminal's palette is changed while the command runs (OSC 4/10/11), then put
back. `t` switches nixcfg to the terminal's own colors instead, for both.

## Files

- `src/main.rs`: the command line (`--foreground`, `--dump`).
- `src/app.rs`: the app ([Ratatui](https://ratatui.rs/)): tabs, dialogs, keys and mouse.
- `src/widgets.rs`: its lists and text input.
- `src/cfg.rs`: the hosts, modules, groups and what each host turns on; the Nix check.
- `src/modfile.rs`: reads and edits the package lists of module files.
- `src/hostfile.rs`: reads and edits the module imports and desktops of host files.
- `src/keybinds.rs`: reads the Hyprland binds of the Caelestia Lua config (Keybinds tab).
- `src/window.rs`: the tmux session, and showing or hiding the window under Hyprland.
- `src/tray.rs`: the tray icon (D-Bus, with `ksni`).
- `src/theme.rs`, `src/nixhl.rs`: the colors, and the Nix highlighting of the preview.
- `default.nix`: builds it with Cargo. It is exposed in `flake.nix` as
  `apps.x86_64-linux.nixcfg`, and installed by `core.nix`.
- `legacy/`: the original Python (Textual) version, see below.
- `compare.py`: checks that both versions read and edit the files the same way.

## The legacy Python version

The original version is kept in [`legacy/`](legacy), unchanged except for
its own tmux socket and window class (`nixcfg-legacy`), so it never attaches
to the Rust one:

```bash
nix run ~/dotfiles#nixcfg-legacy
```

It is not installed. It runs `legacy/nixcfg.py` from the checkout, so edits
to it need no rebuild. The only things it has that the Rust version dropped
are Textual's command palette (`Ctrl+P`, with its theme picker) and its
console for debugging.

`compare.py` checks the two against each other. `nixcfg --dump` prints, as
JSON, everything nixcfg reads (hosts, modules, states, packages, keybinds)
and the text of **every edit it can make** (each module, submodule, desktop
and package toggled, each package removed, a package added). `compare.py`
computes the same with the Python functions and diffs the two. Nothing is
written:

```bash
nix develop ~/dotfiles#nixcfg -c python tools/nixcfg/compare.py
# 4345 values compared, 0 difference(s)
```

Run it after changing the parsing or editing code of either version
(`--dotfiles DIR` checks another dotfiles copy, `--rust BIN` another build).

## Developing

```bash
nix develop ~/dotfiles#nixcfg     # cargo, rustc, clippy, rust-analyzer, and Python for legacy/
cd tools/nixcfg
cargo run -- --foreground          # try a change without rebuilding the system
python compare.py                  # check it still matches the legacy version
```

The installed `nixcfg` is the one built by Nix, so a change shows up there
after a rebuild (`r` in nixcfg). The first build takes a few minutes on the
laptop; later ones only rebuild the crate.
