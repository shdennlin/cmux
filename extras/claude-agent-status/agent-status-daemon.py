#!/usr/bin/env python3
"""One sidebar row per agent, colored by state and decayed by age.

cmux's own claude_code chip is hook-driven and per-workspace: it cannot say how
many agents there are, which of them block you, or how long ago one finished.
This pushes one set_status entry per interesting agent into the BUILT-IN
sidebar. Nothing here replaces or reimplements the sidebar.
"""
import base64, concurrent.futures, glob, json, os, re, subprocess, sys, time
from datetime import datetime

# Production and any tagged dev build each own a socket, so push to every
# CLI that exists: whichever app is running picks its own up, the other is a
# no-op that fails fast.
CMUX_PATHS = [
    "/Applications/cmux.app/Contents/Resources/bin/cmux",
    "/Applications/cmux+.app/Contents/Resources/bin/cmux",
    "/Applications/cmux dev.app/Contents/Resources/bin/cmux",
]


def _owned_private(st):
    """Ours, and not writable by group or others."""
    return st.st_uid == os.getuid() and not (st.st_mode & 0o022)


def _dev_cli():
    """reload.sh records the tagged build's CLI here; the app name changes
    between builds, so never hard-code the bundle path.

    /tmp is shared and this runs every minute with the socket password in its
    environment, so the pointer is trusted only if we own it and nobody else
    can write it (a symlink or a file another user pre-created is refused),
    and the binary it names must be ours and not writable by others either."""
    try:
        fd = os.open("/tmp/cmux-last-cli-path", os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return None
    try:
        if not _owned_private(os.fstat(fd)):
            return None
        path = os.read(fd, 4096).decode("utf-8", "replace").strip()
    finally:
        os.close(fd)
    if not path or not os.path.isabs(path):
        return None
    try:
        st = os.stat(path)
    except OSError:
        return None
    return path if _owned_private(st) and os.access(path, os.X_OK) else None


_dev = _dev_cli()
if _dev:
    CMUX_PATHS.append(_dev)
CMUX = CMUX_PATHS[0]
# set-tab-state exists only in the fork. The official app refuses it, and run()
# would then mark that app dead and drop its set-status rows for the rest of
# the tick, so tab states go through run_fork() to these CLIs alone.
FORK_CLIS = [p for p in CMUX_PATHS if p != CMUX]
STATE_DIR = os.environ.get("CMUX_AGENT_STATUS_DIR") or os.path.expanduser("~/.config/cmux")
WAITING_STORE = os.environ.get("CMUX_AGENT_STATUS_STORE") or os.path.join(STATE_DIR, "agent-waiting.json")
KEYS_STORE = os.path.join(STATE_DIR, "agent-status-keys.json")
TABS_STORE = os.path.join(STATE_DIR, "agent-status-tabs.json")
LAST_STORE = os.path.join(STATE_DIR, "agent-status-last.json")
SOCKET_GLOBS = [
    "/tmp/cmux*.sock",
    os.path.expanduser("~/Library/Application Support/cmux/*.sock"),
    os.path.expanduser("~/.local/state/cmux/*.sock"),
]


def cmux_instance():
    """Fingerprint every running cmux. A restart recreates its socket, and the
    app restores its old status rows from the session snapshot, so the
    unchanged-row cache must be dropped or those stale rows are never fixed.
    Production and each tagged build own a different socket, so all count."""
    parts = []
    for pattern in SOCKET_GLOBS:
        for path in glob.glob(pattern):
            try:
                parts.append("%s:%d" % (path, int(os.stat(path).st_mtime)))
            except OSError:
                pass
    return "|".join(sorted(parts)) or "0"

WAIT_DIM_AFTER = 900.0         # 15 min: a request this old is probably set aside, so it recedes
MAX_ROWS = 12                  # per workspace; more than anyone keeps open, so no live session is cut
SUBAGENT_TTL = 3600            # same limit as the hook: a Stop that never fired stops counting
IDLE_GRAY_AFTER = 6 * 3600     # an idle agent this old stops asking for attention: grey, different icon
IDLE_OLD_ICON = "pause.circle" # outline of the pause glyph the sidebar already draws for idle
# cmux's own claude_code chip is per-workspace and two-state; our rows supersede
# it. There is no setting to hide just that one (Show Status Pills would hide
# ours too), so clear it each tick. The wrapper re-pushes it on the next hook
# event, so it can reappear for up to one interval.
HIDE_NATIVE_CHIP = True   # our rows supersede it; the Running/Idle chip is noise

# One hex per state and appearance, (light, dark). The tab bar draws the same
# values (TopTabActivityState.swift), so a state is one colour on both. A row
# takes a single --color, so the daemon picks the pair half by the appearance.
PALETTE = {
    "done":    ("#34C759", "#3FCF6E"),   # finished, not looked at yet
    "read":    ("#6FB58A", "#4A9B6B"),   # finished and looked at: the same green, quieter
    "running": ("#2F7BF5", "#4C8DFF"),   # dark value is the one cmux draws as its accent
    "need":    ("#E8920A", "#F5A524"),   # waiting on the person
    "old":     ("#E6C27A", "#A47220"),   # the same wait after WAIT_DIM_AFTER
    "error":   ("#E5342B", "#FF453A"),
}
APP_BUNDLES = ["com.cmuxterm.app.staging.plus", "com.cmuxterm.app.debug.dev", "com.cmuxterm.app"]


def is_dark():
    """Whether the sidebar is drawn dark: cmux's own appearance setting when it
    forces one, otherwise the system's. A pair is chosen once per tick, so a
    flip repaints every row through the signature (the colour is part of it)."""
    for bundle in APP_BUNDLES:
        try:
            mode = subprocess.run(["defaults", "read", bundle, "appearanceMode"],
                                  capture_output=True, text=True, timeout=5).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            continue
        if mode in ("dark", "light"):
            return mode == "dark"
    try:
        out = subprocess.run(["defaults", "read", "-g", "AppleInterfaceStyle"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return True
    return out == "Dark"


def pal(name):
    return PALETTE[name][1 if DARK else 0]


DARK = True   # set at the start of every tick

# Status rides on --color plus the --icon shape, with no leading glyph: the
# sidebar row tints both the SF Symbol (iconView.contentTintColor) and the
# label with the entry colour, and under indicatorStyle = "border" that
# explicit colour now survives on the SELECTED row too. Emoji were only ever
# a workaround for the filling styles flattening it to white, so under
# solidFill (the official app's default) the selected row loses the hue and
# only the icon shape and the age number carry state.


ICON = {
    "working": "bolt.fill",        # free now that HIDE_NATIVE_CHIP clears cmux's own chip
    "needs_input": "exclamationmark.triangle.fill",
    "idle": "checkmark.circle.fill",
    "unknown": "questionmark.circle",
    "error": "xmark.octagon.fill",
}
RANK = {"needs_input": 0, "error": 1, "working": 2, "idle": 3, "unknown": 4}
NORM = {"running": "working", "working": "working", "idle": "idle",
        "needsinput": "needs_input", "needs_input": "needs_input"}

# The bar under a tab title, from the same hook state as the sidebar row.
# idle hides the bar. unknown means no hook has spoken, and cmux's own
# lifecycle is sticky and would paint it blue, so it hides the bar too.
TAB_STATE = {"working": "running", "needs_input": "needs-input",
             "error": "error", "idle": "idle", "unknown": "idle"}


# CLIs that failed earlier in this tick. A tagged app that is not running
# costs a process spawn and a failed connect for EVERY row; one failure is
# enough to know, and the daemon is a fresh process each tick so this never
# goes stale.
DEAD_CLIS = set()

# cli path -> that app's own URL scheme, read once per tick. Each build only
# honours its own scheme (cmux, cmux-dev-plus, cmux-dev-dev), so one row's
# deep link has to be spelled differently for each app it is pushed to.
_SCHEMES = {}


def app_scheme(cli):
    """The URL scheme of the app bundle owning this CLI, or None."""
    if cli in _SCHEMES:
        return _SCHEMES[cli]
    scheme = None
    marker = "/Contents/"
    if marker in cli:
        plist = cli[: cli.index(marker)] + "/Contents/Info.plist"
        try:
            import plistlib
            with open(plist, "rb") as fh:
                env = plistlib.load(fh).get("LSEnvironment") or {}
            scheme = (env.get("CMUX_AUTH_CALLBACK_SCHEME") or "").strip() or None
        except Exception:
            scheme = None
    _SCHEMES[cli] = scheme
    return scheme



def run(args, per_cli=None):
    """Run one command against every live cmux CLI.

    `per_cli` is a callable taking the cli path and returning extra arguments
    for that app alone -- a deep link has to carry each build's own scheme, so
    the same row is not the same command for every app.
    """
    r = ok = None
    for cli in CMUX_PATHS:
        if not os.path.exists(cli) or cli in DEAD_CLIS:
            continue
        extra = per_cli(cli) if per_cli else []
        r = subprocess.run([cli] + args + extra, capture_output=True, text=True, timeout=20)
        if r.returncode != 0 and extra:
            # An app that predates the deep-link support refuses the whole
            # command over the URL alone. Losing the row is far worse than
            # losing its link, so fall back rather than let it vanish.
            r = subprocess.run([cli] + args, capture_output=True, text=True, timeout=20)
        if r.returncode == 0 and args[0] in ("sessions", "tree", "list-status"):
            return r          # reads only need one source
        if r.returncode == 0:
            ok = r             # a write: remember that at least one app took it
        elif args[0] not in ("sessions", "tree", "list-status"):
            DEAD_CLIS.add(cli)   # writes only: a read may fail for other reasons
    if r is None:
        raise RuntimeError("no cmux CLI found")
    return ok or r


def unread_surfaces():
    """Uppercase ids of the surfaces that hold an unread notification, or None
    when they cannot be read.

    An agent that finished stays unread until its tab is looked at, which is
    cmux's own mark: it is cleared when the tab is shown, so no tracking here.
    None means unknown, and callers keep the old styling rather than guess.
    Reads only the fork's CLIs and never marks one dead, like run_fork().
    """
    for cli in FORK_CLIS:
        if not os.path.exists(cli):
            continue
        try:
            r = subprocess.run([cli, "list-notifications", "--json"],
                               capture_output=True, text=True, timeout=20)
            if r.returncode != 0:
                continue
            return {str(n.get("surface_id") or "").upper()
                    for n in json.loads(r.stdout) if not n.get("is_read")}
        except (OSError, subprocess.SubprocessError, ValueError, TypeError, AttributeError):
            continue
    return None


def run_fork(args):
    """Run one write against the fork's CLIs only.

    Unlike run(), a failure never lands in DEAD_CLIS: an app that is not
    running, or that does not own the surface, fails this command without
    saying anything about its set-status rows. True when any app took it.
    """
    took = False
    for cli in FORK_CLIS:
        if not os.path.exists(cli):
            continue
        try:
            r = subprocess.run([cli] + args, capture_output=True, text=True, timeout=20)
        except (OSError, subprocess.SubprocessError):
            continue
        if r.returncode == 0:
            took = True
    return took


def load(path):
    try:
        with open(path) as fh:
            d = json.load(fh)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def mono(t):
    """ASCII digits and lowercase letters -> U+1D7F6 / U+1D68A monospace forms."""
    out = []
    for ch in t:
        if "0" <= ch <= "9":
            out.append(chr(0x1D7F6 + ord(ch) - 48))
        elif "a" <= ch <= "z":
            out.append(chr(0x1D68A + ord(ch) - 97))
        else:
            out.append(ch)
    return "".join(out)


def md_plain(text, limit):
    """A label as inert markdown. Tab titles and cwd names are set by whatever
    runs in the terminal, and the row renders as markdown, so a title could
    otherwise inject links or emphasis. Truncate first, so an escape is never
    cut in half, and fold whitespace: a newline makes the row drop markdown."""
    text = " ".join(str(text).split())[:limit]
    return re.sub(r"([\\`*_\[\]()<>!#|~&])", r"\\\1", text)


def age_label(s):
    s = max(0, int(s))
    # Resolution falls off with age, because the churn is what you see: every
    # row whose label changes is a separate write, and when a batch of them
    # turned over together the sidebar used to repaint in a visible ripple.
    # The first ten minutes are the ones you act on, so they stay exact; after
    # that five-minute steps cut how often a row changes by 5x, and hours by
    # 60x. Every bucket floors, like the seconds-to-minutes truncation already
    # did, so a label never claims more time than has passed.
    #
    # Two digits at most, so the column is three characters and titles align.
    if s < 60:
        t = "0m"
    elif s < 600:                  # under 10 minutes: every minute
        t = "%dm" % (s // 60)
    elif s < 6000:                 # 10m-99m: five-minute steps
        t = "%dm" % ((s // 300) * 5)
    elif s < 86400:
        t = "%dh" % (s // 3600)
    else:
        t = "%dd" % min(99, s // 86400)
    # U+2007 FIGURE SPACE is digit-width: one separates the age from the tab
    # number, the rest pad the value out to the fixed three-wide column.
    # The sidebar font has proportional digits ("1" is narrower than "4"), and a
    # figure space cannot fix that. A code span is monospaced but drawn smaller.
    # The mathematical monospace letters (U+1D670..) are fixed-width at the
    # text's own size, so the tab number and the age go through mono().
    return "\u2007" * (3 - len(t)) + mono(t)



def nav_index(lines):
    """surface uuid -> (workspace number, tab number) for ctrl+N / cmd+N.

    surface.focus is broken in 0.64.24 (accepts the call, returns the surface,
    never switches), and set_status rows cannot carry actions. The keyboard
    shortcuts DO work, so print them instead of trying to navigate for the user.
    Numbering follows sidebar/tab-bar order, which is tree order.
    """
    out, ws_n, tab_n = {}, 0, 0
    for line in lines:
        if "workspace workspace:" in line:
            ws_n += 1
            tab_n = 0
            continue
        if "surface surface:" in line:
            tab_n += 1
            m = re.search(r"([0-9A-Fa-f-]{36})", line)
            if m:
                out[m.group(1)] = (ws_n, tab_n)
    return out


def titles(lines):
    """surface uuid -> tab title (shares one tree call with nav_index)."""
    out = {}
    for line in lines:
        m = re.search(r'([0-9A-Fa-f-]{36}).*?\[(?:terminal|customSidebar)\]\s+"([^"]*)"', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def live_subagent_starts(entry, now):
    """Start times of the entry's subagents that are still within SUBAGENT_TTL."""
    subs = entry.get("subagents")
    out = []
    for started in (subs.values() if isinstance(subs, dict) else []):
        try:
            if now - float(started) < SUBAGENT_TTL:
                out.append(float(started))
        except (TypeError, ValueError):
            continue
    return out


def ttys(lines):
    """surface uuid -> controlling tty (ttys003), from the same tree call."""
    out = {}
    for line in lines:
        if "surface surface:" not in line:
            continue
        m = re.search(r"([0-9A-Fa-f-]{36}).*?\btty=(ttys\d+)", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def process_table():
    """The process list, or None when ps cannot be read (callers then filter
    nothing rather than guess): by_tty tty -> [(pid, argv0)], kids ppid -> [pid],
    rss pid -> kB."""
    try:
        r = subprocess.run(["ps", "-axo", "pid=,ppid=,rss=,tty=,command="],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    t = {"by_tty": {}, "kids": {}, "rss": {}}
    for line in r.stdout.splitlines():
        p = line.split(None, 4)
        if len(p) < 5 or not all(x.isdigit() for x in p[:3]):
            continue
        pid, ppid, rss = int(p[0]), int(p[1]), int(p[2])
        t["by_tty"].setdefault(p[3], []).append((pid, os.path.basename(p[4].split()[0])))
        t["kids"].setdefault(ppid, []).append(pid)
        t["rss"][pid] = rss
    return t


def tree_rss_kb(t, roots):
    """rss of the roots and every process started under them."""
    seen, stack = set(), list(roots)
    while stack:
        pid = stack.pop()
        if pid in seen:
            continue
        seen.add(pid)
        stack.extend(t["kids"].get(pid, []))
    return sum(t["rss"].get(pid, 0) for pid in seen)


def mem_label(kb):
    """Compact (410M, 1.2G) and rounded coarsely: rss moves a few MB every
    minute, and every changed label is a write."""
    mb = kb / 1024.0
    if mb < 1024:
        return "%dM" % (int(round(mb / 50.0)) * 50)
    return "%.1fG" % (mb / 1024.0)


def is_old_idle(a, now):
    """Idle for hours: the row goes grey, and the summary counts it as idle."""
    el = max(0.0, now - a["since"]) if a["since"] else 0.0
    return a["state"] == "idle" and el > IDLE_GRAY_AFTER


def strip_glyph(s):
    return re.sub(r"[ -⯿]", "", s or "").strip()


def collect():
    r = run(["sessions", "list", "--json"])
    if r.returncode != 0:
        return {}
    try:
        doc = json.loads(r.stdout)
    except json.JSONDecodeError:
        return {}
    # Hooks are authoritative. The CLI's agent_lifecycle is sticky: a session
    # idle for 12 minutes still reads "running", which painted every row blue.
    hooks = {}
    for k, v in load(WAITING_STORE).items():
        if isinstance(v, dict) and v.get("state"):
            hooks[k] = (v["state"], float(v.get("ts") or 0), live_subagent_starts(v, time.time()))
    tree_lines = run(["tree", "--all", "--id-format", "both"]).stdout.splitlines()
    tmap = titles(tree_lines)
    nav = nav_index(tree_lines)
    tty_of = ttys(tree_lines)
    procs = process_table()
    now = time.time()
    by_ws = {}
    for s in doc.get("sessions", []):
        ws = s.get("workspace_id")
        # stored_pid_exists compares against the pid recorded in the session
        # store, which every session fails right after a cmux restart (restore
        # spawns new processes). Dropping on it hid the whole list; recency of
        # updated_at_unix is the honest liveness signal here.
        if not ws:
            continue
        # The session store keeps a session after its tab closes, and closing
        # a tab or killing the agent fires no hook. A surface missing from the
        # tree cannot host a live agent. An empty tree means the read failed,
        # so it filters nothing rather than hiding every row.
        if tmap and s.get("surface_id") not in tmap:
            continue
        # The session store keeps a record after its agent exits, and the pid it
        # holds goes stale (a restore starts a new process under the same tab),
        # so the tab's own tty is the evidence: a live agent has a process there
        # named after it. The stored pid is only a fallback. No tty or no ps
        # output filters nothing.
        tty = tty_of.get(s.get("surface_id") or "")
        rss_kb = None
        if procs is not None and tty:
            roots = [pid for pid, a0 in procs["by_tty"].get(tty, []) if a0 == (s.get("agent") or "")]
            if not roots and s.get("pid") in procs["rss"]:
                roots = [s.get("pid")]
            if not roots:
                continue                   # the agent exited; only its tab is left
            rss_kb = tree_rss_kb(procs, roots)   # the agent and everything it started
        # Never trust agent_lifecycle: it is sticky and says "running" for
        # sessions that have been idle for ages. Without a hook record we
        # genuinely do not know, and saying so beats guessing confidently.
        since = float(s.get("updated_at_unix") or 0)
        h = hooks.get(s.get("session_id"))
        state = h[0] if h else "unknown"
        if h:
            since = h[1]
            if h[2] and state == "idle":
                # The turn is over but a subagent started in it is still running.
                # needs_input and error stay: they ask more of the person.
                state, since = "working", min(h[2])
        elif s.get("agent") == "claude" and s.get("agent_lifecycle") == "idle":
            # Only "running" is sticky. An idle reading never disagreed with a
            # hook that says working or needs_input, so a session whose hook
            # record is gone (or never existed) is still known to be idle.
            state = "idle"
        if state == "ended":
            continue
        # A live tab keeps its row however long its agent has been idle: the
        # surface check above already drops tabs that no longer exist, and an
        # "ended" hook is the only signal that the agent itself is gone.
        surface = s.get("surface_id") or ""
        label = strip_glyph(tmap.get(surface, "")) or os.path.basename(s.get("cwd") or "agent")
        by_ws.setdefault(ws, []).append(
            {"state": state, "since": since, "surface": surface, "label": label,
             "nav": nav.get(surface), "rss_kb": rss_kb})
    # The session store keeps every session a surface ever hosted, so one tab
    # can carry several records (an old Codex run under a live Claude). A tab
    # is one row: keep its most recent record.
    for ws, rows in by_ws.items():
        latest = {}
        for a in rows:
            key = a["surface"] or id(a)
            if key not in latest or a["since"] > latest[key]["since"]:
                latest[key] = a
        by_ws[ws] = [a for a in rows if latest[a["surface"] or id(a)] is a]
    return by_ws


def color(state, elapsed, seen=False):
    """The row colour for a state, or None to leave the row uncoloured.

    Hue identifies the state and nothing else. Age is already carried by the
    number in the row, so a second encoding of it here only muddied the
    palette. The single exception is the one step amber takes once a request
    has waited a while, and it goes quieter, not louder: a request left open
    that long was probably set aside on purpose, and a row that keeps
    shouting at someone who has chosen to wait stops being a signal.
    """
    if state == "working":
        return pal("running")
    if state == "error":
        return pal("error")
    if state == "needs_input":
        return pal("need" if elapsed < WAIT_DIM_AFTER else "old")
    if state == "idle":
        # Done and unread is the bright green that says "come and look"; done
        # and looked at is the same hue, quieter. The outline icon is the
        # second channel.
        return pal("read" if seen else "done")
    # unknown: no explicit colour at all, so the row draws in the sidebar's own
    # secondary text colour and cannot be mistaken for a faded green.
    return None


def tick():
    global DARK
    DARK = is_dark()
    now = time.time()
    by_ws = collect()
    prev = load(KEYS_STORE)
    last = load(LAST_STORE)
    inst = cmux_instance()
    if last.get("__instance") != inst:
        last = {}                    # cmux restarted: everything must be re-pushed
        # Restored rows can sit under any of our keys, not only last tick's.
        for ws in set(prev) | set(by_ws):
            prev[ws] = ["ag%d" % i for i in range(MAX_ROWS)] + ["agsum"]
    used, shown, pushed = {}, {}, 0
    # Collected, then sent together. One row costs about 0.39 s of subprocess
    # round-trips (3 CLIs), so writing 8 changed rows one after another spread
    # the update across 3 seconds and the sidebar visibly rippled row by row
    # instead of repainting once.
    pending = []
    unread = unread_surfaces()

    for ws, agents in by_ws.items():
        # Mirror the tab bar order; status is already carried by icon + color.
        agents.sort(key=lambda a: (a["nav"][1] if a.get("nav") else 999))
        keys = []
        for i, a in enumerate(agents[:MAX_ROWS]):
            el = max(0.0, now - a["since"]) if a["since"] else 0.0
            key = "ag%d" % i          # positional: stable count, cheap to clear
            # No font-size control on set_status; bold is the only lever we have.
            nav = a.get("nav")
            # The glyph column stays the STATE symbol: colour alone cannot
            # separate unknown from a long-idle agent, since idle fades toward
            # the same grey. The tab number goes back in the text, bare -- no
            # "t", no U+2318, and no trailing space, because age_label's
            # leading figure spaces already separate the two and keep the age
            # and label columns aligned.
            # An idle agent whose tab has been looked at: an outline check in
            # the secondary colour, apart from the filled green check of one
            # that finished unseen. Unknown unread state keeps the green.
            seen = (a["state"] == "idle" and unread is not None
                    and (a["surface"] or "").upper() not in unread)
            # Idle for hours: not asking for anything any more. Grey (no explicit
            # colour, so the sidebar's secondary text colour) and a different
            # icon, because grey alone cannot be told from "unknown".
            old_idle = is_old_idle(a, now)
            icon = IDLE_OLD_ICON if old_idle else ("checkmark.circle" if seen else ICON[a["state"]])
            hint = "%d" % nav[1] if nav else ""
            # One line only. A status entry renders through a single-line
            # markdown view, and a newline makes it give up on markdown
            # entirely -- the row then shows the literal asterisks and drops
            # everything after the break. Two lines would need the app's
            # `stacked` / secondTextView path, which configureMetadataEntry
            # currently hardcodes off.
            text = "%s %s" % (age_label(el), "**%s**" % md_plain(a["label"], 26))
            args = ["set-status", key, text, "--workspace", ws,
                    "--icon", icon,
                    "--priority", str(20 - i), "--format", "markdown"]
            row_color = None if old_idle else color(a["state"], el, seen)
            if row_color:
                args += ["--color", row_color]

            # Clicking the row jumps to the agent's own tab. The link is built
            # per app because each build only accepts its own scheme; a row
            # pushed to an app whose scheme cannot be read stays unclickable
            # rather than carrying a link that app would refuse.
            surface = a["surface"]
            def link_for(cli, ws=ws, surface=surface):
                scheme = app_scheme(cli) if surface else None
                if not scheme:
                    return []
                return ["--url", "%s://workspace/%s/surface/%s" % (scheme, ws, surface)]
            if a["surface"]:
                args += ["--panel", a["surface"]]
            # The link is attached per app, so it never reaches `args` and a
            # row that only gained one would look unchanged to the cache and
            # never be pushed. Fold it into the signature explicitly.
            sig = "|".join(args[2:]) + ("|link:" + surface if surface else "")
            cache_key = "%s/%s" % (ws, key)
            if last.get(cache_key) != sig:             # unchanged rows cost nothing
                pending.append((cache_key, sig, args, link_for))
            else:
                shown[cache_key] = sig
            keys.append(key)
        # One line for the whole workspace, under its rows: what the agents
        # that are not grey cost, and what the grey ones cost. The split is the
        # rows' own, so the two groups match what is on screen. Counts every
        # agent, not only the MAX_ROWS shown.
        groups = []
        for glyph, old in (("\u26a1", False), ("\U0001F4A4", True)):
            members = [a for a in agents if is_old_idle(a, now) == old]
            if not members:
                continue
            known = [a["rss_kb"] for a in members if a.get("rss_kb") is not None]
            groups.append("%s%d%s" % (glyph, len(members), " " + mem_label(sum(known)) if known else ""))
        text = " \u00b7 ".join(groups)
        sum_args = ["set-status", "agsum", text, "--workspace", ws,
                    "--icon", "memorychip", "--priority", "3", "--format", "markdown"]
        sum_sig = "|".join(sum_args[2:])
        sum_key = "%s/agsum" % ws
        if last.get(sum_key) != sum_sig:
            pending.append((sum_key, sum_sig, sum_args, None))
        else:
            shown[sum_key] = sum_sig
        keys.append("agsum")
        if HIDE_NATIVE_CHIP:
            pending.append((None, None, ["clear-status", "claude_code", "--workspace", ws], None))
        used[ws] = keys

    # Drop rows that existed last tick but not this one.
    for ws, keys in prev.items():
        for key in keys:
            if key not in used.get(ws, []):
                pending.append((None, None, ["clear-status", key, "--workspace", ws], None))

    # Send everything at once. The app serializes socket commands itself, so
    # the rows land together and the sidebar repaints once.
    if pending:
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            futures = [(ck, sig, pool.submit(run, args, pc)) for ck, sig, args, pc in pending]
            for cache_key, sig, fut in futures:
                try:
                    okay = fut.result().returncode == 0
                except Exception:
                    okay = False
                if cache_key and okay:
                    # A failed push stays out of `shown`, so the next tick
                    # retries it instead of trusting a row that never changed.
                    shown[cache_key] = sig
                    pushed += 1

    # Tab bars. Every agent with a surface gets one, not only the MAX_ROWS the
    # sidebar lists. A surface we set last tick that has no agent now (it
    # ended or went stale) is set to idle once rather than cleared, because
    # clearing would hand the bar back to cmux's sticky lifecycle.
    prev_tabs = load(TABS_STORE)
    cur_tabs, tab_pending = {}, []
    for ws, agents in by_ws.items():
        for a in agents:
            sid = a["surface"]
            if not sid:
                continue
            state = TAB_STATE.get(a["state"], "idle")
            ck = "tab:" + sid
            sig = "%s|%s" % (ws, state)
            cur_tabs[sid] = ws
            if last.get(ck) == sig:
                shown[ck] = sig
            else:
                tab_pending.append((ck, sig, ["set-tab-state", state, "--surface", sid, "--workspace", ws]))
    for sid, ws in prev_tabs.items():
        if sid not in cur_tabs:
            tab_pending.append((None, None, ["set-tab-state", "idle", "--surface", sid, "--workspace", ws]))
    if tab_pending:
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            futures = [(ck, sig, pool.submit(run_fork, args)) for ck, sig, args in tab_pending]
            for ck, sig, fut in futures:
                try:
                    okay = fut.result()
                except Exception:
                    okay = False
                if ck and okay:
                    shown[ck] = sig
                    pushed += 1
    json.dump(cur_tabs, open(TABS_STORE, "w"))

    json.dump(used, open(KEYS_STORE, "w"))
    shown["__instance"] = inst
    json.dump(shown, open(LAST_STORE, "w"))
    return used, pushed


if __name__ == "__main__":
    try:
        u, n = tick()
        print("rows=%d pushed=%d" % (sum(len(v) for v in u.values()), n))
    except Exception as exc:
        print("tick failed: %s" % exc, file=sys.stderr)
        sys.exit(1)
