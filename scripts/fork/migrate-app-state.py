#!/usr/bin/env python3
"""Copy one cmux bundle id's local state to another bundle id.

Fork-local. cmux names nearly all of its state after the bundle id, so moving a
tagged app between identities (com.cmuxterm.app.debug.plus, a Debug build, and
com.cmuxterm.app.staging.plus, a Release build) starts it empty unless that
state is renamed. The session JSON does not embed the id, so a rename restores
windows, workspaces, tabs and scrollback.

Copy-only: the source is never modified, so switching back keeps working.
Destination files that already exist are moved to a timestamped backup folder
first, never overwritten in place.

Both apps must be quit: a live app rewrites its session file on exit and
cfprefsd caches its preferences domain. Only com.cmuxterm.app.debug.* and
com.cmuxterm.app.staging.* ids are accepted, so this can never write into the
official app's state.

Usage: migrate-app-state.py FROM_BUNDLE_ID TO_BUNDLE_ID [--dry-run]
"""

import os
import shutil
import subprocess
import sys
import time

ALLOWED_PREFIXES = ("com.cmuxterm.app.debug.", "com.cmuxterm.app.staging.")
HOME = os.path.expanduser("~")
CMUX_SUPPORT = os.path.join(HOME, "Library/Application Support/cmux")
APP_SUPPORT = os.path.join(HOME, "Library/Application Support")


def state_pairs(src, dst):
    """(source, destination) paths for every piece of state named after `src`.

    Runtime-only markers (last socket path, lifecycle sentinels) and browser
    caches are left out: the app recreates them.
    """
    pairs = []
    if os.path.isdir(CMUX_SUPPORT):
        for name in sorted(os.listdir(CMUX_SUPPORT)):
            if src not in name:
                continue
            # `src` must end at a separator, so .debug.plus never matches
            # .debug.plus2 while .debug.plus-scrollback and .debug.plus.json do.
            rest = name.split(src, 1)[1]
            if rest and rest[0] not in ".-_":
                continue
            pairs.append((os.path.join(CMUX_SUPPORT, name),
                          os.path.join(CMUX_SUPPORT, name.replace(src, dst, 1))))
        for sub in ("session-history", "sudo"):
            folder = os.path.join(CMUX_SUPPORT, sub)
            if not os.path.isdir(folder):
                continue
            for name in sorted(os.listdir(folder)):
                rest = name.split(src, 1)[1] if src in name else None
                if rest is None or (rest and rest[0] not in ".-_"):
                    continue
                pairs.append((os.path.join(folder, name),
                              os.path.join(folder, name.replace(src, dst, 1))))
    own = os.path.join(APP_SUPPORT, src)
    if os.path.isdir(own):
        pairs.append((own, os.path.join(APP_SUPPORT, dst)))
    return pairs


def copy(src, dst):
    if os.path.isdir(src):
        shutil.copytree(src, dst, symlinks=True)
    else:
        shutil.copy2(src, dst)


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    dry = "--dry-run" in argv
    if len(args) != 2:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    src, dst = args
    for bid in (src, dst):
        if not bid.startswith(ALLOWED_PREFIXES) or "/" in bid:
            print(f"refusing: {bid} is not a debug or staging cmux id", file=sys.stderr)
            return 1
    if src == dst:
        print("refusing: source and destination are the same id", file=sys.stderr)
        return 1

    pairs = state_pairs(src, dst)
    backup = os.path.join(CMUX_SUPPORT, "fork-migrate-backup",
                          f"{dst}-{time.strftime('%Y%m%d-%H%M%S')}")
    print(f"    {src} -> {dst}{' (dry run)' if dry else ''}")
    for s, d in pairs:
        if os.path.lexists(d):
            print(f"    back up {d}")
            if not dry:
                os.makedirs(backup, exist_ok=True)
                shutil.move(d, os.path.join(backup, os.path.basename(d)))
        print(f"    copy    {os.path.relpath(s, HOME)}")
        if not dry:
            copy(s, d)

    # Preferences go through cfprefsd: a copied .plist file is overwritten by
    # its cached view of the domain, so export and import instead.
    print(f"    defaults {src} -> {dst}")
    if not dry:
        exported = subprocess.run(["defaults", "export", src, "-"],
                                  capture_output=True, check=False)
        if exported.returncode == 0 and exported.stdout:
            subprocess.run(["defaults", "import", dst, "-"],
                           input=exported.stdout, check=True)
        else:
            print(f"    (no preferences for {src})")
    print(f"    {len(pairs)} item(s) {'to copy' if dry else 'copied'}" + (f"; replaced ones are in {backup}"
                                                if os.path.isdir(backup) else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
