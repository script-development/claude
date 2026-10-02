import type { On, SessionMessage } from 'claude-code'
import { describe, expect, test } from 'claude-code/testing'

// hooks/register.ts against the engine's test kit. Everything beneath the plugin is stood in for
// here: git and the gate (`process.run`), the store (`fs.*`), the fork (`model.fork`) and core's own
// compaction. What these tests cannot show is the live engine's behaviour, which is what
// docs/measured.md findings #37-#41 are for: this kit raises `prompt.context`, for one, though no
// live build measured does.

const CHECKOUT = 'C:/work/repo'
const HANDOFF = 'C:/store/repo-main-abcd1234.md'
const USAGE = { input_tokens: 1, output_tokens: 2, cache_read_input_tokens: 3, cache_creation_input_tokens: 0 }
const TRANSCRIPT: SessionMessage[] = [{ role: 'user', text: 'do the thing', toolUses: [] }]
const CORE: SessionMessage = { role: 'user', text: 'core summary', toolUses: [] }

const DOC = `# Handoff — the thing
branch: main
checkout: ${CHECKOUT}
status: halfway; the format held
progress: complete

## Do not re-derive

### Decisions
Chose A over B.

### Dead ends
None.

### Traps
None.

## Next
1. Finish it.

## Pointers

\`\`\`
\`\`\`
`

type World = {
  files: Map<string, string>
  forks: string[]
  gateRuns: string[][]
  // argv[0] of every script run: which bash ran it.
  shells: string[]
  toasts: string[]
  core: number
  // The host process's environment, the plugin's store, and its debug log lines.
  env: Map<string, string>
  store: Map<string, unknown>
  logs: string[]
}

type Options = {
  // Exit codes the gate returns, one per run, the last repeating.
  gate?: number[]
  isCheckout?: boolean
  existing?: { mtime: number; doc: string }
  forkText?: string
  // What `git --exec-path` prints; absent, git is not on PATH.
  gitExecPath?: string
  // An orient run that fails the way a non-bash fails, e.g. the WSL launcher.
  orientFailure?: { exitCode: number; stderr: string }
  // The environment the process starts with, e.g. a key inherited from a parent `claude`.
  env?: Record<string, string>
  store?: Record<string, unknown>
}

const slashed = (path: string) => path.replace(/\\/g, '/')

function world(on: On, opts: Options = {}): World {
  const w: World = {
    files: new Map(),
    forks: [],
    gateRuns: [],
    shells: [],
    toasts: [],
    core: 0,
    env: new Map(Object.entries(opts.env ?? {})),
    store: new Map(Object.entries(opts.store ?? {})),
    logs: [],
  }
  if (opts.existing) w.files.set(HANDOFF, opts.existing.doc)
  const exits = opts.gate ?? [0]

  on('session.cwd', () => ({ value: CHECKOUT }))
  on('ui.log', (_$, e) => {
    w.logs.push(e.text)
    return { value: undefined }
  })
  on('env.get', (_$, e) => ({ value: w.env.get(e.name) }))
  on('env.set', (_$, e) => {
    if (e.value === undefined) w.env.delete(e.name)
    else w.env.set(e.name, e.value)
    return { value: undefined }
  })
  on('store.get', (_$, e) => ({ value: w.store.get(e.key) }))
  on('store.set', (_$, e) => {
    w.store.set(e.key, e.value)
    return { value: undefined }
  })
  on('store.delete', (_$, e) => {
    w.store.delete(e.key)
    return { value: undefined }
  })
  on('store.keys', () => ({ value: [...w.store.keys()] }))
  on('session.usage', () => ({ value: { startedAt: 1_000_000, context: {}, rateLimits: [] } }) as never)
  on('ui.status', () => ({ value: undefined }))
  on('ui.toast', (_$, e) => {
    w.toasts.push(e.text)
    return { value: undefined }
  })
  // The engine hands paths over in the host's notation (backslashes on Windows); key on one form.
  on('fs.write', (_$, e) => {
    w.files.set(slashed(e.path), e.text)
    return { value: undefined }
  })
  on('fs.read', (_$, e) => ({ value: w.files.get(slashed(e.path)) ?? '' }))
  on('model.fork', (_$, e) => {
    w.forks.push(e.prompt)
    return { value: { isAnswered: true as const, text: opts.forkText ?? DOC, usage: USAGE } }
  })
  on('process.run', (_$, e) => {
    const ran = (exitCode: number, stdout: string, stderr = '') =>
      ({ value: { exitCode, stdout, stderr, isStdoutTruncated: false, isStderrTruncated: false } })
    if (e.argv[0] === 'git' && e.argv[1] === '--exec-path') {
      return opts.gitExecPath === undefined ? ran(127, '', 'git: not found') : ran(0, `${opts.gitExecPath}\n`)
    }
    // The probe for a working bash: every candidate under test runs.
    if (e.argv[1] === '-c') return ran(0, 'ok\n')
    const script = e.argv[1] ?? ''
    w.shells.push(e.argv[0] ?? '')
    if (script.endsWith('handoff-orient.sh')) {
      if (opts.orientFailure) return ran(opts.orientFailure.exitCode, '', opts.orientFailure.stderr)
      if (opts.isCheckout === false) return { value: { exitCode: 1, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
      const ex = opts.existing
      const stdout = [
        `main=${CHECKOUT}`,
        `checkout=${CHECKOUT}`,
        'branch=main',
        `handoff=${HANDOFF}`,
        `exists=${ex ? 1 : 0}`,
        `mtime=${ex ? ex.mtime : ''}`,
        `progress=${ex ? 'complete' : ''}`,
        'gate=C:/plugin/lib/verify-handoff.sh',
      ].join('\n')
      return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    w.gateRuns.push([...e.argv])
    const exitCode = exits[Math.min(w.gateRuns.length - 1, exits.length - 1)] ?? 0
    const stdout = exitCode === 0 ? 'checkout: C:/work/repo\nWARN size' : 'MISSING src/a.ts:12'
    return { value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.compact', () => {
    w.core++
    return { messages: [CORE] }
  })
  return w
}

describe('compaction', () => {
  test('a passing handoff stands in place of core summary, and is stored', async ($, on) => {
    // Arrange
    const w = world(on)

    // Act
    const res = await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.core).toBe(0)
    expect(w.forks.length).toBe(1)
    expect(res.messages?.length).toBe(1)
    expect(res.messages?.[0]?.text).toContain('GATE: OK (1 advisory WARN line(s) omitted)')
    expect(res.messages?.[0]?.text).toContain('Chose A over B.')
    expect(w.files.get(HANDOFF)).toContain('progress: complete')
  })

  test('the gate runs on the draft against the known checkout, never on the stored file', async ($, on) => {
    // Arrange
    const w = world(on)

    // Act
    await $.session.compact({ trigger: 'manual', messages: TRANSCRIPT })

    // Assert
    expect(w.gateRuns[0]?.slice(2)).toEqual([`${HANDOFF}.draft`, CHECKOUT])
  })

  test('a failed gate gets one corrected retry carrying the report and the draft', async ($, on) => {
    // Arrange
    const w = world(on, { gate: [1, 0] })

    // Act
    const res = await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.forks.length).toBe(2)
    expect(w.forks[1]).toContain('YOUR PREVIOUS DRAFT FAILED THE GATE')
    expect(w.forks[1]).toContain('MISSING src/a.ts:12')
    expect(res.messages?.[0]?.text).toContain('GATE: OK')
  })

  test('a handoff still failing citations after the retry is kept, with its verdict', async ($, on) => {
    // Arrange
    const w = world(on, { gate: [1] })

    // Act
    const res = await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.forks.length).toBe(2)
    expect(w.core).toBe(0)
    expect(res.messages?.[0]?.text).toContain('GATE: FAILED')
    expect(res.messages?.[0]?.text).toContain('MISSING src/a.ts:12')
  })

  test('a handoff malformed twice falls back to core, and never overwrites the stored one', async ($, on) => {
    // Arrange
    const w = world(on, { gate: [2], existing: { mtime: 2_000, doc: 'the older good one' } })

    // Act
    const res = await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.core).toBe(1)
    expect(res.messages?.[0]?.text).toBe('core summary')
    expect(w.files.get(HANDOFF)).toBe('the older good one')
  })

  test('the envelope is forced to the oriented branch and checkout', async ($, on) => {
    // Arrange
    const w = world(on, { forkText: DOC.replace(`checkout: ${CHECKOUT}`, 'checkout: /somewhere/else') })

    // Act
    await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.files.get(HANDOFF)).toContain(`checkout: ${CHECKOUT}`)
    expect(w.files.get(HANDOFF)).not.toContain('/somewhere/else')
  })

  test('outside a git checkout, core compacts as before', async ($, on) => {
    // Arrange
    const w = world(on, { isCheckout: false })

    // Act
    const res = await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.forks.length).toBe(0)
    expect(res.messages?.[0]?.text).toBe('core summary')
  })

  test('outside a git checkout, the toast says so', async ($, on) => {
    // Arrange
    const w = world(on, { isCheckout: false })

    // Act
    await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.toasts).toEqual(['No handoff (not inside a git checkout); compacting the usual way.'])
  })

  test('a bash that cannot run the scripts is reported as such, not as a missing checkout', async ($, on) => {
    // Arrange
    const w = world(on, { orientFailure: { exitCode: 1, stderr: 'WSL ERROR: execvpe(/bin/bash) failed: No such file or directory\r\n' } })

    // Act
    const res = await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(res.messages?.[0]?.text).toBe('core summary')
    expect(w.toasts[0]).toContain('exit 1: WSL ERROR: execvpe(/bin/bash) failed')
    expect(w.toasts[0]).not.toContain('not inside a git checkout')
  })

  test("with Git for Windows on PATH, its own bash runs the scripts, never PATH's bash", async ($, on) => {
    // Arrange
    const w = world(on, { gitExecPath: 'C:\\Program Files\\Git\\mingw64\\libexec\\git-core' })

    // Act
    await $.session.compact({ trigger: 'auto', messages: TRANSCRIPT })

    // Assert
    expect(w.shells.length).toBe(2)
    expect(w.shells.every(sh => sh === 'C:/Program Files/Git/bin/bash.exe')).toBe(true)
  })

  test('a subagent compaction is left to core', async ($, on) => {
    // Arrange
    const w = world(on)

    // Act
    await $.session.compact({ trigger: 'auto', agentId: 'agent-1', messages: TRANSCRIPT })

    // Assert
    expect(w.forks.length).toBe(0)
    expect(w.core).toBe(1)
  })

  test('a precompute is vetoed rather than paid for', async ($, on) => {
    // Arrange
    const w = world(on)

    // Act
    const res = await $.session.compact({ trigger: 'precompute', messages: TRANSCRIPT })

    // Assert
    expect(res.skip).toBeDefined()
    expect(w.core).toBe(0)
    expect(w.forks.length).toBe(0)
  })
})

const KEY_VAR = 'CONTEXT_ECONOMY_PROCESS_KEY'
const START = { cwd: CHECKOUT, surface: 'terminal', isInteractive: true } as never
const CLEAR = { reason: 'clear', sessionId: 'old-session', resume: { id: 'old-session' } } as const
const DAY_MS = 24 * 60 * 60 * 1000
const submit = (text: string) => ({ text, wait: false, origin: { kind: 'composer' } }) as never

// session.start mints the process key, so every /clear test starts the session first, as a live
// process does before its first prompt.
describe('/clear', () => {
  test('the first prompt after a /clear carries the handoff the cleared session wrote, once', async ($, on) => {
    // Arrange
    const w = world(on, { existing: { mtime: 2_000, doc: DOC } })
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
    on('prompt.submit', (_$, e) => ({ text: e.text, context: e.context }))

    // Act
    await $.session.start(START)
    await $.session.end(CLEAR)
    const first = await $.prompt.submit(submit('go on'))
    const second = await $.prompt.submit(submit('and?'))

    // Assert
    expect(first.context?.join('\n')).toContain('Chose A over B.')
    expect(first.context?.join('\n')).toContain('old-session')
    expect(w.files.get(HANDOFF)).toContain('progress: consumed')
    expect(second.context ?? []).toEqual([])
    expect(w.logs.some(l => l.includes('delivered the handoff'))).toBe(true)
  })

  test('a handoff older than the cleared session is not presented as covering it', async ($, on) => {
    // Arrange
    world(on, { existing: { mtime: 500, doc: DOC } })
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('session.end', (_$, e) => ({ sessionId: e.sessionId }))
    on('prompt.submit', (_$, e) => ({ text: e.text, context: e.context }))

    // Act
    await $.session.start(START)
    await $.session.end(CLEAR)
    const first = await $.prompt.submit(submit('go on'))

    // Assert
    const context = first.context?.join('\n') ?? ''
    expect(context).toContain('without writing a handoff')
    expect(context).toContain('claude --resume old-session')
    expect(context).toContain('written before that session began')
    expect(context).not.toContain('Chose A over B.')
  })

  test('the marker is kept in the store under the process key, where a new session finds it', async ($, on) => {
    // Arrange
    const w = world(on)
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('session.end', (_$, e) => ({ sessionId: e.sessionId }))

    // Act
    await $.session.start(START)
    await $.session.end(CLEAR)

    // Assert
    const key = w.env.get(KEY_VAR)
    expect(key).toBeDefined()
    expect(w.store.get(`lastClear:${key}`)).toMatchObject({ sessionId: 'old-session', cwd: CHECKOUT })
  })

  test("another process's marker is never delivered here", async ($, on) => {
    // Arrange
    const theirs = { sessionId: 'theirs', cwd: CHECKOUT, startedAt: 0, clearedAt: Date.now() }
    const w = world(on, { existing: { mtime: 2_000, doc: DOC }, store: { 'lastClear:other-process': theirs } })
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('prompt.submit', (_$, e) => ({ text: e.text, context: e.context }))

    // Act
    await $.session.start(START)
    const res = await $.prompt.submit(submit('hello'))

    // Assert
    expect(res.context ?? []).toEqual([])
    expect(w.store.has('lastClear:other-process')).toBe(true)
  })

  test('a process mints its own key rather than keep the one its parent passed down', async ($, on) => {
    // Arrange
    const w = world(on, { env: { [KEY_VAR]: 'parent-key' } })
    on('session.start', (_$, e) => ({ cwd: e.cwd }))

    // Act
    await $.session.start(START)

    // Assert
    expect(w.env.get(KEY_VAR)).toBeDefined()
    expect(w.env.get(KEY_VAR)).not.toBe('parent-key')
  })

  test('a reload keeps the key the process already has', async ($, on) => {
    // Arrange
    const w = world(on)
    on('session.start', (_$, e) => ({ cwd: e.cwd }))

    // Act
    await $.session.start(START)
    const minted = w.env.get(KEY_VAR)
    await $.session.start(START)

    // Assert
    expect(w.env.get(KEY_VAR)).toBe(minted)
  })

  test("an exit drops this process's marker, and a day-old marker of any process is pruned", async ($, on) => {
    // Arrange
    const dead = { sessionId: 'gone', cwd: CHECKOUT, startedAt: 0, clearedAt: Date.now() - 2 * DAY_MS }
    const w = world(on, { store: { 'lastClear:dead-process': dead } })
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('session.end', (_$, e) => ({ sessionId: e.sessionId }))

    // Act
    await $.session.start(START)
    await $.session.end(CLEAR)
    await $.session.end({ reason: 'other', sessionId: 'new-session', resume: { id: 'new-session' } } as never)

    // Assert
    expect([...w.store.keys()]).toEqual([])
  })

  test('without a /clear, prompts pass through untouched, and the debug log says so', async ($, on) => {
    // Arrange
    const w = world(on)
    on('session.start', (_$, e) => ({ cwd: e.cwd }))
    on('prompt.submit', (_$, e) => ({ text: e.text, context: e.context }))

    // Act
    await $.session.start(START)
    const res = await $.prompt.submit(submit('hello'))

    // Assert
    expect(res.context ?? []).toEqual([])
    expect(w.logs.some(l => l.includes('no /clear marker for process'))).toBe(true)
  })
})
