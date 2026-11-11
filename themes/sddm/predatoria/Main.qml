// Predatoria: vampire SDDM greeter (colors from config/caelestia/schemes/vampire)
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root

    width: 1920
    height: 1080
    color: "#0A0506"

    readonly property real u: Math.min(width / 1920, height / 1080) // 1 at 1080p, 2 at 4K
    readonly property string fontName: config.Font || "Cinzel"
    readonly property color bone: "#EFE3E4"
    readonly property color dim: "#9C878A"
    readonly property color blood: "#8A0012"
    readonly property color crimson: "#D3203C"
    readonly property color fresh: "#FF4A5E"

    property int userIndex: 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    property bool busy: false

    function userAt(i) { const it = users.itemAt(i); return it ? it.name : ""; }
    function userLabel(i) { const it = users.itemAt(i); return it ? (it.realName || it.name) : ""; }
    function sessionLabel(i) { const it = sessions.itemAt(i); return it ? it.name : ""; }

    function login() {
        if (busy) return;
        busy = true;
        message.text = "";
        lids.close();
        // Authenticate only once the eyelids are fully shut: a successful
        // login tears the greeter down instantly, cutting the animation.
        loginDelay.restart();
    }

    Timer {
        id: loginDelay
        interval: 850 // lid animation (700 ms) + a short beat in the dark
        onTriggered: sddm.login(root.userAt(root.userIndex), pw.text, root.sessionIndex)
    }

    // Hidden lookups into the models (role values are only reachable from delegates)
    Repeater {
        id: users
        model: userModel
        delegate: Item {
            required property string name
            required property string realName
            required property int index
            Component.onCompleted: if (name === userModel.lastUser) root.userIndex = index
        }
    }
    Repeater {
        id: sessions
        model: sessionModel
        delegate: Item { required property string name }
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            pw.text = "";
            message.text = config.LoginFailed || "The blood rejects you.";
            lids.open();
            wound.bleed();
            shake.restart();
            pw.forceActiveFocus();
        }
        function onLoginSucceeded() { lids.close(); }
    }

    // ---------- background ----------
    Image {
        anchors.fill: parent
        source: config.Background || "background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }
    Rectangle { // dim + slow heartbeat of red
        anchors.fill: parent
        color: "#0A0506"
        opacity: 0.55
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { to: 0.47; duration: 260; easing.type: Easing.OutQuad }
            NumberAnimation { to: 0.55; duration: 380; easing.type: Easing.InQuad }
            NumberAnimation { to: 0.50; duration: 200; easing.type: Easing.OutQuad }
            NumberAnimation { to: 0.55; duration: 1600; easing.type: Easing.InOutQuad }
        }
    }
    Canvas { // dark red vignette
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            const r = Math.hypot(width, height) / 2;
            const g = ctx.createRadialGradient(width / 2, height / 2, r * 0.35, width / 2, height / 2, r);
            g.addColorStop(0, "rgba(10,5,6,0)");
            g.addColorStop(0.7, "rgba(30,0,4,0.55)");
            g.addColorStop(1, "rgba(5,0,1,0.95)");
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, width, height);
        }
    }

    // ---------- blood dripping from the top edge ----------
    Item {
        id: drips
        anchors.fill: parent
        Repeater {
            model: 14
            Drip { u: root.u; blood: root.blood; bright: root.crimson; floorY: drips.height; areaW: drips.width }
        }
    }

    // ---------- center column ----------
    Column {
        id: column
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -40 * root.u
        spacing: 14 * root.u

        Crest {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300 * root.u
            height: 130 * root.u
        }

        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 110 * root.u
            font.weight: Font.Bold
            color: root.bone
            style: Text.Raised
            styleColor: root.blood
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 26 * root.u
            font.letterSpacing: 4 * root.u
            color: "#CDB6B9"
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

        Item { width: 1; height: 40 * root.u }

        Text { // user, click to cycle
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 30 * root.u
            font.letterSpacing: 2 * root.u
            color: userMouse.containsMouse ? root.fresh : root.bone
            text: (users.count, users.count > 1 ? "‹  " : "") + root.userLabel(root.userIndex) + (users.count > 1 ? "  ›" : "")
            MouseArea {
                id: userMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.userIndex = (root.userIndex + 1) % users.count
            }
        }

        // password field with its wound
        Item {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            width: 460 * root.u
            height: 62 * root.u
            transform: Translate { id: shakeX }

            Rectangle {
                id: frame
                anchors.fill: parent
                radius: 12 * root.u
                color: "#CC1A0B0E"
                border.width: 2 * root.u
                border.color: pw.activeFocus ? root.crimson : "#2A1215"
                Behavior on border.color { ColorAnimation { duration: 300 } }
            }

            TextField {
                id: pw
                anchors.fill: parent
                anchors.leftMargin: 20 * root.u
                anchors.rightMargin: 20 * root.u
                background: null
                echoMode: TextInput.Password
                passwordCharacter: "♦"
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                font.family: root.fontName
                font.pixelSize: (text.length ? 22 : 20) * root.u
                font.letterSpacing: text.length ? 6 * root.u : 1 * root.u
                color: root.bone
                selectionColor: root.crimson
                enabled: !root.busy
                focus: true
                onAccepted: root.login()
                Keys.onEscapePressed: text = ""
            }
            Text { // own placeholder: the Controls one hides while focused
                anchors.centerIn: parent
                visible: pw.text.length === 0
                font.family: root.fontName
                font.pixelSize: 20 * root.u
                font.italic: true
                color: root.dim
                text: config.Placeholder || "Speak the word, mortal..."
            }

            // drips running down from the field after a wrong password
            Item {
                id: wound
                anchors.top: parent.bottom
                anchors.topMargin: -frame.radius
                width: parent.width
                height: 120 * root.u
                z: -1

                function bleed() {
                    for (let i = 0; i < woundRep.count; i++)
                        woundRep.itemAt(i).go();
                }

                Repeater {
                    id: woundRep
                    model: 9
                    Rectangle {
                        id: wd
                        property real target: 0
                        width: (4 + Math.random() * 6) * root.u
                        radius: width / 2
                        height: 0
                        x: frame.radius + Math.random() * (wound.width - 2 * frame.radius - width)
                        color: root.blood
                        opacity: 0
                        Rectangle {
                            width: parent.width * 1.6; height: width; radius: width / 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -width * 0.3
                            color: root.blood
                            visible: parent.height > width
                        }
                        function go() {
                            x = frame.radius + Math.random() * (wound.width - 2 * frame.radius - width);
                            target = (15 + Math.random() * 95) * root.u;
                            anim.restart();
                        }
                        SequentialAnimation {
                            id: anim
                            PropertyAction { target: wd; property: "height"; value: 0 }
                            PropertyAction { target: wd; property: "opacity"; value: 1 }
                            PauseAnimation { duration: Math.random() * 400 }
                            NumberAnimation { target: wd; property: "height"; to: wd.target; duration: 1600 + Math.random() * 1600; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 2500 }
                            NumberAnimation { target: wd; property: "opacity"; to: 0; duration: 2000 }
                        }
                    }
                }
            }

            SequentialAnimation {
                id: shake
                ColorAnimation { target: frame; property: "border.color"; to: root.fresh; duration: 1 }
                NumberAnimation { target: shakeX; property: "x"; to: -18 * root.u; duration: 50 }
                NumberAnimation { target: shakeX; property: "x"; to: 16 * root.u; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: -12 * root.u; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: 8 * root.u; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: -4 * root.u; duration: 70 }
                NumberAnimation { target: shakeX; property: "x"; to: 0; duration: 60 }
                PauseAnimation { duration: 600 }
                ScriptAction { script: frame.border.color = Qt.binding(() => pw.activeFocus ? root.crimson : "#2A1215") }
            }
        }

        Text {
            id: message
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: root.fontName
            font.pixelSize: 20 * root.u
            font.italic: true
            color: root.fresh
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
        color: sessMouse.containsMouse ? root.fresh : root.dim
        text: "⸸  " + (sessions.count, root.sessionLabel(root.sessionIndex))
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
                { label: "Slumber", can: sddm.canSuspend, act: () => sddm.suspend() },
                { label: "Rise again", can: sddm.canReboot, act: () => sddm.reboot() },
                { label: "Return to the grave", can: sddm.canPowerOff, act: () => sddm.powerOff() }
            ]
            Text {
                required property var modelData
                visible: modelData.can
                font.family: root.fontName
                font.pixelSize: 20 * root.u
                color: btn.containsMouse ? root.fresh : root.dim
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

    // ---------- eyelids: close with a bloody rim while logging in ----------
    Item {
        id: lids
        anchors.fill: parent
        property real shut: 0 // 0 open, 1 closed
        Behavior on shut { NumberAnimation { duration: 700; easing.type: Easing.InOutCubic } }
        function close() { shut = 1; }
        function open() { shut = 0; }

        Rectangle {
            width: parent.width
            height: parent.height / 2 + 60 * root.u
            y: -height + lids.shut * (parent.height / 2 + 60 * root.u)
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#000000" }
                GradientStop { position: 0.85; color: "#0A0002" }
                GradientStop { position: 0.95; color: "#5C0A14" }
                GradientStop { position: 1.0; color: "#D3203C" }
            }
        }
        Rectangle {
            width: parent.width
            height: parent.height / 2 + 60 * root.u
            y: parent.height - lids.shut * (parent.height / 2 + 60 * root.u)
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#D3203C" }
                GradientStop { position: 0.05; color: "#5C0A14" }
                GradientStop { position: 0.15; color: "#0A0002" }
                GradientStop { position: 1.0; color: "#000000" }
            }
        }
    }

    Component.onCompleted: pw.forceActiveFocus()
}
