// A flower behind the avatar that blooms as you type, the greeter twin of the Caelestia lock's
// PetalBloom (config/caelestia/lock/PetalBloom.qml). Each character adds a petal (an inner ring of
// 10, then an outer one of 10). While logging in the flower pulses; wilt() makes the petals wilt,
// go grey and fall off (wrong password).
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    required property real size // width of the avatar
    property int count // characters typed
    property bool checking
    property color inner: "#FFA8CF"
    property color outer: "#F2B8D2"
    property color withered: "#9F8A95"

    readonly property int slots: 10
    property int wiltCount
    property real wilt // 0..1, how far the wilting has gone

    function wither(n: int): void {
        wiltCount = Math.max(n, 1);
        wiltAnim.restart();
    }

    width: size
    height: size

    SequentialAnimation {
        id: wiltAnim

        NumberAnimation {
            target: root
            property: "wilt"
            from: 0
            to: 1
            duration: 1100
            easing.type: Easing.OutQuad
        }
        PropertyAction {
            target: root
            property: "wiltCount"
            value: 0
        }
        PropertyAction {
            target: root
            property: "wilt"
            value: 0
        }
    }

    // The whole flower shakes on a wrong password
    SequentialAnimation {
        running: wiltAnim.running
        loops: 2

        NumberAnimation {
            target: flower
            property: "anchors.horizontalCenterOffset"
            to: -8
            duration: 60
        }
        NumberAnimation {
            target: flower
            property: "anchors.horizontalCenterOffset"
            to: 8
            duration: 120
        }
        NumberAnimation {
            target: flower
            property: "anchors.horizontalCenterOffset"
            to: 0
            duration: 60
        }
    }

    Item {
        id: flower

        anchors.centerIn: parent
        width: root.size
        height: root.size

        // Slowly turns, and breathes while logging in
        NumberAnimation on rotation {
            from: 0
            to: 360
            duration: 120000
            loops: Animation.Infinite
        }

        SequentialAnimation on scale {
            running: root.checking
            loops: Animation.Infinite
            onRunningChanged: if (!running)
                flower.scale = 1

            NumberAnimation {
                to: 1.07
                duration: 450
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                to: 1
                duration: 450
                easing.type: Easing.InOutSine
            }
        }

        // Outer ring first so the inner one is drawn on top
        Repeater {
            model: root.slots * 2

            Item {
                id: slot

                required property int index
                readonly property bool outer: index < root.slots
                // Character number this petal stands for
                readonly property int charIndex: outer ? index : index - root.slots
                readonly property int order: outer ? charIndex + root.slots : charIndex
                readonly property bool shown: order < root.count || order < root.wiltCount
                readonly property bool wilting: order < root.wiltCount
                // Each petal wilts a bit after the previous one
                readonly property real myWilt: wilting ? Math.max(0, Math.min(1, root.wilt * 1.6 - order * 0.04)) : 0

                anchors.centerIn: parent
                width: 0
                height: 0
                rotation: charIndex * 36 + (outer ? 18 : 0)

                PetalShape {
                    // The avatar is size / 2 wide from its centre: petals only peek out of it
                    readonly property real len: root.size * (slot.outer ? 0.34 : 0.3)
                    readonly property real base: root.size * (slot.outer ? 0.32 : 0.3)
                    // Wilted petals droop sideways and slide away from the centre
                    readonly property real slide: slot.myWilt * root.size * 0.25

                    x: -width / 2
                    y: -(base + len) - slide
                    width: root.size * (slot.outer ? 0.28 : 0.25)
                    height: len

                    transformOrigin: Item.Bottom
                    rotation: slot.myWilt * (slot.index % 2 ? 40 : -40)
                    scale: slot.shown ? 1 - slot.myWilt * 0.4 : 0
                    opacity: slot.shown ? 1 - slot.myWilt : 0
                    colour: Qt.tint(slot.outer ? root.outer : root.inner, Qt.alpha(root.withered, slot.myWilt * 0.9))

                    Behavior on scale {
                        SpringAnimation {
                            spring: 3.5
                            damping: 0.22
                            epsilon: 0.005
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 180
                        }
                    }
                }
            }
        }
    }
}
