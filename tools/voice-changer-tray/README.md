# voice-changer-tray

A tray icon for the voice changer ([Applio](https://github.com/IAHispano/Applio), packaged in [Dralexgon/nix-voice-changer](https://github.com/Dralexgon/nix-voice-changer)).
Start it from the app launcher ("Voice Changer") or with `voice-changer-tray`: it runs Applio in the background and shows an icon while it runs.

| Menu | Does |
|---|---|
| Open web UI | opens the Applio page (http://127.0.0.1:6969) |
| Show logs | Applio's output, live, in kitty |
| Quit | stops Applio, the icon goes away |

The icon shows a low microphone while Applio starts, then a normal one once the web UI answers.
Starting it again while it runs only opens the web UI. The logs are in `~/.local/state/voice-changer/applio.log`.

## Files

| File | Role |
|---|---|
| `tray.py` | the tray icon (GTK3 + Ayatana AppIndicator) |
| `default.nix` | the `voice-changer-tray` command + launcher entry, installed by `nixos/core.nix` |

`applio` itself comes from `programs.voice-changer` (the nix-voice-changer flake), not from here.
