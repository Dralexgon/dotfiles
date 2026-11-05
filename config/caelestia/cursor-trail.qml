// Mouse pointer trail: a click-through overlay that draws a fading line behind the pointer.
// Run with: quickshell -p ~/.config/caelestia/cursor-trail.qml
// TODO: make this a Hyprland plugin (see README)
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property int lifeMs: 220          // how long a trail point lives
    readonly property real maxWidth: 8
    readonly property int maxPoints: 64        // polling at 125 Hz keeps ~28 points alive
    property color trailColor: "#f5c2e7"       // replaced by the Caelestia scheme primary
    property var points: []                    // [{x, y, t}] in global layout coords
    property real lastX: NaN
    property real lastY: NaN
    property real now: Date.now()

    // Follow the Caelestia colour scheme
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/caelestia/scheme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.trailColor = "#" + JSON.parse(text()).colours.primary;
            } catch (e) {}
        }
    }

    // Hyprland has no pointer-move event, so poll the position. Asking the socket directly
    // instead of forking hyprctl (~20 ms each) keeps the trail close to the pointer.
    // Hyprland answers one request per connection, so reconnect on every tick.
    Socket {
        id: hypr
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + "/.socket.sock"
        onConnectedChanged: {
            if (connected) {
                write("cursorpos");
                flush();
            }
        }
        parser: SplitParser {
            splitMarker: ""                    // the reply has no trailing newline
            onRead: data => {
                const [x, y] = data.split(",").map(Number);
                if (isNaN(x) || isNaN(y))
                    return;
                // Compare with the last polled position, not the last point: points expire,
                // and a still pointer must not keep re-adding itself (and repainting)
                if (x === root.lastX && y === root.lastY)
                    return;
                root.lastX = x;
                root.lastY = y;
                root.now = Date.now();
                root.points = root.points.concat({ x, y, t: root.now }).slice(-root.maxPoints);
            }
        }
    }

    Timer {
        interval: 8
        running: true
        repeat: true
        onTriggered: if (!hypr.connected) hypr.connected = true
    }

    // Age the trail and drop expired points once per frame
    FrameAnimation {
        running: root.points.length > 0
        onTriggered: {
            root.now = Date.now();
            if (root.now - root.points[0].t > root.lifeMs)
                root.points = root.points.filter(p => root.now - p.t <= root.lifeMs);
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "cursor-trail"
            mask: Region {}                    // click-through

            // One rounded rectangle per segment, drawn by the GPU scene graph
            // (a full-screen Canvas costs ~170% CPU at 4K while the pointer moves)
            Repeater {
                model: root.maxPoints - 1

                Rectangle {
                    required property int index
                    readonly property var a: root.points[index]
                    readonly property var b: root.points[index + 1]
                    readonly property real life: b ? 1 - (root.now - b.t) / root.lifeMs : 0
                    readonly property real dx: b ? b.x - a.x : 0
                    readonly property real dy: b ? b.y - a.y : 0

                    visible: life > 0
                    // Centred on the segment and one height longer, so the radius gives round caps
                    width: Math.hypot(dx, dy) + height
                    height: Math.max(root.maxWidth * life, 1)
                    x: b ? (a.x + b.x) / 2 - win.modelData.x - width / 2 : 0
                    y: b ? (a.y + b.y) / 2 - win.modelData.y - height / 2 : 0
                    rotation: Math.atan2(dy, dx) * 180 / Math.PI
                    radius: height / 2
                    antialiasing: true
                    color: root.trailColor
                    opacity: life
                }
            }
        }
    }
}
