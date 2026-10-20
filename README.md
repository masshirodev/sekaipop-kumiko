# sekaipop-kumiko

Desktop widgets for [SekaiPop](https://github.com/Blapples/SekaiPop) that show a
[Kumiko](https://kumiko.ink) account, drawn like the shell's own cards:

| Widget                   | Shows                                                    | Does                                        |
| ------------------------ | -------------------------------------------------------- | ------------------------------------------- |
| **Kumiko Hours**         | the session running now, today's segments, the week       | clock in, pause (by type), resume, clock out |
| **Kumiko Lists**         | what is due today and what is done, late items marked     | tick an item, Undo                          |
| **Kumiko Notifications** | the newest ones, unread first, live from Kumiko's stream  | mark read, dismiss, mark all read, open     |

Each has three looks (Settings > Desktop > Plugins > the widget > Show): the full card, a
one-row card and a compact square.

## Install

```sh
git clone https://github.com/masshirodev/sekaipop-kumiko.git ~/projects/sekaipop-kumiko
cd ~/projects/sekaipop-kumiko && ./install.sh
```

`install.sh` links the three folders into `~/.config/sekaipop/plugins/` and reloads the
shell's plugins. Then add them from **Edit Desktop** (right-click the desktop). `git pull`
updates them; `./install.sh --remove` takes them away.

**The token.** In Kumiko, on a computer: Settings > API tokens. Give it the scopes of the
widgets you use: `hours:write`, `lists:write`, `notifications:write` (write includes read).
Put it in `~/.config/sekaipop-kumiko/token`, or in the `KUMIKO_TOKEN` environment variable
(it must be there when the shell starts). The shell never stores it, and the widgets pass it
to curl through the environment, never on a command line. Until it is found, each widget
says what to do and has a **Check again** key.

Needs SekaiPop with plugin api 1 and `curl`.

## Settings

All three: **Kumiko address** (default `https://kumiko.ink`), **Show** (the three looks).
Hours: **Activity** (its slug, such as `work`, or its id; empty is the first) and how often
to check. Lists: **Rows**, **Show done items**. Notifications: **How many**, **Unread only**.

## Working on it

- `shared/` is the code all three use; each plugin carries a copy in its `lib/`, because a
  plugin loads from its own folder. Edit `shared/`, then `scripts/sync-shared.sh`.
- `node tests/kumiko_unit.js` tests the logic; `scripts/sync-shared.sh --check` that the
  copies match; `qmllint Widget.qml lib/*.qml` in each plugin.
- `doc/KUMIKO-API.md` is the part of Kumiko's API they use, `doc/DESIGN.md` how the design
  became the widgets and where they depart from it, `doc/briefs/` the brief and the
  handoff.
