// One blood drip hanging from the top edge: it grows, lets a drop go,
// the drop falls and splats on the floor, then the drip starts again.
import QtQuick

Item {
    id: d

    property real u: 1
    property real floorY: 1080
    property real areaW: 1920
    property color blood: "#8A0012"
    property color bright: "#D3203C"

    // re-rolled every cycle
    property real thick: 6 * u
    property real len: 80 * u
    property int growMs: 5000
    property int waitMs: 1000

    width: thick * 2
    height: floorY

    function reroll() {
        thick = (3 + Math.random() * 6) * u;
        len = (30 + Math.random() * 180) * u;
        growMs = 3000 + Math.random() * 7000;
        waitMs = 300 + Math.random() * 6000;
        x = Math.random() * (areaW - width);
    }

    // Stem: pill hanging from above the screen edge
    Rectangle {
        id: stem
        x: (d.width - width) / 2
        y: -radius
        width: d.thick
        height: radius
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#3A0006" }
            GradientStop { position: 1.0; color: d.blood }
        }
    }

    // Bulb at the tip of the stem, becomes the falling drop
    Rectangle {
        id: drop
        property real fall: 0
        width: d.thick * 1.7
        height: width * (1 + fall * 0.6)
        radius: width / 2
        x: (d.width - width) / 2
        y: stem.y + stem.height - width / 2
        color: d.blood
        Rectangle { // glint
            width: parent.width * 0.25; height: width; radius: width / 2
            x: parent.width * 0.22; y: parent.width * 0.2
            color: d.bright; opacity: 0.7
        }
    }

    Item {
        id: splat
        y: d.floorY
        x: d.width / 2
        opacity: 0
        Repeater {
            model: 7
            Rectangle {
                required property int index
                property real ang: Math.PI + (index / 6) * Math.PI + (Math.random() - 0.5) * 0.4
                property real dist: index === 3 ? 0 : (8 + Math.random() * 26) * d.u
                width: (index === 3 ? 4.5 : 1.2 + Math.random() * 2.2) * d.thick
                height: index === 3 ? width * 0.35 : width
                radius: height / 2
                x: Math.cos(ang) * dist - width / 2
                y: Math.sin(ang) * dist * 0.6 - height / 2
                color: index === 3 ? d.blood : d.bright
            }
        }
    }

    SequentialAnimation {
        id: cycle
        onFinished: { d.reroll(); Qt.callLater(cycle.start); }

        PauseAnimation { duration: d.waitMs }
        NumberAnimation { target: stem; property: "height"; from: stem.radius; to: d.len; duration: d.growMs; easing.type: Easing.OutQuad }
        ScriptAction { script: drop.y = drop.y } // freeze the binding, drop now moves on its own
        ParallelAnimation {
            NumberAnimation { target: drop; property: "y"; to: d.floorY - drop.height / 2; duration: 900 * Math.sqrt(d.floorY / 1080 / d.u); easing.type: Easing.InQuad }
            NumberAnimation { target: drop; property: "fall"; from: 0; to: 1; duration: 400 }
            NumberAnimation { target: stem; property: "height"; to: d.len * 0.55; duration: 500; easing.type: Easing.OutBack }
        }
        ScriptAction { script: { drop.opacity = 0; splat.opacity = 1; } }
        ParallelAnimation {
            NumberAnimation { target: splat; property: "scale"; from: 0.3; to: 1; duration: 160; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 1800 }
                NumberAnimation { target: splat; property: "opacity"; to: 0; duration: 2500 }
            }
            NumberAnimation { target: stem; property: "height"; to: stem.radius; duration: 3500; easing.type: Easing.InQuad }
        }
        ScriptAction {
            script: {
                drop.fall = 0;
                drop.opacity = 1;
                drop.y = Qt.binding(() => stem.y + stem.height - drop.width / 2);
            }
        }
    }

    Component.onCompleted: Qt.callLater(() => { reroll(); waitMs = Math.random() * 4000; cycle.start(); })
}
