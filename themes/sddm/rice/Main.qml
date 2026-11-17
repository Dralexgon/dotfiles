// Rice: the login screen follows the current rice (config/caelestia/hypr-user.lua, "Rices").
// set_rice() leaves one empty file named after the rice in /var/lib/login-rice (the greeter can't
// read the home folder). petals -> the petals theme, anything else -> predatoria (vampire).
// FolderListModel and not a file read: QML only reads local files with QML_XHR_ALLOW_FILE_READ.
import QtQuick
import Qt.labs.folderlistmodel

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "#000000"

    property string rice: ""

    function pick() {
        if (rice !== "")
            return;
        for (let i = 0; i < marker.count; i++) {
            if (marker.get(i, "fileName") === "petals") {
                rice = "petals";
                return;
            }
        }
        rice = "predatoria";
    }

    FolderListModel {
        id: marker
        folder: "file:///var/lib/login-rice"
        showDirs: false
        showHidden: false
        nameFilters: ["adaptive", "petals", "vampire"]
        onStatusChanged: if (status === FolderListModel.Ready) readyDelay.restart()
    }
    // Ready can come before the rows: give them a moment
    Timer {
        id: readyDelay
        interval: 60
        onTriggered: root.pick()
    }
    // Missing folder (never switched rice yet): don't wait forever
    Timer {
        interval: 1500
        running: true
        onTriggered: root.pick()
    }

    Loader {
        id: loader
        anchors.fill: parent
        focus: true
        source: root.rice === "" ? "" : root.rice + "/Main.qml"
        opacity: status === Loader.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
        onLoaded: item.forceActiveFocus()
    }
}
