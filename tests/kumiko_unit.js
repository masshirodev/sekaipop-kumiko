// The widgets' pure logic (shared/Kumiko.js), in node: node tests/kumiko_unit.js
const assert = require("assert")
const fs = require("fs")
const path = require("path")
const vm = require("vm")

const src = fs.readFileSync(path.join(__dirname, "../shared/Kumiko.js"), "utf8").replace(/^\.pragma library\s*$/m, "")
const ctx = { module: { exports: {} } }
vm.createContext(ctx)
vm.runInContext(src, ctx)
const K = ctx.module.exports

let n = 0
// Values made inside the vm context are another realm's arrays: compare as JSON.
function same(a, b) {
    assert.strictEqual(JSON.stringify(a), JSON.stringify(b))
}
function check(name, fn) {
    fn()
    n++
}

// fixed local times, so the tests don't depend on the machine's zone
const at = (h, m) => new Date(2026, 9, 20, h, m, 0).getTime()
const NOW = at(15, 57)

check("durations", () => {
    assert.strictEqual(K.hms(13338000), "3:42:18")
    assert.strictEqual(K.hm(12240000), "3:24")
    assert.strictEqual(K.hm(-3180000), "-0:53")
    assert.strictEqual(K.signedHm(600000), "+0:10")
    assert.strictEqual(K.hms(-5), "0:00:00")
})

check("clock and ago", () => {
    assert.strictEqual(K.clock(at(9, 0)), "09:00")
    assert.strictEqual(K.clock(at(21, 5), false), "9:05 PM")
    assert.strictEqual(K.ago(NOW - 8 * 60000, NOW), "8m")
    assert.strictEqual(K.ago(NOW - 2 * 3600000, NOW), "2h")
    assert.strictEqual(K.ago(NOW - 26 * 3600000, NOW), "1d")
    assert.strictEqual(K.ago(NOW, NOW), "now")
    assert.strictEqual(K.dateKey(at(0, 5)), "2026-10-20")
})

// Shapes from GET /lists/today (doc/KUMIKO-API.md)
const titles = { lst_med: "Medication", lst_home: "Home", lst_shop: "Groceries", lst_hab: "Habits" }
const items = [
    { id: "a", listId: "lst_med", title: "Vitamin D", state: "open", schedule: { type: "daily", time: "08:00" },
      kindData: { strength: { amount: 1000, unit: "IU" }, form: "cap", perDose: 1 }, nextDueAt: at(8, 0) + 86400000,
      todayEvent: "completed", todayEventAt: at(8, 12), occurrenceAt: at(8, 0), occurrenceEvent: "completed", occurrenceEventAt: at(8, 12), occurrenceEventId: "lev_1" },
    { id: "b", listId: "lst_home", title: "Water the plants", state: "open", schedule: { type: "daily", time: "09:00" },
      kindData: {}, nextDueAt: at(9, 0), todayEvent: null, occurrenceAt: at(9, 0), occurrenceEvent: null },
    { id: "c", listId: "lst_shop", title: "Oat milk", state: "open", schedule: {}, quantity: "2", unit: "L", kindData: {}, nextDueAt: null },
    { id: "d", listId: "lst_hab", title: "Journal", state: "open", schedule: { type: "daily", time: "08:30" }, kindData: {},
      nextDueAt: at(8, 30) + 86400000, todayEvent: "skipped", todayEventAt: at(8, 30), occurrenceEvent: "skipped", occurrenceEventAt: at(8, 30) },
    { id: "e", listId: "lst_hab", title: "Stretch", state: "open", schedule: { type: "daily", time: "18:00" }, kindData: {}, nextDueAt: at(18, 0), occurrenceAt: at(18, 0) }
]

check("a ticked scheduled item is done though its state stays open", () => {
    const r = K.listRow(items[0], titles, NOW)
    assert.strictEqual(r.state, "done")
    assert.strictEqual(r.time, "08:12")
    assert.strictEqual(r.meta, "Medication · 1000 IU · 1 cap")
    assert.strictEqual(r.eventId, "lev_1")
    assert.strictEqual(r.late, false)
})

check("overdue, unscheduled, skipped", () => {
    const late = K.listRow(items[1], titles, NOW)
    assert.ok(late.late && late.state === "open" && late.time === "09:00")
    const milk = K.listRow(items[2], titles, NOW)
    assert.strictEqual(milk.meta, "Groceries · 2 L")
    assert.strictEqual(milk.time, "")
    assert.strictEqual(milk.late, false)
    const skip = K.listRow(items[3], titles, NOW)
    assert.strictEqual(skip.state, "skipped")
    assert.strictEqual(skip.meta, "Habits · skipped")
    assert.strictEqual(K.listRow(items[4], titles, NOW).late, false)
})

check("rows: settled first, counts, the next thing", () => {
    const rows = K.listRows(items, titles, NOW)
    same(rows.map(r => r.id), ["a", "d", "b", "c", "e"])
    same(K.listCounts(rows), { done: 2, total: 5, left: 3 })
    assert.strictEqual(K.nextRow(rows).id, "b")
    same(K.listRows(items, titles, NOW, true, false).map(r => r.id), ["b", "c", "e"])
    assert.strictEqual(K.nextRow([]), null)
})

check("an as-needed dose says so", () => {
    const r = K.listRow({ id: "x", listId: "lst_med", title: "Ibuprofen", state: "open", schedule: {},
        kindData: { strength: { amount: 200, unit: "mg" }, form: "tab", perDose: 1, prn: { minIntervalHours: 4 } } }, titles, NOW)
    assert.strictEqual(r.meta, "Medication · 200 mg · 1 tab · as needed")
})

// Shapes from /hours/activities and /hours/sessions
const work = { id: "hac_w", name: "Work", slug: "work", color: "var(--accent)", archived: false,
               segmentTypes: [{ id: "hst_l", name: "Lunch", kind: "pause", counts: false }, { id: "hst_b", name: "Break", kind: "pause", counts: false }] }
const gym = { id: "hac_g", name: "Gym", slug: "gym", color: "#3b82f6", archived: false, segmentTypes: [{ id: "hst_w", name: "Warm-up", kind: "active", counts: true }] }
const old = { id: "hac_o", name: "Old", slug: "old", color: "#000000", archived: true, segmentTypes: [] }

check("activities", () => {
    assert.strictEqual(K.pickActivity([old, work, gym], "").id, "hac_w")
    assert.strictEqual(K.pickActivity([work, gym], "gym").id, "hac_g")
    assert.strictEqual(K.pickActivity([work, gym], "hac_g").id, "hac_g")
    assert.strictEqual(K.pickActivity([old], ""), null)
    assert.strictEqual(K.activityColor(work), "")
    assert.strictEqual(K.activityColor(gym), "#3b82f6")
    same(K.pauseTypes(work).map(t => t.name), ["Lunch", "Break"])
    assert.strictEqual(K.pauseTypes(gym).length, 0)
})

check("a running session grows by the local clock", () => {
    const s = [{ id: "s1", activityId: "hac_w", startedAt: at(12, 15), endedAt: null, status: "running", elapsedMs: 3 * 3600000, countedMs: 2.5 * 3600000,
                 segments: [{ id: "g1", typeId: "hst_l", startedAt: at(13, 0), endedAt: at(13, 30) }] }]
    const v = K.sessionNow(s, work, NOW - 60000, NOW)
    assert.strictEqual(v.status, "running")
    assert.strictEqual(v.elapsedMs, 3 * 3600000 + 60000)
    assert.strictEqual(v.countedMs, 2.5 * 3600000 + 60000)
    same(v.spans.map(x => x.kind), ["work", "pause", "work"])
    assert.strictEqual(v.spans[2].open, true)
    assert.strictEqual(v.spans[1].ms, 30 * 60000)
})

check("a paused session names its pause and freezes the count", () => {
    const s = [{ id: "s1", activityId: "hac_w", startedAt: at(12, 15), status: "paused", elapsedMs: 3 * 3600000, countedMs: 2 * 3600000,
                 segments: [{ id: "g1", typeId: "hst_l", startedAt: at(15, 45), endedAt: null }] }]
    const v = K.sessionNow(s, work, NOW - 60000, NOW)
    assert.strictEqual(v.status, "paused")
    assert.strictEqual(v.pauseName, "Lunch")
    assert.strictEqual(v.pauseMs, 12 * 60000)
    assert.strictEqual(v.countedMs, 2 * 3600000)
    assert.strictEqual(v.spans[v.spans.length - 1].kind, "pause")
})

check("no open session: today's ended ones still count", () => {
    const s = [{ id: "s0", activityId: "hac_w", startedAt: at(8, 0), endedAt: at(11, 0), status: "ended", elapsedMs: 3 * 3600000, countedMs: 3 * 3600000, segments: [] },
               { id: "sg", activityId: "hac_g", startedAt: at(7, 0), endedAt: at(8, 0), status: "ended", elapsedMs: 3600000, countedMs: 3600000, segments: [] }]
    const v = K.sessionNow(s, work, NOW, NOW)
    assert.strictEqual(v.status, "none")
    assert.strictEqual(v.todayCountedMs, 3 * 3600000)
    assert.strictEqual(v.spans.length, 1)
})

// Shape from /hours/overview?scope=week
const overview = { countedMs: 60392108, targetMs: 158400000, days: [
    { date: "2026-10-19", countedMs: 31920000, targetMs: 31680000, balanceMs: 240000, live: false, mark: null },
    { date: "2026-10-20", countedMs: 13308000, targetMs: 31680000, balanceMs: -18372000, live: true, mark: null },
    { date: "2026-10-21", countedMs: 0, targetMs: 31680000, balanceMs: -31680000, live: false, mark: null },
    { date: "2026-10-22", countedMs: 0, targetMs: 31680000, balanceMs: -31680000, live: false, mark: null },
    { date: "2026-10-23", countedMs: 0, targetMs: 31680000, balanceMs: -31680000, live: false, mark: null },
    { date: "2026-10-24", countedMs: 0, targetMs: 0, balanceMs: 0, live: false, mark: null },
    { date: "2026-10-25", countedMs: 0, targetMs: 0, balanceMs: 0, live: false, mark: null }] }

check("the week as bars", () => {
    const bars = K.weekBars(overview, "2026-10-20")
    same(bars.map(b => b.label).join(""), "MTWTFSS")
    assert.strictEqual(bars[0].fill, 1)
    assert.ok(bars[1].today && bars[1].live && Math.abs(bars[1].fill - 0.42) < 0.01)
    assert.ok(bars[5].off && bars[6].off && !bars[2].off)
    assert.strictEqual(K.balanceToDate(overview, "2026-10-20"), 240000)
})

check("notifications: unread first, one line of body, link mark", () => {
    const list = [
        { id: "1", title: "Weekly review is ready", source: "planning", priority: "normal", action: { type: "none" }, createdAt: NOW - 86400000, readAt: NOW - 1000 },
        { id: "2", title: "Invoice INV-0042 overdue", body: "3 days past its due date\nmore", source: "cash", priority: "high", action: { type: "none" }, createdAt: NOW - 8 * 60000, readAt: null },
        { id: "3", title: "CI failed on main", source: "code", priority: "normal", action: { type: "open_url", url: "https://example.org/run" }, createdAt: NOW - 41 * 60000, readAt: null }
    ]
    const rows = K.notifRows(list, NOW, 5)
    same(rows.map(r => r.id), ["2", "3", "1"])
    assert.strictEqual(rows[0].body, "3 days past its due date")
    assert.strictEqual(rows[0].meta, "cash · 8m")
    assert.ok(rows[0].high && rows[0].unread && !rows[2].unread)
    assert.strictEqual(rows[1].url, "https://example.org/run")
    same(K.notifRows(list, NOW, 5, true).map(r => r.id), ["2", "3"])
    assert.strictEqual(K.notifRows(list, NOW, 1).length, 1)
})

check("the stream reader", () => {
    const r = new K.SseReader()
    assert.strictEqual(r.line(": ping"), null)
    assert.strictEqual(r.line("event: notifications"), null)
    assert.strictEqual(r.line('data: {"unread":4,'), null)
    assert.strictEqual(r.line('data: "notifications":[]}'), null)
    const ev = r.line("")
    assert.strictEqual(ev.event, "notifications")
    assert.strictEqual(ev.data.unread, 4)
    assert.strictEqual(r.line(""), null)
    assert.strictEqual(r.line("data: not json"), null)
    assert.strictEqual(r.line(""), null)
})

check("problems, by status and error code", () => {
    assert.strictEqual(K.problem(0, null, "lists:write").kind, "offline")
    assert.strictEqual(K.problem(401, null, "lists:write").kind, "token")
    assert.strictEqual(K.problem(403, { error: { code: "token_wrong_space", message: "" } }, "lists:write").kind, "space")
    const scope = K.problem(403, { error: { code: "forbidden", message: "This API token lacks notifications:read" } }, "notifications:write")
    assert.strictEqual(scope.kind, "scope")
    assert.ok(scope.text.indexOf("notifications:read") >= 0)
    assert.strictEqual(K.problem(409, { error: { code: "conflict", message: "Already paused" } }, "hours:write").kind, "conflict")
    assert.strictEqual(K.problem(500, null, "hours:write").kind, "other")
})

console.log("kumiko_unit: " + n + " checks passed")
