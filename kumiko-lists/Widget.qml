import QtQuick
import Quickshell
import "lib"
import "lib/Kumiko.js" as K

// Kumiko Lists: what is due today and what is already done, with a key per row to tick it
// (and Undo after). Three views (setting `view`): "list" (the default), "next" (the next
// thing to do, one press) and "compact" (a count and the next item).
// Design: doc/briefs/handoff-kumiko-widgets/project/Lists.dc.html.
Item {
    id: root

    required property var host
    readonly property var t: root.host.theme
    readonly property var cfg: root.host.settings
    readonly property string view: ["list", "next", "compact"].indexOf(root.cfg.view) >= 0 ? root.cfg.view : "list"
    readonly property bool use24h: root.cfg.use24h !== false
    readonly property int maxRows: Math.max(1, Number(root.cfg.rows) || 6)

    // ===== data =====
    property var items: []
    property var titles: ({})           // list id -> its title
    property double fetchedAt: 0
    property double now: Date.now()
    property var problem: null
    property bool offline: false
    property string noticeTitle: ""
    property string notice: ""
    property var busy: ({})             // item id -> true while its call runs
    property var undo: null             // { row, eventId, text } after a tick
    property bool tokenWait: true

    readonly property var rows: K.listRows(root.items, root.titles, root.now, root.use24h, root.cfg.showDone !== false)
    readonly property var counts: K.listCounts(K.listRows(root.items, root.titles, root.now, root.use24h, true))
    readonly property var next: K.nextRow(root.rows)
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

    Timer {
        interval: 1500
        running: true
        onTriggered: root.tokenWait = false
    }
    Timer {
        interval: Math.max(1, Number(root.cfg.refreshMinutes) || 5) * 60000
        running: root.host.working && api.ready
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        // "late" changes as time passes, without a fetch.
        interval: 60000
        running: root.host.working
        repeat: true
        onTriggered: root.now = Date.now()
    }
    Timer {
        id: noticeTimer
        interval: 7000
        onTriggered: {
            root.notice = ""
            root.noticeTitle = ""
        }
    }
    Timer {
        id: undoTimer
        interval: 8000
        onTriggered: root.undo = null
    }
    Component.onCompleted: root.refresh()

    // "Check again": read the token file again (a token put in place since the shell
    // started), then ask Kumiko. host.reloadSecrets() is newer than plugin api 1's first
    // release; a shell without it re-reads secret files only from the Reload key in
    // Settings > Desktop > Plugins, so that card is opened on this plugin instead.
    function recheck() {
        if (typeof root.host.reloadSecrets === "function")
            root.host.reloadSecrets()
        else if (!api.ready)
            Quickshell.execDetached(["qs", "-c", "sekaipop", "ipc", "call", "plugins", "settings", root.host.id])
        root.refresh()
    }

    function answer(status, body) {
        if (status >= 200 && status < 300) {
            root.problem = null
            root.offline = false
            return true
        }
        const p = K.problem(status, body, "lists:write")
        if (p.kind === "offline")
            root.offline = true
        else if (p.kind === "token" || p.kind === "scope" || p.kind === "space")
            root.problem = p
        return false
    }

    function refresh() {
        if (!api.ready)
            return
        api.call("GET", "/lists", null, (st, body) => {
            if (!root.answer(st, body))
                return
            const m = {}
            for (const l of body.lists || [])
                m[l.id] = l.title
            root.titles = m
            api.call("GET", "/lists/today", null, (st2, b2) => {
                if (!root.answer(st2, b2))
                    return
                root.items = b2.items || []
                root.fetchedAt = Date.now()
                root.now = root.fetchedAt
            })
        })
    }

    function setBusy(id, on) {
        const b = Object.assign({}, root.busy)
        if (on) b[id] = true
        else delete b[id]
        root.busy = b
    }

    function say(title, text) {
        root.noticeTitle = title
        root.notice = text
        noticeTimer.restart()
    }

    // A press on a row's key: tick an open row, take back a done or skipped one.
    function press(row) {
        if (!root.canAct || root.busy[row.id])
            return
        if (row.state === "open")
            root.complete(row)
        else
            root.reverse(row, row.eventId)
    }

    function complete(row) {
        root.setBusy(row.id, true)
        api.call("POST", "/lists/" + row.listId + "/items/" + row.id + "/complete",
                 { idempotencyKey: api.idempotencyKey() }, (st, body) => {
            root.setBusy(row.id, false)
            if (st === 409) {
                const msg = body && body.error ? String(body.error.message || "") : ""
                root.say("Not logged: too soon.", msg || "Kumiko refused it, nothing changed.")
                return
            }
            if (!root.answer(st, body)) {
                if (root.offline)
                    root.say("", "Can't reach Kumiko, so nothing was ticked.")
                return
            }
            if (body && body.event) {
                root.undo = { row: row, eventId: body.event.id, text: row.title + " done · " + K.clock(body.event.occurredAt || Date.now(), root.use24h) }
                undoTimer.restart()
            }
            root.refresh()
        })
    }

    function reverse(row, eventId) {
        if (!eventId) {
            root.refresh()
            return
        }
        root.setBusy(row.id, true)
        api.call("POST", "/lists/" + row.listId + "/items/" + row.id + "/reverse",
                 { idempotencyKey: api.idempotencyKey(), reverses: eventId }, (st, body) => {
            root.setBusy(row.id, false)
            root.undo = null
            if (st === 409)
                root.say("Not undone.", "It was changed somewhere else meanwhile; the list is up to date now.")
            else
                root.answer(st, body)
            root.refresh()
        })
    }

    // ===== size =====
    readonly property real pad: root.view === "compact" ? 0 : 6
    implicitWidth: root.view === "compact" ? 148 : 334
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
            scope: "lists:write"
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
            sourceComponent: root.view === "compact" ? compactView : (root.view === "next" ? nextView : listView)
        }

        Notice {
            visible: root.notice !== "" || (root.offline && root.loaded)
            width: parent.width
            theme: root.t
            title: root.notice !== "" ? root.noticeTitle : ""
            text: root.notice !== "" ? root.notice
                : "Offline · updated " + K.ago(root.fetchedAt, Date.now()) + " ago. Ticks are paused."
        }

        // Undo, for a moment after a tick.
        Item {
            visible: root.undo !== null && root.view !== "compact"
            width: parent.width
            height: undoKey.height
            Txt {
                theme: root.t
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - undoKey.width - 12
                text: root.undo ? root.undo.text : ""
            }
            Key {
                id: undoKey
                anchors.right: parent.right
                theme: root.t
                text: "Undo"
                size: 40
                ring: 3
                onClicked: if (root.undo) root.reverse(root.undo.row, root.undo.eventId)
            }
        }
    }

    // The round key at the start of a row: empty open, lit with a tick when done, dashed
    // with a dash when skipped.
    component RowKey: Key {
        required property var row
        theme: root.t
        icon: row.state === "done" ? "check" : (row.state === "skipped" ? "remove" : "")
        lit: row.state === "done"
        dashed: row.state === "skipped"
        enabled: root.canAct && !root.busy[row.id]
        iconSize: 18
        onClicked: root.press(row)
    }

    Component {
        id: listView

        Column {
            spacing: 0

            Item {
                width: parent.width
                height: 44
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Txt { theme: root.t; anchors.verticalCenter: parent.verticalCenter; text: "Today"; weight: 800; font.pixelSize: 18 }
                    Txt { theme: root.t; anchors.verticalCenter: parent.verticalCenter; sub: true; weight: 600; font.pixelSize: 15
                          text: root.counts.done + " of " + root.counts.total + " done" }
                }
                Key {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    theme: root.t
                    icon: "refresh"
                    size: 38
                    iconSize: 16
                    enabled: !api.busy
                    onClicked: root.refresh()
                }
            }

            // How much of today is done.
            Rectangle {
                width: parent.width
                height: 14
                radius: 7
                color: root.t.pSurfaceDivider
                border.width: root.t.borderWidth
                border.color: root.t.pLine
                clip: true
                Rectangle {
                    x: root.t.borderWidth
                    y: root.t.borderWidth
                    height: parent.height - root.t.borderWidth * 2
                    width: (parent.width - root.t.borderWidth * 2) * (root.counts.total ? root.counts.done / root.counts.total : 0)
                    color: root.t.pInk
                }
            }
            Item { width: 1; height: 6 }

            Txt {
                visible: root.rows.length === 0
                theme: root.t
                sub: true
                topPadding: 8
                bottomPadding: 8
                text: "Nothing due today."
            }

            Repeater {
                model: root.rows.slice(0, root.maxRows)
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 54
                    RowKey {
                        id: rk
                        row: modelData
                        anchors.verticalCenter: parent.verticalCenter
                        size: 36
                    }
                    Column {
                        x: rk.width + 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - timeText.width - 8
                        Txt {
                            theme: root.t
                            width: parent.width
                            text: modelData.title
                            sub: modelData.state !== "open"
                            weight: modelData.state === "open" ? 800 : 400
                            font.strikeout: modelData.state === "done"
                        }
                        Txt {
                            theme: root.t
                            width: parent.width
                            visible: text !== ""
                            text: modelData.meta
                            font.pixelSize: 14
                        }
                    }
                    Txt {
                        id: timeText
                        theme: root.t
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.time + (modelData.late ? " · late" : "")
                        weight: modelData.late ? 800 : 600
                        sub: !modelData.late
                        font.pixelSize: 15
                    }
                }
            }

            Txt {
                visible: root.rows.length > root.maxRows
                theme: root.t
                height: 40
                verticalAlignment: Text.AlignVCenter
                text: "+" + (root.rows.length - root.maxRows) + " more in Kumiko"
                weight: 800
                font.pixelSize: 15
                font.underline: true
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: api.openInBrowser("/lists")
                }
            }
        }
    }

    Component {
        id: nextView

        Item {
            height: 56
            Txt {
                visible: !root.next
                theme: root.t
                anchors.verticalCenter: parent.verticalCenter
                text: root.counts.total ? "All " + root.counts.total + " done" : "Nothing due today."
                weight: 800
                font.pixelSize: 18
            }
            RowKey {
                id: nk
                visible: !!root.next
                row: root.next || ({ id: "", state: "open" })
                anchors.verticalCenter: parent.verticalCenter
                size: 40
            }
            Column {
                visible: !!root.next
                x: nk.width + 12
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - leftCol.width - 8
                Txt { theme: root.t; width: parent.width; text: root.next ? root.next.title : ""; weight: 800; font.pixelSize: 18 }
                Txt {
                    theme: root.t
                    width: parent.width
                    weight: 800
                    font.pixelSize: 15
                    text: root.next ? (root.next.time ? "Due " + root.next.time : "Today") + (root.next.late ? " · late" : "") : ""
                }
            }
            Column {
                id: leftCol
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: !!root.next
                Txt { anchors.right: parent.right; theme: root.t; text: String(root.counts.left); weight: 800; font.pixelSize: 26 }
                Txt { anchors.right: parent.right; theme: root.t; text: "left"; sub: true; weight: 600; font.pixelSize: 15 }
            }
        }
    }

    Component {
        id: compactView

        Column {
            height: 156
            spacing: 4

            Txt { theme: root.t; text: "Today"; weight: 800; font.pixelSize: 15 }

            // Still to do: the count and the next item.
            Row {
                visible: !!root.next
                spacing: 6
                Txt { id: bigLeft; theme: root.t; text: String(root.counts.left); weight: 800; font.pixelSize: 44 }
                Txt { theme: root.t; anchors.baseline: bigLeft.baseline; sub: true; weight: 600; font.pixelSize: 15; text: "left of " + root.counts.total }
            }
            Item {
                visible: !!root.next
                width: parent.width
                height: parent.height - 4 - 20 - bigLeft.height - 8
                Row {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    spacing: 10
                    RowKey { id: ck; row: root.next || ({ id: "", state: "open" }); size: 34 }
                    Column {
                        anchors.verticalCenter: ck.verticalCenter
                        width: parent.width - ck.width - 10
                        Txt { theme: root.t; width: parent.width; text: root.next ? root.next.title : ""; weight: 800; font.pixelSize: 14 }
                        Txt { theme: root.t; width: parent.width; font.pixelSize: 14
                              text: root.next ? (root.next.time || "today") + (root.next.late ? " · late" : "") : "" }
                    }
                }
            }

            // Everything done.
            Item {
                visible: !root.next
                width: parent.width
                height: parent.height - 24
                Column {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    spacing: 4
                    Key { theme: root.t; icon: "check"; lit: true; size: 42; ring: 0; enabled: false; opacity: 1 }
                    Txt { theme: root.t; width: parent.width; topPadding: 6; weight: 800
                          text: root.counts.total ? "All " + root.counts.total + " done" : "Nothing due" }
                }
            }
        }
    }
}
