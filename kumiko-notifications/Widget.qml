import QtQuick
import Quickshell
import "lib"
import "lib/Kumiko.js" as K

// Kumiko Notifications: the newest ones, unread first, live from Kumiko's stream, with
// keys to mark one read, dismiss one, mark all read, and open one. Three views (setting
// `view`): "list" (the default), "latest" (the newest unread, one row) and "compact"
// (the unread count). Design: doc/briefs/handoff-kumiko-widgets/project/Notifications.dc.html.
Item {
    id: root

    required property var host
    readonly property var t: root.host.theme
    readonly property var cfg: root.host.settings
    readonly property string view: ["list", "latest", "compact"].indexOf(root.cfg.view) >= 0 ? root.cfg.view : "list"
    readonly property int limit: Math.max(1, Number(root.cfg.count) || 5)

    // ===== data =====
    property var list: []
    property int unread: 0
    property double fetchedAt: 0
    property double now: Date.now()
    property var problem: null
    property bool offline: false
    property string notice: ""
    property var gone: ({})             // dismissed or read here, before Kumiko says so
    property bool tokenWait: true

    readonly property var rows: K.notifRows(root.list.filter(n => !root.gone[n.id + ":x"])
                                                .map(n => root.gone[n.id + ":r"] && !n.readAt ? Object.assign({}, n, { readAt: root.now }) : n),
                                            root.now, root.limit, root.cfg.unreadOnly === true)
    readonly property var latest: root.rows.length && root.rows[0].unread ? root.rows[0] : null
    readonly property int highCount: root.list.filter(n => !n.readAt && n.priority === "high").length
    readonly property bool loaded: root.fetchedAt > 0
    readonly property bool canAct: root.loaded && !root.offline

    KumikoClient {
        id: api
        server: root.cfg.server
        token: root.host.secrets.token || ""
        onTokenChanged: {
            root.tokenWait = false
            root.refresh()
        }
    }

    KumikoStream {
        id: stream
        server: root.cfg.server
        token: root.host.secrets.token || ""
        active: root.host.working && root.problem === null
        onSnapshot: data => {
            root.take(data.notifications || [], data.unread || 0)
        }
        onStateChanged: {
            if (stream.state === "reconnecting" && stream.failStatus >= 400)
                root.answer(stream.failStatus, null)
        }
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: root.tokenWait = false
    }
    Timer {
        // Ages ("8m") move on.
        interval: 60000
        running: root.host.working
        repeat: true
        onTriggered: root.now = Date.now()
    }
    Timer {
        id: noticeTimer
        interval: 6000
        onTriggered: root.notice = ""
    }
    Component.onCompleted: root.refresh()

    // "Check again": read the token file again (a token put in place since the shell
    // started), then ask Kumiko. host.reloadSecrets() is newer than plugin api 1's first
    // release; without it, reloading the plugins reads the files too.
    function recheck() {
        if (typeof root.host.reloadSecrets === "function")
            root.host.reloadSecrets()
        else if (!api.ready)
            Quickshell.execDetached(["qs", "-c", "sekaipop", "ipc", "call", "plugins", "reload"])
        root.refresh()
    }

    function take(list, unread) {
        root.list = list
        root.unread = unread
        root.gone = ({})
        root.fetchedAt = Date.now()
        root.now = root.fetchedAt
        root.offline = false
        root.problem = null
    }

    function answer(status, body) {
        if (status >= 200 && status < 300) {
            root.problem = null
            root.offline = false
            return true
        }
        const p = K.problem(status, body, "notifications:write")
        if (p.kind === "offline")
            root.offline = true
        else if (p.kind === "token" || p.kind === "scope" || p.kind === "space")
            root.problem = p
        return false
    }

    // The stream sends a snapshot as soon as it connects; this one is for the first paint
    // and for "Check again".
    function refresh() {
        if (!api.ready)
            return
        api.call("GET", "/notifications?limit=20", null, (st, body) => {
            if (root.answer(st, body))
                root.take(body.notifications || [], body.unread || 0)
        })
    }

    function mark(key, on) {
        const g = Object.assign({}, root.gone)
        if (on) g[key] = true
        else delete g[key]
        root.gone = g
    }

    function markRead(row) {
        if (!root.canAct)
            return
        root.mark(row.id + ":r", true)
        api.call("PATCH", "/notifications/" + row.id, { read: true }, (st, body) => {
            if (!root.answer(st, body)) {
                root.mark(row.id + ":r", false)
                root.say("Couldn't mark it read.")
            }
        })
    }

    function dismiss(row) {
        if (!root.canAct)
            return
        root.mark(row.id + ":x", true)
        api.call("DELETE", "/notifications/" + row.id, null, (st, body) => {
            if (!root.answer(st, body)) {
                root.mark(row.id + ":x", false)
                root.say("Couldn't dismiss it.")
            }
        })
    }

    function readAll() {
        if (!root.canAct)
            return
        api.call("POST", "/notifications/read-all", {}, (st, body) => {
            if (root.answer(st, body))
                root.unread = body.unread || 0
            root.refresh()
        })
    }

    function open(row) {
        if (row.unread)
            root.markRead(row)
        if (row.url !== "")
            Qt.openUrlExternally(row.url)
        else
            api.openInBrowser("/notifications")
    }

    function say(text) {
        root.notice = text
        noticeTimer.restart()
    }

    // ===== size =====
    readonly property real pad: root.view === "compact" ? 0 : 6
    implicitWidth: root.view === "compact" ? 148 : 354
    implicitHeight: content.implicitHeight + root.pad * 2

    Column {
        id: content
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: 10

        SetupView {
            visible: !api.ready && !root.tokenWait || root.problem !== null
            width: parent.width
            theme: root.t
            problem: api.ready ? root.problem : null
            scope: "notifications:write"
            onRetry: root.recheck()
        }

        Txt {
            visible: api.ready && root.problem === null && !root.loaded && !root.offline
            theme: root.t
            sub: true
            text: "Asking Kumiko…"
        }

        Loader {
            active: root.loaded && root.problem === null
            visible: active
            width: parent.width
            sourceComponent: root.view === "compact" ? compactView : (root.view === "latest" ? latestView : listView)
        }

        Notice {
            visible: root.notice !== "" || ((root.offline || stream.state === "reconnecting") && root.loaded && root.view !== "compact")
            width: parent.width
            theme: root.t
            title: root.notice !== "" ? "" : "Reconnecting…"
            text: root.notice !== "" ? root.notice : "Showing the last snapshot from " + K.clock(root.fetchedAt) + "."
        }
    }

    // The unread count, as a chip.
    component Count: Rectangle {
        property int value: 0
        width: Math.max(26, countText.implicitWidth + 16)
        height: 26
        radius: 13
        color: root.t.chipFill
        Txt {
            id: countText
            anchors.centerIn: parent
            theme: root.t
            color: root.t.chipInk
            weight: 800
            font.pixelSize: 14
            text: String(parent.value)
        }
    }

    // A lit dot while the stream is live.
    component Live: Row {
        spacing: 6
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 6
            border.width: 2
            border.color: root.t.colBorder
            readonly property bool on: stream.state === "live"
            color: on ? "transparent" : root.t.pSurfaceDivider
            gradient: on ? liveLit : null
            Gradient {
                id: liveLit
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: root.t.accentMint }
                GradientStop { position: 1; color: root.t.accentCyan }
            }
        }
        Txt {
            theme: root.t
            weight: 800
            font.pixelSize: 14
            text: stream.state === "live" ? "Live" : (stream.state === "off" ? "Paused" : "Connecting")
        }
    }

    // The mark at the start of a row: a badge for high priority, a dot for unread.
    component Mark: Item {
        property var row
        width: 26
        height: 26
        Rectangle {
            visible: parent.row && parent.row.high
            anchors.fill: parent
            radius: 9
            color: root.t.chipFill
            Txt { anchors.centerIn: parent; theme: root.t; color: root.t.chipInk; weight: 800; text: "!"; font.pixelSize: 16 }
        }
        Rectangle {
            visible: parent.row && !parent.row.high && parent.row.unread
            anchors.centerIn: parent
            width: 9
            height: 9
            radius: 5
            color: root.t.pInk
        }
    }

    Component {
        id: listView

        Column {
            spacing: 0

            Item {
                width: parent.width
                height: 34
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Txt { theme: root.t; anchors.verticalCenter: parent.verticalCenter; text: "Notifications"; weight: 800; font.pixelSize: 18 }
                    Count { visible: root.unread > 0; value: root.unread; anchors.verticalCenter: parent.verticalCenter }
                }
                Live { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
            }

            Txt {
                visible: root.rows.length === 0
                theme: root.t
                width: parent.width
                topPadding: 14
                bottomPadding: 10
                wrapMode: Text.Wrap
                text: "All caught up. New ones appear here as they arrive."
            }

            Repeater {
                model: root.rows
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: Math.max(56, texts.implicitHeight + 16)
                    Mark { id: mk; row: modelData; anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        id: texts
                        x: mk.width + 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - keys.width - 10
                        Row {
                            width: parent.width
                            spacing: 6
                            Txt {
                                id: title
                                theme: root.t
                                width: Math.min(implicitWidth, parent.width - (modelData.url !== "" ? 20 : 0))
                                text: modelData.title
                                weight: modelData.unread ? 800 : 400
                            }
                            Text {
                                visible: modelData.url !== ""
                                anchors.verticalCenter: title.verticalCenter
                                text: "open_in_new"
                                color: root.t.pInk
                                font.family: root.t.iconFont
                                font.pixelSize: 14
                            }
                        }
                        Txt { theme: root.t; width: parent.width; visible: modelData.body !== ""; text: modelData.body; font.pixelSize: 14 }
                        Txt { theme: root.t; width: parent.width; text: modelData.meta; font.pixelSize: 14 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.open(modelData)
                        }
                    }
                    Row {
                        id: keys
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Key { visible: modelData.unread; theme: root.t; icon: "check"; size: 38; iconSize: 16; enabled: root.canAct; onClicked: root.markRead(modelData) }
                        Key { theme: root.t; icon: "close"; size: 38; iconSize: 16; enabled: root.canAct; onClicked: root.dismiss(modelData) }
                    }
                }
            }

            Item {
                width: parent.width
                height: 54
                Key {
                    visible: root.unread > 0
                    anchors.bottom: parent.bottom
                    theme: root.t
                    text: "Mark all read"
                    size: 40
                    ring: 3
                    enabled: root.canAct
                    onClicked: root.readAll()
                }
                Txt {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    theme: root.t
                    text: "Open Kumiko"
                    weight: 800
                    font.pixelSize: 15
                    font.underline: true
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: api.openInBrowser("/notifications")
                    }
                }
            }
        }
    }

    Component {
        id: latestView

        Item {
            height: 50
            // A bell on an attribute colour, with the unread count on its corner.
            Rectangle {
                id: bell
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                height: 42
                radius: 9
                color: root.t.attributeColors ? root.t.attributeColors[1] : root.t.accentMint
                Text {
                    anchors.centerIn: parent
                    text: "notifications"
                    color: root.t.colBorder
                    font.family: root.t.iconFont
                    font.pixelSize: 22
                }
                Count { visible: root.unread > 0; value: root.unread; x: parent.width - width + 10; y: -8; height: 24 }
            }
            Column {
                x: bell.width + 14
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - (root.latest ? 50 : 0)
                Txt { theme: root.t; width: parent.width; weight: 800; text: root.latest ? root.latest.title : "All caught up" }
                Txt {
                    theme: root.t
                    width: parent.width
                    font.pixelSize: 14
                    text: root.latest ? root.latest.meta + (root.unread > 1 ? " · +" + (root.unread - 1) + " more" : "")
                        : (root.rows.length ? "Last: " + root.rows[0].title + ", " + K.ago(root.list[0].createdAt, root.now) : "Nothing yet")
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.latest ? root.open(root.latest) : api.openInBrowser("/notifications")
                }
            }
            Key {
                visible: !!root.latest
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                theme: root.t
                icon: "check"
                size: 40
                iconSize: 16
                enabled: root.canAct
                onClicked: root.markRead(root.latest)
            }
        }
    }

    Component {
        id: compactView

        Column {
            height: 156
            spacing: 2
            Item {
                width: parent.width
                height: 22
                Txt { theme: root.t; text: "Notifications"; weight: 800; font.pixelSize: 15; width: parent.width - 20 }
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12; height: 12; radius: 6
                    border.width: 2
                    border.color: root.t.colBorder
                    color: stream.state === "live" ? root.t.accentCyan : root.t.pSurfaceDivider
                }
            }
            Item { width: 1; height: 8 }
            Txt {
                theme: root.t
                weight: 800
                font.pixelSize: root.unread > 0 ? 44 : 18
                text: root.unread > 0 ? String(root.unread) : "All caught up"
            }
            Txt { visible: root.unread > 0; theme: root.t; sub: true; weight: 600; font.pixelSize: 15; text: "unread" }
            Txt {
                theme: root.t
                width: parent.width
                font.pixelSize: 14
                weight: 800
                visible: root.highCount > 0
                text: root.highCount + " high priority"
            }
            Txt {
                theme: root.t
                width: parent.width
                font.pixelSize: 14
                visible: root.unread === 0 && root.list.length > 0
                text: root.list.length ? "Last: " + root.list[0].title + ", " + K.ago(root.list[0].createdAt, root.now) : ""
            }
            MouseArea {
                width: parent.width
                height: 40
                cursorShape: Qt.PointingHandCursor
                onClicked: api.openInBrowser("/notifications")
            }
        }
    }
}
