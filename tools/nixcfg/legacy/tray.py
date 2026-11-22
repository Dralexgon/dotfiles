"""A tray icon for nixcfg (StatusNotifierItem over D-Bus, like Discord's).

It shows while nixcfg runs in the background: clicking it opens the window,
and its menu (on hover in Caelestia) can open or quit nixcfg. It runs in its
own thread and event loop, so it keeps answering while the app is suspended
for an update or rebuild.
"""

import asyncio
import os
import threading
from typing import Callable

from dbus_fast import BusType, PropertyAccess, Variant
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, dbus_property, method, signal

ICON = "nix-snowflake"
WATCHER = "org.kde.StatusNotifierWatcher"

# Menu item ids (0 is the root).
OPEN, STATUS, SEPARATOR, QUIT = 1, 2, 3, 4


class Item(ServiceInterface):
    def __init__(self, tray: "Tray") -> None:
        super().__init__("org.kde.StatusNotifierItem")
        self.tray = tray

    @dbus_property(access=PropertyAccess.READ)
    def Category(self) -> "s":
        return "SystemServices"

    @dbus_property(access=PropertyAccess.READ)
    def Id(self) -> "s":
        return "nixcfg"

    @dbus_property(access=PropertyAccess.READ)
    def Title(self) -> "s":
        return "nixcfg"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return "Active"

    @dbus_property(access=PropertyAccess.READ)
    def IconName(self) -> "s":
        return ICON

    @dbus_property(access=PropertyAccess.READ)
    def IconPixmap(self) -> "a(iiay)":
        return []

    @dbus_property(access=PropertyAccess.READ)
    def ToolTip(self) -> "(sa(iiay)ss)":
        return [ICON, [], "nixcfg", self.tray.busy or "Running in the background"]

    @dbus_property(access=PropertyAccess.READ)
    def ItemIsMenu(self) -> "b":
        return False

    @dbus_property(access=PropertyAccess.READ)
    def Menu(self) -> "o":
        return "/MenuBar"

    @method()
    def Activate(self, x: "i", y: "i"):
        self.tray.on_open()

    @method()
    def SecondaryActivate(self, x: "i", y: "i"):
        self.tray.on_open()

    @method()
    def ContextMenu(self, x: "i", y: "i"):
        pass

    @method()
    def Scroll(self, delta: "i", orientation: "s"):
        pass

    @signal()
    def NewToolTip(self):
        pass


class Menu(ServiceInterface):
    """The smallest com.canonical.dbusmenu: a flat list of items."""

    def __init__(self, tray: "Tray") -> None:
        super().__init__("com.canonical.dbusmenu")
        self.tray = tray
        self.revision = 1

    def items(self) -> dict[int, dict[str, Variant]]:
        busy = self.tray.busy
        return {
            OPEN: {"label": Variant("s", "Open nixcfg")},
            STATUS: {"label": Variant("s", busy or ""), "enabled": Variant("b", False),
                     "visible": Variant("b", bool(busy))},
            SEPARATOR: {"type": Variant("s", "separator")},
            # Quitting would kill the running command: wait for it.
            QUIT: {"label": Variant("s", "Quit nixcfg"), "enabled": Variant("b", not busy)},
        }

    def props(self, item: int) -> dict[str, Variant]:
        if item == 0:
            return {"children-display": Variant("s", "submenu")}
        return self.items().get(item, {})

    @dbus_property(access=PropertyAccess.READ)
    def Version(self) -> "u":
        return 3

    @dbus_property(access=PropertyAccess.READ)
    def TextDirection(self) -> "s":
        return "ltr"

    @dbus_property(access=PropertyAccess.READ)
    def Status(self) -> "s":
        return "normal"

    @dbus_property(access=PropertyAccess.READ)
    def IconThemePath(self) -> "as":
        return []

    @method()
    def GetLayout(self, parent: "i", depth: "i", names: "as") -> "u(ia{sv}av)":
        children = [] if parent != 0 or depth == 0 else [
            Variant("(ia{sv}av)", [i, props, []]) for i, props in self.items().items()
        ]
        return [self.revision, [parent, self.props(parent), children]]

    @method()
    def GetGroupProperties(self, ids: "ai", names: "as") -> "a(ia{sv})":
        return [[i, self.props(i)] for i in (ids or [0, *self.items()])]

    @method()
    def GetProperty(self, item: "i", name: "s") -> "v":
        return self.props(item).get(name, Variant("s", ""))

    @method()
    def Event(self, item: "i", event: "s", data: "v", timestamp: "u"):
        if event == "clicked":
            self.clicked(item)

    @method()
    def EventGroup(self, events: "a(isvu)") -> "ai":
        for item, event, _, _ in events:
            if event == "clicked":
                self.clicked(item)
        return []

    @method()
    def AboutToShow(self, item: "i") -> "b":
        return False

    @method()
    def AboutToShowGroup(self, ids: "ai") -> "aiai":
        return [[], []]

    @signal()
    def LayoutUpdated(self) -> "ui":
        return [self.revision, 0]

    def clicked(self, item: int) -> None:
        if item == OPEN:
            self.tray.on_open()
        elif item == QUIT and not self.tray.busy:
            self.tray.on_quit()


class Tray:
    def __init__(self, on_open: Callable[[], None], on_quit: Callable[[], None]) -> None:
        self.on_open = on_open
        self.on_quit = on_quit
        self.busy = ""  # what is running, shown in the tooltip and the menu
        self.loop: asyncio.AbstractEventLoop | None = None

    def start(self) -> None:
        threading.Thread(target=lambda: asyncio.run(self.main()), daemon=True).start()

    def set_busy(self, text: str) -> None:
        """Safe to call from any thread."""
        if self.loop:
            self.loop.call_soon_threadsafe(self.update, text)

    def update(self, text: str) -> None:
        self.busy = text
        self.item.NewToolTip()
        self.menu.revision += 1
        self.menu.LayoutUpdated()

    async def main(self) -> None:
        self.loop = asyncio.get_running_loop()
        bus = await MessageBus(bus_type=BusType.SESSION).connect()
        self.item, self.menu = Item(self), Menu(self)
        bus.export("/StatusNotifierItem", self.item)
        bus.export("/MenuBar", self.menu)
        name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
        await bus.request_name(name)

        async def register() -> None:
            try:
                node = await bus.introspect(WATCHER, "/StatusNotifierWatcher")
                watcher = bus.get_proxy_object(WATCHER, "/StatusNotifierWatcher", node)
                await watcher.get_interface(WATCHER).call_register_status_notifier_item(name)
            except Exception:
                pass  # no tray yet: registered when one starts

        # Register again whenever the tray restarts (e.g. Caelestia reloads).
        node = await bus.introspect("org.freedesktop.DBus", "/org/freedesktop/DBus")
        dbus = bus.get_proxy_object("org.freedesktop.DBus", "/org/freedesktop/DBus", node)
        dbus.get_interface("org.freedesktop.DBus").on_name_owner_changed(
            lambda owner, old, new: owner == WATCHER and new and
            asyncio.ensure_future(register())
        )
        await register()
        await bus.wait_for_disconnect()
