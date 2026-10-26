import { test, expect, mock } from 'claude-code/testing'
import type { On } from 'claude-code'

/**
 * What these can and cannot check.
 *
 * The mod's whole effect is a file write and a process spawn, and the test
 * kit's `$` carries neither noun, so there is no oracle here for "the store
 * now says working". What these do cover is the part that broke twice while
 * the mod was written: the module loading at all, and every hook running to
 * `next` without throwing or swallowing a turn. The store contents are
 * verified live instead, against the running sidebar.
 *
 * Each test points the mod at a scratch path and at `/usr/bin/true`, so even
 * the unobservable side effects stay away from the live sidebar.
 */
const scratch = () => `/tmp/cmux-agent-status-test-${Math.random().toString(36).slice(2)}.json`

const engine = (on: On, store: string) => {
  mock.env(on, {
    CMUX_AGENT_STATUS_STORE: store,
    CMUX_AGENT_STATUS_DAEMON: '/usr/bin/true',
    CMUX_AGENT_STATUS_PYTHON: '/usr/bin/env',
  })
  on('turn.start', async (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', async (_$, e) => ({ text: e.answer }))
  on('session.end', async () => ({ sessionId: 's1' }))
}

test('a turn start passes through the mod unchanged', async ($, on) => {
  engine(on, scratch())
  const result = await $.turn.start({ text: 'hello', turnId: 't1' })
  expect(result.turnId).toEqual('t1')
})

test('an answered turn passes through the mod unchanged', async ($, on) => {
  engine(on, scratch())
  const result = await $.turn.complete({
    answer: 'done',
    reason: 'answer',
    turnId: 't1',
    isAborted: false,
  })
  expect(result.text).toEqual('done')
})

test('a turn that died on an API error still reaches the engine', async ($, on) => {
  engine(on, scratch())
  const result = await $.turn.complete({
    answer: '',
    reason: 'error',
    turnId: 't1',
    isAborted: false,
  })
  expect(result.text).toEqual('')
})

test("a subagent's turn passes through without the mod acting on it", async ($, on) => {
  engine(on, scratch())
  const result = await $.turn.complete({
    answer: 'child done',
    reason: 'answer',
    turnId: 't2',
    isAborted: false,
    agentId: 'sub-1',
  })
  expect(result.text).toEqual('child done')
})

test('a session end reaches the engine after the mod marks it ended', async ($, on) => {
  engine(on, scratch())
  const result = await $.session.end({ reason: 'exit' })
  expect(result.sessionId).toEqual('s1')
})
