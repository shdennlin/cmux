#!/usr/bin/env python3
"""Rewrite Workspace's `bonsplitController` to `activeBonsplitController`.

Usage: --bulk FILE... for a first pass over conflicted files, then feed it
an xcodebuild log (repeat build + run until the build is clean).

Feed it an xcodebuild log. Only positions the compiler flags as a missing
Workspace member (or an unresolved bare name inside a Workspace extension)
are rewritten, so other types' own `bonsplitController` stay untouched.
Re-run after following upstream to resolve rename conflicts.
"""
import collections, re, sys

# Receivers whose own `bonsplitController` is not Workspace's.
NON_WORKSPACE = re.compile(
    r"\b(dock|store|mirror|windowDock|sourceDock|destinationDock|destinationStore|sourceStore|"
    r"workspaceDock|dockSplit|viewer|secondHost|firstHost|host|dockStore|split)\s*[?!]?\.$"
)


def bulk(paths):
    """First pass for conflicted files: rename every Workspace-looking use.

    Bare and `self.` uses are renamed only in files that extend or declare
    Workspace. Run the compiler-driven pass afterwards to fix stragglers.
    """
    for path in paths:
        text = open(path).read()
        is_workspace = bool(re.search(r"\bextension Workspace\b|\bclass Workspace\b", text))
        out, pos, count = [], 0, 0
        for m in re.finditer(r"\bbonsplitController\b", text):
            start = m.start()
            before = text[max(0, start - 40):start]
            if text[max(0, start - 6):start] == "active":
                continue
            dotted = re.search(r"([A-Za-z_][A-Za-z_0-9]*)?\s*[?!]?\.$", before)
            if dotted:
                receiver = dotted.group(1) or ""
                if receiver == "self":
                    ok = is_workspace
                elif NON_WORKSPACE.search(before) or receiver == "":
                    ok = False
                else:
                    ok = True
            else:
                label = text[m.end():m.end() + 1] == ":" and re.search(r"[(,]\s*$", before)
                ok = is_workspace and not re.search(r"(let|var|func)\s+$", before) and not label
            if ok:
                out.append(text[pos:start] + "activeBonsplitController")
                pos = m.end()
                count += 1
        out.append(text[pos:])
        open(path, "w").write("".join(out))
        print(f"{count:4d} {path}")

# Forward: a Workspace member still spelled the old way.
FWD = re.compile(
    r"^(/[^:]+\.swift):(\d+):(\d+): error: "
    r"(value of type '[^']*Workspace[^']*' has no member 'bonsplitController'"
    r"|cannot find 'bonsplitController' in scope)"
)
# Reverse: a bulk rename hit another type (Dock, tmux mirror, ...).
REV = re.compile(
    r"^(/[^:]+\.swift):(\d+):(\d+): error: "
    r"(value of type '(?![^']*Workspace)[^']*' has no member 'activeBonsplitController'"
    r"|cannot find 'activeBonsplitController' in scope)"
)

if sys.argv[1] == "--bulk":
    bulk(sys.argv[2:])
    sys.exit(0)

hits = collections.defaultdict(set)
for line in open(sys.argv[1], errors="replace"):
    for pat, mode in ((FWD, "fwd"), (REV, "rev")):
        m = pat.match(line)
        if m:
            hits[m.group(1)].add((int(m.group(2)), int(m.group(3)), mode))

for path, positions in sorted(hits.items()):
    lines = open(path).read().split("\n")
    for ln, col, mode in sorted(positions, reverse=True):
        s = lines[ln - 1]
        old, new = (("bonsplitController", "activeBonsplitController") if mode == "fwd"
                    else ("activeBonsplitController", "bonsplitController"))
        j = s.find(old, col - 1)
        if j == -1 or (mode == "fwd" and s[max(0, j - 6):j] == "active"):
            print("MISS", mode, path, ln, col)
            continue
        lines[ln - 1] = s[:j] + new + s[j + len(old):]
    open(path, "w").write("\n".join(lines))
    print(f"{len(positions):4d} {path}")
