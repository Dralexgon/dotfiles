# rgbfx

Lighting effects for the Razer keyboard (BlackWidow V3 Tenkeyless) and the
case fans, picked from a GTK window or the command line. Everything follows
the Caelestia colour scheme, so the lights change with the wallpaper (or rice).

```bash
rgbfx                    # the window (also in the app launcher)
nix run ~/dotfiles#rgbfx # same, without installing
```

It's two parts:

- **the daemon** (`rgbfx daemon`, run by the `rgbfx` systemd user service)
  draws the keyboard about 30 times a second through openrazer, and the case
  fans (any non-keyboard OpenRGB device) through the OpenRGB SDK server;
- **the window and the CLI**, which only edit
  `~/.local/state/rgbfx/state.json`. The daemon picks changes up within a
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
| Screen mirror | `screen` | The keyboard **mimics the screen**, like an ambilight: each key takes the colour of the part of the focused monitor it sits under (the screen is split into 6 rows × 18 columns). Colours are saturated and darks stay dark so it reads well on LEDs, and it fades smoothly between frames. The capture runs **on the GPU**: `gpu-screen-recorder` grabs the monitor through KMS, scales it to 256×144 and encodes it with the GPU's hardware encoder (VA-API on AMD), then `ffmpeg` decodes that tiny stream down to 18×6. Up to 20 frames a second, and none while the screen doesn't change. |
| Typing ripples | `ripple` | Each key press sends a ring outward from that key. Each new ring takes the next colour of the scheme gradient. |
| Live status | `status` | **Number keys 1–0** are Hyprland workspaces 1–10: bright primary = current, dim secondary = has windows, very dim = exists but empty. **The F-row** is a CPU load bar (F1 → F12) that goes from green to red as the CPU heats up (45 °C → 85 °C). |
| Typing heatmap | `heatmap` | Each key glows from **cold blue** through cyan, green and yellow to **hot red** with how much you've typed it lately. Presses cool down by half every 5 minutes (real time, not the speed setting), and a square-root scale keeps rarely used keys visible. Your most used keys, at a glance. |

### Themed

| Effect | Name | What it does |
|---|---|---|
| Predatoria 🩸 | `predatoria` | For the Empress of Vampires. A deep crimson **heartbeat** (a strong *lub* and a weaker *dub*, about 60 bpm, faster with the speed setting) with **blood drips** that swell on the top row, then fall down the rows and leave fading stains. Pressing a key makes it bleed from that key. |
| Fire | `fire` | Flames rising from the bottom row (the demoscene fire). Typing stokes the flames under the keys you press. |
| Plasma | `plasma` | Smooth flowing blobs in the scheme colours (the demoscene plasma). |
| Game of Life | `life` | Conway's Game of Life on the 6×18 keys, wrapping around the edges. Newborn cells are **tertiary**, older ones **primary**, dying cells leave a **secondary** ghost. Pressing a key brings cells to life around it. It reseeds itself when it dies out or loops. |
| Thunderstorm | `storm` | Blue **rain** streaks falling down the keys, and every few seconds a **lightning bolt** forks down from the top row while the whole keyboard flickers white. **Enter** calls one down. |
| Fireworks | `fireworks` | **Rockets** climb from the bottom row and **burst into sparks** in the scheme colours, which fall under gravity and fade. Pressing a key launches a rocket that bursts right on that key. |

### Ambient

Slow and calm, for when you're not typing much.

| Effect | Name | What it does |
|---|---|---|
| Aurora | `aurora` | **Northern lights**: curtains of light hang from the top of the keyboard and ripple sideways, their lower edge waving, in the scheme gradient. Stars twinkle in the dark parts below. |
| Digital rain | `matrix` | Streams of light **fall down the columns** in the primary colour, with near-white heads and flickering trails, like the code rain from the films. Typing sends a stream down from the key you pressed. |
| Meteor shower | `meteors` | **Shooting stars** streak diagonally across the keys with a white-hot head and a scheme-coloured tail that cools down. They move between keys smoothly (each one lights the 4 nearest keys). |
| Lava lamp | `lava` | Soft **blobs** (metaballs) slowly rise, sink, drift and merge, each with its own colour of the scheme gradient. |

### Games

They play themselves.

| Effect | Name | What it does |
|---|---|---|
| Snake | `snake` | A **snake that plays by itself**: it finds the shortest path to the pulsing **tertiary** food (only over keys that have an LED) and grows each time it eats. Its head is near-white and its body fades along the scheme gradient. **Press a key to drop the food there.** When it traps itself it turns red, fades and starts over. |

### Test

| Effect | Name | What it does |
|---|---|---|
| Row scan | `row-scan` | One **row** lit in primary, sweeping **top to bottom** (one row every 0.5 s). To check the LED grid row by row. |
| Column scan | `column-scan` | One **column** lit in primary, sweeping **left to right** (one column every 0.2 s). Also shows the fans' column mapping. |

## Overlays

Drawn on top of the effect, always in this order (so the Super hints win):

| Overlay | Name | What it does |
|---|---|---|
| App context | `context` | Highlights the keys that matter in the focused window and dims the rest. **Neovim** (a kitty/foot/Alacritty window whose title has `nvim` or `vim`, or Neovide): `hjkl` in primary; Esc, `:`, `/`, `i`, `v` in secondary; `w b e u p y d` in tertiary. **Games** (`steam_app_*`, Albion Online, Minecraft, gamescope, `*.exe`): WASD in primary; Space, Shift, Ctrl, E, Q, R, F in secondary; 1–5, Tab, Esc in tertiary. Rules are in `Context_.RULES` in `effects.py`. |
| Pomodoro timer | `pomodoro` | While a timer runs, the **F-row** is a tertiary bar that drains from F12 to F1. When time's up it **blinks green** for 8 seconds. Start it from the window or with `rgbfx pomodoro 25` (this also turns the overlay on). |
| Caps Lock glow | `caps-lock` | Caps Lock pulses white while it's on (read from the keyboard LED). |
| Mic muted | `mic-mute` | **Esc** pulses red while the default microphone is muted (`wpctl`). |
| Notification flash | `notifications` | The whole keyboard pulses twice on each desktop notification: **Discord blurple** for Discord/Vesktop/WebCord, primary otherwise. It watches the `Notify` calls on the session D-Bus. |
| Super key hints | `super-hints` | **Hold Super** (the Windows key) and every key that has a Hyprland shortcut lights up in **primary**, the rest goes dark. Add **Shift, Ctrl or Alt** and it follows: it then shows the shortcuts of that exact combination. Modifiers that would unlock more shortcuts glow in **tertiary**, held modifiers are **white**, and keys only bound with more modifiers are **dim secondary**. Binds come live from Hyprland (`hyprctl binds`), so new shortcuts show up by themselves. It waits 0.12 s before showing, so quick shortcuts don't flash the keyboard. |

There is also a **flash** that is always available: `rgbfx flash [colour]`
pulses the keyboard twice. It's meant for scripts and hooks (see below).

## Case fans

The fans (every OpenRGB device that isn't a keyboard: here the B550M's ARGB
headers and its single-LED headers) show the **same effect** as the keyboard,
through the OpenRGB SDK server (`services.hardware.openrgb`, in
[`nixos/modules/openrgb.nix`](../../nixos/modules/openrgb.nix)), in Direct mode.

- Each LED strip is laid along the width of the keyboard: LED *i* of *n* takes
  the colour of column *i / n*, so waves and gradients run along the fans. A
  column's colour is its brightest key, so ripples and sparks still show.
  Single-LED zones take the average.
- Per-key overlays stay on the keyboard (holding Super doesn't black out the
  case). Only the **notification** pulses and `rgbfx flash` reach the fans.
- Brightness, speed and game mode apply to them too.
- **Set the real LED count** of each ARGB header in the OpenRGB GUI (Resize
  zone, then restart the daemon). OpenRGB reports 60 by default, and the
  effect is then spread over 60 LEDs, so only its start shows on the fans.
- If the OpenRGB server isn't up, the keyboard still runs and the daemon
  tries again every 10 s.

## Game mode

While Caelestia's **game mode** is on (Utilities panel, or
`caelestia shell gameMode toggle`), effects, overlays and flashes pause: the
keyboard and fans stay in the static **primary** colour and the daemon only wakes
twice a second, so the audio and screen captures stop too. The daemon asks
the shell every 2 s (`caelestia-shell ipc call gameMode isEnabled`), because
game mode only lives in the shell's memory. The mouse pointer trail
(`tools/hypr-cursortrail`) disappears too: it hides while Hyprland animations
are off, which is what game mode turns off.

To keep the lights going in game mode, turn on **Run in game mode** in the
window (or `rgbfx gamemode run`; `rgbfx gamemode pause` brings the pause back).

## Window

A GTK4 + libadwaita window, coloured by Caelestia's GTK theme
(`~/.config/gtk-4.0/gtk.css`), so it follows the wallpaper like the keyboard.

- **Live preview** at the top: the keyboard as the daemon draws it, overlays
  and brightness included, and next to it **the PC case** seen through its
  glass side, each fan's LEDs in the colour the daemon sent them. While the
  window is open it touches `$XDG_RUNTIME_DIR/rgbfx/preview-wanted`, and the
  daemon then writes each frame to `$XDG_RUNTIME_DIR/rgbfx/frame` (324
  bytes) and the fan colours to `fans.json` next to it (tmpfs). When the
  window closes, the daemon stops writing within 3 s.
- The case layout is in `case.py`: which zone and LED range each fan and the
  pump use, and where they sit. It was measured by lighting blocks of LEDs
  and looking through the webcam: everything is on **D_LED2**, the pump
  (LEDs 0–11) then the 3 top fans, front to rear (12–23, 24–35, 36–47), in
  one daisy chain, and the 4 ring fans (3 front, 1 rear) on a splitter (all
  four show LEDs 0–19).
- **Effects** on the left, by category (click one to apply it).
- **Settings** on the right: brightness, animation speed, and a pomodoro
  (minutes, Start / Stop, time left).
- **Overlays** below them, one switch each.
- Header bar: ☀ test flash, ⟳ restart the daemon (after editing the code).
  Ctrl+Q / Ctrl+W close it.

It floats centred (window rule on `dev.dralexgon.rgbfx` in
`config/caelestia/hypr-user.lua`).

## Command line

```bash
rgbfx list                         # effects and overlays
rgbfx status                       # current settings
rgbfx set predatoria               # switch effect
rgbfx overlay super-hints toggle   # on | off | toggle (default)
rgbfx brightness 60                # 0-100
rgbfx speed 1.5                    # 0.1-5
rgbfx pomodoro 25                  # minutes, or `stop`
rgbfx flash discord                # primary | secondary | tertiary | error,
                                     # red green blue white yellow orange purple
                                     # pink cyan discord blood, or #rrggbb
```

### Flash when Claude Code finishes

Add a `Stop` hook to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "rgbfx flash tertiary" }] }]
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

- installs `rgbfx` (with its app launcher entry);
- runs `rgbfx daemon` as the `rgbfx` systemd **user** service, started
  with the graphical session after `openrazer-daemon`;
- adds you to the **`openrazer`** group. Besides talking to the openrazer
  daemon, it lets rgbfx read key presses (typing effects, Caps Lock, Super
  hints): openrazer's udev rule gives the Razer `/dev/input` devices to that
  group, so no `input` group is needed and other keyboards stay private.
- enables `programs.gpu-screen-recorder`, which gives its KMS helper the
  capability to capture the screen without asking for root (for the screen
  mirror).

Like nixcfg, the `rgbfx` command runs the code from the checkout
(`~/dotfiles/tools/rgbfx`, or `$RGBFX_DOTFILES/tools/rgbfx`), so code
edits need no rebuild, only a daemon restart (⟳ in the window, or
`systemctl --user restart rgbfx`). A rebuild is only needed when
`default.nix` changes (Python packages, launcher, GTK libraries).

Logs: `journalctl --user -u rgbfx -f`.

## Code

| File | What's in it |
|---|---|
| `rgbfx.py` | Entry point: the CLI, opens the window without arguments |
| `gui.py` | The GTK4 + libadwaita window and its live keyboard preview |
| `daemon.py` | The render loop and the openrazer output |
| `fans.py` | The OpenRGB output (case fans) |
| `case.py` | Where each case LED is, for the case preview |
| `effects.py` | Every effect and overlay |
| `inputs.py` | Background readers: keyboard (evdev), audio and mic (`pw-record`), screen (`gpu-screen-recorder` + `ffmpeg`), Hyprland (IPC sockets), CPU/temperature/mic, notifications (D-Bus) |
| `keymap.py` | Key → LED position on the 6×18 TKL matrix, and Hyprland key names → keys |
| `palette.py` | Caelestia colours made LED-friendly |
| `state.py` | Reading and writing `state.json` |

**Adding an effect**: write a class in `effects.py` with `@effect`, a `name`,
`title`, `category`, `description` and a `render(ctx)` that returns a 6×18×3
array of RGB floats in [0, 1]. Set `needs` to the inputs it uses. For an
overlay, use `@overlay` and `apply(frame, ctx)`, and add it to `ORDER`. Both
show up in the window and `rgbfx list` by themselves. **Then add it to this
README.**

To work on it: `nix develop ~/dotfiles#rgbfx`, then
`python tools/rgbfx/rgbfx.py`. To run your own daemon, stop the service
first (`systemctl --user stop rgbfx`).

## Troubleshooting

- **Nothing lights up**: is the daemon running (`systemctl --user status
  rgbfx`) and does openrazer see the keyboard (`polychromatic`)? Polychromatic
  and rgbfx fight over the keyboard: set effects in only one of them.
- **Fans don't follow**: is the OpenRGB server up (`systemctl status openrgb`)?
  The journal logs `openrgb: drawing on ...` once connected. Don't set the
  fans in the OpenRGB GUI at the same time: both draw on them.
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
