import type { EngineInterface, Register } from 'claude-code'
import type { ContextEconomyLastClear } from '../types'
import {
  afterClearContext,
  compactedMessage,
  forkPrompt,
  noHandoffContext,
  normalizeEnvelope,
  retryPrompt,
  setProgress,
  type GateResult,
  type Orientation,
} from './handoff-text'

// context-economy v2: handoffs as function hooks. docs/design.md, "v2 — function hooks", D29-D33.
//
//   session.compact  every compaction of the main conversation becomes a handoff: a fork of the
//                    live session writes it, the gate checks it, the store keeps it, and it stands
//                    in place of core's summary (D29, D30). Autocompact's threshold is the trigger;
//                    this plugin has none of its own (D31).
//   session.end      a /clear records which session ended, in $.state (D32).
//   prompt.submit    the first prompt after that /clear carries the handoff that session wrote,
//                    or says it wrote none (D32). Not prompt.context: that event never fires on
//                    the builds measured (docs/measured.md finding #40).

const LAST_CLEAR = { plugin: 'context-economy', key: 'lastClear' } as const

type Written = { doc: string; path: string; gate: GateResult | undefined }

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

// Fork, gate, and at most one corrected retry. Drafts go to `<path>.draft` and only a document
// that passed the contract (exit 0 or 1) replaces the stored handoff, so a malformed draft never
// overwrites a good one. The draft file is not `*.md`, so the store's enumeration never lists it.
async function writeHandoff($: EngineInterface, instructions: string | undefined): Promise<Written | string> {
  const o = await orient($, await $.session.cwd())
  if (typeof o === 'string') return o
  const draftPath = `${o.handoff}.draft`

  let prompt = forkPrompt(o, instructions)
  let last: { doc: string; gate: GateResult | undefined } | undefined
  for (let attempt = 0; attempt < 2; attempt++) {
    const reply = await $.model.fork({ prompt })
    if (!reply.isAnswered) return `the fork returned no text (${reply.reason})`
    const doc = normalizeEnvelope(reply.text, o)
    await $.fs.write(draftPath, doc)
    const gate = await runGate($, o, draftPath, o.checkout)
    last = { doc, gate }
    if (!gate || gate.exitCode === 0) break
    prompt = retryPrompt(o, instructions, doc, gate)
  }
  if (!last) return 'no draft was written'
  if (last.gate?.exitCode === 2) return 'the handoff broke the format contract twice'

  await $.fs.write(o.handoff, last.doc)
  return { doc: last.doc, path: o.handoff, gate: last.gate }
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
    $.ui.toast(`Handoff written: ${written.path}`)
    return {
      messages: [{ role: 'user', text: compactedMessage(written.doc, written.gate, written.path), toolUses: [] }],
    }
  })

  on('session.end', async ($, e, next) => {
    if (e.reason === 'clear') {
      const lastClear: ContextEconomyLastClear = {
        sessionId: e.sessionId,
        cwd: await $.session.cwd(),
        startedAt: (await $.session.usage()).startedAt,
      }
      await $.state.set(LAST_CLEAR, lastClear)
    }
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    const { value: lastClear } = await $.state.get(LAST_CLEAR)
    if (!lastClear) return next(e)
    await $.state.set(LAST_CLEAR, null)

    const oriented = await orient($, lastClear.cwd)
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
    return next({ ...e, context: [...(e.context ?? []), context] })
  })
}
