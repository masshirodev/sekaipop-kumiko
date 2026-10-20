import QtQuick

// One line (or two) of news inside a card: a refused tick, "already paused elsewhere",
// "offline, updated 14 min ago". Outlined, on the hover fill, with an info icon.
Rectangle {
    id: root

    required property var theme
    property string title: ""
    property string text: ""
    property string icon: "info"

    implicitHeight: body.implicitHeight + 20
    radius: root.theme.radiusOuter
    color: root.theme.pSurfaceHover
    border.width: root.theme.borderWidth
    border.color: root.theme.pLine

    Text {
        id: glyph
        x: 12
        y: 11
        text: root.icon
        color: root.theme.pInk
        font.family: root.theme.iconFont
        font.pixelSize: 18
    }

    Text {
        id: body
        x: 40
        y: 10
        width: root.width - 52
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        text: (root.title !== "" ? "<b>" + root.title + "</b> " : "") + root.text.replace(/&/g, "&amp;").replace(/</g, "&lt;")
        color: root.theme.pInk
        font.family: root.theme.fontFamily
        font.pixelSize: 14
        lineHeight: 1.15
    }
}
