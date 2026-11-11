"""The razerfx TUI: pick an effect, toggle overlays, tune brightness and speed.

It only edits state.json; the daemon picks changes up within a frame.
"""

import json
import subprocess
import time

from rich.text import Text
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.theme import Theme
from textual.widgets import Footer, Label, OptionList, SelectionList, Static
from textual.widgets.option_list import Option
from textual.widgets.selection_list import Selection

import effects
import state
from palette import SCHEME


def caelestia_theme() -> Theme | None:
    """The Caelestia colours, like nixcfg."""
    try:
        scheme = json.loads(SCHEME.read_text())
        c = {k: f"#{v}" for k, v in scheme["colours"].items()}
        return Theme(
            name="caelestia",
            dark=scheme.get("mode", "dark") == "dark",
            primary=c["primary"],
            secondary=c["secondary"],
            accent=c["tertiary"],
            error=c["error"],
            warning=c.get("term3", c["tertiary"]),
            success=c.get("term2", c["secondary"]),
            foreground=c["onSurface"],
            background=c["background"],
            surface=c["surfaceContainerLow"],
            panel=c["surfaceContainer"],
        )
    except (OSError, KeyError, ValueError, AttributeError):
        return None


def daemon_status() -> str:
    try:
        return subprocess.run(["systemctl", "--user", "is-active", "razerfx"],
                              capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "unknown"


class RazerFX(App):
    TITLE = "razerfx"
    CSS = """
    Screen { layout: vertical; }
    #main { height: 1fr; }
    #effects { width: 34; height: 1fr; border: round $primary; border-title-color: $primary; }
    #side { width: 1fr; }
    #description { height: auto; min-height: 5; padding: 0 1; border: round $secondary;
                   border-title-color: $secondary; }
    #overlays { height: 1fr; border: round $accent; border-title-color: $accent; }
    #settings { width: 100%; height: auto; padding: 0 1; border: round $panel-lighten-2; }
    """

    BINDINGS = [
        Binding("q", "quit", "Quit"),
        Binding("tab", "focus_next", "Switch pane", show=False),
        Binding("plus,equals_sign", "brightness(10)", "Brighter"),
        Binding("minus", "brightness(-10)", "Dimmer"),
        Binding("right_square_bracket", "speed(1.25)", "Faster"),
        Binding("left_square_bracket", "speed(0.8)", "Slower"),
        Binding("p", "pomodoro", "Pomodoro"),
        Binding("f", "flash", "Test flash"),
        Binding("r", "restart", "Restart daemon"),
    ]

    def compose(self) -> ComposeResult:
        options, category = [], None
        for name, cls in effects.EFFECTS.items():
            if cls.category != category:
                if category is not None:
                    options.append(None)  # separator
                category = cls.category
                options.append(Option(f"[b]{category}[/b]", disabled=True))
            options.append(Option(cls.title, id=name))
        with Horizontal(id="main"):
            effect_list = OptionList(*options, id="effects")
            effect_list.border_title = "Effect (Enter)"
            yield effect_list
            with Vertical(id="side"):
                desc = Static(id="description")
                desc.border_title = "About"
                yield desc
                overlays = SelectionList(
                    *[Selection(effects.OVERLAYS[n].title, n) for n in effects.ORDER],
                    id="overlays",
                )
                overlays.border_title = "Overlays (Space)"
                yield overlays
                yield Label(id="settings")
        yield Footer()

    def on_mount(self) -> None:
        theme = caelestia_theme()
        if theme:
            self.register_theme(theme)
            self.theme = "caelestia"
        self.mtime = None
        self.daemon = daemon_status()
        self.syncing = False
        self.reload()
        self.query_one("#effects").focus()
        self.set_interval(0.5, self.reload)
        self.set_interval(1, self.show_settings)
        self.set_interval(3, self.check_daemon)

    # State -> widgets

    def reload(self) -> None:
        if state.mtime() == self.mtime:
            return
        self.mtime = state.mtime()
        self.settings = state.load()
        effect_list = self.query_one("#effects", OptionList)
        for i in range(effect_list.option_count):
            opt = effect_list.get_option_at_index(i)
            if opt.id:
                cls = effects.EFFECTS[opt.id]
                mark = "● " if opt.id == self.settings["effect"] else "  "
                effect_list.replace_option_prompt(opt.id, mark + cls.title)
                if opt.id == self.settings["effect"] and effect_list.highlighted is None:
                    effect_list.highlighted = i
        self.syncing = True
        overlays = self.query_one("#overlays", SelectionList)
        for name in effects.ORDER:
            if name in self.settings["overlays"]:
                overlays.select(name)
            else:
                overlays.deselect(name)
        self.syncing = False
        self.show_settings()

    def show_settings(self) -> None:
        s = self.settings
        parts = [
            ("Daemon", self.daemon),
            ("Brightness", f"{round(s['brightness'] * 100)}%"),
            ("Speed", f"{s['speed']:.2f}x"),
        ]
        if pomo := s.get("pomodoro"):
            left = pomo["start"] + pomo["minutes"] * 60 - time.time()
            parts.append(("Pomodoro", f"{int(left // 60)}:{int(left % 60):02d}" if left > 0 else "done!"))
        text = Text()
        for i, (name, value) in enumerate(parts):
            text.append(("  ·  " if i else "") + f"{name}: ")
            text.append(value, style="bold")
        self.query_one("#settings", Label).update(text)

    def check_daemon(self) -> None:
        self.daemon = daemon_status()

    # Widgets -> state

    def on_option_list_option_highlighted(self, event: OptionList.OptionHighlighted) -> None:
        cls = effects.EFFECTS.get(event.option.id or "")
        if cls:
            self.query_one("#description", Static).update(f"[b]{cls.title}[/b]\n{cls.description}")

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        if event.option.id:
            state.update(effect=event.option.id)
            self.reload()

    def on_selection_list_selection_highlighted(self, event: SelectionList.SelectionHighlighted) -> None:
        cls = effects.OVERLAYS[event.selection.value]
        self.query_one("#description", Static).update(f"[b]{cls.title}[/b] (overlay)\n{cls.description}")

    def on_selection_list_selected_changed(self, event: SelectionList.SelectedChanged) -> None:
        if not self.syncing:
            state.update(overlays=list(event.selection_list.selected))

    def action_brightness(self, delta: int) -> None:
        b = state.load()["brightness"]
        state.update(brightness=round(min(1.0, max(0.0, b + delta / 100)), 2))
        self.reload()

    def action_speed(self, factor: float) -> None:
        s = state.load()["speed"]
        state.update(speed=round(min(5.0, max(0.1, s * factor)), 2))
        self.reload()

    def action_pomodoro(self) -> None:
        s = state.load()
        pomo = s["pomodoro"]
        if pomo and time.time() < pomo["start"] + pomo["minutes"] * 60:
            state.update(pomodoro=None)
            self.notify("Pomodoro stopped")
        else:
            overlays = s["overlays"] + ["pomodoro"] * ("pomodoro" not in s["overlays"])
            state.update(pomodoro={"start": time.time(), "minutes": 25}, overlays=overlays)
            self.notify("Pomodoro: 25 minutes")
        self.reload()

    def action_flash(self) -> None:
        state.flash()

    def action_restart(self) -> None:
        subprocess.run(["systemctl", "--user", "restart", "razerfx"])
        self.daemon = daemon_status()
        self.notify(f"Daemon {self.daemon}")


def main():
    RazerFX().run()
