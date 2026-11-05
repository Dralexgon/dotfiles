"""razerfx: effects for the Razer keyboard, picked from a TUI or the command line.

    razerfx                     open the TUI
    razerfx daemon              run the render loop (the razerfx systemd user service)
    razerfx list                list effects and overlays
    razerfx status              show the current settings
    razerfx set <effect>        switch effect
    razerfx overlay <name> [on|off|toggle]
    razerfx brightness <0-100>
    razerfx speed <multiplier>  e.g. 0.5, 1, 2
    razerfx pomodoro [minutes|stop]
    razerfx flash [colour]      pulse the keyboard (primary, discord, red, #ff00aa...)
"""

import sys
import time

import effects
import state


def usage(code=1):
    print(__doc__.strip())
    sys.exit(code)


def cmd_list():
    print("Effects:")
    for name, cls in effects.EFFECTS.items():
        print(f"  {name:<14} {cls.category:<9} {cls.title}")
    print("Overlays:")
    for name in effects.ORDER:
        print(f"  {name:<14} {effects.OVERLAYS[name].title}")


def cmd_status():
    s = state.load()
    print(f"effect:     {s['effect']}")
    print(f"overlays:   {', '.join(s['overlays']) or '-'}")
    print(f"brightness: {round(s['brightness'] * 100)}%")
    print(f"speed:      {s['speed']}x")
    if pomo := s["pomodoro"]:
        left = pomo["start"] + pomo["minutes"] * 60 - time.time()
        print(f"pomodoro:   {max(0, left) / 60:.1f} min left")


def main(argv):
    if not argv:
        import tui

        return tui.main()
    cmd, args = argv[0], argv[1:]
    if cmd in ("-h", "--help", "help"):
        usage(0)
    elif cmd == "daemon":
        import daemon

        daemon.run()
    elif cmd == "list":
        cmd_list()
    elif cmd == "status":
        cmd_status()
    elif cmd == "set" and len(args) == 1:
        if args[0] not in effects.EFFECTS:
            sys.exit(f"unknown effect {args[0]!r} (see razerfx list)")
        state.update(effect=args[0])
    elif cmd == "overlay" and len(args) in (1, 2):
        name, mode = args[0], (args[1] if len(args) == 2 else "toggle")
        if name not in effects.OVERLAYS or mode not in ("on", "off", "toggle"):
            usage()
        enabled = state.load()["overlays"]
        on = (name not in enabled) if mode == "toggle" else mode == "on"
        enabled = [o for o in enabled if o != name] + ([name] if on else [])
        state.update(overlays=enabled)
    elif cmd == "brightness" and len(args) == 1:
        state.update(brightness=max(0, min(100, float(args[0]))) / 100)
    elif cmd == "speed" and len(args) == 1:
        state.update(speed=max(0.1, min(5.0, float(args[0]))))
    elif cmd == "pomodoro" and len(args) <= 1:
        if args and args[0] == "stop":
            state.update(pomodoro=None)
        else:
            minutes = float(args[0]) if args else 25
            enabled = state.load()["overlays"]
            state.update(pomodoro={"start": time.time(), "minutes": minutes},
                         overlays=enabled + ["pomodoro"] * ("pomodoro" not in enabled))
    elif cmd == "flash" and len(args) <= 1:
        state.flash(args[0] if args else None)
    else:
        usage()


if __name__ == "__main__":
    main(sys.argv[1:])
