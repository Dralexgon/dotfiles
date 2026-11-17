// bat-swarm: a cloud of bats flying across every screen, the transition of the vampire rice:
// set_rice() (config/caelestia/hypr-user.lua) plays it while the colours and the wallpaper change.
// A click-through overlay layer: it never takes the keyboard or the mouse, and quits by itself.
//
// Environment (set by the bat-swarm wrapper, tools/bat-swarm/default.nix):
//   BAT_SWARM_SVG   the bat shape, themes/assets/simple-bat.svg ("Bat" by Skoll, CC BY 3.0)
// Try it: bat-swarm
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // How long the swarm lasts (ms): bats leave over the first `spread`, each crossing in `flight`
    readonly property int spread: 1500
    readonly property int flightMin: 1300
    readonly property int flightMax: 2300
    readonly property int lifetime: spread + flightMax + 200

    // body: the silhouette; glow: a thin crimson halo so the bats show on dark wallpapers too
    readonly property var look: ({ body: "#0a0506", glow: "#b0001e" })

    // The `d` of the svg path, read once (the file is a single <path>, viewBox 0 0 512 512)
    FileView {
        id: svgFile
        path: Quickshell.env("BAT_SWARM_SVG") || Qt.resolvedUrl("../../themes/assets/simple-bat.svg")
        blockLoading: true
    }
    readonly property string batPath: {
        const m = svgFile.text().match(/\sd="([^"]+)"/);
        return m ? m[1] : "";
    }

    Timer {
        running: true
        interval: root.lifetime
        onTriggered: Qt.quit()
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
            WlrLayershell.namespace: "bat-swarm"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region {} // empty input region: clicks go through to the windows below

            // Wider screens get more bats; they all fly the same way across one run
            readonly property int count: Math.round(Math.max(50, Math.min(150, width / 15)))
            readonly property bool leftToRight: Math.random() < 0.5

            Repeater {
                model: root.batPath ? win.count : 0

                Item {
                    id: bat

                    // depth 0 = far (small, faint, slow), 1 = near (big, dark, fast)
                    readonly property real depth: Math.pow(Math.random(), 1.6)
                    readonly property real size: 30 + depth * 120
                    readonly property int delay: Math.round(Math.pow(Math.random(), 0.8) * root.spread)
                    readonly property int flight: root.flightMax - depth * (root.flightMax - root.flightMin)
                    // A slight climb or dive, and a wavy path on top of it
                    readonly property real startY: win.height * (0.05 + Math.random() * 0.9)
                    readonly property real climb: (Math.random() - 0.6) * win.height * 0.35
                    readonly property real waveAmp: 10 + Math.random() * 35
                    readonly property real waves: 1 + Math.random() * 2.5
                    readonly property real phase: Math.random() * Math.PI * 2
                    readonly property int flapMs: 150 + Math.random() * 110 - depth * 50

                    property real t: 0 // 0 → 1 along the flight

                    width: size
                    height: size
                    opacity: t > 0 ? 0.55 + depth * 0.45 : 0
                    z: depth
                    x: {
                        const from = -size, to = win.width + size;
                        return win.leftToRight ? from + (to - from) * t : to - (to - from) * t;
                    }
                    y: startY + climb * t + waveAmp * Math.sin(phase + t * waves * 2 * Math.PI) - size / 2
                    // tilt into the climb, mirror when flying right to left
                    rotation: (win.leftToRight ? 1 : -1) * climb / win.height * -25

                    NumberAnimation on t {
                        from: 0; to: 1
                        duration: bat.flight
                        // starts at once: the delay is a PauseAnimation below
                        running: false
                        id: fly
                    }
                    SequentialAnimation {
                        running: true
                        PauseAnimation { duration: bat.delay }
                        ScriptAction { script: fly.start() }
                    }

                    // The wings: the shape folded up and down around the body (scale y through 0)
                    Item {
                        id: wings
                        anchors.fill: parent
                        transform: Scale {
                            id: flap
                            origin.x: wings.width / 2
                            origin.y: wings.height * 0.47
                            yScale: 1
                            xScale: 0.82 + 0.18 * Math.abs(yScale)
                        }

                        SequentialAnimation {
                            running: bat.t > 0
                            loops: Animation.Infinite
                            NumberAnimation { target: flap; property: "yScale"; from: 1; to: -0.55; duration: bat.flapMs * 0.45; easing.type: Easing.InQuad }
                            NumberAnimation { target: flap; property: "yScale"; from: -0.55; to: 1; duration: bat.flapMs * 0.55; easing.type: Easing.OutQuad }
                        }

                        // halo, then the silhouette on top
                        Repeater {
                            model: [
                                { colour: root.look.glow, grow: 1.12, alpha: 0.28 + bat.depth * 0.25 },
                                { colour: root.look.body, grow: 1.0, alpha: 1.0 }
                            ]
                            Shape {
                                required property var modelData
                                anchors.centerIn: parent
                                width: parent.width
                                height: parent.height
                                scale: modelData.grow
                                opacity: modelData.alpha
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: modelData.colour
                                    strokeColor: "transparent"
                                    scale: Qt.size(bat.size / 512, bat.size / 512)
                                    PathSvg { path: root.batPath }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
