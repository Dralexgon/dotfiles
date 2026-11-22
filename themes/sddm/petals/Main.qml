// Petals: soft pink SDDM greeter (colours from config/caelestia/schemes/petals), the login twin of
// the petals lock screen: falling petals pushed by the mouse, a flower blooming behind the avatar
// as you type (wilting on a wrong password), blossom password dots, and a petal burst on login.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: bgColour

    readonly property real u: Math.min(width / 1920, height / 1080) // 1 at 1080p, 2 at 4K
    readonly property string fontName: config.PetalsFont || "Quicksand"
    readonly property color bgColour: "#1A1318"
    readonly property color surface: "#CC271E24"
    readonly property color textColour: "#F6E8EF"
    readonly property color dim: "#D8C2CD"
    readonly property color outline: "#9F8A95"
    readonly property color primary: "#FFA8CF"
    readonly property color secondary: "#F2B8D2"
    readonly property color tertiary: "#E8B4F0"
    readonly property color container: "#6A2D4A"
    readonly property color blush: "#FFD9E8"
    readonly property color errorColour: "#FFB4AB"

    property int userIndex: 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false
    property int held: 0 // characters sent, the field is emptied on failure

    function userAt(i) { const it = users.itemAt(i); return it ? it.name : ""; }
    function userLabel(i) { const it = users.itemAt(i); return it ? (it.realName || it.name) : ""; }
    function userIcon(i) { const it = users.itemAt(i); return it ? it.icon : ""; }
    function sessionLabel(i) { const it = sessions.itemAt(i); return it ? it.name : ""; }

    function login() {
        if (busy) return;
        busy = true;
        held = pw.text.length;
        message.text = "";
        // Authenticate only once the burst has blown away: a successful
        // login tears the greeter down instantly, cutting the animation.
        loginDelay.restart();
    }

    Timer {
        id: loginDelay
        interval: 450 // the flower breathes a little first
        onTriggered: {
            petalField.burstRect = Qt.rect(column.x, column.y, column.width, column.height);
            petalField.burst();
            column.opacity = 0;
            authDelay.restart();
        }
    }
    Timer {
        id: authDelay
        interval: 900
        onTriggered: sddm.login(root.userAt(root.userIndex), pw.text, root.sessionIndex)
    }

    // Hidden lookups into the models (role values are only reachable from delegates)
    Repeater {
        id: users
        model: userModel
        delegate: Item {
            required property string name
            required property string realName
            required property string icon
            required property int index
            Component.onCompleted: if (name === userModel.lastUser) root.userIndex = index
        }
    }
    Repeater {
        id: sessions
        model: sessionModel
        delegate: Item { required property string name }
    }

    function failed() {
        busy = false;
        pw.text = "";
        column.opacity = 1;
        petalField.calm();
        bloom.wither(held);
        held = 0;
        message.text = config.PetalsLoginFailed || "The petals didn't recognise you…";
        shake.restart();
        pw.forceActiveFocus();
    }

    Connections {
        target: sddm
        function onLoginFailed() { root.failed(); }
    }

    // ---------- background ----------
    Image {
        anchors.fill: parent
        source: config.PetalsBackground || "background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
    Rectangle { // dim with the scheme's background
        anchors.fill: parent
        color: root.bgColour
        opacity: 0.45
    }
    Canvas { // soft plum vignette
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            const r = Math.hypot(width, height) / 2;
            const g = ctx.createRadialGradient(width / 2, height / 2, r * 0.3, width / 2, height / 2, r);
            g.addColorStop(0, "rgba(26,19,24,0)");
            g.addColorStop(0.7, "rgba(40,16,30,0.45)");
            g.addColorStop(1, "rgba(16,8,13,0.9)");
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, width, height);
        }
    }

    // ---------- falling petals, under the controls ----------
    PetalField {
        id: petalField
        anchors.fill: parent
        colours: [root.primary, root.primary, root.secondary, root.tertiary, root.blush]
    }

    // ---------- center column ----------
    Column {
        id: column
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20 * root.u
        spacing: 12 * root.u
        Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 112 * root.u
            font.weight: Font.Bold
            color: root.textColour
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 26 * root.u
            font.weight: Font.Medium
            font.letterSpacing: 2 * root.u
            color: root.secondary
            text: Qt.formatDate(new Date(), "dddd d MMMM")
        }
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
                const now = new Date();
                clock.text = Qt.formatTime(now, "HH:mm");
                date.text = Qt.formatDate(now, "dddd d MMMM");
            }
        }

        Item { width: 1; height: 56 * root.u }

        // avatar, with the flower blooming behind it
        Item {
            id: card
            anchors.horizontalCenter: parent.horizontalCenter
            width: 150 * root.u
            height: 150 * root.u

            Bloom {
                id: bloom
                anchors.centerIn: parent
                size: card.width
                count: root.busy ? root.held : pw.text.length
                checking: root.busy
                inner: root.primary
                outer: root.secondary
                withered: root.outline
            }

            Rectangle {
                id: avatarBg
                anchors.fill: parent
                radius: width / 2
                color: root.container
                border.width: 3 * root.u
                border.color: pw.activeFocus ? root.primary : root.secondary
                Behavior on border.color { ColorAnimation { duration: 300 } }

                Text { // initial, when there is no avatar picture (or only SDDM's default face)
                    anchors.centerIn: parent
                    visible: !avatar.real
                    font.family: root.fontName
                    font.pixelSize: 64 * root.u
                    font.weight: Font.Bold
                    color: root.blush
                    text: (users.count, root.userLabel(root.userIndex).charAt(0).toUpperCase())
                }
                Image {
                    id: avatar
                    readonly property bool real: status === Image.Ready && !String(source).includes("/sddm/faces/")
                    anchors.fill: parent
                    anchors.margins: parent.border.width
                    source: (users.count, root.userIcon(root.userIndex))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                // Round the picture with a circle mask
                Rectangle {
                    id: avatarMask
                    anchors.fill: avatar
                    radius: width / 2
                    layer.enabled: true
                    visible: false
                }
                MultiEffect {
                    anchors.fill: avatar
                    visible: avatar.real
                    source: avatar
                    maskEnabled: true
                    maskSource: avatarMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
            }
        }

        Item { width: 1; height: 4 * root.u }

        Text { // user, click to cycle
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 30 * root.u
            font.weight: Font.DemiBold
            color: userMouse.containsMouse ? root.primary : root.textColour
            Behavior on color { ColorAnimation { duration: 200 } }
            text: (users.count, users.count > 1 ? "‹  " : "") + root.userLabel(root.userIndex) + (users.count > 1 ? "  ›" : "")
            MouseArea {
                id: userMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.userIndex = (root.userIndex + 1) % users.count
            }
        }

        // password field, its characters drawn as blossoms
        Item {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 420 * root.u
            height: 60 * root.u
            transform: Translate { id: shakeX }

            Rectangle {
                id: frame
                anchors.fill: parent
                radius: height / 2
                color: root.surface
                border.width: 2 * root.u
                border.color: pw.activeFocus ? root.primary : "#4A3A43"
                Behavior on border.color { ColorAnimation { duration: 300 } }
            }

            TextField {
                id: pw
                anchors.fill: parent
                anchors.leftMargin: 24 * root.u
                anchors.rightMargin: 24 * root.u
                background: null
                echoMode: TextInput.Password
                color: "transparent" // the blossoms below show the characters
                selectionColor: "transparent"
                selectedTextColor: "transparent"
                cursorDelegate: Item {}
                font.pixelSize: 20 * root.u
                enabled: !root.busy
                focus: true
                onAccepted: root.login()
                Keys.onEscapePressed: text = ""
            }
            Row {
                id: blossomRow
                anchors.centerIn: parent
                spacing: 6 * root.u
                // The newest blossoms stay in view when the field is full
                readonly property int fits: Math.max(0, Math.floor((field.width - 48 * root.u) / (28 * root.u)))

                // A ListModel, not `model: pw.text.length`: an int model rebuilds every blossom
                // on each change, so they all popped in again. Here only the changed one moves.
                // `n` is the character's position, so colours and tilts don't shift when the
                // oldest blossom scrolls out of a full field.
                ListModel { id: blossoms }
                function sync() {
                    const len = pw.text.length;
                    const shown = Math.min(len, fits);
                    // deleted characters: drop from the end
                    while (blossoms.count > 0 && blossoms.get(blossoms.count - 1).n >= len)
                        blossoms.remove(blossoms.count - 1);
                    // new characters: add at the end (only these pop in)
                    let next = blossoms.count > 0 ? blossoms.get(blossoms.count - 1).n + 1 : len - shown;
                    for (; next < len; next++)
                        blossoms.append({ n: next });
                    // full field: the oldest scroll out at the start
                    while (blossoms.count > shown)
                        blossoms.remove(0);
                    // room again (after a delete, or a wider field): bring older ones back
                    while (blossoms.count < shown)
                        blossoms.insert(0, { n: blossoms.get(0).n - 1 });
                }
                Connections {
                    target: pw
                    function onTextChanged() { blossomRow.sync() }
                }
                onFitsChanged: sync()

                Repeater {
                    model: blossoms
                    Blossom {
                        required property int n
                        width: 22 * root.u
                        height: 22 * root.u
                        colour: [root.primary, root.secondary, root.tertiary][n % 3]
                        heart: root.blush
                        scale: 0
                        rotation: n * 23
                        Component.onCompleted: scale = 1
                        Behavior on scale { SpringAnimation { spring: 4; damping: 0.25; epsilon: 0.005 } }
                    }
                }
            }
            Text { // own placeholder: the Controls one hides while focused
                anchors.centerIn: parent
                visible: pw.text.length === 0
                font.family: root.fontName
                font.pixelSize: 19 * root.u
                color: root.outline
                text: config.PetalsPlaceholder || "Whisper your password…"
            }

            SequentialAnimation {
                id: shake
                ColorAnimation { target: frame; property: "border.color"; to: root.errorColour; duration: 1 }
                NumberAnimation { target: shakeX; property: "x"; to: -16 * root.u; duration: 50 }
                NumberAnimation { target: shakeX; property: "x"; to: 14 * root.u; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: -10 * root.u; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: 6 * root.u; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 60 }
                PauseAnimation { duration: 600 }
                ScriptAction { script: frame.border.color = Qt.binding(() => pw.activeFocus ? root.primary : "#4A3A43") }
            }
        }

        Text {
            id: message
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 19 * root.u
            font.weight: Font.Medium
            color: root.errorColour
            text: keyboard.capsLock ? "Caps Lock" : ""
        }
    }

    // ---------- bottom bar ----------
    Text { // session, click to cycle
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 36 * root.u
        font.family: root.fontName
        font.pixelSize: 20 * root.u
        font.weight: Font.Medium
        color: sessMouse.containsMouse ? root.primary : root.dim
        text: "✿  " + (sessions.count, root.sessionLabel(root.sessionIndex))
        MouseArea {
            id: sessMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessions.count
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 36 * root.u
        spacing: 36 * root.u
        Repeater {
            model: [
                { label: "Sleep", can: sddm.canSuspend, act: () => sddm.suspend() },
                { label: "Restart", can: sddm.canReboot, act: () => sddm.reboot() },
                { label: "Power off", can: sddm.canPowerOff, act: () => sddm.powerOff() }
            ]
            Text {
                required property var modelData
                visible: modelData.can
                font.family: root.fontName
                font.pixelSize: 20 * root.u
                font.weight: Font.Medium
                color: btn.containsMouse ? root.primary : root.dim
                text: modelData.label
                MouseArea {
                    id: btn
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.modelData.act()
                }
            }
        }
    }

    Component.onCompleted: pw.forceActiveFocus()
}
