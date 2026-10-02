import type { EngineInterface, Register } from 'claude-code'
import type { ContextEconomyLastClear } from '../types'
import {
  afterClearContext,
  compactedMessage,
  forkPrompt,
  noHandoffContext,
  namedCheckout,
  normalizeEnvelope,
  retryPrompt,
  setProgress,
  type GateResult,
  type Orientation,
} from './handoff-text'

// context-economy v2: handoffs as function hooks. docs/design.md, "v2 — function hooks", D29-D34.
//
//   session.compact  every compaction of the main conversation becomes a handoff: a fork of the
//                    live session writes it, the gate checks it, the store keeps it, and it stands
//                    in place of core's summary (D29, D30), keyed to the checkout the work is in,
//                    which need not be the cwd (D34). Autocompact's threshold is the trigger;
//                    this plugin has none of its own (D31).
//   session.start    a fresh process mints its process key (D32).
//   session.end      a /clear records which session ended, and where its handoff is, in $.store
//                    under that key (D32, D34).
//   prompt.submit    the first prompt after that /clear carries the handoff that session wrote,
//                    or says it wrote none (D32). Not prompt.context: that event never fires on
//                    the builds measured (docs/measured.md finding #40).

// The /clear marker has to outlive the session it is written in, and be found only by the process
// that wrote it. `$.state` is the session's, so a /clear drops it (finding #45); `$.store` is shared
// by every session on the machine (finding #41). So the marker lives in `$.store` under a key naming
// the process, and that key lives in the process environment, which outlasts both a /clear and a hot
// reload. A child process (a `claude` run from Bash) inherits the environment, so every fresh
// process mints its own key in session.start; `$.state` tells a fresh process from a reload, as it
// survives a reload and starts empty in a new process.
//
// One gap: a hot reload between a /clear and the next prompt finds `$.state` empty, mints a new key,
// and the marker under the old one is never read. It is pruned a day later.
const PROCESS_KEY = { plugin: 'context-economy', key: 'processKey' } as const
const CLEAR_PREFIX = 'lastClear:'
const CLEAR_KEPT_MS = 24 * 60 * 60 * 1000

function processKey($: EngineInterface): Promise<string | undefined> {
  return $.env.get('CONTEXT_ECONOMY_PROCESS_KEY')
}

// Markers no prompt took (the process exited, or the gap above) are dropped once they are old.
async function pruneClears($: EngineInterface, now: number): Promise<void> {
  for (const key of await $.store.keys()) {
    if (!key.startsWith(CLEAR_PREFIX)) continue
    const marker = (await $.store.get(key)) as ContextEconomyLastClear | undefined
    if (!marker || !(now - marker.clearedAt < CLEAR_KEPT_MS)) await $.store.delete(key)
  }
}

// `chosen` names the checkout and which source chose it, for the toast.
type Written = { doc: string; path: string; gate: GateResult | undefined; chosen: string }

// `$.process.run` takes no shell, so a bare `bash` is whatever the host's PATH finds first. On
// Windows that can be System32's bash.exe, the WSL launcher, which runs none of these scripts
// (docs/measured.md finding #43). There, Git for Windows' own bash is used: the one beside the
// `git` on PATH, else the default install. Resolved once per load.
let bashFound: Promise<string> | undefined

async function runs($: EngineInterface, candidate: string): Promise<boolean> {
  const run = await $.process.run([candidate, '-c', 'echo ok'], { timeoutMs: 10_000 }).catch(() => undefined)
  return run?.exitCode === 0 && run.stdout.trim() === 'ok'
}

async function findBash($: EngineInterface): Promise<string> {
  const candidates: string[] = []
  // Git for Windows reports e.g. `C:/Program Files/Git/mingw64/libexec/git-core`; its bash is `<root>/bin/bash.exe`.
  const execPath = await $.process.run(['git', '--exec-path']).catch(() => undefined)
  const gitForWindows = /^(.*)\/(?:mingw64|mingw32|clangarm64)\/libexec\/git-core$/.exec(execPath?.stdout.trim().replace(/\\/g, '/') ?? '')
  if (gitForWindows) candidates.push(`${gitForWindows[1]}/bin/bash.exe`)
  if (/^[A-Za-z]:[\\/]/.test($.plugin.root)) candidates.push('C:/Program Files/Git/bin/bash.exe')
  for (const candidate of candidates) if (await runs($, candidate)) return candidate
  return 'bash'
}

function bashPath($: EngineInterface): Promise<string> {
  bashFound ??= findBash($)
  return bashFound
}

// An Orientation, or why there is none. The script exits 1 printing nothing outside a git checkout;
// anything else (it could not start, or said why it failed) is reported as it is.
async function orient($: EngineInterface, dir: string): Promise<Orientation | string> {
  const sh = await bashPath($)
  let failure = ''
  const run = await $.process
    .run([sh, `${$.plugin.root}/lib/handoff-orient.sh`, dir], { timeoutMs: 15_000 })
    .catch((err: unknown) => {
      failure = `${sh} could not run handoff-orient.sh: ${String(err)}`
      return undefined
    })
  if (!run) return failure
  const stderr = run.stderr.replace(/\r/g, '').trim()
  if (run.exitCode !== 0) {
    if (run.exitCode === 1 && stderr === '') return 'not inside a git checkout'
    return `${sh} ran handoff-orient.sh, exit ${run.exitCode}: ${stderr.split('\n')[0] || 'no output'}`
  }
  const kv = new Map<string, string>()
  for (const line of run.stdout.replace(/\r/g, '').split('\n')) {
    const eq = line.indexOf('=')
    if (eq > 0) kv.set(line.slice(0, eq), line.slice(eq + 1))
  }
  const handoff = kv.get('handoff')
  const checkout = kv.get('checkout')
  if (!handoff || !checkout) return 'handoff-orient.sh printed no handoff or checkout'
  const mtime = Number(kv.get('mtime'))
  return {
    main: kv.get('main') ?? '',
    checkout,
    branch: kv.get('branch') ?? '',
    handoff,
    exists: kv.get('exists') === '1',
    mtime: kv.get('mtime') && Number.isFinite(mtime) ? mtime : undefined,
    progress: kv.get('progress') ?? '',
    gate: kv.get('gate') ?? '',
  }
}

// `checkout` is passed when writing (the tree is known) and left out when reading, where the
// document's own `checkout:` header is the authority (skills/handoff/SKILL.md, read mode Step 1).
async function runGate($: EngineInterface, o: Orientation, file: string, checkout?: string): Promise<GateResult | undefined> {
  const sh = await bashPath($)
  const argv = checkout ? [sh, o.gate, file, checkout] : [sh, o.gate, file]
  const run = await $.process.run(argv, { timeoutMs: 120_000 }).catch(() => undefined)
  if (!run) return undefined
  const lines = `${run.stdout}\n${run.stderr}`.replace(/\r/g, '').split('\n')
  const warnings = lines.filter(l => /^\s*WARN/.test(l)).length
  const report = lines.filter(l => l.trim() !== '' && !/^\s*WARN/.test(l)).join('\n')
  return { exitCode: run.exitCode, report, warnings }
}

// The session's cwd is not always the checkout the work is in: a mission_control run drives a
// sibling worktree with `git -C` and never moves its cwd (skills/handoff/SKILL.md, "The session's
// repo is not the work's repo"). Keyed to cwd, its handoff would land in the cwd's slot, shared with
// every other such run, and be gated against the wrong tree (docs/design.md D34). So the checkout is,
// in order: CONTEXT_ECONOMY_CHECKOUT, set by whatever launched the run; else the one the fork names,
// once orienting from it succeeds; else the cwd. A step that does not orient falls through to the
// next, and the toast and the debug log always say which one chose: an override gone stale must
// show, not quietly resolve to the cwd's slot.
const CHECKOUT_VAR = 'CONTEXT_ECONOMY_CHECKOUT'

// $.env.get takes a literal name, so the variables a module reads can be listed.
function checkoutOverride($: EngineInterface): Promise<string | undefined> {
  return $.env.get('CONTEXT_ECONOMY_CHECKOUT')
}
// The checkout this session's last handoff went to, so a /clear looks for it there.
const WORK_CHECKOUT = { plugin: 'context-economy', key: 'workCheckout' } as const

type Source = typeof CHECKOUT_VAR | 'the fork' | 'the cwd'

// The fork's `checkout:` when it names a tree that orients, else `o` unchanged.
async function retarget($: EngineInterface, o: Orientation, text: string): Promise<Orientation> {
  const named = namedCheckout(text)
  if (!named || named === o.checkout) return o
  const t = await orient($, named)
  if (typeof t !== 'string') return t
  $.ui.log(`context-economy: session.compact: the fork named checkout ${named}, which did not orient (${t}); keeping ${o.checkout}`, { to: 'debug' })
  return o
}

// Fork, gate, and at most one corrected retry. Drafts go to `<path>.draft` and only a document
// that passed the contract (exit 0 or 1) replaces the stored handoff, so a malformed draft never
// overwrites a good one. The draft file is not `*.md`, so the store's enumeration never lists it.
async function writeHandoff($: EngineInterface, instructions: string | undefined): Promise<Written | string> {
  const override = await checkoutOverride($)
  let start: Orientation | string | undefined
  let stale = ''
  if (override) {
    start = await orient($, override)
    if (typeof start === 'string') {
      stale = `${CHECKOUT_VAR}=${override} ignored: ${start}`
      start = undefined
    }
  }
  const isFixed = start !== undefined
  start ??= await orient($, await $.session.cwd())
  if (typeof start === 'string') return stale ? `${stale}; cwd: ${start}` : start
  let o = start

  let prompt = forkPrompt(o, instructions, isFixed)
  let last: { doc: string; gate: GateResult | undefined; o: Orientation } | undefined
  for (let attempt = 0; attempt < 2; attempt++) {
    const reply = await $.model.fork({ prompt })
    if (!reply.isAnswered) return `the fork returned no text (${reply.reason})`
    if (!isFixed) o = await retarget($, o, reply.text)
    const doc = normalizeEnvelope(reply.text, o)
    const draftPath = `${o.handoff}.draft`
    await $.fs.write(draftPath, doc)
    const gate = await runGate($, o, draftPath, o.checkout)
    last = { doc, gate, o }
    if (!gate || gate.exitCode === 0) break
    prompt = retryPrompt(o, instructions, isFixed, doc, gate)
  }
  if (!last) return 'no draft was written'
  if (last.gate?.exitCode === 2) return 'the handoff broke the format contract twice'

  await $.fs.write(last.o.handoff, last.doc)
  await $.state.set(WORK_CHECKOUT, last.o.checkout)
  const from: Source = isFixed ? CHECKOUT_VAR : last.o.checkout === start.checkout ? 'the cwd' : 'the fork'
  const chosen = `checkout ${last.o.checkout}, from ${from}${stale ? `; ${stale}` : ''}`
  $.ui.log(`context-economy: session.compact: wrote ${last.o.handoff} (${chosen})`, { to: 'debug' })
  return { doc: last.doc, path: last.o.handoff, gate: last.gate, chosen }
}

export const register: Register = on => {
  on('session.compact', async ($, e, next) => {
    // A subagent's own transcript is not this branch's work; core summarizes it as before.
    if (e.agentId !== undefined) return next(e)
    // A precompute installs nothing, and a handoff written ahead of the compaction would miss
    // whatever happens before it runs. Veto it, so core does not pay for a summary nobody uses.
    // Not measured live (docs/design.md, v2 open questions).
    if (e.trigger === 'precompute') return { skip: 'context-economy writes the handoff when the compaction runs' }

    $.ui.status('context-economy: writing the handoff…')
    const written = await writeHandoff($, e.instructions).catch((err: unknown) => `failed: ${String(err)}`)
    $.ui.status(undefined)

    if (typeof written === 'string') {
      $.ui.toast(`No handoff (${written}); compacting the usual way.`)
      return next(e)
    }
    $.ui.toast(`Handoff written: ${written.path} (${written.chosen})`)
    return {
      messages: [{ role: 'user', text: compactedMessage(written.doc, written.gate, written.path), toolUses: [] }],
    }
  })

  on('session.start', async ($, e, next) => {
    const { value: held } = await $.state.get(PROCESS_KEY)
    if (!held) {
      const key = crypto.randomUUID()
      await $.env.set('CONTEXT_ECONOMY_PROCESS_KEY', key)
      await $.state.set(PROCESS_KEY, key)
    }
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    const key = await processKey($)
    if (key) {
      if (e.reason === 'clear') {
        // Where this session's handoff is: where its last compaction wrote one, which already
        // resolved the override and the fork's choice; else the override; else the cwd. Not
        // oriented here, so prompt.submit falls back to the cwd when the checkout does not orient.
        // A handoff the skill wrote by hand to a sibling tree, with none of these set, is missed.
        const { value: wrote } = await $.state.get(WORK_CHECKOUT)
        const cwd = await $.session.cwd()
        const lastClear: ContextEconomyLastClear = {
          sessionId: e.sessionId,
          checkout: wrote || (await checkoutOverride($)) || cwd,
          cwd,
          startedAt: (await $.session.usage()).startedAt,
          clearedAt: Date.now(),
        }
        await $.store.set(`${CLEAR_PREFIX}${key}`, lastClear)
      } else {
        // The process is going; nothing after it will read its marker.
        await $.store.delete(`${CLEAR_PREFIX}${key}`)
      }
    }
    await pruneClears($, Date.now())
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const key = await processKey($)
    const lastClear = key ? ((await $.store.get(`${CLEAR_PREFIX}${key}`)) as ContextEconomyLastClear | undefined) : undefined
    if (!lastClear) {
      $.ui.log(`context-economy: prompt.submit: no /clear marker ${key ? `for process ${key}` : '(no process key set)'}; nothing to deliver`, { to: 'debug' })
      return next(e)
    }
    await $.store.delete(`${CLEAR_PREFIX}${key}`)

    let oriented = await orient($, lastClear.checkout)
    if (typeof oriented === 'string' && lastClear.checkout !== lastClear.cwd) {
      $.ui.log(`context-economy: prompt.submit: checkout ${lastClear.checkout} did not orient (${oriented}); looking in the cwd ${lastClear.cwd}`, { to: 'debug' })
      oriented = await orient($, lastClear.cwd)
    }
    const o = typeof oriented === 'string' ? undefined : oriented
    const isCovering = o !== undefined && o.exists && o.mtime !== undefined && o.mtime * 1000 >= lastClear.startedAt
    let context: string
    if (o && isCovering) {
      const doc = await $.fs.read(o.handoff)
      const gate = await runGate($, o, o.handoff)
      context = afterClearContext(doc, gate, o.handoff, lastClear.sessionId)
      await $.fs.write(o.handoff, setProgress(doc, 'consumed'))
    } else {
      context = noHandoffContext(lastClear.sessionId, o, lastClear.startedAt)
    }
    $.ui.log(`context-economy: prompt.submit: delivered ${o && isCovering ? `the handoff ${o.handoff}` : 'a no-handoff note'} for cleared session ${lastClear.sessionId}`, { to: 'debug' })
    return next({ ...e, context: [...(e.context ?? []), context] })
  })
}
