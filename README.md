<!-- LOCAL FORK NOTICE — none of the section below is upstream cmux. Drop it before opening an upstream PR. -->

> ### Local fork additions
>
> Branch `cmux-local` carries everything below; `main` stays a plain mirror of `origin/main`. One commit per feature:
>
> | feature | what it does | how to change it | upstream |
> | --- | --- | --- | --- |
> | border indicator | Workspace indicator draws a border instead of filling the row, so `set-status --color` tints and the unread badge accent survive selection | `indicatorStyle: "border"` in `cmux.json` | [#7460](https://github.com/manaflow-ai/cmux/issues/7460) |
> | always show all | Sidebar setting that always shows every custom metadata row (no Show more / Show less) | Settings → Sidebar | [#8655](https://github.com/manaflow-ai/cmux/issues/8655) |
> | surface slide | Arriving surface slides in when ⌘⇧[ / ⌘⇧] switches surfaces | `defaults write <app domain> cmux.surfaceSlide.duration -float 0.2` (also `.offset`, `.enabled`) | [#1988](https://github.com/manaflow-ai/cmux/issues/1988) |
> | row deep link | A sidebar status entry's `--url` may be a `cmux://workspace/<id>/surface/<id>` deep link, so clicking the row jumps to that workspace and tab without leaving fullscreen | `cmux set-status <key> <text> --url "<this build's scheme>://workspace/…"` | [#2784](https://github.com/manaflow-ai/cmux/issues/2784), [#3390](https://github.com/manaflow-ai/cmux/issues/3390), [#9011](https://github.com/manaflow-ai/cmux/pull/9011) |
> | hover underline | A linked status row is underlined only while the pointer is on that line | — | — |
> | fork-rebuild.sh | `scripts/fork-rebuild.sh` builds, installs and verifies a tagged app, Debug or Release, optionally certificate-signed so macOS permissions survive rebuilds | `scripts/fork-rebuild.sh [tag] [--release]`, `--verify-only <tag>`; details in [BUILD-NOTES.md](BUILD-NOTES.md) | — |
> | ctrl+tab focus last | Ctrl+Tab / Ctrl+Shift+Tab yield to any action bound to them, so Focus Last on Ctrl+Tab toggles between the last two places instead of cycling surfaces | `"shortcuts": { "focusHistoryLast": "ctrl+tab" }` in `cmux.json` | [#474](https://github.com/manaflow-ai/cmux/issues/474) |
> | top tabs | Tabs above the split area, each owning its own split layout (Ghostty / iTerm2 style): ⌘T opens a tab, ⌘D splits only the current tab, the existing tab shortcuts and Ctrl+Tab act on top tabs; turning it on splits stacked surfaces into tabs and turning it off moves extra tabs into workspaces below. Renames `Workspace.bonsplitController` to `activeBonsplitController` (separate refactor commit; `scripts/fork/rename-bonsplit-controller.py` resolves its rebase conflicts) | Settings → App → Tabs Contain Splits, or `"workspaceTopTabs": true` under `app` in `cmux.json` | [#1362](https://github.com/manaflow-ai/cmux/issues/1362) |
> | top tab activity bar | A thin bar under each top tab for the agent in its panels: a sweep while it runs, solid amber when it needs input, solid red when it failed; a tab shows its loudest pane, and Reduce Motion stills the sweep. It reads cmux's own agent state, which stays `running` after a turn is interrupted with Esc unless a tool corrects it with `set-tab-state` | Automatic with top tabs on | — |
> | set-tab-state | `set-tab-state <running\|needs-input\|error\|idle>`, `clear-tab-state` and `list-tab-state` set what a tab's activity bar shows, ahead of cmux's agent state until cleared (`idle` hides the bar); display-only, per surface, last writer wins, and refused through the remote relay | `cmux set-tab-state running [--surface <id\|ref\|index>]`, `cmux list-tab-state --json` | [#9226](https://github.com/manaflow-ai/cmux/issues/9226), [#15246](https://github.com/manaflow-ai/cmux/issues/15246) |
> | workspace numbers | Always shows the configured number shortcut before the workspace title, leaving the hover close button available; 1–8 reach the first eight workspaces and 9 reaches the last | Settings → Sidebar Appearance → Always Show Workspace Numbers, or `"alwaysShowWorkspaceNumbers": true` under `sidebar` in `cmux.json` | [#1096](https://github.com/manaflow-ai/cmux/issues/1096), [#7517](https://github.com/manaflow-ai/cmux/pull/7517) |
>
> The upstream column is where each feature would land if it goes up, not a claim that it answers the issue: `row deep link` admits only this build's own scheme, where [#2784](https://github.com/manaflow-ai/cmux/issues/2784) and [#3390](https://github.com/manaflow-ai/cmux/issues/3390) ask for arbitrary ones, and `always show all` is a switch where [#8655](https://github.com/manaflow-ai/cmux/issues/8655) asks for a configurable limit. [#1988](https://github.com/manaflow-ai/cmux/issues/1988) wants the trackpad gesture that `surface slide` would animate, not the animation. [#474](https://github.com/manaflow-ai/cmux/issues/474) was closed by #14700, which added Focus Last but left Ctrl+Tab unreachable for it; `ctrl+tab focus last` can go once upstream lets a binding beat the legacy stroke. `top tabs` covers #1362's model but has no CLI/socket verbs for top tabs, does not restore a whole closed tab, and leaves Canvas mode unavailable while a workspace has several tabs. `set-tab-state` sets one of four states, where [#9226](https://github.com/manaflow-ai/cmux/issues/9226) asks for surface-scoped pills with text and [#15246](https://github.com/manaflow-ai/cmux/issues/15246) sketches a `status` verb with text and color reachable through the CLI, the socket and an escape sequence; this has only the CLI and socket. `top tab activity bar` inherits [#4389](https://github.com/manaflow-ai/cmux/issues/4389): cmux's lifecycle stays running after an interrupted turn. `hover underline`, `fork-rebuild.sh` and `top tab activity bar` have no upstream issue; searched 2026-10-04 and 2026-10-06.
>
> `workspace numbers` is off by default, while #1096 asks for numbers by default. Related upstream PR #7517 keeps its hints in the trailing slot; this fork places them before the title in both sidebar renderers.
>
> Commit hashes are deliberately absent: following upstream rewrites every one of them, and this table went stale each time it carried them. `git log --oneline origin/main..cmux-local` is the live list, newest first, and the subjects match the rows above.
>
> Follow upstream with `git fetch origin && git rebase origin/main` on `cmux-local` — one conflict pass, and `git log origin/main..` is then exactly this fork's diff. Never commit on `main`: `scripts/merge-main.sh` and the rest of the tooling assume it equals upstream.
>
> To send one feature upstream, it is already its own commit: `git switch -c pr-<name> origin/main && git cherry-pick "$(git log --format=%H --grep '<subject fragment>' origin/main..cmux-local)"`.
>
> Builds and the installed app slots are in [BUILD-NOTES.md](BUILD-NOTES.md).

<h1 align="center">cmux</h1>
<p align="center">A Ghostty-based macOS terminal with vertical tabs and notifications for AI coding agents</p>

<p align="center">
  <a href="https://github.com/manaflow-ai/cmux/releases/latest/download/cmux-macos.dmg">
    <img src="./docs/assets/macos-badge.png" alt="Download cmux for macOS" width="180" />
  </a>
</p>

<p align="center">
  English | <a href="README.ja.md">日本語</a> | <a href="README.vi.md">Tiếng Việt</a> | <a href="README.zh-CN.md">简体中文</a> | <a href="README.zh-TW.md">繁體中文</a> | <a href="README.ko.md">한국어</a> | <a href="README.de.md">Deutsch</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.it.md">Italiano</a> | <a href="README.da.md">Dansk</a> | <a href="README.pl.md">Polski</a> | <a href="README.ru.md">Русский</a> | <a href="README.bs.md">Bosanski</a> | <a href="README.ar.md">العربية</a> | <a href="README.no.md">Norsk</a> | <a href="README.pt-BR.md">Português (Brasil)</a> | <a href="README.th.md">ไทย</a> | <a href="README.tr.md">Türkçe</a> | <a href="README.km.md">ភាសាខ្មែរ</a> | <a href="README.uk.md">Українська</a>
</p>

<p align="center">
  <a href="https://x.com/manaflowai"><img src="https://img.shields.io/badge/@manaflow-555?logo=x" alt="X / Twitter" /></a>
  <a href="https://discord.gg/xsgFEVrWCZ"><img src="https://img.shields.io/badge/Discord-555?logo=discord" alt="Discord" /></a>
  <a href="https://github.com/manaflow-ai/cmux"><img src="https://img.shields.io/github/stars/manaflow-ai/cmux?style=flat&logo=github&label=stars&color=4c71f2" alt="GitHub stars" /></a>
</p>

<p align="center">
  <img src="./docs/assets/main-first-image.png" alt="cmux screenshot" width="900" />
</p>

<p align="center">
  <a href="https://www.youtube.com/watch?v=i-WxO5YUTOs">▶ Demo video</a> · <a href="https://cmux.com/blog/zen-of-cmux">The Zen of cmux</a>
</p>

<p align="center">
  <a href="https://cmux.com/docs/getting-started">Docs</a> · <a href="https://cmux.com/blog">Blog</a> · <a href="https://cmux.com/docs/changelog">Changelog</a> · <a href="https://cmux.com/community">Community</a>
</p>

## Features

<table>
<tr>
<td width="40%" valign="middle">
<h3>Notification rings</h3>
Panes get a blue ring and tabs light up when coding agents need your attention
</td>
<td width="60%">
<img src="./docs/assets/notification-rings.png" alt="Notification rings" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Notification panel</h3>
See all pending notifications in one place, jump to the most recent unread
</td>
<td width="60%">
<img src="./docs/assets/sidebar-notification-badge.png" alt="Sidebar notification badge" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>In-app browser</h3>
Split a browser alongside your terminal with a scriptable API ported from <a href="https://github.com/vercel-labs/agent-browser">agent-browser</a>
</td>
<td width="60%">
<img src="./docs/assets/built-in-browser.png" alt="Built-in browser" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Vertical + horizontal tabs</h3>
Sidebar shows git branch, linked PR status/number, working directory, listening ports, and latest notification text. Split horizontally and vertically.
</td>
<td width="60%">
<img src="./docs/assets/vertical-horizontal-tabs-and-splits.png" alt="Vertical tabs and split panes" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>SSH</h3>
<code>cmux ssh user@remote</code> creates a workspace for a remote machine. Pass <code>--command 'omp "investigate auth"'</code> to run an initial command once in its first remote terminal. Browser panes route through the remote network so localhost just works. Drag an image into a remote session to upload via scp.
</td>
<td width="60%">
<img src="./docs/assets/ssh.png" alt="cmux SSH" width="100%" />
</td>
</tr>
<tr>
<td width="40%" valign="middle">
<h3>Claude Code Teams</h3>
<code>cmux claude-teams</code> runs Claude Code's teammate mode with one command. Teammates spawn as native splits with sidebar metadata and notifications. No tmux required.
</td>
<td width="60%">
<img src="./docs/assets/claude-code-teams.png" alt="Claude Code Teams" width="100%" />
</td>
</tr>
</table>

- **Browser import** — Import cookies, history, and sessions from Chrome, Firefox, Arc, and 20+ browsers so browser panes start authenticated
- **Custom commands** — Define project-specific actions in [`cmux.json`](https://cmux.com/docs/custom-commands) that launch from the command palette
- **Programmable** — CLI and socket API to create workspaces, split panes, send keystrokes, and automate the browser
- **Native macOS app** — Built with Swift and AppKit, not Electron. Fast startup, low memory.
- **Ghostty compatible** — Reads your existing `~/.config/ghostty/config` for themes, fonts, and colors
- **GPU-accelerated** — Powered by libghostty for smooth rendering
- **Keyboard shortcuts** — [Extensive shortcuts](https://cmux.com/docs/keyboard-shortcuts) for workspaces, splits, browser, and more
- **Open source** — Free and GPL-licensed

## Install

### DMG (recommended)

<a href="https://github.com/manaflow-ai/cmux/releases/latest/download/cmux-macos.dmg">
  <img src="./docs/assets/macos-badge.png" alt="Download cmux for macOS" width="180" />
</a>

Open the `.dmg` and drag cmux to your Applications folder. cmux auto-updates via Sparkle, so you only need to download once.

### Homebrew

```bash
brew tap manaflow-ai/cmux
brew install --cask cmux
```

To update later:

```bash
brew upgrade --cask cmux
```

On first launch, macOS may ask you to confirm opening an app from an identified developer. Click **Open** to proceed.

## Why cmux?

I run a lot of Claude Code and Codex sessions in parallel. I was using Ghostty with a bunch of split panes, and relying on native macOS notifications to know when an agent needed me. But Claude Code's notification body is always just "Claude is waiting for your input" with no context, and with enough tabs open I couldn't even read the titles anymore.

I tried a few coding orchestrators but most of them were Electron/Tauri apps and the performance bugged me. I also just prefer the terminal since GUI orchestrators lock you into their workflow. So I built cmux as a native macOS app in Swift/AppKit. It uses libghostty for terminal rendering and reads your existing Ghostty config for themes, fonts, and colors.

The main additions are the sidebar and notification system. The sidebar has vertical tabs that show git branch, linked PR status/number, working directory, listening ports, and the latest notification text for each workspace. The notification system picks up terminal sequences (OSC 9/99/777) and has a CLI (`cmux notify`) you can wire into agent hooks for Claude Code, OpenCode, etc. When an agent is waiting, its pane gets a blue ring and the tab lights up in the sidebar, so I can tell which one needs me across splits and tabs. Cmd+Shift+U jumps to the most recent unread.

The in-app browser has a scriptable API ported from [agent-browser](https://github.com/vercel-labs/agent-browser). Agents can snapshot the accessibility tree, get element refs, click, fill forms, and evaluate JS. You can split a browser pane next to your terminal and have Claude Code interact with your dev server directly.

Everything is scriptable through the CLI and socket API — create workspaces/tabs, split panes, send keystrokes, open URLs in the browser.

## The Zen of cmux

cmux is not prescriptive about how developers hold their tools. It's a terminal and browser with a CLI, and the rest is up to you.

cmux is a primitive, not a solution. It gives you a terminal, a browser, notifications, workspaces, splits, tabs, and a CLI to control all of it. cmux doesn't force you into an opinionated way to use coding agents. What you build with the primitives is yours.

The best developers have always built their own tools. Nobody has figured out the best way to work with agents yet, and the teams building closed products definitely haven't either. The developers closest to their own codebases will figure it out first.

Give a million developers composable primitives and they'll collectively find the most efficient workflows faster than any product team could design top-down.

## Documentation

For more info on how to configure cmux, [head over to our docs](https://cmux.com/docs/getting-started?utm_source=readme).

To theme cmux (colors, fonts, transparency, sidebar, and more), see [Customizing cmux's look](docs/customizing-appearance.md).

For shell watcher churn and managed-Mac process audit volume, see the supported
[`CMUX_NO_GIT_WATCH=1` mitigation](docs/shell-integration.md) and its Git/PR update trade-offs.

## Keyboard Shortcuts

### Workspaces

| Shortcut | Action |
|----------|--------|
| ⌘ N | New local workspace |
| ⌘ Y | New Cloud workspace on the last usable Cloud context; opens New Cloud Machine when none is available |
| ⌘ ⇧ Y | New Cloud machine |
| ⌘ 1–8 | Jump to workspace 1–8 |
| ⌘ 9 | Jump to last workspace |
| ⌃ ⌘ ] | Next workspace |
| ⌃ ⌘ [ | Previous workspace |
| ⌘ ⇧ W | Close workspace |
| ⌘ ⇧ R | Rename workspace |
| ⌥ ⌘ E | Edit workspace description |
| ⌘ B | Toggle sidebar |
| ⌥ ⌘ B | Toggle right sidebar |
| ⌘ ⇧ E | Toggle right sidebar focus |

### Surfaces

| Shortcut | Action |
|----------|--------|
| ⌘ T | New surface |
| ⌘ ⇧ ] | Next surface |
| ⌘ ⇧ [ | Previous surface |
| ⌃ Tab | Next surface |
| ⌃ ⇧ Tab | Previous surface |
| ⌃ 1–8 | Jump to surface 1–8 |
| ⌃ 9 | Jump to last surface |
| ⌘ W | Close surface |

### Split Panes

| Shortcut | Action |
|----------|--------|
| ⌘ D | Split right |
| ⌘ ⇧ D | Split down |
| ⌥ ⌘ ← → ↑ ↓ | Focus pane directionally |
| ⌃ ⇧ H J K L | Resize pane left/down/up/right |
| ⌘ ⇧ H | Flash focused panel |

### Browser

Browser developer-tool shortcuts follow Safari defaults and are customizable in `Settings → Keyboard Shortcuts`.
Command palette navigation shortcuts, including ⌃ P, are also customizable and can be cleared so the keypress reaches the active terminal.

| Shortcut | Action |
|----------|--------|
| ⌘ ⇧ L | Open browser in split |
| ⌘ L | Focus address bar |
| ⌘ [ | Back |
| ⌘ ] | Forward |
| ⌘ R | Reload page |
| ⌥ ⌘ I | Toggle Developer Tools (Safari default) |
| ⌥ ⌘ C | Show JavaScript Console (Safari default) |

### Notifications

| Shortcut | Action |
|----------|--------|
| ⌘ I | Show notifications panel |
| ⌘ ⇧ U | Jump to latest unread |
| ⌥ ⌘ U | Toggle current item unread state |
| ⌃ ⌘ U | Mark current item as oldest unread and jump to next latest unread |
| — | Mark all notifications read (unbound by default; configure in Settings or `cmux.json`) |
| — | Clear all notifications (unbound by default; configure in Settings or `cmux.json`) |

### Find

| Shortcut | Action |
|----------|--------|
| ⌘ F | Find |
| ⌘ ⇧ F | Find in directory |
| ⌘ G / ⌥ ⌘ G | Find next / previous |
| ⌥ ⌘ ⇧ F | Hide find bar |
| ⌘ E | Use selection for find |

### Terminal

| Shortcut | Action |
|----------|--------|
| ⌘ K | Clear scrollback |
| ⌘ C | Copy (with selection) |
| ⌘ V | Paste |
| ⌘ + / ⌘ - | Increase / decrease font size |
| ⌘ 0 | Reset font size |

### Window

| Shortcut | Action |
|----------|--------|
| ⌘ ⇧ N | New window |
| ⌘ ⇧ O | Reopen previous session |
| ⌘ , | Settings |
| ⌘ ⇧ , | Reload configuration |
| ⌘ Q | Quit |

## Nightly Builds

[Download cmux NIGHTLY](https://github.com/manaflow-ai/cmux/releases/download/nightly/cmux-nightly-macos.dmg) (universal; updates then switch to your Mac's architecture automatically)

cmux NIGHTLY is a separate app with its own bundle ID, so it runs alongside the stable version. Built automatically from the latest `main` commit and auto-updates via its own Sparkle feed.

Report nightly bugs on [GitHub Issues](https://github.com/manaflow-ai/cmux/issues) or in [#nightly-bugs on Discord](https://discord.gg/xsgFEVrWCZ).

## Session restore

Quitting cmux saves the current session. On relaunch, cmux restores app-owned
state:
- Window/workspace/pane layout
- Working directories
- Terminal scrollback (best effort)
- Browser URL and navigation history

cmux does not checkpoint arbitrary live process state. Ordinary terminals,
tmux, vim, shells, and unsupported terminal apps reopen as normal terminals.
For live detach/reattach across cmux quit, crashes, and updates, opt in to the
local tmux owner with `cmux local-tmux`; see [`docs/local-tmux.md`](docs/local-tmux.md)
for its lifecycle and machine-sleep limits. zellij users can use `cmux local-zellij`
instead; see [`docs/local-zellij.md`](docs/local-zellij.md).

Supported agent sessions can resume when hooks have saved a native session ID.
Install hooks after installing the agent CLI so its binary is on `PATH`:

```bash
cmux hooks setup
cmux hooks setup codex
cmux hooks setup --agent opencode
```

`cmux hooks setup` installs supported agents it can find and prints a summary
for skipped agents. Supported resume integrations include Claude Code, Codex,
Grok, OpenCode, Pi, Amp, Cursor CLI, Gemini, Rovo Dev, Copilot, CodeBuddy,
Factory, and Qoder. Claude Code is handled by the cmux Claude wrapper when Claude
integration is enabled in Settings.

Advanced users and integrations can attach a custom resume command to the
current terminal surface. This is useful for tools with their own durable state,
such as tmux sessions or custom agent CLIs:

```bash
cmux surface resume set --kind tmux --checkpoint work --shell "tmux attach -t work"
cmux surface resume show --json
cmux surface resume clear --checkpoint work
```

The binding stays attached to the cmux surface. Public CLI or socket-created
bindings are stored for inspection and manual restore unless you approve a
signed command prefix for automatic restore. Approved prefixes are also bound to
the working directory and exact environment values, when present. Review or edit
approvals in **Settings > Terminal > Resume Commands**. cmux only auto-runs
resume bindings it marks trusted, such as live process-detected tmux bindings or
user-approved prefixes. Sensitive environment keys such as tokens, passwords,
secrets, and API keys are dropped before a resume binding is stored.

To keep restored agent terminals idle instead of automatically running their resume commands,
turn off **Settings > Terminal > Resume Agent Sessions on Reopen** or set this in
`~/.config/cmux/cmux.json`:

```json
{
  "terminal": {
    "autoResumeAgentSessions": false
  }
}
```

This only disables automatic agent resume commands. cmux still restores the saved layout,
working directories, scrollback, and browser history.

If you need to reapply the last saved snapshot manually, use:
- `File > Reopen Previous Session`
- `⌘ ⇧ O`
- `cmux restore-session`

Each cmux install (stable, nightly, rc, staging, and tagged debug builds) keeps its own
saved session. To bring a session from one install into another, for example after trying
nightly and switching back to stable, run this from the install you want to open it in:

```bash
cmux restore-session --from nightly          # or stable, rc, staging, debug:<tag>
cmux restore-session --export ~/session.json # write this install's saved session to a file
cmux restore-session --export ~/session.json --force # replace an existing export file
cmux restore-session --from ~/session.json   # reopen an exported file
```

The imported session opens as additional windows next to the ones you have, like
`cmux restore-session`; the other install's saved file is only read. Agent resume carries
over because hook session mappings in `~/.cmuxterm/` are shared by every install. Browser
cookies and logins are per install and do not move.

`--from <channel>` restores another install's own session file with the same trust as your
own session, including automatic agent resume. `--from <path>` treats the file as untrusted:
layout, working directories, text scrollback, and http(s) browser tabs restore, but nothing in
the file runs automatically. Built-in agents (Claude Code, Codex, Amp, and the rest) resume with
the command cmux builds from the agent kind and session id, ignoring launch arguments stored in
the file, and only when the working directory already exists on this Mac. Custom agent resume
commands, resume bindings, and tmux start commands are kept for manual restore only (approved
resume prefixes never apply to them): the CLI reports how many were held back, and in each
terminal `cmux surface resume show` shows the command and `cmux restore --surface` runs it.
Terminal control sequences in the scrollback (clipboard, notifications, links, titles), draft
attachments, non-http(s) browser pages and profiles, SSH/cloud connections, and workspace
environment variables from the file are dropped. A snapshot saved by a newer cmux
(newer session format) is refused with an error; if a downgraded cmux finds one in its own
session file, it keeps a copy next to it as `session-<bundle id>.schema-v<N>.json`.

Under the hood, cmux writes a versioned snapshot under
`~/Library/Application Support/cmux/` and agent hooks write session mappings
under `~/.cmuxterm/`. On restore, cmux rebuilds the layout first, then runs the
supported agent's native resume command when automatic agent resume is enabled.

Read the full guide at <https://cmux.com/docs/session-restore>.

## FAQ

### How does cmux relate to Ghostty?

cmux is not a fork of Ghostty. It uses [libghostty](https://github.com/ghostty-org/ghostty) as a library for terminal rendering, the same way apps use WebKit for web views. Ghostty is a standalone terminal; cmux is a different app built on top of its rendering engine.

### What platforms does it support?

macOS only, for now. cmux is a native Swift + AppKit app.

### Is there an iOS app?

Yes, in beta. Pair your iPhone with your Mac from the Mobile Connect window and attach to your terminals from your phone, with optional forwarding of terminal notifications. It ships on TestFlight as cmux BETA. Early access is included with [cmux Founders Edition](https://github.com/manaflow-ai/cmux#founders-edition). See the [iOS docs](https://cmux.com/docs/ios).

### What coding agents does cmux work with?

All of them. cmux is a terminal, so any agent that runs in a terminal works out of the box: Claude Code, Codex, OpenCode, Gemini CLI, Kiro, Aider, Goose, Amp, Cline, Cursor Agent, and anything else you can launch from the command line.

### Can cmux orchestrate multiple agents and subagents?

Yes. When an agent spawns subagents or teammates, cmux turns them into native panes and splits instead of hidden background processes. It supports [Claude Code teams](https://cmux.com/docs/agent-integrations/claude-code-teams) and [oh-my-opencode](https://cmux.com/docs/agent-integrations/oh-my-opencode) multi-model orchestration, so every agent in a run is visible and controllable.

### Can I use cmux with remote machines?

Yes. Open workspaces over SSH and attach to remote tmux sessions, so agents can run on a remote host while you drive them from cmux. See [SSH and remote](https://cmux.com/docs/ssh).

### How do notifications work?

When a process needs attention, cmux shows notification rings around panes, unread badges in the sidebar, a notification popover, and a macOS desktop notification. These fire automatically via standard terminal escape sequences (OSC 9/99/777), or you can trigger them with the [cmux CLI](https://cmux.com/docs/notifications#cli-usage) and [agent hooks](https://cmux.com/docs/notifications#integration-examples). Any agent that supports hooks or OSC works, including Claude Code, Codex, OpenCode, and pi.

### Is cmux programmable?

Yes. Every action is available through the cmux CLI and a Unix socket: create workspaces, open split panes, send input, read screen contents, take screenshots, and drive the in-app browser. See the [CLI reference](https://cmux.com/docs/api) and [browser automation](https://cmux.com/docs/browser-automation) docs.

### What can the built-in browser do?

cmux can split a real browser pane next to your terminal, and it is fully programmable: navigate, snapshot the DOM, click, type, evaluate JavaScript, and read console and network activity over the same socket API. Agents use it to verify their own web changes without leaving cmux. See [browser automation](https://cmux.com/docs/browser-automation).

### Does cmux have skills?

Yes. Skills are reusable workflows you can give any agent running in cmux, for things like CLI control, workspace automation, settings, and browser surfaces. Browse the open collection at [cmux-skills](https://github.com/manaflow-ai/cmux-skills), or read the [skills docs](https://cmux.com/docs/skills).

### Can I customize keyboard shortcuts?

Terminal keybindings are read from your Ghostty config file (`~/.config/ghostty/config`), including leader sequences and key tables. Ghostty tab actions target cmux workspaces; see the [action mapping, precedence, and limitations](docs/ghostty-keybindings.md). cmux-specific shortcuts (workspaces, splits, browser, notifications) can be customized in Settings. See the [default shortcuts](https://cmux.com/docs/keyboard-shortcuts) for a full list.

### Can I customize cmux?

Yes. Terminal rendering uses your Ghostty config, so themes, fonts, colors, and cursor carry over directly. cmux's own settings in `~/.config/cmux/cmux.json` control the sidebar, tab bar, split panes, and behavior, and every [keyboard shortcut](https://cmux.com/docs/keyboard-shortcuts) is editable. See [configuration](https://cmux.com/docs/configuration).

### Are my sessions saved?

cmux restores windows, workspaces, panes, working directories, and best-effort
scrollback when you relaunch. Supported agent integrations can resume from
their saved session IDs. Those are reconstructed app state and resume commands;
they do not keep arbitrary live processes running. Use `cmux local-tmux` for
live local detach/reattach across cmux quit, crashes, and updates. A local tmux
server cannot survive logout, restart, shutdown, or power loss; use
`cmux ssh-tmux`, `cmux mosh-tmux`, or a persistent cloud VM when the owner must
remain online while this Mac is offline. See [session restore](https://cmux.com/docs/session-restore)
and [`docs/local-tmux.md`](docs/local-tmux.md).

### How does it compare to tmux?

tmux is a terminal multiplexer that runs inside any terminal. cmux is a native macOS app with a GUI: vertical tabs, split panes, an embedded browser, and a socket API, all built in, no config files or prefix keys needed. That said, lots of people happily run cmux with SSH and tmux together, and cmux can attach to your remote tmux sessions natively ([beta](https://cmux.com/docs/remote-tmux)).

### Is cmux free?

Yes, cmux is free to use. The source code is available on [GitHub](https://github.com/manaflow-ai/cmux).

### How can I support cmux?

cmux is free and open source, and always will be. If you want to back development and get early access to what's next, including cmux AI, the iOS app, and Cloud VMs, check out [cmux Founders Edition](https://github.com/manaflow-ai/cmux#founders-edition).

### I have a feature request or found a bug?

We want to hear it. Open an [issue](https://github.com/manaflow-ai/cmux/issues) or [pull request](https://github.com/manaflow-ai/cmux/pulls) on GitHub, or [email us](mailto:founders@cmux.com?subject=cmux%20feature%20request).

## Star History

<a href="https://www.star-history.com/?repos=manaflow-ai%2Fcmux&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=manaflow-ai/cmux&type=date&theme=dark&legend=top-left&sealed_token=N5E-Mdh7zIesE2fP9_q8wEZyOg3un2Ki7u61afJnUUu6ZIUEUsrH_dsPrA8CWrw12owIEezjOyhDiXcfIEoSzAlIybOqvxTk-xCpuXbpnFk86SkJzfErObW1u0MrAuLp-_tXZDM1kAMI2jMtAeXZK3_VEe2HH9dNyhXxgMTCns6c7lMmCJ_kSIgtooYf" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=manaflow-ai/cmux&type=date&legend=top-left&sealed_token=N5E-Mdh7zIesE2fP9_q8wEZyOg3un2Ki7u61afJnUUu6ZIUEUsrH_dsPrA8CWrw12owIEezjOyhDiXcfIEoSzAlIybOqvxTk-xCpuXbpnFk86SkJzfErObW1u0MrAuLp-_tXZDM1kAMI2jMtAeXZK3_VEe2HH9dNyhXxgMTCns6c7lMmCJ_kSIgtooYf" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=manaflow-ai/cmux&type=date&legend=top-left&sealed_token=N5E-Mdh7zIesE2fP9_q8wEZyOg3un2Ki7u61afJnUUu6ZIUEUsrH_dsPrA8CWrw12owIEezjOyhDiXcfIEoSzAlIybOqvxTk-xCpuXbpnFk86SkJzfErObW1u0MrAuLp-_tXZDM1kAMI2jMtAeXZK3_VEe2HH9dNyhXxgMTCns6c7lMmCJ_kSIgtooYf" />
 </picture>
</a>

## Contributing

New here? [Start here](docs/start-here.md) is the short path from "I want to
change something" to a merged pull request, including what you can fix without a
Mac. Then the [contributor guide](CONTRIBUTING.md) and
[fast local checks](CONTRIBUTING.md#fast-checks-before-building-or-pushing).

Ways to get involved:

- Follow us on X for updates [@manaflowai](https://x.com/manaflowai), [@lawrencecchen](https://x.com/lawrencecchen), and [@austinywang](https://x.com/austinywang)
- Join the conversation on [Discord](https://discord.gg/xsgFEVrWCZ)
- Create and participate in [GitHub issues](https://github.com/manaflow-ai/cmux/issues) and [discussions](https://github.com/manaflow-ai/cmux/discussions)
- Let us know what you're building with cmux

## Community

- [Discord](https://discord.gg/xsgFEVrWCZ)
- [WhatsApp](https://chat.whatsapp.com/Fblh7FB58lOI2cx6ccdIqY?mode=gi_t)
- [GitHub](https://github.com/manaflow-ai/cmux)
- [X / Twitter](https://twitter.com/manaflowai)
- [YouTube](https://www.youtube.com/channel/UCAa89_j-TWkrXfk9A3CbASw)
- [LinkedIn](https://www.linkedin.com/company/manaflow-ai/)
- [Reddit](https://www.reddit.com/r/cmux/)

<p>
  <strong>WeChat:</strong> Scan the QR code to join the community.<br />
  <img src="./docs/assets/wechat-community-qr.jpg" alt="WeChat QR code to join the cmux community" width="240" />
</p>

## Founder's Edition

cmux is free, open source, and always will be. If you'd like to support development and get early access to what's coming next:

**[Get Founder's Edition](https://buy.stripe.com/3cI00j2Ld0it5OU33r5EY0q)**

- **Prioritized feature requests/bug fixes**
- **Early access: cmux AI that gives you context on every workspace, tab and panel**
- **Early access: iOS app with terminals synced between desktop and phone**
- **Early access: Cloud VMs**
- **Early access: Voice mode**
- **My personal iMessage/WhatsApp**

## Install

### DMG (recommended)

<a href="https://github.com/manaflow-ai/cmux/releases/latest/download/cmux-macos.dmg">
  <img src="./docs/assets/macos-badge.png" alt="Download cmux for macOS" width="180" />
</a>

Open the `.dmg` and drag cmux to your Applications folder. cmux auto-updates via Sparkle, so you only need to download once.

### Homebrew

```bash
brew tap manaflow-ai/cmux
brew install --cask cmux
```

To update later:

```bash
brew upgrade --cask cmux
```

On first launch, macOS may ask you to confirm opening an app from an identified developer. Click **Open** to proceed.

## License

cmux is open source under [GPL-3.0-or-later](LICENSE). The cmux server software (`web/`, the Cloudflare workers, and the relay services listed in [LICENSE](LICENSE)) uses the [Business Source License 1.1](web/LICENSE) instead: you can read, modify, and run it for non-production use, and production use or self-hosting requires a commercial license.

If your organization cannot comply with GPL, commercial terms may be available
for portions for which Manaflow controls the necessary rights. They do not
relicense third-party material or outside contributions for which Manaflow
lacks a separate grant. See [LICENSE](LICENSE) for the exact scope and contact
[founders@cmux.com](mailto:founders@cmux.com) for details.
