# cmux Border Only — local patch

Adds a `border` workspace indicator style: the selected row draws an outline
with no fill, and keeps caller-supplied `set_status --color` tints instead of
flattening them to the selected foreground.

## Rebuild

```bash
./scripts/reload.sh --tag borderfix --prod-auth
pkill -f 'cmux DEV'
/bin/rm -rf "/Applications/cmux DEV borderfix.app"
ditto ~/Library/Developer/Xcode/DerivedData/cmux-borderfix/Build/Products/Debug/"cmux DEV.app" \
      "/Applications/cmux DEV borderfix.app"
```

## Gotchas hit while building

- `/usr/bin/python3` and Homebrew `zig` are both wrong: the project pins
  Zig 0.16.x (major+minor must match `ghostty/build.zig.zon`), installed here
  via asdf.
- `ENABLE_USER_SCRIPT_SANDBOXING = YES` blocks the Ghostty CLI helper's build
  phase from fetching Zig deps. Warm the cache first by running
  `./scripts/build-ghostty-cli-helper.sh --target aarch64-macos --output /tmp/x`
  outside Xcode.
- Zig's HTTP client stalls indefinitely on some VPN paths while curl succeeds;
  symptom is elapsed time climbing with CPU time flat.
- Two render paths exist. Background style is shared
  (`sidebarWorkspaceRowBackgroundStyle`), but the foreground-inversion rule is
  duplicated in SwiftUI `ContentView` and AppKit `SidebarWorkspaceRowCellView`.
  The AppKit one is what actually renders when
  `cmux.flags.remote.sidebar-appkit-list-experiment` is on.
