import type { Register } from 'claude-code'

/**
 * Reports this session's state to the cmux sidebar daemon.
 *
 * The Python hook this replaces was registered on PreToolUse, so it paid a
 * fresh interpreter start (measured: 32 ms, of which 20 ms is startup alone)
 * for every tool call of every agent. A turn's state only changes at its
 * edges, so the edges are all this listens to, and it runs in process.
 *
 * It writes the same `agent-waiting.json` the daemon already prefers over
 * `cmux sessions list` (whose agent_lifecycle is sticky and reports "running"
 * for sessions idle for many minutes), then kicks one daemon tick so the row
 * repaints now rather than within the launchd interval.
 */

/** Homebrew's, not /usr/bin/python3: that one is the Xcode CLT shim. */
const DEFAULT_PYTHON = '/opt/homebrew/bin/python3'

/**
 * Where the sidebar's files are, resolved per call.
 *
 * Nothing is hardcoded to one account: HOME comes from the environment, so
 * the mod can live in a shared plugin folder. Every path is overridable,
 * which is also what lets a test point at a scratch file and a harmless
 * command -- `$.fs` and `$.process` are not mockable nouns, so without that
 * a test would rewrite the live store and wake the real daemon.
 *
 * `store` is null when there is no cmux store to write, which is how this
 * stays quiet on a machine that does not run cmux rather than failing once
 * per turn.
 */
async function settings($: any): Promise<{ store: string | null; daemon: string; python: string }> {
  // One literal per call: the engine requires it so a module's environment
  // reads can be listed without running it.
  let home = ''
  let dir = ''
  let store = ''
  let daemon = ''
  let python = DEFAULT_PYTHON
  try {
    home = (await $.env.get('HOME')) || ''
  } catch {}
  try {
    dir = (await $.env.get('CMUX_AGENT_STATUS_DIR')) || ''
  } catch {}
  try {
    store = (await $.env.get('CMUX_AGENT_STATUS_STORE')) || ''
  } catch {}
  try {
    daemon = (await $.env.get('CMUX_AGENT_STATUS_DAEMON')) || ''
  } catch {}
  try {
    python = (await $.env.get('CMUX_AGENT_STATUS_PYTHON')) || DEFAULT_PYTHON
  } catch {}
  if (!dir && home) dir = `${home}/.config/cmux`
  if (!store && dir) store = `${dir}/agent-waiting.json`
  if (!daemon && dir) daemon = `${dir}/agent-status-daemon.py`
  return { store: store || null, daemon, python }
}

/** A tick costs ~0.3 s of CPU; two turn edges can land within milliseconds. */
const KICK_MIN_MS = 1500
/** An `ended` tombstone older than this is dropped, matching the Python hook. */
const STALE_SECONDS = 24 * 3600
/** Any other state is the only record of a tab that may still be open. */
const STALE_LIVE_SECONDS = 30 * 24 * 3600

type AgentState = 'working' | 'idle' | 'error'
type Entry = { state: string; ts: number; by?: string; subagents?: Record<string, number> }

/** Module scope, so a reload clears it — which is the behaviour we want. */
let lastKick = 0

async function readStore($: any, store: string): Promise<Record<string, Entry>> {
  try {
    const text = await $.fs.read(store)
    const parsed = JSON.parse(typeof text === 'string' ? text : String(text))
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

/**
 * Runs one daemon tick, not awaited: the turn is over and its result should
 * not wait on a repaint. A tick dropped because the module unloaded mid-run
 * costs at most one interval, since the periodic run redoes the same work.
 */
function kick($: any, python: string, daemon: string): void {
  const now = Date.now()
  if (!daemon || now - lastKick < KICK_MIN_MS) return
  lastKick = now
  void $.process.run([python, daemon], { timeoutMs: 25_000 }).catch(() => {})
}

/**
 * Merges this session's state into the store and asks for one repaint.
 *
 * Read-modify-write over a file several sessions share has a lost-update
 * window the Python hook's atomic replace did not. The cost is bounded: that
 * session's row keeps its previous state until the next write or the next
 * periodic tick picks it up.
 */
async function record($: any, state: AgentState): Promise<void> {
  let sid = ''
  try {
    sid = await $.session.id()
  } catch {
    return
  }
  if (!sid) return

  const paths = await settings($)
  if (!paths.store) return
  const store = await readStore($, paths.store)
  const previous = store[sid]
  // Keep the original timestamp while the state is unchanged, so the age in
  // the sidebar answers "how long has it been like this", not "how long since
  // the last event".
  const now = Date.now() / 1000
  const ts = previous && previous.state === state ? previous.ts : now

  const fresh: Record<string, Entry> = {}
  for (const [key, value] of Object.entries(store)) {
    const limit = (value as Entry | undefined)?.state === 'ended' ? STALE_SECONDS : STALE_LIVE_SECONDS
    if (value && typeof value === 'object' && now - Number(value.ts ?? 0) < limit) {
      fresh[key] = value as Entry
    }
  }
  // Signed, so a reader can tell this apart from the Python hook's write:
  // both set the same state names, and the daemon ignores the extra field.
  // `subagents` belongs to the SubagentStart/Stop hooks; keep it across this write.
  fresh[sid] = { state, ts, by: 'plugin', ...(previous?.subagents ? { subagents: previous.subagents } : {}) }

  try {
    await $.fs.write(paths.store, JSON.stringify(fresh))
  } catch {
    return
  }
  // A second file nothing else writes. The shared store cannot prove this ran:
  // the Python hook rewrites the same entry on every tool call and drops the
  // marker within milliseconds, so proof needs a page it never touches.
  try {
    await $.fs.write(
      `${paths.store}.plugin-proof`,
      JSON.stringify({ session: sid, state, ts, at: new Date().toISOString() }),
    )
  } catch {}
  kick($, paths.python, paths.daemon)
}

/**
 * Marks this session ended so no row outlives it. A tombstone, not a delete:
 * `cmux sessions list` keeps the session while its tab stays open, and the
 * daemon shows a session with no entry as "unknown" for hours.
 */
async function markEnded($: any): Promise<void> {
  try {
    const sid = await $.session.id()
    if (!sid) return
    const paths = await settings($)
    if (!paths.store) return
    const store = await readStore($, paths.store)
    store[sid] = { state: 'ended', ts: Date.now() / 1000, by: 'plugin' }
    await $.fs.write(paths.store, JSON.stringify(store))
    kick($, paths.python, paths.daemon)
  } catch {
    // A hook must never block the session from ending.
  }
}

export const register: Register = (on) => {
  on('turn.start', async ($, e, next) => {
    // A subagent's turn carries agentId; its parent's row already says the
    // workspace is busy, so only the main loop reports.
    if (!(e as { agentId?: string }).agentId) void record($, 'working')
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (!(e as { agentId?: string }).agentId) {
      const reason = (e as { reason?: string }).reason
      // 'answer' and 'aborted' both leave the agent waiting on you; only an
      // error or a refusal is a turn that failed.
      void record($, reason === 'error' || reason === 'refusal' ? 'error' : 'idle')
    }
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    void markEnded($)
    return next(e)
  })
}
