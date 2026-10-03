#!/usr/bin/env bash
# Rebuild and install one of this fork's tagged cmux apps, then wait while you
# open it yourself.
#
# Fork-local: upstream has no such script, and `scripts/reload.sh` deliberately
# stops at "built" so it never touches an installed app. This adds the install
# step and the guards that cost real time to learn:
#
#   * the shared derived-data path, without which every build is a full one
#   * a graceful quit first, so the app writes its session file before dying
#   * a refusal to target anything but com.cmuxterm.app.debug.*, so this can
#     never quit the official app
#
# It does NOT launch the app. A cmux launched from inside another cmux inherits
# that one's CMUX_TAG, CMUX_AUTH_CALLBACK_SCHEME and CMUX_SOCKET_PATH — which
# breaks its deep links and points it at the wrong socket — and scrubbing the
# environment did not reliably prevent it. Opening it from the Dock, Spotlight
# or Finder always gives it its own identity, so that is the step left to you.
# The script waits for it and verifies the result.
#
# Run it from any terminal; it never launches anything. See --help.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/fork-rebuild.sh [tag] [options]

Rebuilds one of this fork's tagged cmux apps, installs it, and waits while you
open it yourself. The tag defaults to "plus" and must be lowercase letters,
digits and hyphens; it becomes the app name, the bundle id and the socket path.

Environment:
  CMUX_FORK_SIGN_IDENTITY   Re-sign the installed app with this codesigning
                            identity (SHA-1 from `security find-identity -v
                            -p codesigning`), so TCC grants survive rebuilds.
                            Unset: the app stays ad hoc, as reload.sh signs it.
  CMUX_FORK_BUILD_JOBS      --release only: parallel build tasks (default 4).
                            Each Release compile task can take several GB.
  CMUX_FORK_BUILD_BACKGROUND=1
                            --release only: build at background QoS
                            (taskpolicy -b) instead of nice 15. Slower, but
                            the machine stays responsive.

Options:
  --build-only      Build and stop. Does not install, and does not stop the
                    running app -- the flag is passed through to reload.sh,
                    which otherwise terminates the same-tag app after a
                    successful build so macOS picks up the new binary.
  --release         Build the Release configuration through reloads.sh and
                    install it under the staging id com.cmuxterm.app.staging.<tag>
                    with the same app name. Faster, and cmux treats it like a
                    shipped build (Cmd+Q asks before quitting). Switching
                    between --release and a plain build copies the app's
                    windows, settings and history to the other id with
                    scripts/fork/migrate-app-state.py; the old copy is kept.
  --verify-only     Skip the build. Probe the installed app's socket and ask
                    whether it accepts its own deep links.
  -h, --help        Print this.

Examples:
  scripts/fork-rebuild.sh                 # rebuild and reinstall cmux+
  scripts/fork-rebuild.sh dev             # ... the "dev" slot instead
  scripts/fork-rebuild.sh plus --build-only
  scripts/fork-rebuild.sh plus --release  # Release build of cmux+
  scripts/fork-rebuild.sh --verify-only plus

It deliberately does not open the app. A cmux launched from inside another cmux
inherits that one's CMUX_TAG, CMUX_AUTH_CALLBACK_SCHEME and CMUX_SOCKET_PATH,
which breaks its deep links and points it at the wrong socket.
EOF
}

# Options and the tag may come in any order: the tag is the one bare word.
VERIFY_ONLY=0
BUILD_ONLY=0
RELEASE=0
TAG=""
while (( $# )); do
  case "$1" in
    --build-only)  BUILD_ONLY=1 ;;
    --verify-only) VERIFY_ONLY=1 ;;
    --release)     RELEASE=1 ;;
    -h|--help)     usage; exit 0 ;;
    -*)            echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$TAG" ]]; then
        echo "refusing: more than one tag given ('$TAG' and '$1')" >&2
        exit 2
      fi
      TAG="$1"
      ;;
  esac
  shift
done
TAG="${TAG:-plus}"

if (( VERIFY_ONLY && BUILD_ONLY )); then
  echo "refusing: --verify-only and --build-only do nothing together" >&2
  exit 2
fi

case "$TAG" in
  plus) APP_NAME="cmux+" ;;
  dev)  APP_NAME="cmux dev" ;;
  *)    APP_NAME="cmux $TAG" ;;
esac

APP_PATH="/Applications/${APP_NAME}.app"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if (( RELEASE )); then
  BUNDLE_ID="com.cmuxterm.app.staging.${TAG}"
  SOCK="/tmp/cmux-staging-${TAG}.sock"
  # reloads.sh builds under a throwaway tag of its own: it quits, kills and
  # reopens whatever app carries its tag, and none of that may reach the
  # installed one. Its product is then installed under the real identity.
  BUILD_TAG="fork-build-${TAG}"
  DERIVED="${CMUX_RELEASE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/cmux-fork-release}"
  PRODUCTS="$DERIVED/Build/Products/Release"
  BUILT_APP="$PRODUCTS/cmux STAGING ${BUILD_TAG}.app"
else
  BUNDLE_ID="com.cmuxterm.app.debug.${TAG}"
  SOCK="/tmp/cmux-debug-${TAG}.sock"
  DERIVED="${CMUX_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/cmux-borderfix}"
  PRODUCTS="$DERIVED/Build/Products/Debug"
  BUILT_APP="$PRODUCTS/$APP_NAME.app"
fi

# A tag becomes a bundle id, an app path and a socket path, so it has to be a
# plain word. Without this, a tag with a slash walks out of every one of them.
if [[ ! "$TAG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "refusing: tag '$TAG' must be lowercase letters, digits and hyphens" >&2
  exit 1
fi
case "$BUNDLE_ID" in
  com.cmuxterm.app.debug.*|com.cmuxterm.app.staging.*) ;;
  *) echo "refusing: $BUNDLE_ID is not a debug or staging id" >&2; exit 1 ;;
esac

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# pgrep/pkill take an extended regex, and "cmux+" is a regex: x+ matches the
# single x of /Applications/cmux.app, so an unescaped path would find (and
# force-kill) the official app. Every process pattern goes through this.
APP_PROC_RE="$(printf '%s' "$APP_PATH/Contents/MacOS/" | sed 's/[][\\.*^$+?(){}|]/\\&/g')"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

app_scheme() {
  /usr/bin/python3 - "$APP_PATH" <<'PY' 2>/dev/null || true
import plistlib, sys
with open(sys.argv[1] + "/Contents/Info.plist", "rb") as fh:
    env = plistlib.load(fh).get("LSEnvironment") or {}
print((env.get("CMUX_AUTH_CALLBACK_SCHEME") or "").strip())
PY
}

verify() {
  say "Verifying"
  if [[ ! -S "$SOCK" ]]; then
    note "socket $SOCK is not there — the app is not running"
    return 1
  fi
  note "socket:  $SOCK"

  local scheme; scheme="$(app_scheme)"
  note "scheme:  ${scheme:-<unknown>}"
  [[ -n "$scheme" ]] || return 0

  # Does this build think it IS the app it was installed as? A cmux opened from
  # inside another cmux answers with that one's scheme instead.
  local live
  live="$(/usr/bin/python3 - "$SOCK" "$scheme" <<'PY' 2>/dev/null || true
import socket, sys, time
sock, scheme = sys.argv[1], sys.argv[2]
def ask(cmd):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(10)
    s.connect(sock); s.sendall((cmd + "\n").encode()); time.sleep(0.6)
    out = s.recv(4096).decode("utf-8", "replace").strip(); s.close(); return out
probe = "set_status __rebuild_probe x --url=%s://workspace/A/surface/B --tab=1" % scheme
reply = ask(probe)
if reply == "OK":
    ask("clear_status __rebuild_probe --tab=1")
    print("ok")
elif "expected http(s) URL" in reply:
    print("old")          # a build from before the deep-link policy
else:
    print("wrong-identity")
PY
)"
  case "$live" in
    ok)             note "deep links: accepted — identity is clean" ;;
    old)            note "deep links: refused — this build predates the policy change" ;;
    wrong-identity) note "deep links: refused — the app answers to a DIFFERENT scheme;"
                    note "            it was opened from inside another cmux. Quit it and"
                    note "            open it from the Dock or Spotlight instead." ;;
    *)              note "deep links: could not tell" ;;
  esac
}

# --verify-only probes whichever identity is installed, Debug or Release.
installed_plist_value() {
  /usr/bin/python3 - "$APP_PATH/Contents/Info.plist" "$1" <<'PY' 2>/dev/null || true
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    info = plistlib.load(fh)
key = sys.argv[2]
value = (info.get("LSEnvironment") or {}).get(key) if key.startswith("CMUX") else info.get(key)
print(value or "")
PY
}
if (( VERIFY_ONLY )); then
  INSTALLED_SOCK="$(installed_plist_value CMUX_SOCKET_PATH)"
  SOCK="${INSTALLED_SOCK:-$SOCK}"
  verify; exit $?
fi

# ---------------------------------------------------------------- build
say "Building $APP_NAME (tag: $TAG$( (( RELEASE )) && echo ", Release" ))"
note "derived data: $DERIVED"
cd "$REPO"
if (( RELEASE )); then
  # reloads.sh ends by opening the app it built. Shadow `open` for that one
  # call: the app is opened by you, from the Dock, and only once installed.
  OPEN_SHIM="$(mktemp -d)"
  trap 'rm -rf "$OPEN_SHIM"' EXIT
  printf '#!/bin/sh\necho "    (fork-rebuild: not opening the build product)"\n' > "$OPEN_SHIM/open"
  chmod +x "$OPEN_SHIM/open"
  # Release carries keychain-access-groups, which Xcode will only sign with a
  # team and provisioning profile. Build unsigned, as build-sign-upload.sh
  # does; reloads.sh signs ad hoc afterwards and this script re-signs below,
  # without entitlements, exactly like the Debug build.
  # Release also builds every architecture (arm64 and x86_64); this machine
  # runs one, so the second slice only doubles the compile.
  printf 'CODE_SIGNING_ALLOWED = NO\nONLY_ACTIVE_ARCH = YES\n' > "$OPEN_SHIM/unsigned.xcconfig"
  # A whole-module Release compile runs one multi-GB swift-frontend per
  # module, and xcodebuild starts one task per core: on a 24 GB machine that
  # exhausts memory and stalls the desktop. Cap the parallel tasks (memory)
  # and lower the priority (CPU) unless asked otherwise. reloads.sh takes no
  # xcodebuild arguments, so the cap rides on a PATH wrapper like `open`.
  JOBS="${CMUX_FORK_BUILD_JOBS:-4}"
  [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo "refusing: CMUX_FORK_BUILD_JOBS=$JOBS" >&2; exit 2; }
  printf '#!/bin/sh\nexec /usr/bin/xcodebuild -jobs %s "$@"\n' "$JOBS" > "$OPEN_SHIM/xcodebuild"
  chmod +x "$OPEN_SHIM/xcodebuild"
  if [[ "${CMUX_FORK_BUILD_BACKGROUND:-0}" == 1 ]]; then
    PRIORITY=(/usr/sbin/taskpolicy -b)
    note "parallel tasks: $JOBS, background QoS (efficiency cores)"
  else
    PRIORITY=(/usr/bin/nice -n 15)
    note "parallel tasks: $JOBS, nice 15"
  fi
  "${PRIORITY[@]}" env PATH="$OPEN_SHIM:$PATH" XCODE_XCCONFIG_FILE="$OPEN_SHIM/unsigned.xcconfig" \
    ./scripts/reloads.sh --tag "$BUILD_TAG" --derived-data "$DERIVED"
  # The raw product is a com.cmuxterm.app bundle claiming the official cmux://
  # scheme, and Xcode registers what it builds. Withdraw both build products
  # so no link or bundle-id lookup meant for the official app reaches them.
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$PRODUCTS/cmux.app" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$BUILT_APP" >/dev/null 2>&1 || true
  fi
else
  RELOAD_ARGS=(--tag "$TAG" --name "$APP_NAME" --prod-auth)
  (( BUILD_ONLY )) && RELOAD_ARGS+=(--build-only)
  CMUX_DERIVED_DATA="$DERIVED" ./scripts/reload.sh "${RELOAD_ARGS[@]}"
fi

if [[ ! -d "$BUILT_APP" ]]; then
  echo "build finished but $BUILT_APP is missing" >&2
  exit 1
fi

if (( BUILD_ONLY )); then
  say "Built, not installed (--build-only)"
  note "$BUILT_APP"
  exit 0
fi

# The id now installed, which decides what to quit and whether state moves.
INSTALLED_ID="$(installed_plist_value CFBundleIdentifier)"
case "$INSTALLED_ID" in
  ""|com.cmuxterm.app.debug.*|com.cmuxterm.app.staging.*) ;;
  *) echo "refusing: $APP_PATH carries $INSTALLED_ID, not a fork build" >&2; exit 1 ;;
esac
OLD_ENV_PLIST="$(mktemp)"
[[ -f "$APP_PATH/Contents/Info.plist" ]] && cp "$APP_PATH/Contents/Info.plist" "$OLD_ENV_PLIST"

# ---------------------------------------------------------------- quit
say "Quitting $APP_NAME"
# Ask first: a graceful quit writes the session file, so workspaces and
# scrollback come back when you reopen it.
osascript -e "quit app id \"${INSTALLED_ID:-$BUNDLE_ID}\"" 2>/dev/null || true
for _ in $(seq 1 15); do
  pgrep -f "$APP_PROC_RE" >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -f "$APP_PROC_RE" >/dev/null 2>&1; then
  note "still running after 15s, forcing"
  # The full path matters: every tagged build's executable is named "cmux DEV",
  # so a pattern without it would match the other slots too.
  pkill -f "$APP_PROC_RE" || true
  sleep 3
fi

# ---------------------------------------------------------------- migrate
# Debug and Release builds have different ids, so each starts from its own
# state. Carry the windows, settings and history across on a switch.
if [[ -n "$INSTALLED_ID" && "$INSTALLED_ID" != "$BUNDLE_ID" ]]; then
  say "Copying app state $INSTALLED_ID -> $BUNDLE_ID"
  /usr/bin/python3 "$REPO/scripts/fork/migrate-app-state.py" "$INSTALLED_ID" "$BUNDLE_ID"
fi

# ---------------------------------------------------------------- install
say "Installing to $APP_PATH"
rm -rf "$APP_PATH"
ditto "$BUILT_APP" "$APP_PATH"
note "installed"

if (( RELEASE )); then
  # Give the staging product this app's name and id, its own sockets, and
  # the URL scheme the Debug build used. The scheme is the important one:
  # Release defaults to cmux://, the official app's, and two claimants let
  # the official app's deep links and sign-in land here. The environment is
  # carried over from the app being replaced, so socket access, auth and
  # cloud settings stay as they were.
  /usr/bin/python3 - "$APP_PATH/Contents/Info.plist" "$OLD_ENV_PLIST" \
      "$APP_NAME" "$BUNDLE_ID" "$TAG" "$SOCK" <<'PY'
import os, plistlib, sys
path, old_path, name, bundle_id, tag, sock = sys.argv[1:]
with open(path, "rb") as fh:
    info = plistlib.load(fh)
old_env = {}
if os.path.getsize(old_path):
    with open(old_path, "rb") as fh:
        old_env = plistlib.load(fh).get("LSEnvironment") or {}
scheme = "cmux-dev-" + tag
info["CFBundleName"] = name
info["CFBundleDisplayName"] = name
info["CFBundleIdentifier"] = bundle_id
for url_type in info.get("CFBundleURLTypes") or []:
    url_name = url_type.get("CFBundleURLName", "")
    if url_name.endswith(".auth"):
        url_type["CFBundleURLSchemes"] = [scheme]
        url_type["CFBundleURLName"] = bundle_id + ".auth"
    elif url_name.endswith(".web"):
        url_type["CFBundleURLName"] = bundle_id + ".web"
env = dict(old_env)
# Paths into a DerivedData product are gone once installed; the app falls
# back to the copies inside its own bundle.
for key in ("CMUX_SHELL_INTEGRATION_DIR", "CMUX_BUNDLED_CLI_PATH"):
    env.pop(key, None)
env.update({
    "CMUX_BUNDLE_ID": bundle_id,
    "CMUX_TAG": tag,
    "CMUX_SOCKET_PATH": sock,
    "CMUXD_UNIX_PATH": os.path.expanduser(
        "~/Library/Application Support/cmux/cmuxd-staging-%s.sock" % tag),
    "CMUX_DEBUG_LOG": "/tmp/cmux-staging-%s.log" % tag,
    "CMUX_AUTH_CALLBACK_SCHEME": scheme,
})
env.setdefault("CMUX_SOCKET_ENABLE", "1")
env.setdefault("CMUX_SOCKET_MODE", "allowAll")
info["LSEnvironment"] = env
with open(path, "wb") as fh:
    plistlib.dump(info, fh)
PY
  note "renamed to $BUNDLE_ID, scheme cmux-dev-$TAG"
fi
rm -f "$OLD_ENV_PLIST"

# reload.sh signs ad hoc, and an ad-hoc designated requirement is the cdhash,
# so every rebuild looks like a new app to TCC and the keychain: Accessibility,
# Screen Recording and folder grants have to be given again. A certificate
# signature pins the requirement to the bundle id and the certificate instead.
# Set CMUX_FORK_SIGN_IDENTITY to an identity from
# `security find-identity -v -p codesigning` (its SHA-1 is unambiguous).
#
# Only the outer bundle is signed, never --deep: the nested Computer Use helper
# keeps its ad-hoc `identifier "com.cmuxterm.cua"` requirement, which is what
# lets every cmux share one Accessibility grant.
sign_app() {
  /usr/bin/codesign --force --sign "$1" --timestamp=none \
    --generate-entitlement-der "$APP_PATH" >/dev/null 2>&1 \
    && /usr/bin/codesign --verify --strict "$APP_PATH" >/dev/null 2>&1
}
if [[ -n "${CMUX_FORK_SIGN_IDENTITY:-}" ]] && sign_app "$CMUX_FORK_SIGN_IDENTITY"; then
  note "signed with $CMUX_FORK_SIGN_IDENTITY"
elif (( RELEASE )) || [[ -n "${CMUX_FORK_SIGN_IDENTITY:-}" ]]; then
  # The Release path rewrote Info.plist, which breaks the seal either way.
  [[ -n "${CMUX_FORK_SIGN_IDENTITY:-}" ]] \
    && note "WARNING: signing with $CMUX_FORK_SIGN_IDENTITY failed; signing ad hoc"
  sign_app - || { echo "codesign failed for $APP_PATH" >&2; exit 1; }
  note "signed ad hoc"
fi

# The build product under DerivedData registers the same URL scheme as the
# copy in /Applications, so LaunchServices has two claimants for
# cmux-dev-<tag>:// and may hand a deep link to the build directory -- an app
# with none of your session in it. Withdraw the build product; a later build
# re-registers it, which is why this runs on every install.
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$BUILT_APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f "$APP_PATH" >/dev/null 2>&1 || true
  note "URL scheme points at $APP_PATH alone"
fi

# ---------------------------------------------------------------- your turn
say "Open $APP_NAME yourself now"
note "Dock, Spotlight or Finder — anything but another cmux's terminal."
note "Waiting up to 3 minutes for it..."

for _ in $(seq 1 180); do
  [[ -S "$SOCK" ]] && break
  sleep 1
done

if [[ ! -S "$SOCK" ]]; then
  say "Gave up waiting"
  note "Open $APP_NAME, then run:  scripts/fork-rebuild.sh --verify-only $TAG"
  exit 0
fi

verify
say "$APP_NAME is up"
