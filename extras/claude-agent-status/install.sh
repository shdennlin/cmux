#!/usr/bin/env bash
# Link the agent-status pieces from this checkout into the places that read them.
#
# Symlinks, not copies: the file in git is the file that runs, so the two
# cannot drift. An existing regular file is moved to <name>.pre-extras once.
#
#   ./install.sh              link the daemon, the hook and the Claude plugin
#   ./install.sh --launchd    also write and load the LaunchAgent (needs
#                             CMUX_SOCKET_PASSWORD; it is never stored in git)
#
# Overrides: CMUX_AGENT_STATUS_DIR (default ~/.config/cmux),
#            CMUX_AGENT_STATUS_PYTHON (default: python3 on PATH, Homebrew first),
#            CLAUDE_PLUGIN_DIR (default ~/.claude/plugins).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="${CMUX_AGENT_STATUS_DIR:-$HOME/.config/cmux}"
plugins="${CLAUDE_PLUGIN_DIR:-$HOME/.claude/plugins}"
label="com.shdennlin.cmux-agent-status"

link() { # link <source> <destination>
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.pre-extras"
    echo "moved existing $dst -> $dst.pre-extras"
  fi
  ln -sfn "$src" "$dst"
  echo "linked $dst"
}

link "$here/agent-status-daemon.py" "$dir/agent-status-daemon.py"
link "$here/agent-waiting-hook.py" "$dir/agent-waiting-hook.py"
link "$here/plugin" "$plugins/cmux-agent-status"

if [ "${1:-}" = "--launchd" ]; then
  : "${CMUX_SOCKET_PASSWORD:?set CMUX_SOCKET_PASSWORD to write the LaunchAgent}"
  if [ -n "${CMUX_AGENT_STATUS_PYTHON:-}" ]; then
    python="$CMUX_AGENT_STATUS_PYTHON"
  elif [ -x /opt/homebrew/bin/python3 ]; then
    python=/opt/homebrew/bin/python3   # /usr/bin/python3 is the Xcode CLT shim
  else
    python="$(command -v python3)"
  fi
  plist="$HOME/Library/LaunchAgents/$label.plist"
  mkdir -p "$(dirname "$plist")"
  # plistlib reads the secret from the environment, so it never appears in
  # argv (visible to `ps`), and it escapes XML instead of trusting sed.
  # umask 077 makes the file private from its first byte.
  (umask 077
   PLIST_PYTHON="$python" PLIST_DAEMON="$dir/agent-status-daemon.py" \
   /usr/bin/python3 - "$here/$label.plist.template" "$plist" <<'PY'
import os, plistlib, sys
src, dst = sys.argv[1:3]
with open(src, "rb") as fh:
    plist = plistlib.load(fh)
plist["ProgramArguments"] = [os.environ["PLIST_PYTHON"], os.environ["PLIST_DAEMON"]]
plist["EnvironmentVariables"]["CMUX_SOCKET_PASSWORD"] = os.environ["CMUX_SOCKET_PASSWORD"]
with open(dst, "wb") as fh:
    plistlib.dump(plist, fh)
PY
  )
  chmod 600 "$plist"
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "loaded $label"
fi

cat <<MSG

Still manual: register agent-waiting-hook.py in ~/.claude/settings.json on
Notification, StopFailure and PostToolUse (matcher AskUserQuestion|ExitPlanMode),
pointing at $dir/agent-waiting-hook.py.
MSG
