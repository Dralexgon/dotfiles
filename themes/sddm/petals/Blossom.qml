// A five petal cherry blossom, one per password character.
import QtQuick

Item {
    id: root

    property color colour: "#FFA8CF"
    property color heart: "#FFE0EC"

    implicitWidth: 22
    implicitHeight: 22

    Repeater {
        model: 5

        Item {
            required property int index

            anchors.centerIn: parent
            width: 0
            height: 0
            rotation: index * 72

            PetalShape {
                x: -width / 2
                y: -height - root.height * 0.04
                width: root.width * 0.42
                height: root.height * 0.48
                colour: root.colour
            }
        }
    }
    Rectangle {
        anchors.centerIn: parent
        width: root.width * 0.2
        height: width
        radius: width / 2
        color: root.heart
    }
}
