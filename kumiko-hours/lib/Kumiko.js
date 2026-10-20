.pragma library

// What the three widgets work out from Kumiko's answers: times, an item's state, the
// session, the week, and which message an error gets. Pure functions, no Qt: the tests
// run this file in node (tests/kumiko_unit.js). doc/KUMIKO-API.md has the shapes.

var DAY = 86400000

function pad2(n) {
    return (n < 10 ? "0" : "") + n
}

// 13338000 -> "3:42:18"
function hms(ms) {
    var s = Math.max(0, Math.floor(ms / 1000))
    return Math.floor(s / 3600) + ":" + pad2(Math.floor(s % 3600 / 60)) + ":" + pad2(s % 60)
}

// 12240000 -> "3:24"; a negative balance keeps its sign ("-0:53")
function hm(ms) {
    var neg = ms < 0
    var m = Math.floor(Math.abs(ms) / 60000)
    return (neg ? "-" : "") + Math.floor(m / 60) + ":" + pad2(m % 60)
}

// A balance as the design writes it: "+0:10", "-2:05"
function signedHm(ms) {
    return ms >= 0 ? "+" + hm(ms) : hm(ms)
}

// Epoch ms -> "09:00" in the local time zone (or 12-hour, "9:00 AM")
function clock(at, use24h) {
    var d = new Date(at)
    if (use24h !== false)
        return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
    var h = d.getHours() % 12 || 12
    return h + ":" + pad2(d.getMinutes()) + (d.getHours() < 12 ? " AM" : " PM")
}

// How long ago, short: "now", "8m", "2h", "1d"
function ago(at, now) {
    var m = Math.floor((now - at) / 60000)
    if (m < 1) return "now"
    if (m < 60) return m + "m"
    if (m < 60 * 24) return Math.floor(m / 60) + "h"
    return Math.floor(m / 1440) + "d"
}

// Local YYYY-MM-DD, what Hours wants as `date` (its default "today" is the server's zone)
function dateKey(at) {
    var d = new Date(at)
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// ===== lists =====

// One of today's rows, as the widget draws it. A scheduled item stays `open` after it is
// ticked (it moves on to its next occurrence), so "done today" is the occurrence's event,
// or failing that today's event.
//   { id, listId, title, meta, state: "open" | "done" | "skipped", late, time, eventId, item }
function listRow(item, listTitles, now, use24h) {
    var ev = item.occurrenceEvent || item.todayEvent || null
    var state = ev === "completed" ? "done" : (ev === "skipped" ? "skipped" : "open")
    if (state === "open" && item.state === "completed")
        state = "done"
    var due = item.occurrenceAt || item.nextDueAt || null
    var late = state === "open" && due !== null && due < now
    var at = state === "open" ? due : (item.occurrenceEventAt || item.todayEventAt || null)
    var hasTime = item.schedule && item.schedule.time
    return {
        id: item.id,
        listId: item.listId,
        title: item.title || "",
        meta: rowMeta(item, listTitles ? listTitles[item.listId] : "", state),
        state: state,
        late: late,
        time: at !== null && (state !== "open" || hasTime) ? clock(at, use24h) : "",
        eventId: item.occurrenceEventId || null,
        item: item
    }
}

// "Medication · 450 mg · 2 tablet", "Groceries · 2 L", "Habits · skipped"
function rowMeta(item, listTitle, state) {
    var parts = []
    if (listTitle) parts.push(listTitle)
    var k = item.kindData || {}
    if (k.strength && k.strength.amount)
        parts.push(k.strength.amount + " " + (k.strength.unit || ""))
    if (k.perDose)
        parts.push(k.perDose + " " + (k.form || item.unit || ""))
    else if (item.quantity)
        parts.push(item.quantity + (item.unit ? " " + item.unit : ""))
    if (k.prn) parts.push("as needed")
    if (state === "skipped") parts.push("skipped")
    return parts.map(function (p) { return String(p).trim() }).join(" · ")
}

// The rows in the order the card shows them: done first by when, then open by due time
// (Kumiko already sorts by nextDueAt; done rows keep that order too).
function listRows(items, listTitles, now, use24h, showDone) {
    var rows = (items || []).map(function (it) { return listRow(it, listTitles, now, use24h) })
    if (showDone === false)
        rows = rows.filter(function (r) { return r.state === "open" })
    var settled = rows.filter(function (r) { return r.state !== "open" })
    var open = rows.filter(function (r) { return r.state === "open" })
    return settled.concat(open)
}

function listCounts(rows) {
    var done = 0
    for (var i = 0; i < rows.length; i++)
        if (rows[i].state !== "open") done++
    return { done: done, total: rows.length, left: rows.length - done }
}

// The next thing to do: the first open row, overdue first.
function nextRow(rows) {
    var open = rows.filter(function (r) { return r.state === "open" })
    var late = open.filter(function (r) { return r.late })
    return late.length ? late[0] : (open.length ? open[0] : null)
}

// ===== hours =====

function pauseTypes(activity) {
    return ((activity && activity.segmentTypes) || []).filter(function (t) { return t.kind === "pause" })
}

// The activity to follow: the setting (id or slug), else the first one.
function pickActivity(activities, wanted) {
    var list = (activities || []).filter(function (a) { return !a.archived })
    for (var i = 0; i < list.length; i++)
        if (wanted && (list[i].id === wanted || list[i].slug === wanted)) return list[i]
    return list.length ? list[0] : null
}

// Kumiko colours are CSS: a hex is used, anything else ("var(--accent)") is not.
function activityColor(activity) {
    var c = activity ? String(activity.color || "") : ""
    return /^#[0-9a-fA-F]{6}$/.test(c) ? c : ""
}

// The session that is open now for this activity, as the widget draws it. `fetchedAt` is
// when the answer came; a running session's times grow from there by the local clock.
//   { status: "running" | "paused" | "none", startedAt, elapsedMs, countedMs,
//     pauseName, pauseSince, spans: [{ kind: "work" | "pause", ms, open }] }
function sessionNow(sessions, activity, fetchedAt, now) {
    var mine = (sessions || []).filter(function (s) { return activity && s.activityId === activity.id })
    var open = null
    for (var i = 0; i < mine.length; i++)
        if (mine[i].status === "running" || mine[i].status === "paused") open = mine[i]
    var countedToday = 0
    for (var j = 0; j < mine.length; j++)
        countedToday += mine[j].countedMs || 0
    var grow = Math.max(0, now - fetchedAt)
    var out = { status: "none", startedAt: null, elapsedMs: 0, countedMs: countedToday, todayCountedMs: countedToday,
                pauseName: "", pauseSince: null, pauseMs: 0, spans: spansOf(mine, now), sessionId: null }
    if (!open)
        return out
    out.status = open.status
    out.sessionId = open.id
    out.startedAt = open.startedAt
    out.elapsedMs = (open.elapsedMs || 0) + grow
    out.countedMs = countedToday + (open.status === "running" ? grow : 0)
    out.todayCountedMs = out.countedMs
    if (open.status === "paused") {
        var seg = openSegment(open)
        var types = pauseTypes(activity)
        for (var k = 0; seg && k < types.length; k++)
            if (types[k].id === seg.typeId) out.pauseName = types[k].name
        out.pauseSince = seg ? seg.startedAt : null
        out.pauseMs = seg ? Math.max(0, now - seg.startedAt) : 0
    }
    return out
}

function openSegment(session) {
    var segs = session.segments || []
    for (var i = segs.length - 1; i >= 0; i--)
        if (!segs[i].endedAt) return segs[i]
    return null
}

// Today's sessions as alternating work and pause spans, in time order, for the bar.
function spansOf(sessions, now) {
    var spans = []
    sessions.slice().sort(function (a, b) { return a.startedAt - b.startedAt }).forEach(function (s) {
        var end = s.endedAt || now
        var t = s.startedAt
        var segs = (s.segments || []).slice().sort(function (a, b) { return a.startedAt - b.startedAt })
        segs.forEach(function (g) {
            if (g.startedAt > t) spans.push({ kind: "work", ms: g.startedAt - t, open: false })
            var gEnd = g.endedAt || now
            spans.push({ kind: "pause", ms: Math.max(0, gEnd - g.startedAt), open: !g.endedAt && !s.endedAt })
            t = Math.max(t, gEnd)
        })
        if (end > t) spans.push({ kind: "work", ms: end - t, open: !s.endedAt && s.status === "running" })
    })
    return spans
}

// The week from /hours/overview as seven bars: { label, target, fill (0..1), today, live, off }
function weekBars(overview, todayKey) {
    var labels = ["S", "M", "T", "W", "T", "F", "S"]
    return ((overview && overview.days) || []).map(function (d) {
        var parts = d.date.split("-")
        var wd = new Date(+parts[0], +parts[1] - 1, +parts[2]).getDay()
        var off = !(d.targetMs > 0)
        return {
            label: labels[wd],
            off: off,
            fill: off ? 0 : Math.max(0, Math.min(1, d.countedMs / d.targetMs)),
            today: d.date === todayKey,
            live: !!d.live,
            mark: d.mark || null
        }
    })
}

// Balance to date: Kumiko's balanceMs of the days before today. Today is left out while it
// is under way, or every morning would read as hours behind.
function balanceToDate(overview, todayKey) {
    var b = 0
    var days = (overview && overview.days) || []
    for (var i = 0; i < days.length; i++)
        if (days[i].date < todayKey) b += days[i].balanceMs || 0
    return b
}

// ===== notifications =====

function notifRow(n, now) {
    var meta = [n.source || "", ago(n.createdAt, now)].filter(function (x) { return x }).join(" · ")
    var body = String(n.body || "").split("\n")[0]
    return {
        id: n.id,
        title: n.title || "",
        body: body.length > 80 ? body.slice(0, 79) + "…" : body,
        meta: meta,
        unread: !n.readAt,
        high: n.priority === "high",
        url: n.action && n.action.type === "open_url" ? String(n.action.url || "") : ""
    }
}

// Unread first (newest first within each), then read; at most `limit`.
function notifRows(list, now, limit, unreadOnly) {
    var rows = (list || []).map(function (n) { return notifRow(n, now) })
    var unread = rows.filter(function (r) { return r.unread })
    var read = unreadOnly ? [] : rows.filter(function (r) { return !r.unread })
    return unread.concat(read).slice(0, limit || 5)
}

// One event of the stream, "event: notifications" + "data: {...}": feed it lines, it
// answers the event when a blank line ends it, or as soon as its data is whole JSON:
// Quickshell's SplitParser does not pass empty lines on, so the blank line may never come.
function SseReader() {
    this.event = ""
    this.data = []
}
SseReader.prototype.line = function (l) {
    if (l === "" || l === "\r") {
        var ev = this.event, data = this.data.join("\n")
        this.event = ""
        this.data = []
        if (!data) return null
        try { return { event: ev || "message", data: JSON.parse(data) } } catch (e) { return null }
    }
    if (l.charAt(0) === ":") return null
    var at = l.indexOf(":")
    var field = at < 0 ? l : l.slice(0, at)
    var value = at < 0 ? "" : l.slice(at + 1).replace(/^ /, "").replace(/\r$/, "")
    if (field === "event") {
        this.event = value
        this.data = []
    } else if (field === "data") {
        this.data.push(value)
        try {
            var whole = JSON.parse(this.data.join("\n"))
            var ev = this.event || "message"
            this.event = ""
            this.data = []
            return { event: ev, data: whole }
        } catch (e) {}
    }
    return null
}

// ===== errors =====

// What a failed call means for the widget, from its HTTP status and Kumiko's error
// envelope { error: { code, message } }. `scope` is the module's ("lists:write").
//   { kind: "token" | "scope" | "space" | "offline" | "conflict" | "refused" | "other",
//     title, text }
function problem(status, body, scope) {
    var err = (body && body.error) || {}
    var msg = String(err.message || "")
    if (status === 0)
        return { kind: "offline", title: "Can't reach Kumiko", text: "Showing what it said last." }
    if (status === 401)
        return { kind: "token", title: "Sign-in expired",
                 text: "This token was revoked or has expired. Make a new one in Kumiko on a computer and put it in ~/.config/sekaipop-kumiko/token." }
    if (status === 403 && err.code === "token_wrong_space")
        return { kind: "space", title: "Token is for another space",
                 text: "Switch to the right space in Kumiko and make the token there." }
    if (status === 403) {
        var m = /lacks\s+([a-z-]+:[a-z]+)/.exec(msg)
        var lacking = m ? m[1] : scope
        return { kind: "scope", title: "Not allowed",
                 text: "This token lacks " + lacking + ". Add it to the token in Kumiko, or use another token." }
    }
    if (status === 409)
        return { kind: "conflict", title: "Already changed", text: msg }
    return { kind: "other", title: "Kumiko said no", text: msg || ("HTTP " + status) }
}

if (typeof module !== "undefined")
    module.exports = { hms: hms, hm: hm, signedHm: signedHm, clock: clock, ago: ago, dateKey: dateKey,
                       listRow: listRow, listRows: listRows, listCounts: listCounts, nextRow: nextRow, rowMeta: rowMeta,
                       pauseTypes: pauseTypes, pickActivity: pickActivity, activityColor: activityColor,
                       sessionNow: sessionNow, spansOf: spansOf, weekBars: weekBars, balanceToDate: balanceToDate,
                       notifRow: notifRow, notifRows: notifRows, SseReader: SseReader, problem: problem, DAY: DAY }
