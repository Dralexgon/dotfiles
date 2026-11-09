"""The viewer in its own window: GTK4 + WebKitGTK showing the same page as the browser version.

One instance only (Gtk.Application): launching it again while it is open reloads the binds and
brings the window up, or closes it when it already has the focus, so SUPER + / toggles it.
Escape (when the page has nothing to clear), Ctrl + W and Ctrl + Q close it.
"""

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("WebKit", "6.0")
from gi.repository import Gio, Gtk, WebKit  # noqa: E402

APP_ID = "dev.dralexgon.KeybindsViewer"  # also the Wayland app id, matched by the Hyprland window rule


class Viewer(Gtk.Application):
    def __init__(self, build_page):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.build_page = build_page  # () -> path of a freshly generated page
        self.window = None
        self.view = None

    def do_activate(self):
        if self.window and self.window.is_active():
            self.window.close()
            return
        uri = self.build_page().as_uri()
        if not self.window:
            self.window = self.make_window()
            self.view.load_uri(uri)
        else:
            self.view.load_uri(uri)  # fresh binds (config reloaded since?)
        self.window.present()

    def make_window(self):
        win = Gtk.ApplicationWindow(application=self, title="Keybinds")
        win.set_default_size(1500, 1000)

        content = WebKit.UserContentManager()
        content.register_script_message_handler("kbv", None)
        content.connect("script-message-received::kbv", lambda _m, value: self.on_message(value.to_string()))
        self.view = WebKit.WebView(user_content_manager=content)
        settings = self.view.get_settings()
        settings.set_allow_file_access_from_file_urls(True)
        settings.set_enable_developer_extras(True)  # right click > Inspect
        self.view.connect("decide-policy", self.on_policy)
        win.set_child(self.view)

        close = Gtk.ShortcutController(scope=Gtk.ShortcutScope.GLOBAL)
        for accel in ("<Control>w", "<Control>q"):
            close.add_shortcut(Gtk.Shortcut(trigger=Gtk.ShortcutTrigger.parse_string(accel),
                                            action=Gtk.CallbackAction.new(lambda *_: win.close() or True)))
        win.add_controller(close)
        return win

    def on_message(self, message):
        if message == "close" and self.window:
            self.window.close()

    @staticmethod
    def on_policy(_view, decision, kind):
        # links leave for the real browser instead of replacing the page
        if kind == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION:
            Gtk.show_uri(None, decision.get_navigation_action().get_request().get_uri(), 0)
            decision.ignore()
            return True
        return False


def run(build_page):
    return Viewer(build_page).run(None)
