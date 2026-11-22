# bat-swarm

A cloud of bats flying across every screen: the transition of the **vampire** rice.
`set_rice()` in `config/caelestia/hypr-user.lua` plays it while the colours and the wallpaper change. Try it with `bat-swarm`.

It is a Quickshell overlay: click-through (it never takes the keyboard or the mouse), and it quits by itself after about 4 seconds.
Starting it again while bats are still flying replaces the swarm instead of adding a second one.

## Files

| File | Role |
|---|---|
| `shell.qml` | the overlay: timing, flight paths, the bat look (dark body, thin crimson glow) |
| `default.nix` | the `bat-swarm` command, installed by `nixos/modules/desktop/caelestia.nix` |

The bat shape is [`themes/assets/simple-bat.svg`](../../themes/assets/simple-bat.svg) ("Bat" by Skoll, CC BY 3.0).
The command runs `shell.qml` from the dotfiles checkout (`$BAT_SWARM_DOTFILES`, default `~/dotfiles`) when there is one, so editing it needs no rebuild.
