// One cherry blossom petal: rounded, with the little notch at its tip.
// The base is at the bottom (y = height), the tip at the top (y = 0).
// Copied into Caelestia's modules/lock by nixos/modules/caelestia.nix.
import QtQuick
import QtQuick.Shapes

Shape {
    id: root

    property color colour: "#FFA8CF"
    // Horizontal scale, -1..1: a petal tumbling in the air shows its edge (0) and its back (< 0)
    property real flip: 1

    readonly property real w: width
    readonly property real h: height

    implicitWidth: 16
    implicitHeight: 18
    preferredRendererType: Shape.CurveRenderer

    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: root.flip
    }

    ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillGradient: LinearGradient {
            x1: root.width / 2
            y1: root.height
            x2: root.width / 2
            y2: 0

            GradientStop {
                position: 0
                color: Qt.darker(root.colour, 1.35)
            }
            // The back of the petal is a little darker
            GradientStop {
                position: 0.5
                color: root.flip < 0 ? Qt.darker(root.colour, 1.15) : root.colour
            }
            GradientStop {
                position: 1
                color: Qt.lighter(root.colour, 1.12)
            }
        }

        startX: root.w / 2
        startY: root.h

        PathCubic {
            control1X: root.w * 0.06
            control1Y: root.h * 0.85
            control2X: 0
            control2Y: root.h * 0.55
            x: root.w * 0.02
            y: root.h * 0.32
        }
        PathCubic {
            control1X: root.w * 0.04
            control1Y: root.h * 0.1
            control2X: root.w * 0.22
            control2Y: 0
            x: root.w * 0.4
            y: root.h * 0.02
        }
        PathLine {
            x: root.w / 2
            y: root.h * 0.15
        }
        PathLine {
            x: root.w * 0.6
            y: root.h * 0.02
        }
        PathCubic {
            control1X: root.w * 0.78
            control1Y: 0
            control2X: root.w * 0.96
            control2Y: root.h * 0.1
            x: root.w * 0.98
            y: root.h * 0.32
        }
        PathCubic {
            control1X: root.w
            control1Y: root.h * 0.55
            control2X: root.w * 0.94
            control2Y: root.h * 0.85
            x: root.w / 2
            y: root.h
        }
    }
}
