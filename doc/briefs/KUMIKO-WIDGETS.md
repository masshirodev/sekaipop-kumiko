# Brief: Kumiko desktop widgets for SekaiPop (Lists, Hours, Notifications)

**This repository:** https://github.com/masshirodev/sekaipop-kumiko (public). It is new: this
brief is its first file, and the three plugins will be built here from your design.

**SekaiPop, the shell the widgets live in:** https://github.com/Blapples/SekaiPop (public).
Read these first:

- `docs/PLUGINS.md`: what a desktop widget plugin is, what the shell does for it (placing,
  dragging, the card frame, Edit Desktop, Focus Mode) and what the widget gets (`host`: theme,
  settings, secrets, `working`, `editing`). **This is the whole interface; read it whole.** The
  theme names it promises are the only colours and type a plugin can use.
- `examples/plugins/hello-clock/`: the example plugin, for the size and feel of a plugin card.
- `sekaipop/modules/sekai/desktopWidgets/`: the built-in desktop cards. The closest in spirit
  are `TodoWidget.qml` (a list you tick), `CalendarCardWidget.qml` (dense, with a header and
  rows), `WeatherCardWidget.qml` and `UserCardWidget.qml` (small, one glance).
- `docs/shot-desktop-widgets.png` and `docs/shot-edit-desktop.png`: the desktop cards and Edit
  Desktop as they look today.
- `docs/briefs/PLUGIN-SETTINGS.md` and `docs/handoffs/plugin-settings/`: the last plugin brief
  and its handoff (Settings > Desktop > Plugins, where these widgets' settings will be edited).

**Kumiko, the app they show:** https://github.com/masshirodev/kumiko is **private**, so you may
not be able to open it. Everything the design needs from it is in this brief.

## What it is for

Kumiko is the owner's self-hosted everything-app: work hours, recurring lists (chores,
medication, habits), a notification inbox fed by CI runs and agents, and much more. Today it
lives in a browser tab. These three widgets put the three parts that are looked at all day on
the desktop, and let the most common action on each happen right there:

| Widget                  | Shows                                              | Does                                    |
| ----------------------- | -------------------------------------------------- | --------------------------------------- |
| **Kumiko Hours**        | whether a work session is running, today and the week against their targets | clock in, pause, resume, clock out |
| **Kumiko Lists**        | what is due today, and what is already done        | tick an item done (and undo it)         |
| **Kumiko Notifications** | the newest notifications, unread first            | mark read, mark all read, open one      |

They are **three separate plugins**, each its own card, so each is placed, sized, switched on
and copied to other monitors on its own. They share nothing visible except a family look: it
should be obvious at a glance that the three belong together, and just as obvious that they are
SekaiPop cards (the shell draws the card's frame; see "Look").

## The data, per widget

Field names are the Kumiko API's, so the design only asks for what exists. Sample values below
are made up.

### Hours

- **Activities**: each has a `name` ("Work", "Gym", "Japanese"), a `color`, and pause types
  (`segmentTypes` of kind `pause`: "Lunch", "Break"). The widget follows **one** activity, a
  setting (default: the first, usually Work).
- **The session** (`status`): `running` (since `startedAt`), `paused` (which pause, since when:
  the open segment), or none today. The server gives `countedMs` (time that counts, pauses
  left out) and `elapsedMs`. The clock call is one endpoint with `action`: `start`, `pause`
  (with which pause type), `resume`, `end`, and `revert` (undo the last clock call).
- **Totals**, per day and for the week: `countedMs` against `targetMs`, and `balanceMs` (how far
  ahead or behind). Today is `live` while a session runs, so its count grows. Example week:
  Mon 8:52 of 8:48, Tue 7:54 so far of 8:48 (live), Wed to Fri 0 of 8:48, Sat and Sun no target.
- A day can carry a `mark` (holiday, sick day) instead of a target.

Questions for the design: how big is the running timer against the totals; is the week a row
of seven small bars, one bar, or only a number; where do pause and its type choice go (a pause
type picker is needed only when the activity has more than one).

### Lists

- **Today's items** (`/api/lists/today`): items due today or earlier, plus items already handled
  today. Each has a `title`, optional `notes` ("after dinner"), the list it belongs to, a due
  time from its schedule ("21:00"), and today's outcome: still to do, `completed`, or
  `skipped`. Example: "Water the plants" 08:00 done, "Vitamin D" 1 tablet 08:00
  done, "Japanese study" 21:00, "Charge the bike" 22:00, "Take out the recycling" 22:00.
- **Medication-kind items** carry a dose: an amount and unit ("2 tablets", "450 mg"). Show it
  quietly; it matters for those rows only.
- An item can be overdue (due earlier than now and still open).
- **Ticking** records a completion; the answer can be used to **undo** it (a reversal). An item
  can also be **skipped** (not done today, on purpose). A tick can be refused (an as-needed medication taken too soon answers "not yet"); the widget needs a
  way to say so briefly.

Questions for the design: grouped by list or one list by time; how done items look (struck,
faded, moved down, hidden after a while); how many rows before it scrolls or says "+3 more".

### Notifications

- Each has a `title`, a `body` (can be long, multi-line: CI logs), a `source` ("kumiko-ci",
  "agent", "automation"), a `priority` (`low`, `normal`, `high`), `createdAt`, `readAt` (null =
  unread), and an `action`: none, or open a URL.
- The list answer also carries the `unread` count.
- **Live:** notifications arrive as they happen (Kumiko streams them), so a new one can appear
  while the widget is on screen. Lists and Hours refresh every few minutes instead.
- Actions: mark one read, mark all read, dismiss one, open one (the browser, at its URL, and it
  counts as read).

Questions for the design: how much of a body shows (one line, two, none); how `high` stands out
without shouting; whether read ones stay visible (faded) or only unread show.

## States to design, for each widget

1. **Normal**, with realistic content (use the samples above).
2. **Busy day / overflow**: many items, a long title, a long notification body.
3. **Empty**: nothing due today, no notifications, no session today. Each says so in one quiet
   line, the way SekaiPop's empty Quick Panel card does.
4. **Not set up**: no API token found, or the token is refused (expired, revoked, or missing
   the module's scope: say which). The widget is the first place the user learns this, so it
   says what to do: "Make a token in Kumiko (Settings > API tokens) and put it in
   `~/.config/sekaipop-kumiko/token`", with the env variable as the other option. One shared
   look for all three widgets.
5. **Can't reach Kumiko**: offline or server down. Keep showing the last data, marked as stale
   (since when), rather than going blank.
6. **An action in flight and an action refused**: the tick or the clock button while the call
   runs, and what a refusal looks like (one line, then gone).
7. **In Edit Desktop**: the shelf tile (each plugin's `icon` and `name`) and the card selected.

## Sizes

A widget is sized by its own content (`implicitWidth` x `implicitHeight`, design pixels, at the
shell's scale; between 24 and 1600 x 1200). Please design one default size per widget, and say
whether a **compact** setting (a smaller variant: Hours as a single line timer, Lists as a count
with the next item, Notifications as an unread badge with the newest title) is worth having. A
setting that changes the card's size is fine; it is a plugin setting like any other.

## Settings the design may ask for

Each plugin has its own settings, edited in SekaiPop's Settings > Desktop > Plugins (already
designed; the plugin only declares them). Strings, numbers and true / false only, with labels,
ranges and choices. Candidates: the server address (shared default `https://kumiko.ink`), how
often to refresh, Hours: which activity; Lists: which lists, show done items; Notifications: how
many, unread only. Add or drop as the design needs. The token is a **secret**, never a setting.

## Look

- **The shell draws the card's frame** (outline, ring, surface, hard shadow) around a plugin,
  like the built-in cards, unless the plugin asks for none (`frame: false`). Design inside that
  frame, or argue for `frame: false` if the widget needs its own shape.
- **Only the theme's colours and type**, through the names `docs/PLUGINS.md` promises
  (`pSurface`, `pInk`, `pInkSub`, `pLine`, `chipFill`, `chipInk`, `accentCyan`, `accentMint`,
  `colBorder`, `dark`, `fontFamily`, `fontStyleBold`, `iconFont`, `borderWidth`, `radiusOuter`).
  It must work in Light, Dark and Darker modes and with every theme, including Matugen (colours
  from the wallpaper). An activity's own `color` from Kumiko may be used as an accent, but must
  read on any theme.
- Icons are Material Symbols names.
- **Clicks**: anything the widget makes clickable keeps its clicks; the rest of the card is the
  shell's handle for dragging the widget around. So buttons and rows should look clickable, and
  there must be some plain card surface left to grab.
- Motion should be small: a tick, a counter moving, a row leaving. SekaiPop's built-in cards pop
  in and out by themselves; the widget doesn't need its own entrance.

## When you are done

As the very last step, append ` [finished]` to this artifact's title and add a closing line
`Status: finished` to the page itself. That is how the implementing agent knows the design is
complete. The agent polls from the kizuna profile `max`, so the design should live on the account
that profile is signed in to; otherwise the handoff is downloaded into this repo's
`doc/briefs/` by hand.
