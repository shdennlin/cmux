#!/usr/bin/env python3
"""Track each Claude session's real state from its own hook events.

`cmux sessions list` reports agent_lifecycle=running for any session whose
process is alive, so a session idle for 12 minutes still reads as running.
Claude's hooks are the same signal cmux's own chip uses, so record them here
and let the daemon prefer this over the coarse CLI value.

UserPromptSubmit / PreToolUse -> working
Notification                  -> needs_input (blocked on the user)
Stop / SubagentStop           -> idle (turn finished)
SessionEnd                    -> ended (a tombstone: dropping the entry would
                                 make a session whose tab stays open read as
                                 unknown, and still get a row)
SubagentStart / SubagentStop  -> adds / removes the agent id in the entry's
                                 `subagents`, so a subagent that outlives the
                                 turn that started it still counts as working.
                                 It never changes `state`: the main loop owns it.
"""
import json, os, sys, time, tempfile

STORE = os.environ.get("CMUX_AGENT_STATUS_STORE") or os.path.join(
    os.environ.get("CMUX_AGENT_STATUS_DIR") or os.path.expanduser("~/.config/cmux"),
    "agent-waiting.json")
# A tombstone only has to outlive the tab's own cleanup. Any other state is the
# only record of a session whose tab is still open: dropping it after a day made
# every agent left idle overnight read as "unknown".
STALE = 24 * 3600
STALE_LIVE = 30 * 24 * 3600
# A SubagentStop that never fires (the agent was killed) must not leave the row
# working for ever. The daemon applies the same limit when it reads.
SUBAGENT_TTL = 3600
EVENT_STATE = {
    "UserPromptSubmit": "working",
    "PreToolUse": "working",
    "Notification": "needs_input",
    "Stop": "idle",
    "StopFailure": "error",
    "PostToolUse": "working",
}

# A permission or a question only ends when its tool runs, and nothing else
# says so mid-turn, so the amber would stay until the turn ends. These tools
# are the ones that ask the person first; registered in settings.json with the
# same matcher, and checked here too so a wider matcher cannot flip every tool.
ASKING_TOOLS = {"AskUserQuestion", "ExitPlanMode"}

# Only a notification that asks something of the person is "blocked on you".
# idle_prompt fires ~60 s after a turn finished, so counting it turned every
# finished-and-left agent amber; auth_success, agent_completed and the quota
# events say nothing about waiting. Matching is on notification_type.
BLOCKING_NOTIFICATIONS = {
    "permission_prompt",
    "elicitation_dialog",
    "elicitation_url_dialog",
    "agent_needs_input",    # a background agent is waiting on the person
}


def live_subagents(entry, now):
    """The entry's subagents that started within SUBAGENT_TTL: id -> start time."""
    out = {}
    subs = entry.get("subagents") if isinstance(entry, dict) else None
    for aid, started in (subs.items() if isinstance(subs, dict) else []):
        try:
            if now - float(started) < SUBAGENT_TTL:
                out[aid] = float(started)
        except (TypeError, ValueError):
            continue
    return out


def load():
    try:
        with open(STORE) as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save(d):
    now = time.time()
    d = {k: v for k, v in d.items()
         if isinstance(v, dict)
         and now - float(v.get("ts", 0)) < (STALE if v.get("state") == "ended" else STALE_LIVE)}
    tmp = tempfile.NamedTemporaryFile("w", dir=os.path.dirname(STORE),
                                      delete=False, suffix=".tmp")
    try:
        json.dump(d, tmp)
        tmp.close()
        os.replace(tmp.name, STORE)      # atomic; hooks can fire concurrently
    except Exception:
        os.unlink(tmp.name)
        raise


def main():
    try:
        ev = json.load(sys.stdin)
    except ValueError:
        return 0
    sid = ev.get("session_id")
    name = ev.get("hook_event_name") or ""
    if not sid:
        return 0
    d = load()
    if name in ("SubagentStart", "SubagentStop"):
        aid = ev.get("agent_id")
        if not aid:
            return 0
        now = time.time()
        entry = dict(d.get(sid) or {})
        subs = live_subagents(entry, now)
        if name == "SubagentStart":
            subs[aid] = now
        else:
            subs.pop(aid, None)
        if entry.get("state") in (None, "ended"):
            entry["state"], entry["ts"] = "idle", now
        if subs:
            entry["subagents"] = subs
        else:
            entry.pop("subagents", None)
        d[sid] = entry
        save(d)
        return 0
    if name == "SessionEnd":
        d[sid] = {"state": "ended", "ts": time.time()}
    elif name in EVENT_STATE:
        # A payload without notification_type predates the field: keep the old
        # behaviour for it rather than going silent.
        ntype = ev.get("notification_type")
        if name == "Notification" and ntype and ntype not in BLOCKING_NOTIFICATIONS:
            return 0
        if name == "PostToolUse" and ev.get("tool_name") not in ASKING_TOOLS:
            return 0
        state = EVENT_STATE[name]
        prev = d.get(sid) or {}
        # Keep the ORIGINAL wait start so "how long has it blocked me" is real.
        if state == "needs_input" and prev.get("state") == "needs_input":
            return 0
        entry = {"state": state, "ts": time.time()}
        subs = live_subagents(prev, entry["ts"])
        if subs:
            entry["subagents"] = subs        # a state write must not drop them
        d[sid] = entry
    else:
        return 0
    save(d)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)                      # a hook must never block Claude
