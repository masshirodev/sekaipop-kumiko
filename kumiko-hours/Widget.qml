import QtQuick
import Quickshell
import "lib"
import "lib/Kumiko.js" as K

// Kumiko Hours: the session running now (or not), today's segments, the week, and the
// keys to clock in, pause, resume and clock out. Three views (setting `view`): "session"
// (the default), "week" and "compact". Design: doc/briefs/handoff-kumiko-widgets/project/Hours.dc.html.
Item {
    id: root

    required property var host
    readonly property var t: root.host.theme
    readonly property var cfg: root.host.settings
    readonly property string view: ["session", "week", "compact"].indexOf(root.cfg.view) >= 0 ? root.cfg.view : "session"
    readonly property bool use24h: root.cfg.use24h !== false

    // ===== data =====
    property var activities: []
    property var sessions: []
    property var overview: null
    property double fetchedAt: 0
    property double now: Date.now()
    property var problem: null          // a token / scope problem: the whole card says so
    property bool offline: false
    property string notice: ""          // one line of news after an action
    property bool picking: false        // choosing a pause type
    property bool acting: false         // a clock call in flight
    property bool tokenWait: true       // a file secret arrives a moment after start

    readonly property var followed: K.pickActivity(root.activities, root.cfg.activity)
    // What is open now: a running or paused session of any activity wins over the one followed.
    readonly property var current: {
        for (let i = 0; i < root.sessions.length; i++) {
            const s = root.sessions[i]
            if (s.status === "running" || s.status === "paused") {
                for (let j = 0; j < root.activities.length; j++)
                    if (root.activities[j].id === s.activityId) return root.activities[j]
            }
        }
        return root.followed
    }
    readonly property var sess: K.sessionNow(root.sessions, root.current, root.fetchedAt, root.now)
    readonly property string dot: K.activityColor(root.current) || String(root.t.accentCyan)
    readonly property var pauses: K.pauseTypes(root.current)
    readonly property string todayKey: K.dateKey(root.now)
    readonly property bool loaded: root.fetchedAt > 0
    readonly property bool canAct: root.loaded && !root.offline && !root.acting

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
        // Give a file secret its moment before saying there is none.
        interval: 1500
        running: true
        onTriggered: root.tokenWait = false
    }
    Timer {
        interval: Math.max(1, Number(root.cfg.refreshMinutes) || 2) * 60000
        running: root.host.working && api.ready
        repeat: true
        onTriggered: root.refresh()
    }
    Timer {
        // The running clock ticks locally between fetches.
        interval: 1000
        running: (root.host.working || root.host.editing) && root.sess.status !== "none"
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

    function answer(status, body) {
        if (status >= 200 && status < 300) {
            root.problem = null
            root.offline = false
            return true
        }
        const p = K.problem(status, body, "hours:write")
        if (p.kind === "offline")
            root.offline = true
        else if (p.kind === "token" || p.kind === "scope" || p.kind === "space")
            root.problem = p
        return false
    }

    function refresh() {
        if (!api.ready)
            return
        root.now = Date.now()
        const day = K.dateKey(root.now)
        api.call("GET", "/hours/activities", null, (st, body) => {
            if (!root.answer(st, body))
                return
            root.activities = body.activities || []
            api.call("GET", "/hours/sessions?date=" + day + "&scope=day", null, (st2, b2) => {
                if (!root.answer(st2, b2))
                    return
                root.sessions = b2.sessions || []
                root.fetchedAt = Date.now()
                root.now = root.fetchedAt
            })
            const a = K.pickActivity(root.activities, root.cfg.activity)
            if (a)
                api.call("GET", "/hours/overview?activity=" + encodeURIComponent(a.slug || a.id) + "&date=" + day + "&scope=week", null, (st3, b3) => {
                    if (root.answer(st3, b3))
                        root.overview = b3
                })
        })
    }

    function clock(action, activity, typeId) {
        if (!root.canAct || !activity)
            return
        root.picking = false
        root.acting = true
        const body = { action: action, activityId: activity.id }
        if (typeId)
            body.typeId = typeId
        api.call("POST", "/hours/clock", body, (st, b) => {
            root.acting = false
            if (st === 409) {
                root.say("Already changed elsewhere. The widget refreshed to show the current state.")
            } else if (!root.answer(st, b)) {
                if (root.offline)
                    root.say("Can't reach Kumiko, so nothing was changed.")
            }
            root.refresh()
        })
    }

    function pause() {
        if (root.pauses.length > 1)
            root.picking = true
        else
            root.clock("pause", root.current, root.pauses.length ? root.pauses[0].id : "")
    }

    function say(text) {
        root.notice = text
        noticeTimer.restart()
    }

    // ===== size =====
    readonly property real pad: root.view === "compact" ? 0 : 6
    implicitWidth: root.view === "compact" ? 148 : (root.view === "week" ? 306 : 366)
    implicitHeight: content.implicitHeight + root.pad * 2

    Column {
        id: content
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: 12

        // ----- can't work -----
        SetupView {
            visible: !api.ready && !root.tokenWait || root.problem !== null
            width: parent.width
            theme: root.t
            problem: api.ready ? root.problem : null
            scope: "hours:write"
            onRetry: root.recheck()
        }

        Txt {
            visible: api.ready && root.problem === null && !root.loaded && !root.offline
            theme: root.t
            sub: true
            text: "Asking Kumiko…"
        }

        // ----- picking a pause type -----
        Column {
            visible: root.picking && root.problem === null
            width: parent.width
            spacing: 4

            Txt {
                theme: root.t
                text: "Pause " + (root.current ? root.current.name : "") + " as"
                weight: 800
                font.pixelSize: 18
                bottomPadding: 6
            }
            Repeater {
                model: root.picking ? root.pauses : []
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 52
                    radius: root.t.radiusOuter
                    color: rowArea.containsMouse ? root.t.pSurfaceHover : "transparent"
                    Txt {
                        theme: root.t
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120
                        text: modelData.name
                        weight: 800
                    }
                    Txt {
                        theme: root.t
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.counts ? "counted" : "not counted"
                        font.pixelSize: 14
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clock("pause", root.current, modelData.id)
                    }
                }
            }
            Item {
                width: parent.width
                height: cancel.height + 8
                Key {
                    id: cancel
                    theme: root.t
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: "Cancel"
                    size: 40
                    ring: 3
                    onClicked: root.picking = false
                }
            }
        }

        // ----- the session (and compact) -----
        Loader {
            active: root.loaded && root.problem === null && !root.picking && root.view !== "week"
            visible: active
            width: parent.width
            sourceComponent: root.view === "compact" ? compactView : sessionView
        }

        // ----- the week -----
        Loader {
            active: root.loaded && root.problem === null && !root.picking && root.view === "week"
            visible: active
            width: parent.width
            sourceComponent: weekView
        }

        Notice {
            visible: root.notice !== "" || (root.offline && root.loaded)
            width: parent.width
            theme: root.t
            text: root.notice !== "" ? root.notice
                : "Offline · updated " + K.ago(root.fetchedAt, root.now) + " ago. Clocking is paused."
        }
    }

    // A small coloured dot for the activity.
    component Dot: Rectangle {
        width: 11
        height: 11
        radius: 6
        color: root.dot
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    Component {
        id: sessionView

        Column {
            spacing: 12

            // Not clocked in: today so far, and a key per activity.
            Column {
                visible: root.sess.status === "none"
                width: parent.width
                spacing: 14

                Item {
                    width: parent.width
                    height: idleTitle.height
                    Txt {
                        id: idleTitle
                        theme: root.t
                        text: "Not clocked in"
                        weight: 800
                        font.pixelSize: 18
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.baseline: idleTitle.baseline
                        spacing: 4
                        Txt { theme: root.t; sub: true; weight: 600; font.pixelSize: 15; text: "Today" }
                        Txt { theme: root.t; weight: 800; font.pixelSize: 15; text: K.hm(root.sess.todayCountedMs) }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        // The followed activity first, then the rest.
                        model: {
                            const list = root.activities.filter(a => !a.archived)
                            const f = root.followed
                            return f ? [f].concat(list.filter(a => a.id !== f.id)) : list
                        }
                        delegate: Key {
                            required property var modelData
                            theme: root.t
                            text: modelData.name
                            icon: "play_arrow"
                            size: 42
                            ring: 3
                            enabled: root.canAct
                            onClicked: root.clock("start", modelData, "")
                        }
                    }
                }
            }

            // Running or paused.
            Column {
                visible: root.sess.status !== "none"
                width: parent.width
                spacing: 12

                Item {
                    width: parent.width
                    height: 30
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Dot {}
                        Txt { theme: root.t; weight: 800; font.pixelSize: 18; text: root.current ? root.current.name : "" }
                        Txt {
                            theme: root.t; sub: true; weight: 600; font.pixelSize: 15
                            text: root.sess.startedAt ? "since " + K.clock(root.sess.startedAt, root.use24h) : ""
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        height: 30
                        width: chipText.implicitWidth + 24
                        radius: 15
                        readonly property bool on: root.sess.status === "running"
                        color: on ? "transparent" : root.t.chipFill
                        border.width: on ? root.t.borderWidth : 0
                        border.color: root.t.colBorder
                        gradient: on ? chipLit : null
                        Gradient {
                            id: chipLit
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.t.accentMint }
                            GradientStop { position: 1; color: root.t.accentCyan }
                        }
                        Txt {
                            id: chipText
                            theme: root.t
                            anchors.centerIn: parent
                            weight: 800
                            font.pixelSize: 14
                            color: parent.on ? root.t.colBorder : root.t.chipInk
                            text: parent.on ? "Running"
                                : (root.sess.pauseName || "Paused") + " · " + K.hm(root.sess.pauseMs)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 48 + 3
                    Txt {
                        theme: root.t
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120
                        text: K.hms(root.sess.elapsedMs)
                        sub: root.sess.status === "paused"
                        weight: 800
                        font.pixelSize: 46
                        font.letterSpacing: -1
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Key {
                            theme: root.t
                            icon: root.sess.status === "paused" ? "play_arrow" : "pause"
                            size: 48
                            ring: 3
                            iconSize: 22
                            enabled: root.canAct
                            onClicked: root.sess.status === "paused" ? root.clock("resume", root.current, "") : root.pause()
                        }
                        Key {
                            theme: root.t
                            icon: "stop"
                            size: 48
                            ring: 3
                            iconSize: 22
                            enabled: root.canAct
                            onClicked: root.clock("end", root.current, "")
                        }
                    }
                }

                // Today's segments: work in ink, pauses in the line colour, the open one lit.
                Rectangle {
                    width: parent.width
                    height: 18
                    radius: 9
                    color: root.t.pSurfaceDivider
                    border.width: root.t.borderWidth
                    border.color: root.t.pLine
                    clip: true
                    Row {
                        id: spanRow
                        x: root.t.borderWidth
                        y: root.t.borderWidth
                        height: parent.height - root.t.borderWidth * 2
                        spacing: 2
                        readonly property real total: root.sess.spans.reduce((n, s) => n + s.ms, 0) || 1
                        readonly property real room: parent.width - root.t.borderWidth * 2 - Math.max(0, root.sess.spans.length - 1) * 2
                        Repeater {
                            model: root.sess.spans
                            delegate: Rectangle {
                                required property var modelData
                                width: Math.max(2, spanRow.room * modelData.ms / spanRow.total)
                                height: spanRow.height
                                color: modelData.kind === "pause" ? root.t.pLine : (modelData.open ? "transparent" : root.t.pInk)
                                gradient: modelData.open && modelData.kind === "work" ? spanLit : null
                                Gradient {
                                    id: spanLit
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: root.t.accentMint }
                                    GradientStop { position: 1; color: root.t.accentCyan }
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: countedLine.height
                    Row {
                        id: countedLine
                        spacing: 4
                        Txt { theme: root.t; sub: true; weight: 600; font.pixelSize: 15; text: "Counted" }
                        Txt { theme: root.t; weight: 800; font.pixelSize: 15; text: K.hm(root.sess.countedMs) }
                        Txt { theme: root.t; sub: true; weight: 600; font.pixelSize: 15; text: root.sess.status === "paused" ? "(frozen)" : ""; visible: text !== "" }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 4
                        visible: root.overview !== null
                        Txt { theme: root.t; sub: true; weight: 600; font.pixelSize: 15; text: "Week" }
                        Txt { theme: root.t; weight: 800; font.pixelSize: 15; text: root.overview ? K.hm(root.overview.countedMs) : "" }
                        Txt { theme: root.t; sub: true; weight: 600; font.pixelSize: 15; text: root.overview ? "/ " + K.hm(root.overview.targetMs) : "" }
                    }
                }
            }
        }
    }

    Component {
        id: compactView

        Column {
            spacing: 4
            readonly property bool open: root.sess.status !== "none"

            Row {
                spacing: 8
                height: 20
                Dot { visible: parent.parent.open; width: 10; height: 10 }
                Txt {
                    theme: root.t
                    anchors.verticalCenter: parent.verticalCenter
                    weight: 800
                    font.pixelSize: 15
                    sub: !parent.parent.open
                    text: root.current ? root.current.name : ""
                }
            }
            Txt {
                theme: root.t
                weight: 800
                font.pixelSize: 34
                text: parent.open ? K.hm(root.sess.elapsedMs) : K.hm(root.sess.todayCountedMs)
                sub: root.sess.status === "paused"
            }
            Txt {
                theme: root.t
                sub: true
                weight: 600
                font.pixelSize: 15
                text: {
                    if (parent.open)
                        return root.sess.status === "paused" ? (root.sess.pauseName || "Paused") + " · " + K.hm(root.sess.pauseMs)
                            : "counted " + K.hm(root.sess.countedMs)
                    const d = root.overview ? root.overview.days.find(x => x.date === root.todayKey) : null
                    return d && d.targetMs > 0 ? "today, of " + K.hm(d.targetMs) : "today"
                }
                bottomPadding: 14
            }
            Row {
                visible: parent.open
                spacing: 10
                Key {
                    theme: root.t
                    icon: root.sess.status === "paused" ? "play_arrow" : "pause"
                    size: 44
                    ring: 3
                    enabled: root.canAct
                    onClicked: root.sess.status === "paused" ? root.clock("resume", root.current, "") : root.pause()
                }
                Key {
                    theme: root.t
                    icon: "stop"
                    size: 44
                    ring: 3
                    enabled: root.canAct
                    onClicked: root.clock("end", root.current, "")
                }
            }
            Key {
                visible: !parent.open
                width: parent.width
                theme: root.t
                text: "Start"
                icon: "play_arrow"
                size: 42
                ring: 3
                enabled: root.canAct
                onClicked: root.clock("start", root.current, "")
            }
        }
    }

    Component {
        id: weekView

        Column {
            spacing: 10
            readonly property var bars: K.weekBars(root.overview, root.todayKey)

            Row {
                spacing: 10
                height: 24
                Dot { color: K.activityColor(root.followed) || String(root.t.accentCyan) }
                Txt { theme: root.t; anchors.verticalCenter: parent.verticalCenter; weight: 800; font.pixelSize: 18; text: root.followed ? root.followed.name : "" }
                Txt { theme: root.t; anchors.verticalCenter: parent.verticalCenter; sub: true; weight: 600; font.pixelSize: 15; text: "this week" }
            }
            Item {
                width: parent.width
                height: weekTotal.height
                Row {
                    spacing: 8
                    Txt { id: weekTotal; theme: root.t; weight: 800; font.pixelSize: 36; text: root.overview ? K.hm(root.overview.countedMs) : "–" }
                    Txt { theme: root.t; anchors.baseline: weekTotal.baseline; sub: true; weight: 600; font.pixelSize: 15; text: root.overview ? "of " + K.hm(root.overview.targetMs) : "" }
                }
                Txt {
                    anchors.right: parent.right
                    anchors.baseline: weekTotal.baseline
                    theme: root.t
                    weight: 800
                    text: K.signedHm(K.balanceToDate(root.overview, root.todayKey))
                }
            }
            Txt {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                theme: root.t
                sub: true
                weight: 600
                font.pixelSize: 15
                text: "balance to date"
                bottomPadding: 14
            }
            Row {
                id: barRow
                width: parent.width
                spacing: 8
                readonly property real barW: (width - 6 * spacing) / 7
                Repeater {
                    model: parent.parent.bars
                    delegate: Column {
                        required property var modelData
                        width: barRow.barW
                        spacing: 6
                        Item {
                            width: parent.width
                            height: 110
                            Rectangle {
                                visible: !modelData.off
                                anchors.fill: parent
                                radius: 9
                                color: root.t.pSurfaceDivider
                                border.width: root.t.borderWidth
                                border.color: modelData.today ? root.t.colBorder : root.t.pLine
                                clip: true
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: root.t.borderWidth
                                    height: (parent.height - root.t.borderWidth * 2) * modelData.fill
                                    radius: 6
                                    color: modelData.today ? "transparent" : root.t.pInk
                                    gradient: modelData.today ? todayLit : null
                                    Gradient {
                                        id: todayLit
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: root.t.accentMint }
                                        GradientStop { position: 1; color: root.t.accentCyan }
                                    }
                                }
                            }
                            Rectangle {
                                visible: modelData.off
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 9
                                radius: 5
                                color: root.t.pLine
                            }
                        }
                        Txt {
                            anchors.horizontalCenter: parent.horizontalCenter
                            theme: root.t
                            font.pixelSize: 14
                            weight: modelData.today ? 800 : 400
                            text: modelData.label
                        }
                    }
                }
            }
        }
    }
}
