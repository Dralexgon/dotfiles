#!/usr/bin/env python3
"""installer-gui: install.sh in a window (GTK4 + libadwaita).

It runs `install.sh --gui-backend` and shows each of its questions as a page; the install
logic stays in install.sh. A question is one line on the script's stdout, "\\x1e" then a
JSON object, and the answer goes back on its stdin as one line:

  {"type": "text", "prompt", "default", "pattern"}    -> the text
  {"type": "password", "prompt"}                      -> the password (asked twice here)
  {"type": "yesno", "prompt", "default": "y" | "n"}   -> y or n
  {"type": "one", "title", "default", "options"}      -> the index of the option
  {"type": "many", "title", "options", "checked"}     -> one 0 / 1 per option, space separated

Everything else the script prints goes to the log at the bottom, and the lines printed
since the last question are shown above the next one (warnings, "already installed"...).
sudo asks for its password with `installer-gui --askpass` (SUDO_ASKPASS).

Usage: installer-gui DOTFILES_DIR [install.sh options] | installer-gui --askpass [PROMPT]
"""

import json
import os
import re
import sys
from pathlib import Path

APP_ID = "dev.dralexgon.Installer"
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def askpass_command():
    """An executable for SUDO_ASKPASS (it can't take arguments)."""
    if os.environ.get("INSTALLER_GUI_ASKPASS"):  # set by the nix wrapper
        return os.environ["INSTALLER_GUI_ASKPASS"]
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
    script = runtime / f"installer-gui-askpass-{os.getpid()}"
    script.write_text(f"#!/bin/sh\nexec '{sys.executable}' '{Path(__file__).resolve()}' --askpass \"$@\"\n")
    script.chmod(0o700)
    return str(script)


def main():
    import gi

    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gio, GLib, Gtk

    args = sys.argv[1:]

    # ---------------------------------------------------------------- askpass
    if args[:1] == ["--askpass"]:
        prompt = " ".join(args[1:]).strip() or "Password"
        app = Adw.Application(application_id=APP_ID + ".Askpass", flags=Gio.ApplicationFlags.NON_UNIQUE)
        result = {"code": 1}

        def activate(app):
            win = Adw.ApplicationWindow(application=app, title="Administrator password", default_width=420)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_top=24, margin_bottom=24,
                          margin_start=24, margin_end=24)
            box.append(Gtk.Label(label="The installer needs administrator rights (sudo).", wrap=True, xalign=0))
            group = Adw.PreferencesGroup()
            entry = Adw.PasswordEntryRow(title=re.sub(r"^\[sudo\]\s*", "", prompt).rstrip(": "))
            group.add(entry)
            box.append(group)
            buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END)
            cancel = Gtk.Button(label="Cancel")
            ok = Gtk.Button(label="OK")
            ok.add_css_class("suggested-action")
            buttons.append(cancel)
            buttons.append(ok)
            box.append(buttons)
            content = Adw.ToolbarView()
            content.add_top_bar(Adw.HeaderBar())
            content.set_content(box)
            win.set_content(content)

            def submit(*_):
                print(entry.get_text())
                result["code"] = 0
                win.close()

            ok.connect("clicked", submit)
            entry.connect("entry-activated", submit)
            cancel.connect("clicked", lambda *_: win.close())
            win.present()
            entry.grab_focus()

        app.connect("activate", activate)
        app.run(None)
        return result["code"]

    if not args or args[0].startswith("-"):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    dotfiles = Path(args[0]).resolve()
    script_args = args[1:]
    if not (dotfiles / "install.sh").is_file():
        print(f"{dotfiles}/install.sh not found", file=sys.stderr)
        return 1

    Spinner = getattr(Adw, "Spinner", None) or Gtk.Spinner

    # ---------------------------------------------------------------- window
    class Installer(Adw.Application):
        def __init__(self):
            super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.NON_UNIQUE)
            self.proc = None
            self.context = []  # lines printed since the last question
            self.next_steps = []
            self.connect("activate", lambda *_: self.build())

        def build(self):
            self.win = Adw.ApplicationWindow(application=self, title="Dotfiles installer",
                                             default_width=720, default_height=760)
            self.win.connect("close-request", self.on_close)

            self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.SLIDE_LEFT, vexpand=True)

            # the log, at the bottom of every page
            self.log = Gtk.TextView(editable=False, cursor_visible=False, monospace=True,
                                    wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=8, bottom_margin=8,
                                    left_margin=10, right_margin=10)
            self.log_end = self.log.get_buffer().create_mark("end", self.log.get_buffer().get_end_iter(), False)
            scroll = Gtk.ScrolledWindow(min_content_height=180, max_content_height=180, child=self.log)
            scroll.add_css_class("card")
            self.expander = Gtk.Expander(label="Details", child=scroll, margin_start=18, margin_end=18,
                                         margin_bottom=12)

            body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            body.append(self.stack)
            body.append(self.expander)
            view = Adw.ToolbarView()
            view.add_top_bar(Adw.HeaderBar())
            view.set_content(body)
            self.win.set_content(view)

            start = Gtk.Button(label="Start", halign=Gtk.Align.CENTER)
            start.add_css_class("pill")
            start.add_css_class("suggested-action")
            start.connect("clicked", lambda *_: self.start())
            self.show_page(Adw.StatusPage(
                icon_name="system-software-install-symbolic", title="Dralexgon's dotfiles",
                description=("This sets up these dotfiles on this machine: an optional test user, the "
                             "Caelestia desktop, a NixOS host configuration with the modules you pick, "
                             f"and links to your configs.\n\nFrom <tt>{GLib.markup_escape_text(str(dotfiles))}</tt>. "
                             "Nothing is applied to the system until you run nixos-rebuild at the end."),
                child=start))
            self.win.present()

        # ---- pages
        def show_page(self, widget):
            name = f"p{id(widget)}"
            old = self.stack.get_visible_child()
            self.stack.add_named(widget, name)
            self.stack.set_visible_child_name(name)
            if old is not None:
                GLib.timeout_add(400, lambda: (old.get_parent() and self.stack.remove(old)) and False)

        def page(self, title, description=None):
            """A question page: returns (page, content box, bottom button box)."""
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_top=24, margin_bottom=18,
                          margin_start=18, margin_end=18)
            heading = Gtk.Label(label=title, wrap=True, xalign=0)
            heading.add_css_class("title-2")
            box.append(heading)
            context = "\n".join(l for l in self.context if l.strip()).strip()
            self.context = []
            if context:
                note = Gtk.Label(label=context, wrap=True, xalign=0, selectable=True)
                note.add_css_class("dim-label")
                box.append(note)
            if description:
                desc = Gtk.Label(label=description, wrap=True, xalign=0)
                desc.add_css_class("dim-label")
                box.append(desc)
            content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            box.append(content)
            buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=6)
            box.append(buttons)
            clamp = Adw.Clamp(maximum_size=640, child=box)
            return Gtk.ScrolledWindow(child=clamp, hscrollbar_policy=Gtk.PolicyType.NEVER), content, buttons

        def working(self, text="Working…"):
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, valign=Gtk.Align.CENTER)
            spinner = Spinner(width_request=48, height_request=48, halign=Gtk.Align.CENTER)
            if hasattr(spinner, "start"):
                spinner.start()
            box.append(spinner)
            label = Gtk.Label(label=text)
            label.add_css_class("title-4")
            box.append(label)
            self.status_line = Gtk.Label(wrap=True, max_width_chars=70, justify=Gtk.Justification.CENTER)
            self.status_line.add_css_class("dim-label")
            box.append(self.status_line)
            self.show_page(box)

        # ---- the script
        def start(self):
            launcher = Gio.SubprocessLauncher.new(
                Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_MERGE)
            launcher.setenv("SUDO_ASKPASS", askpass_command(), True)
            launcher.set_cwd(str(dotfiles))
            self.proc = launcher.spawnv(["bash", str(dotfiles / "install.sh"), "--gui-backend", *script_args])
            self.stdin = self.proc.get_stdin_pipe()
            self.stdout = Gio.DataInputStream.new(self.proc.get_stdout_pipe())
            self.proc.wait_async(None, self.on_exit)
            self.working()
            self.read_line()

        def read_line(self):
            self.stdout.read_line_async(GLib.PRIORITY_DEFAULT, None, self.on_line)

        def on_line(self, stream, result):
            try:
                data, _ = stream.read_line_finish(result)
            except GLib.Error:
                data = None
            if data is None:
                return  # end of output; on_exit shows the result
            line = ANSI.sub("", bytes(data).decode("utf-8", "replace")).replace("\r", "")
            if line.startswith("\x1e"):
                try:
                    self.ask(json.loads(line[1:]))
                except ValueError as e:
                    self.add_log(f"[installer-gui] bad question: {e}: {line[1:]}")
                    self.answer("")
            else:
                self.add_log(line)
                self.context.append(line)
                if line.startswith("Apply it with:") or line.startswith("  sudo userdel"):
                    self.next_steps.append(line.split(":", 1)[-1].strip() if line.startswith("Apply") else line.strip())
                if getattr(self, "status_line", None):
                    self.status_line.set_text(line)
            self.read_line()

        def add_log(self, line):
            buf = self.log.get_buffer()
            buf.insert(buf.get_end_iter(), line + "\n")
            self.log.scroll_mark_onscreen(self.log_end)

        def answer(self, text):
            self.stdin.write_all(text.replace("\n", " ").encode() + b"\n", None)
            self.stdin.flush(None)
            self.working()

        def on_exit(self, proc, result):
            try:
                proc.wait_finish(result)
            except GLib.Error:
                pass
            # drain what's left of the output before the final page
            GLib.timeout_add(200, self.finished)

        def finished(self):
            ok = self.proc.get_if_exited() and self.proc.get_exit_status() == 0
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
            for step in self.next_steps:
                row = Gtk.Box(spacing=8)
                cmd = Gtk.Label(label=step, selectable=True, wrap=True, xalign=0, hexpand=True)
                cmd.add_css_class("monospace")
                copy = Gtk.Button(icon_name="edit-copy-symbolic", tooltip_text="Copy", valign=Gtk.Align.CENTER)
                copy.connect("clicked", lambda _b, s=step: self.win.get_clipboard().set(s))
                row.append(cmd)
                row.append(copy)
                box.append(row)
            close = Gtk.Button(label="Close", halign=Gtk.Align.CENTER, margin_top=12)
            close.add_css_class("pill")
            close.connect("clicked", lambda *_: self.win.close())
            box.append(close)
            if ok:
                page = Adw.StatusPage(icon_name="emblem-ok-symbolic", title="Installation complete",
                                      description="Next steps:" if self.next_steps else None, child=box)
            else:
                code = self.proc.get_exit_status() if self.proc.get_if_exited() else "a signal"
                page = Adw.StatusPage(icon_name="dialog-error-symbolic", title="The installer stopped",
                                      description=f"install.sh exited with {code}. The details are below.",
                                      child=box)
                self.expander.set_expanded(True)
            self.show_page(page)
            return False

        def on_close(self, *_):
            if self.proc and not self.proc.get_if_exited():
                self.proc.send_signal(15)
            return False

        # ---- questions
        def ask(self, q):
            kind = q.get("type")
            handler = {"text": self.ask_text, "password": self.ask_password, "yesno": self.ask_yesno,
                       "one": self.ask_one, "many": self.ask_many}.get(kind)
            if handler is None:
                self.add_log(f"[installer-gui] unknown question type {kind!r}")
                return self.answer("")
            handler(q)

        def continue_button(self, buttons, callback):
            button = Gtk.Button(label="Continue")
            button.add_css_class("suggested-action")
            button.add_css_class("pill")
            button.connect("clicked", lambda *_: callback())
            buttons.append(button)
            return button

        def ask_text(self, q):
            page, content, buttons = self.page(q.get("prompt", ""))
            group = Adw.PreferencesGroup()
            entry = Adw.EntryRow(title=q.get("prompt", ""), text=q.get("default") or "")
            group.add(entry)
            content.append(group)
            pattern = q.get("pattern") or ""
            hint = Gtk.Label(xalign=0, wrap=True)
            hint.add_css_class("error")
            content.append(hint)
            button = self.continue_button(buttons, lambda: self.answer(entry.get_text()))

            def check(*_):
                text = entry.get_text()
                good = bool(text) and (not pattern or re.fullmatch(pattern, text) is not None)
                button.set_sensitive(good)
                hint.set_text("" if good or not text else "Letters, digits, - and _ only"
                              if "a-zA-Z" in pattern else f"Expected something like {q.get('default') or pattern}")
                (entry.remove_css_class if good or not text else entry.add_css_class)("error")

            entry.connect("changed", check)
            entry.connect("entry-activated", lambda *_: button.get_sensitive() and button.emit("clicked"))
            check()
            self.show_page(page)
            entry.grab_focus()

        def ask_password(self, q):
            page, content, buttons = self.page(q.get("prompt", "Password"))
            group = Adw.PreferencesGroup()
            first = Adw.PasswordEntryRow(title="Password")
            second = Adw.PasswordEntryRow(title="Confirm password")
            group.add(first)
            group.add(second)
            content.append(group)
            hint = Gtk.Label(xalign=0)
            hint.add_css_class("error")
            content.append(hint)
            button = self.continue_button(buttons, lambda: self.answer(first.get_text()))

            def check(*_):
                a, b = first.get_text(), second.get_text()
                button.set_sensitive(bool(a) and a == b)
                hint.set_text("The passwords don't match" if b and a != b else "")

            first.connect("changed", check)
            second.connect("changed", check)
            second.connect("entry-activated", lambda *_: button.get_sensitive() and button.emit("clicked"))
            check()
            self.show_page(page)
            first.grab_focus()

        def ask_yesno(self, q):
            page, content, buttons = self.page(q.get("prompt", ""))
            yes = Gtk.Button(label="Yes")
            no = Gtk.Button(label="No")
            for b in (no, yes):
                b.add_css_class("pill")
                buttons.append(b)
            default = yes if q.get("default") == "y" else no
            default.add_css_class("suggested-action")
            yes.connect("clicked", lambda *_: self.answer("y"))
            no.connect("clicked", lambda *_: self.answer("n"))
            self.show_page(page)
            default.grab_focus()

        def ask_one(self, q):
            page, content, buttons = self.page(q.get("title", ""))
            group = Adw.PreferencesGroup()
            checks, leader = [], None
            for i, option in enumerate(q.get("options", [])):
                check = Gtk.CheckButton(group=leader, active=(i == q.get("default", 0)))
                leader = leader or check
                row = Adw.ActionRow(title=GLib.markup_escape_text(option), activatable_widget=check)
                row.add_prefix(check)
                group.add(row)
                checks.append(check)
            content.append(group)
            self.continue_button(
                buttons, lambda: self.answer(str(next((i for i, c in enumerate(checks) if c.get_active()), 0))))
            self.show_page(page)
            (checks[q.get("default", 0)] if checks else buttons).grab_focus()

        def ask_many(self, q):
            page, content, buttons = self.page(q.get("title", ""))
            group = Adw.PreferencesGroup()
            toggle = Gtk.Button(label="Select all", valign=Gtk.Align.CENTER)
            toggle.add_css_class("flat")
            group.set_header_suffix(toggle)
            checks = []
            checked = q.get("checked", [])
            for i, option in enumerate(q.get("options", [])):
                check = Gtk.CheckButton(active=bool(checked[i]) if i < len(checked) else False)
                row = Adw.ActionRow(title=GLib.markup_escape_text(option), activatable_widget=check)
                row.add_prefix(check)
                group.add(row)
                checks.append(check)
            content.append(group)

            def sync(*_):
                toggle.set_label("Select none" if checks and all(c.get_active() for c in checks) else "Select all")

            def toggle_all(*_):
                value = not all(c.get_active() for c in checks)
                for c in checks:
                    c.set_active(value)

            for c in checks:
                c.connect("toggled", sync)
            toggle.connect("clicked", toggle_all)
            sync()
            button = self.continue_button(
                buttons, lambda: self.answer(" ".join("1" if c.get_active() else "0" for c in checks)))
            self.show_page(page)
            button.grab_focus()

    return Installer().run(None)


if __name__ == "__main__":
    sys.exit(main())
