# Fork builds — local notes

How this fork's apps are built and installed, and what was learned the hard way.
The features themselves are listed in the fork table at the top of
[README.md](README.md).

## Installed slots

Every slot is isolated from the official app: its own bundle id, and therefore
its own UserDefaults domain, socket, session file and
`Application Support/<bundle-id>/config.ghostty`.

| app | bundle id | build | role |
| --- | --- | --- | --- |
| `/Applications/cmux.app` | `com.cmuxterm.app` | official | untouched; never quit, replace or launch a copy of it |
| `/Applications/cmux+.app` | `com.cmuxterm.app.debug.plus`, or `….staging.plus` with `--release` | Debug or Release | the one in daily use |
| `/Applications/cmux dev.app` | `com.cmuxterm.app.debug.dev`, or `….staging.dev` | Debug or Release | testing slot |
| `/Applications/cmux stage.app` | `com.cmuxterm.app.staging.stage` | Release | Release trial slot |

Quit the official app (⌘Q) before launching `cmux+`: both resume their own
session file but would race for the same Claude sessions.

## Rebuild and install

`scripts/fork-rebuild.sh` (see `--help`) builds, quits the slot gracefully,
installs to `/Applications`, and waits for you to open the app yourself, then
probes its socket and deep links. It never launches anything.

```bash
export CMUX_FORK_SIGN_IDENTITY=<sha1 from: security find-identity -v -p codesigning>
./scripts/fork-rebuild.sh                    # Debug cmux+
./scripts/fork-rebuild.sh dev                # Debug cmux dev
./scripts/fork-rebuild.sh plus --release     # Release cmux+
./scripts/fork-rebuild.sh plus --build-only  # compile check; touches no app
```

- Debug builds share one DerivedData (`cmux-borderfix`) across tags, which makes
  the second variant incremental (~90s instead of ~20min).
- `--prod-auth` (passed by the script) points a Debug build at production
  auth/API/Iroh. It is the alternative to `CMUX_DEV_BACKEND_MODE=local`, not a
  companion.
- Build from a clean tree. A build compiles whatever is in the working copy,
  including another session's half-finished edits.

### Debug or Release

cmux decides it is a dev build from the bundle id (`.debug.`) or a `DEV` word in
the app or executable name, not from the compiler configuration. A dev build
skips the Cmd+Q confirmation (`QuitConfirmationStore`) among other things.
`--release` therefore installs under a staging id, `com.cmuxterm.app.staging.<tag>`,
which cmux treats as `stable`, and the Swift layer is optimized. libghostty and
cmuxd are ReleaseFast in both builds, so the terminal itself is equally fast.

Switching a slot between Debug and Release copies its windows, settings and
history to the other id with `scripts/fork/migrate-app-state.py` (copy-only; the
old id keeps its copy, replaced files go to `fork-migrate-backup/`). Switching
back runs the same copy in reverse.

What `--release` has to work around, all inside `fork-rebuild.sh` so upstream's
`reloads.sh` stays unmodified:

- `reloads.sh` quits, kills and reopens whatever carries its tag. It runs under
  a throwaway tag (`fork-build-<tag>`) with `open` shadowed on `PATH`.
- Release carries `keychain-access-groups`, which Xcode signs only with a team
  and profile, so it builds with `CODE_SIGNING_ALLOWED = NO` (as
  `build-sign-upload.sh` does) through `XCODE_XCCONFIG_FILE`. The installed app
  is then signed without entitlements, like the Debug build.
- Release defaults to the `cmux://` scheme, the official app's. The installed
  copy is rewritten to `cmux-dev-<tag>`, and both build products are
  unregistered from LaunchServices, so official deep links and sign-in never
  land in a fork build.
- A first Release build runs one multi-GB `swift-frontend` per module, one task
  per core, and exhausted a 24 GB machine. It is capped at
  `CMUX_FORK_BUILD_JOBS` (default 4) under `nice 15`
  (`CMUX_FORK_BUILD_BACKGROUND=1` for `taskpolicy -b`), and builds only the
  active architecture. Whole-module optimization still recompiles the whole app
  module for a one-line change, so iterate in Debug.

Staging and debug ids never query the public appcast (`UpdateController`, #6292),
so no fork build is offered an upstream update; they move forward only when
rebuilt.

## Signing

`reload.sh` and `reloads.sh` sign ad hoc. An ad-hoc designated requirement is
the bare `cdhash`, so every rebuild is a new app to TCC and the keychain:
Accessibility, Screen Recording and folder grants re-prompt. With
`CMUX_FORK_SIGN_IDENTITY` set (a free Apple Development certificate is enough),
`fork-rebuild.sh` re-signs the installed app so the requirement becomes the
bundle id plus that certificate, and grants survive rebuilds. Switching a slot
from ad hoc to the certificate re-prompts once.

Only the outer bundle is signed, never `--deep`. The nested
`Contents/Library/cmux Computer Use.app` (`com.cmuxterm.cua`) is shared by every
cmux, official included, under one TCC row, and its ad-hoc requirement is just
`identifier "com.cmuxterm.cua"`, which every copy satisfies. If the row was
granted from the official app first, it requires Manaflow's team and fork
builds can never be granted (the System Settings "−" button is disabled). Fix:
`tccutil reset Accessibility com.cmuxterm.cua` and
`tccutil reset ScreenCapture com.cmuxterm.cua`, then grant from a fork build;
the official app then matches the looser row too.

Verification signals that look like breakage and are not:

- `spctl -a` rejects an ad-hoc bundle by definition. Locally built apps carry no
  quarantine xattr, so Gatekeeper does not block launch.
- `codesign --verify --strict` fails with `a sealed resource is missing or
  invalid` on any bundle that has been launched, the official app included: zsh
  compiles the shell integration into `Contents/Resources/shell-integration/*.zsh.zwc`
  inside the bundle. Only a never-launched copy verifies clean.

Fork builds carry no entitlements, where the official app has
`networking.networkextension`, `system-extension.install`, an app group and
keychain access groups. Entitlement-backed features (Cloud tunnel / system
extension, app-group or keychain-group sharing) are not expected to work.

## Pitfalls hit while building

- `pgrep -f` / `pkill -f` take a regex, and `cmux+` is one: an unescaped
  `/Applications/cmux+.app/` also matches `/Applications/cmux.app/`, so a forced
  quit of cmux+ would kill the official app. `fork-rebuild.sh` escapes the path.
- `/usr/bin/python3` and Homebrew `zig` are both wrong: the project pins
  Zig 0.16.x (major+minor must match `ghostty/build.zig.zon`), installed here
  via asdf.
- `ENABLE_USER_SCRIPT_SANDBOXING = YES` blocks the Ghostty CLI helper's build
  phase from fetching Zig deps. Warm the cache first by running
  `./scripts/build-ghostty-cli-helper.sh --target aarch64-macos --output /tmp/x`
  outside Xcode.
- Zig's HTTP client stalls indefinitely on some VPN paths while curl succeeds;
  symptom is elapsed time climbing with CPU time flat.
- Two sidebar render paths exist. Background style is shared
  (`sidebarWorkspaceRowBackgroundStyle`), but the foreground-inversion rule is
  duplicated in SwiftUI `ContentView` and AppKit `SidebarWorkspaceRowCellView`.
  The AppKit one is what actually renders when
  `cmux.flags.remote.sidebar-appkit-list-experiment` is on.
