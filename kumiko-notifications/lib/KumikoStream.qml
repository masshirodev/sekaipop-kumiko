import QtQuick
import Quickshell.Io
import "Kumiko.js" as K

// Kumiko's notification stream (GET /api/notifications/stream, server-sent events), read
// by `curl -N` while `active`. Every event is a full snapshot { unread, notifications }
// (the newest 20); a reconnect gets one again, so a dropped stream loses nothing. It
// reconnects by itself, waiting longer each time it fails (2 s, 4 s ... 60 s).
QtObject {
    id: root

    property string server: "https://kumiko.ink"
    property string token: ""
    property bool active: false

    // "off" | "connecting" | "live" | "reconnecting"
    property string state: "off"
    // The HTTP status of the last failed attempt (401, 403 ...), 0 when it never got one.
    property int failStatus: 0

    signal snapshot(var data)

    readonly property bool wanted: root.active && root.token !== ""
    onWantedChanged: root.restart()
    onServerChanged: root.restart()
    onTokenChanged: root.restart()

    property int backoff: 2000
    property var reader: new K.SseReader()

    function restart() {
        retry.stop()
        proc.running = false
        root.backoff = 2000
        if (root.wanted) {
            root.state = "connecting"
            Qt.callLater(() => { if (root.wanted) proc.running = true })
        } else {
            root.state = "off"
        }
    }

    property Process proc: Process {
        environment: ({ KUMIKO_AUTH: "Authorization: Bearer " + root.token })
        // --fail makes curl stop with exit 22 on 4xx / 5xx; -w prints the status after.
        command: ["sh", "-c",
            "exec curl -sS -N --fail -H \"$KUMIKO_AUTH\" -H 'Accept: text/event-stream' -w '\\n\\036%{http_code}\\n' \"$1\"",
            "sh", String(root.server).replace(/\/+$/, "") + "/api/notifications/stream"]
        stdout: SplitParser {
            onRead: line => {
                if (line.charAt(0) === "\x1e") {
                    root.failStatus = parseInt(line.slice(1)) || 0
                    return
                }
                const ev = root.reader.line(line)
                if (ev && ev.event === "notifications") {
                    root.state = "live"
                    root.backoff = 2000
                    root.failStatus = 0
                    root.snapshot(ev.data)
                }
            }
        }
        onExited: code => {
            root.reader = new K.SseReader()
            if (!root.wanted)
                return
            root.state = "reconnecting"
            retry.interval = root.backoff
            root.backoff = Math.min(60000, root.backoff * 2)
            retry.restart()
        }
    }

    property Timer retry: Timer {
        repeat: false
        onTriggered: {
            if (root.wanted)
                root.proc.running = true
        }
    }
}
