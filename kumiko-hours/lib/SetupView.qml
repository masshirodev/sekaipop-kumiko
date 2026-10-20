import QtQuick

// What a widget shows instead of its content while it can't work: no token yet, or the
// token refused (expired, wrong space, missing this module's scope). The same look in all
// three widgets (States board: "Setup & errors").
//
//   SetupView { theme: host.theme; problem: K.problem(401, body, "lists:write") or null
//               scope: "lists:write"; onRetry: refresh() }
// With `problem` null it is the "not set up" view.
Column {
    id: root

    required property var theme
    property var problem: null
    property string scope: ""
    signal retry()

    readonly property bool setup: root.problem === null
    spacing: 10

    Txt {
        theme: root.theme
        width: root.width
        text: root.setup ? "Connect to Kumiko" : root.problem.title
        weight: 800
        font.pixelSize: 18
    }

    Txt {
        theme: root.theme
        width: root.width
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        font.pixelSize: 14
        text: root.setup
            ? "Put your API token in ~/.config/sekaipop-kumiko/token, then Check again. (KUMIKO_TOKEN works too, but only once the shell is restarted after it is set.) Make one in Kumiko on a computer: Settings › API tokens, with " + root.scope + "."
            : root.problem.text
    }

    Key {
        theme: root.theme
        text: "Check again"
        icon: "refresh"
        size: 40
        ring: 3
        onClicked: root.retry()
    }
}
