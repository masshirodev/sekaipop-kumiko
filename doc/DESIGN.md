# From the handoff to the widgets

The design is `doc/briefs/handoff-kumiko-widgets/` (Claude Design canvas "Kumiko Widgets",
built in the SekaiPop design system), from the brief `doc/briefs/KUMIKO-WIDGETS.md`. The
first version of the canvas was drawn as phone home-screen widgets in its own palette; it was
redrawn in SekaiPop's look before any code, and only that version is kept here.

## What was taken as drawn

- Every widget's three looks and their sizes: the full card (Hours and Notifications 400
  wide, Lists 380), the one-row card, the compact square (182). The shell's frame adds 17 px
  a side (outline 3, ring 4, padding 10), so the content is the drawn width less 34, with 6
  px of the widget's own margin in the wide looks (the mock's 20 px of padding inside a 3 px
  border is 23 px from the edge; the shell gives 17).
- Keys: round icon keys (36 to 48) and pill keys (40 to 42), outline, white ring, idle fill
  `pSurfaceDivider`, hard shadow 4 by 3 in `pLineShadow`, pressed onto the shadow and back
  past rest (OutBack, 260 ms). "On" (running, done, today) is the accent gradient with
  `colBorder` outline and ink. `shared/Key.qml`.
- The copy, the states and their order: "3 of 7 done", "· late" in bold rather than a
  colour, the refused tick ("Not logged: too soon."), Undo after a tick, "Pause Work as",
  "Already changed elsewhere…", "Reconnecting… Showing the last snapshot", the four token
  messages and "Check again".

## Where the widgets depart from the mock, and why

- **Colours are the theme's roles, never the mock's hexes.** The mock wrote the Virtual
  Singer values into each board; the widgets read `host.theme`, so they follow every palette,
  mode and per-monitor theme. The roles it uses beyond the first promised list
  (`pSurfaceDivider`, `pRingWhite`, `pSurfaceRing`, `pLineShadow`, `shadowOffset`) are
  promised to plugins by SekaiPop PR #70.
- **Activity dots** are Kumiko's colour when it is a hex. Kumiko gives "Work" the colour
  `var(--accent)` (CSS, meaningless outside Kumiko), so such an activity takes `accentCyan`.
  The mock's green / purple / orange were made up.
- **Icons** are Material Symbols glyphs through the theme's `iconFont` (the mock drew inline
  SVG), because a plugin cannot use the shell's icon set.
- **"Balance to date"** is the sum of Kumiko's `balanceMs` for the days *before* today. The
  mock showed a number without saying how; counting today while it is under way would read
  as hours behind every morning.
- **Starting another activity** from "Not clocked in" shows that activity's session while it
  runs, though the widget follows the one in its setting otherwise; the mock only drew one.
- **The "Live" dot of the compact Notifications** is a plain fill rather than the gradient, at
  12 px the gradient does not read.
- **Notifications are read, not counted, by row:** the list shows Kumiko's newest (the
  stream's snapshot is the newest 20), unread first, cut to the setting's count; the unread
  number is the account's.
