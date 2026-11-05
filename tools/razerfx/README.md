# razerfx

Lighting effects for the Razer keyboard (BlackWidow V3 Tenkeyless), picked from
a terminal UI or the command line. Everything follows the Caelestia colour
scheme, so the keyboard changes with the wallpaper.

```bash
razerfx                    # the TUI (also in the app launcher)
nix run ~/dotfiles#razerfx # same, without installing
```

It's two parts:

- **the daemon** (`razerfx daemon`, run by the `razerfx` systemd user service)
  draws the keyboard about 30 times a second through openrazer;
- **the TUI and the CLI**, which only edit
  `~/.local/state/razerfx/state.json`. The daemon picks changes up within a
  frame.

You pick **one effect** and any number of **overlays**, which are drawn on
top of it (the Super key hints show up whatever the effect is).

## Effects

### Classic

The keyboard's built-in effects, redone in the scheme colours. They are drawn
in software so that overlays work on top of them.

| Effect | Name | What it does |
|---|---|---|
| Off | `off` | All LEDs off. Overlays still show up. |
| Static | `static` | The whole keyboard in the Caelestia **primary** colour. This is what `razer-colour.py` used to do. |
| Breathing | `breathing` | Breathes in **primary**, then in **tertiary** (like openrazer's `breath_dual`). |
| Starlight | `starlight` | Random keys twinkle in **primary** and **secondary** (like `starlight_dual`). |
| Reactive | `reactive` | Pressed keys light up in **primary** and fade out over about a second (like `reactive`). |
| Wave | `wave` | A primary → secondary → tertiary gradient scrolling across the keys. |
| Rainbow | `spectrum` | The full rainbow scrolling across the keys. Ignores the scheme. |

### Per-key

| Effect | Name | What it does |
|---|---|---|
| Audio visualiser | `audio` | What's playing, as a spectrum analyser: 18 columns = 18 frequency bands from 40 Hz (left) to 16 kHz (right). Bars rise from the bottom row in **primary** and turn **tertiary** at the top. Gain adjusts itself to the volume. |
| Mic visualiser | `mic` | Same, but for your **microphone** (the default input), over the voice range: 80 Hz (left) to 8 kHz (right). Bars go from **secondary** at the bottom to **tertiary** at the top. Talk, sing, or watch it light up during calls. |
| Screen mirror | `screen` | The keyboard **mimics the screen**, like an ambilight: each key takes the colour of the part of the focused monitor it sits under (the screen is split into 6 rows × 18 columns). Colours are saturated and darks stay dark so it reads well on LEDs, and it fades smoothly between frames. The capture runs **on the GPU**: `gpu-screen-recorder` grabs the monitor through KMS, scales it to 256×144 and encodes it with NVENC, then `ffmpeg` decodes that tiny stream down to 18×6. Up to 20 frames a second, and none while the screen doesn't change. |
| Typing ripples | `ripple` | Each key press sends a ring outward from that key. Each new ring takes the next colour of the scheme gradient. |
| Live status | `status` | **Number keys 1–0** are Hyprland workspaces 1–10: bright primary = current, dim secondary = has windows, very dim = exists but empty. **The F-row** is a CPU load bar (F1 → F12) that goes from green to red as the CPU heats up (45 °C → 85 °C). |

### Themed

| Effect | Name | What it does |
|---|---|---|
| Predatoria 🩸 | `predatoria` | For the Empress of Vampires. A deep crimson **heartbeat** (a strong *lub* and a weaker *dub*, about 60 bpm, faster with the speed setting) with **blood drips** that swell on the top row, then fall down the rows and leave fading stains. Pressing a key makes it bleed from that key. |
| Fire | `fire` | Flames rising from the bottom row (the demoscene fire). Typing stokes the flames under the keys you press. |
| Plasma | `plasma` | Smooth flowing blobs in the scheme colours (the demoscene plasma). |
| Game of Life | `life` | Conway's Game of Life on the 6×18 keys, wrapping around the edges. Newborn cells are **tertiary**, older ones **primary**, dying cells leave a **secondary** ghost. Pressing a key brings cells to life around it. It reseeds itself when it dies out or loops. |

## Overlays

Drawn on top of the effect, always in this order (so the Super hints win):

| Overlay | Name | What it does |
|---|---|---|
| App context | `context` | Highlights the keys that matter in the focused window and dims the rest. **Neovim** (a kitty/foot/Alacritty window whose title has `nvim` or `vim`, or Neovide): `hjkl` in primary; Esc, `:`, `/`, `i`, `v` in secondary; `w b e u p y d` in tertiary. **Games** (`steam_app_*`, Albion Online, Minecraft, gamescope, `*.exe`): WASD in primary; Space, Shift, Ctrl, E, Q, R, F in secondary; 1–5, Tab, Esc in tertiary. Rules are in `Context_.RULES` in `effects.py`. |
| Pomodoro timer | `pomodoro` | While a timer runs, the **F-row** is a tertiary bar that drains from F12 to F1. When time's up it **blinks green** for 8 seconds. Start it with `p` in the TUI or `razerfx pomodoro 25` (this also turns the overlay on). |
| Caps Lock glow | `caps-lock` | Caps Lock pulses white while it's on (read from the keyboard LED). |
| Mic muted | `mic-mute` | **Esc** pulses red while the default microphone is muted (`wpctl`). |
| Notification flash | `notifications` | The whole keyboard pulses twice on each desktop notification: **Discord blurple** for Discord/Vesktop/WebCord, primary otherwise. It watches the `Notify` calls on the session D-Bus. |
| Super key hints | `super-hints` | **Hold Super** (the Windows key) and every key that has a Hyprland shortcut lights up in **primary**, the rest goes dark. Add **Shift, Ctrl or Alt** and it follows: it then shows the shortcuts of that exact combination. Modifiers that would unlock more shortcuts glow in **tertiary**, held modifiers are **white**, and keys only bound with more modifiers are **dim secondary**. Binds come live from Hyprland (`hyprctl binds`), so new shortcuts show up by themselves. It waits 0.12 s before showing, so quick shortcuts don't flash the keyboard. |

There is also a **flash** that is always available: `razerfx flash [colour]`
pulses the keyboard twice. It's meant for scripts and hooks (see below).

## Game mode

While Caelestia's **game mode** is on (Utilities panel, or
`caelestia shell gameMode toggle`), effects, overlays and flashes pause: the
keyboard stays in the static **primary** colour and the daemon only wakes
twice a second, so the audio and screen captures stop too. The daemon asks
the shell every 2 s (`caelestia-shell ipc call gameMode isEnabled`), because
game mode only lives in the shell's memory. The mouse pointer trail
(`tools/hypr-cursortrail`) disappears too: it hides while Hyprland animations
are off, which is what game mode turns off.

## TUI

Effects on the left (Enter to apply, `●` marks the current one), overlays on
the right (Space to toggle), and a description of whatever is highlighted.

| Key | Action |
|---|---|
| Enter | Apply the highlighted effect |
| Space | Toggle the highlighted overlay |
| Tab | Switch between effects and overlays |
| `+` / `-` | Brightness up / down (10 % steps) |
| `]` / `[` | Faster / slower animations |
| `p` | Start a 25-minute pomodoro, or stop the running one |
| `f` | Test flash |
| `r` | Restart the daemon (after editing the code) |
| `q` | Quit |

## Command line

```bash
razerfx list                         # effects and overlays
razerfx status                       # current settings
razerfx set predatoria               # switch effect
razerfx overlay super-hints toggle   # on | off | toggle (default)
razerfx brightness 60                # 0-100
razerfx speed 1.5                    # 0.1-5
razerfx pomodoro 25                  # minutes, or `stop`
razerfx flash discord                # primary | secondary | tertiary | error,
                                     # red green blue white yellow orange purple
                                     # pink cyan discord blood, or #rrggbb
```

### Flash when Claude Code finishes

Add a `Stop` hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "razerfx flash tertiary" }] }]
  }
}
```

## Colours

Effects use the Caelestia scheme (`~/.local/state/caelestia/scheme.json`),
reloaded as soon as it changes. Material You colours are pastel in dark mode
and LEDs render pastels as almost white, so each colour keeps its hue but gets
full saturation and brightness. When secondary or tertiary end up too close
to primary, their hue is pushed away a bit so gradients stay visible.

## Setup

All of it is in [`nixos/modules/razer.nix`](../../nixos/modules/razer.nix)
(the `razer` module):

- installs `razerfx` (with its app launcher entry);
- runs `razerfx daemon` as the `razerfx` systemd **user** service, started
  with the graphical session after `openrazer-daemon`;
- adds you to the **`openrazer`** group. Besides talking to the openrazer
  daemon, it lets razerfx read key presses (typing effects, Caps Lock, Super
  hints): openrazer's udev rule gives the Razer `/dev/input` devices to that
  group, so no `input` group is needed and other keyboards stay private.
- enables `programs.gpu-screen-recorder`, which gives its KMS helper the
  capability to capture the screen without asking for root (for the screen
  mirror).

Like nixcfg, the `razerfx` command runs the code from the checkout
(`~/dotfiles/tools/razerfx`, or `$RAZERFX_DOTFILES/tools/razerfx`), so code
edits need no rebuild, only a daemon restart (`r` in the TUI, or
`systemctl --user restart razerfx`). A rebuild is only needed when
`default.nix` changes (Python packages, launcher).

Logs: `journalctl --user -u razerfx -f`.

## Code

| File | What's in it |
|---|---|
| `razerfx.py` | Entry point: the CLI, opens the TUI without arguments |
| `tui.py` | The Textual TUI |
| `daemon.py` | The render loop and the openrazer output |
| `effects.py` | Every effect and overlay |
| `inputs.py` | Background readers: keyboard (evdev), audio and mic (`pw-record`), screen (`gpu-screen-recorder` + `ffmpeg`), Hyprland (IPC sockets), CPU/temperature/mic, notifications (D-Bus) |
| `keymap.py` | Key → LED position on the 6×18 TKL matrix, and Hyprland key names → keys |
| `palette.py` | Caelestia colours made LED-friendly |
| `state.py` | Reading and writing `state.json` |

**Adding an effect**: write a class in `effects.py` with `@effect`, a `name`,
`title`, `category`, `description` and a `render(ctx)` that returns a 6×18×3
array of RGB floats in [0, 1]. Set `needs` to the inputs it uses. For an
overlay, use `@overlay` and `apply(frame, ctx)`, and add it to `ORDER`. Both
show up in the TUI and `razerfx list` by themselves. **Then add it to this
README.**

To work on it: `nix develop ~/dotfiles#razerfx`, then
`python tools/razerfx/razerfx.py`. To run your own daemon, stop the service
first (`systemctl --user stop razerfx`).

## Troubleshooting

- **Nothing lights up**: is the daemon running (`systemctl --user status
  razerfx`) and does openrazer see the keyboard (`polychromatic`)? Polychromatic
  and razerfx fight over the keyboard: set effects in only one of them.
- **No typing effects or Super hints**: `ls -l /dev/input/by-id/*Razer*kbd`
  should point to devices of group `openrazer`, and `id` must list
  `openrazer`. The journal says so when it can't read them.
- **Super hints are wrong on another layout**: keys are matched on the US
  layout (as Hyprland names them), whatever the active layout is.
- **Audio visualiser stays dark**: it listens to the default output through
  `pw-record`; check that something plays on that output.
- **Mic visualiser stays dark**: it listens to the default input; check it's
  the right microphone and not muted (`wpctl status`). Quiet background noise
  is ignored on purpose.
- **Screen mirror stays dark**: it needs Hyprland (to know the focused
  monitor) and gpu-screen-recorder's KMS helper with its capability
  (`programs.gpu-screen-recorder.enable` in `razer.nix`, check
  `ls /run/wrappers/bin/gsr-kms-server`). The journal shows why a capture
  stopped.
