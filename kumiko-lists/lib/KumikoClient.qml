import QtQuick
import Quickshell.Io

// Calls Kumiko's API with curl, one Process per call, like the shell does for its own
// network work. The token goes to curl through the environment (KUMIKO_AUTH), never on
// its command line, so `ps` can't show it.
//
//   KumikoClient { id: api; server: host.settings.server; token: host.secrets.token }
//   api.call("GET", "/lists/today", null, (status, body) => { ... })
//
// `status` is the HTTP status, 0 when Kumiko could not be reached (no network, a
// timeout, curl missing); `body` is the parsed JSON or null.
QtObject {
    id: root

    property string server: "https://kumiko.ink"
    property string token: ""
    readonly property bool ready: root.token !== ""
    readonly property string base: String(root.server).replace(/\/+$/, "") + "/api"

    // Calls in flight, so a widget can show that it is waiting.
    property int busy: 0

    property Component runner: Component {
        Process {
            id: proc
            property var done: null
            stdout: StdioCollector {
                id: out
            }
            onExited: code => {
                const text = out.text
                const cut = text.lastIndexOf("\n")
                const status = code === 0 ? (parseInt(text.slice(cut + 1)) || 0) : 0
                let body = null
                try {
                    body = JSON.parse(cut >= 0 ? text.slice(0, cut) : "")
                } catch (e) {
                    body = null
                }
                root.busy = Math.max(0, root.busy - 1)
                const cb = proc.done
                // Not destroyed inside its own signal handler.
                Qt.callLater(() => proc.destroy())
                if (cb)
                    cb(status, body)
            }
        }
    }

    function call(method, path, body, done) {
        if (!root.ready) {
            if (done)
                done(401, null)
            return
        }
        const args = ["-X", method, root.base + path]
        if (body !== null && body !== undefined)
            args.push("-H", "Content-Type: application/json", "--data-binary", JSON.stringify(body))
        const p = root.runner.createObject(root, {
            done: done,
            environment: { KUMIKO_AUTH: "Authorization: Bearer " + root.token },
            command: ["sh", "-c",
                "exec curl -sS -m 15 -H \"$KUMIKO_AUTH\" -H 'Accept: application/json' -w '\\n%{http_code}' \"$@\"",
                "sh"].concat(args)
        })
        root.busy++
        p.running = true
    }

    // A key Kumiko uses to recognise a retried write, so a tick sent twice counts once.
    function idempotencyKey() {
        return "spk-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 1e9).toString(36)
    }

    function openInBrowser(path) {
        Qt.openUrlExternally(String(root.server).replace(/\/+$/, "") + (path || ""))
    }
}
