import QtQuick

// Text in the shell's font and the card's ink. `weight`: 400, 600 or 800 (ExtraBold, named
// as the shell names it); `sub` is the secondary ink.
Text {
    required property var theme
    property int weight: 400
    property bool sub: false

    color: sub ? theme.pInkSub : theme.pInk
    font.family: theme.fontFamily
    font.pixelSize: 16
    font.weight: weight >= 800 ? Font.ExtraBold : (weight >= 600 ? Font.DemiBold : Font.Normal)
    font.styleName: weight >= 800 ? theme.fontStyleBold : ""
    font.features: ({ "tnum": 1 })
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
