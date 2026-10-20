# The Kumiko API, as these widgets use it

Read on 2026-10-20 from the Kumiko source (private repo `masshirodev/kumiko`) and from live
read-only calls. Kumiko is the source of truth; when this disagrees with it, Kumiko is right
and this file is out of date. Its live OpenAPI spec is `/api/openapi.json` (scope `api:read`).

## Host and auth

- Base: `https://kumiko.ink/api`. The old hosts (`lattice.masshiro.pro`, `apps.masshiro.pro`)
  still proxy `/api`, but don't follow a redirect across hosts: it can drop the
  `Authorization` header.
- `Authorization: Bearer wh_...`, made in Kumiko at **Settings > API tokens** (desktop only).
  OAuth tokens are refused on REST (they are bound to `/api/mcp`).
- Scopes, one per path prefix; GET needs `:read`, anything else `:write` (write implies read):
  `lists:write`, `hours:write`, `notifications:write`. One token with all three serves the
  three widgets; a token per widget with only its own scope works too.
- Refusals: `401` bad / expired / revoked token; `403 token_wrong_space` token from another
  space; `403` "This API token lacks X" missing scope. Errors are
  `{ "error": { "code", "message", "details"? } }`.
- No REST rate limit, no cache headers, CORS irrelevant (native client). Send
  `Content-Type: application/json` on writes.

## Lists

- `GET /lists/today` -> `{ items }`: open items due by the end of today (the account's time
  zone) and items with an event today, sorted by `nextDueAt`. Optional `from` / `until` (ms).
- `GET /lists` -> `{ lists: [{ id, title, kind, archived, ... }] }`. Today's rows carry only
  `listId`: join on it for the list's title.
- Item fields used: `id, listId, title, notes, quantity, unit, state, schedule, kindData,
  nextDueAt, todayEvent, todayEventAt, occurrenceAt, occurrenceEvent, occurrenceEventId, rev`.
  **A scheduled item stays `state: "open"` after it is ticked** (it moves on to its next
  occurrence): "done today" is `occurrenceEvent === "completed"` (or `"skipped"`), or
  `todayEvent`. Medication items carry `kindData.strength { amount, unit }`, `perDose`.
- `POST /lists/{id}/items/{itemId}/complete` (also `/skip`, `/reverse`, `/retime`), body
  `{ idempotencyKey, occurredAt?, scheduledFor?, note?, rev? }`; `reverse` also takes
  `reverses` (the event id). Answers `{ item, event: { id, type, occurredAt, scheduledFor },
  replayed }`. `409` when the list's kind refuses (an as-needed dose too soon, over the cap) or
  the list is archived.

## Hours

- No single "now" endpoint. `GET /hours/sessions?date=YYYY-MM-DD&scope=day` ->
  `{ activities, sessions }`, open sessions always included (also ones started before
  midnight). `SessionView`: `id, activityId, startedAt, endedAt, status (running | paused |
  ended), elapsedMs, countedMs, segments: [{ id, typeId, startedAt, endedAt }]`. The open pause
  is the segment with no `endedAt`. Always pass `date`: the default "today" is the
  **instance's** time zone, not the account's.
- `GET /hours/overview?activity=X&date=...&scope=week` -> `{ days: [{ date, countedMs,
  targetMs, balanceMs, creditMs, mark, live, recorded }], countedMs, targetMs, creditMs,
  ledger }`. Prefer it over `/hours/summary`, whose targets read 0 for weekly targets.
  `activity` is required.
- `GET /hours/activities` -> `{ activities: [{ id, name, slug, color, icon, kind,
  segmentTypes: [{ id, name, kind (pause | active), counts }] }] }`.
- `POST /hours/clock`, body `{ action: start | end | pause | resume | revert, activityId?
  (id or slug), typeId? (pause type), at? (ms, ignored if > 30 s off), writeId (revert) }` ->
  `{ action, activity, session, openedSegmentId, closedSegmentIds, writeId }`. `409` when
  already running / not running / already paused.

## Notifications

- `GET /notifications?state=all|unread|read&source=&before=&limit=` (max 100) ->
  `{ notifications, count, unread }` (`unread` is the account's total).
- Fields: `id, title, body, source, priority (low | normal | high), action ({ type: "none" } |
  { type: "open_url", url } | { type: "open_app", ... }), createdAt, readAt` (null = unread).
- `PATCH /notifications/{id}` `{ "read": true }`; `DELETE /notifications/{id}` dismisses;
  `POST /notifications/read-all` -> `{ marked, unread }`.
- **Live:** `GET /notifications/stream` (SSE): `event: notifications` with `{ unread,
  notifications }` (newest 20) on connect and on every change, `: ping` every 15 s; a
  reconnect gets a full snapshot. Bearer auth on it is expected to work (inferred from the
  hooks, not yet tried). Lists and Hours have no stream: poll them.
