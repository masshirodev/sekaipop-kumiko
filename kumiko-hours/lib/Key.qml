import QtQuick

// A key drawn like the shell's own (SekaiKey / Pill): an outline, a ring inside it, the
// fill, and a hard shadow it drops onto when pressed, springing back past rest on release.
// Round when `text` is empty (an icon key), a pill otherwise. `lit` is "on": the accent
// gradient with the border colour for outline and ink.
//
//   Key { theme: host.theme; icon: "pause"; onClicked: ... }
//   Key { theme: host.theme; text: "Mark all read"; onClicked: ... }
Item {
    id: root

    required property var theme
    property string icon: ""
    property string text: ""
    property bool lit: false
    property bool dashed: false
    property real size: 38          // height; also the width of a round key
    property real ring: 2           // white ring inside the outline
    property real iconSize: 18
    property int fontSize: 15
    // An icon drawn by the caller instead of a font glyph (put it in `contentItem`).
    default property alias content: face.data

    signal clicked()

    readonly property bool round: root.text === ""
    readonly property real dx: root.theme.shadowOffset !== undefined ? root.theme.shadowOffset : 4
    readonly property real dy: root.dx - 1
    readonly property color ink: root.lit ? root.theme.colBorder : root.theme.pInk

    implicitWidth: (root.round ? root.size : label.implicitWidth + (root.icon !== "" ? root.iconSize + 8 : 0) + 36) + root.dx
    implicitHeight: root.size + root.dy
    opacity: root.enabled ? 1 : 0.45

    // The hard shadow: never moves; the cap covers it when pressed.
    Rectangle {
        x: root.dx
        y: root.dy
        width: root.width - root.dx
        height: root.height - root.dy
        radius: height / 2
        color: root.theme.pLineShadow
        visible: !root.dashed
    }

    Item {
        id: cap
        width: root.width - root.dx
        height: root.height - root.dy
        x: area.pressed ? root.dx : 0
        y: area.pressed ? root.dy : 0
        Behavior on x { NumberAnimation { duration: area.pressed ? 60 : 260; easing.type: area.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 2.2 } }
        Behavior on y { NumberAnimation { duration: area.pressed ? 60 : 260; easing.type: area.pressed ? Easing.OutQuad : Easing.OutBack; easing.overshoot: 2.2 } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.lit ? "transparent" : (root.dashed ? root.theme.pSurface : root.theme.pSurfaceDivider)
            gradient: root.lit ? litGradient : null
            border.width: root.theme.borderWidth
            border.color: root.lit ? root.theme.colBorder : root.theme.pLine
            antialiasing: true

            Gradient {
                id: litGradient
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.theme.accentMint }
                GradientStop { position: 1; color: root.theme.accentCyan }
            }

            // The ring just inside the outline.
            Rectangle {
                visible: !root.dashed && root.ring > 0
                anchors.fill: parent
                anchors.margins: root.theme.borderWidth
                radius: height / 2
                color: "transparent"
                border.width: root.ring
                border.color: root.theme.pRingWhite
                antialiasing: true
            }
        }

        Item {
            id: face
            anchors.fill: parent

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    visible: root.icon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.icon
                    color: root.ink
                    font.family: root.theme.iconFont
                    font.pixelSize: root.iconSize
                    font.weight: Font.DemiBold
                }

                Text {
                    id: label
                    visible: root.text !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.text
                    color: root.ink
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.fontSize
                    font.weight: Font.ExtraBold
                    font.styleName: root.theme.fontStyleBold
                }
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
