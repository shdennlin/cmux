# claude-agent-status (fork only)

Feeds Claude Code session state to the cmux sidebar and to the top-tab activity
bar (`set-tab-state`). **Not for upstream:** it depends on `set-tab-state`, which
only this fork has, so the commit that adds it is deliberately not cherry-pickable.

| Piece | Role |
| --- | --- |
| `plugin/` | Claude Code plugin; writes turn start/complete/end to `agent-waiting.json` in process |
| `agent-waiting-hook.py` | `settings.json` hook for Notification, StopFailure, ask-tools and SubagentStart/Stop |
| `agent-status-daemon.py` | Reads the store and pushes sidebar rows and tab states; run by launchd every 60 s |
| `com.shdennlin.cmux-agent-status.plist.template` | LaunchAgent; `install.sh` fills in the socket password, it is never committed |

## What the sidebar shows

One row per live agent tab, in tab order (at most 12 per workspace), then one
summary row.

A tab has a row while its agent process is still on the tab's tty. The pid in
the session store is only a fallback: it goes stale when cmux restores a session
under a new process. A tab that no longer exists, or whose agent has exited, has
no row, and a tab with several old records keeps only its newest.

| State | Icon | Colour |
| --- | --- | --- |
| working | `bolt.fill` | blue |
| needs input | `exclamationmark.triangle.fill` | amber, quieter after 15 min |
| error | `xmark.octagon.fill` | red |
| idle, under 6 h | `checkmark.circle.fill` (outline once the tab was looked at) | green |
| idle, over 6 h | `pause.circle` | grey |
| unknown | `questionmark.circle` | grey |

The 6 hours are `IDLE_GRAY_AFTER` in the daemon. Grey alone cannot be told from
unknown, which is why the icon differs.

The summary row reads `⚡2 450M · 💤4 700M`: how many agents are not grey and how
much memory they use, then the same for the grey ones. It counts every agent in
the workspace, not only the rows shown. Memory is the agent process plus
everything started under it (`ps` RSS, followed through parent pids), rounded to
50 MB. Treat it as a lower bound: macOS compresses idle processes, so their RSS
shrinks. It is left out when `ps` cannot be read.

State comes from the hook records in `agent-waiting.json`. A record is kept for
30 days, except the `ended` tombstone, which goes after 24 h, so an agent left
idle overnight keeps its state. Both the hook and the plugin enforce this, as
they write the same file.

A subagent that outlives the turn that started it (a background one) keeps the
row working. `SubagentStart` and `SubagentStop` add and remove its id in the
record's `subagents`, and an `idle` row with any live id reads as working, aged
from the oldest start. `needs input` and `error` win over it. The ids are never
the main loop's state, and a state write keeps them. A subagent killed without a
`SubagentStop` stops counting after an hour (`SUBAGENT_TTL`, in both the hook and
the daemon). A Claude session with no record whose CLI
lifecycle is `idle` is shown as idle; anything else without a record is
`unknown`. Codex has no hook and stays `unknown`.

## Requirements

- macOS, with Homebrew `python3` (`/usr/bin/python3` is the Xcode CLT shim; the
  installer prefers `/opt/homebrew/bin/python3`).
- A cmux built from this fork's `cmux-local`. Check with `cmux set-tab-state --help`:
  the official app refuses the verb, and without it only the sidebar rows work,
  not the tab bar.
- Claude Code **2.1.310 or newer** (the version this was written and tested on).
  The plugin uses the in-process hooks API (`hooks.json` with `modules`), which
  Claude Code labels *early access*: it may change between releases. Run
  `claude plugin validate extras/claude-agent-status/plugin` after an update.
- A cmux socket password (below), needed only for the LaunchAgent.

## Socket password

The daemon talks to the running cmux over its socket. The password is one you
choose: set it in cmux under **Settings → Automation → Socket Password**. The CLI
reads it from `--password`, then `CMUX_SOCKET_PASSWORD`, then that saved setting.
The installer takes it from the environment and writes it only into
`~/Library/LaunchAgents/` (mode 600). Without one, skip `--launchd`: the plugin
and hook still record state, but nothing repaints the sidebar.

## Install

```bash
git switch cmux-local
extras/claude-agent-status/install.sh                      # symlinks only
CMUX_SOCKET_PASSWORD='…' extras/claude-agent-status/install.sh --launchd
```

`install.sh` symlinks the daemon and hook into `~/.config/cmux/` and the plugin
into `~/.claude/plugins/`, so the file in git is the file that runs. A regular
file already there is moved to `<name>.pre-extras`; **move a replaced plugin
directory out of `~/.claude/plugins/`**, or Claude Code may load it twice.
Then register the hook (below) and start a new Claude Code session.

Overrides: `CMUX_AGENT_STATUS_DIR` (default `~/.config/cmux`),
`CMUX_AGENT_STATUS_STORE`, `CMUX_AGENT_STATUS_PYTHON`, `CLAUDE_PLUGIN_DIR`.

## `~/.claude/settings.json`

Merge into your existing `hooks`; do not replace it. Use your absolute path.

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "/Users/YOU/.config/cmux/agent-waiting-hook.py" }] }
    ],
    "StopFailure": [
      { "hooks": [{ "type": "command", "command": "/Users/YOU/.config/cmux/agent-waiting-hook.py" }] }
    ],
    "SubagentStart": [
      { "hooks": [{ "type": "command", "command": "/Users/YOU/.config/cmux/agent-waiting-hook.py" }] }
    ],
    "SubagentStop": [
      { "hooks": [{ "type": "command", "command": "/Users/YOU/.config/cmux/agent-waiting-hook.py" }] }
    ],
    "PostToolUse": [
      {
        "matcher": "AskUserQuestion|ExitPlanMode",
        "hooks": [{ "type": "command", "command": "/Users/YOU/.config/cmux/agent-waiting-hook.py" }]
      }
    ]
  }
}
```

## Check it works

```bash
launchctl print gui/$(id -u)/com.shdennlin.cmux-agent-status | grep -E 'state|last exit'
cat /tmp/cmux-agent-status.err                  # empty when healthy
launchctl kickstart -k gui/$(id -u)/com.shdennlin.cmux-agent-status   # run one tick now
```

## Uninstall

Remove the three symlinks, `launchctl bootout gui/$(id -u)/com.shdennlin.cmux-agent-status`,
delete the plist, and drop the five hook entries.
