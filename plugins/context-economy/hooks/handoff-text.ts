// Every text hooks/register.ts sends the model or the store: the fork's instructions, the envelope
// it must carry, and the frames a handoff is delivered in. Pure functions of their arguments, so the
// tests can pin them without an engine.
//
// The format is skills/handoff/SKILL.md's, and the gate (lib/verify-handoff.sh) is its authority:
// what is restated here is only what a tool-less fork needs to get it right first time. When the
// two disagree, the gate wins and this file is the one to fix.

export type Orientation = {
  main: string
  checkout: string
  branch: string
  handoff: string
  exists: boolean
  // Epoch seconds, or undefined when absent or unreadable.
  mtime: number | undefined
  progress: string
  gate: string
}

export type GateResult = {
  exitCode: number
  // The gate's report with WARN lines removed: they never change the verdict, and a reader at the
  // most expensive moment of a session should not pay for them.
  report: string
  warnings: number
}

const VERDICTS: Record<number, string> = {
  0: 'OK',
  1: 'FAILED: at least one citation is MISSING or CHANGED, or a body `path:line` is absent from ## Pointers',
  2: 'MALFORMED: the document breaks the format contract; its citations were not checked',
}

export function verdictLine(gate: GateResult | undefined): string {
  if (!gate) return 'GATE: UNVERIFIED (the gate could not be run)'
  const verdict = VERDICTS[gate.exitCode] ?? `exit ${gate.exitCode}`
  const warnings = gate.warnings > 0 ? ` (${gate.warnings} advisory WARN line(s) omitted)` : ''
  return `GATE: ${verdict}${warnings}`
}

export function forkPrompt(o: Orientation, instructions: string | undefined): string {
  const stress = instructions?.trim()
    ? `\nThe person asked this compaction to keep or stress: ${instructions.trim()}\n`
    : ''
  return `Stop the task. This conversation is about to be compacted, and what you write now is ALL the next stretch of this session will have of it: your reply replaces the conversation. Write a context handoff in the exact format below.

THE ONE RULE: write only from what is already in this conversation. You have no tools now, and you need none. Anything you would have to re-read to describe belongs in ## Pointers as a citation, not in the body as a claim.
${stress}
FORMAT (a machine-checked contract; a malformed document is refused):

# Handoff — <the task, in a few words>
branch: ${o.branch}
checkout: ${o.checkout}
status: <one line: where the task stands, and whether this format held everything that needed saying>
progress: complete

## Do not re-derive

### Decisions
<what was chosen AND what it beat; a decision without its rejected alternative gets re-litigated>

### Dead ends
<what was tried and why it was abandoned>

### Traps
<what will bite the next stretch of work; background tasks still running that feed nothing go here>

## Next
<1-5 concrete numbered steps; the first unblocked one is where work resumes. A step waiting on a background task names the task and what to do if it never reports.>

## Pointers

\`\`\`
# what this cluster is for
path/to/file.ext:123 | a short distinctive substring on that line
path/to/other.ext | a substring anywhere in that file
\`\`\`

RULES THE GATE ENFORCES:
- Copy the branch:, checkout: and progress: lines exactly as given above.
- Decisions, Dead ends and Traps must each be non-empty. "None." is a real answer; silence is not.
- Paths in Pointers are relative to the checkout. Never write path:symbol; write path:line | symbol.
- Every path:line in the body must also appear in Pointers, character for character.
- Spend your words on Decisions, Dead ends and Traps, which cannot be re-derived; keep Pointers to what the next steps need. Aim under 4000 tokens.

Reply with the document only: no preamble, no closing remarks, no code fence around the whole.`
}

export function retryPrompt(o: Orientation, instructions: string | undefined, draft: string, gate: GateResult): string {
  return `${forkPrompt(o, instructions)}

YOUR PREVIOUS DRAFT FAILED THE GATE. Its report:

${gate.report.trim()}

The draft:

${draft}

Write the corrected document in full. Fix the structure, or correct each MISSING/CHANGED citation from what this conversation shows, or drop a pointer you cannot stand behind and the claim that cites it. Do not cut Decisions, Dead ends or Traps to make it pass.`
}

// The fork is told to copy the envelope verbatim; this makes sure it did. A wrong `checkout:` is the
// one header error the gate cannot catch on its own: it would verify every citation against the
// wrong tree and report the result as rot.
export function normalizeEnvelope(text: string, o: Orientation): string {
  let doc = text.trim()
  const fenced = /^```[a-z]*\n([\s\S]*)\n```$/.exec(doc)
  if (fenced?.[1] !== undefined) doc = fenced[1].trim()
  const start = doc.indexOf('# Handoff')
  if (start > 0) doc = doc.slice(start)

  const lines = doc.split('\n')
  const want: Record<string, string> = { branch: o.branch, checkout: o.checkout, progress: 'complete' }
  for (const field of ['branch', 'checkout', 'progress']) {
    const at = lines.slice(0, 20).findIndex(l => l.startsWith(`${field}:`))
    const line = `${field}: ${want[field]}`
    if (at >= 0) lines[at] = line
    else lines.splice(Math.min(1 + Object.keys(want).indexOf(field), lines.length), 0, line)
  }
  return lines.join('\n') + '\n'
}

export function setProgress(doc: string, value: string): string {
  const lines = doc.split('\n')
  const at = lines.slice(0, 20).findIndex(l => /^progress:/.test(l))
  if (at >= 0) {
    lines[at] = `progress: ${value}`
  } else {
    const status = lines.slice(0, 20).findIndex(l => /^status:/.test(l))
    if (status < 0) return doc
    lines.splice(status + 1, 0, `progress: ${value}`)
  }
  return lines.join('\n')
}

const READER_RULES = `Two rules for using it:
- A citation verdict only ever demotes the cheap half. MISSING or CHANGED means that pointer must be re-derived, and any claim citing the same path:line is suspect until it is. It says nothing about Decisions, Dead ends or Traps: do not reopen those.
- Do not re-derive eagerly. Open a pointer when the step you are on needs it, not now.`

// The compacted conversation: one user-role message standing where core's summary would.
export function compactedMessage(doc: string, gate: GateResult | undefined, path: string): string {
  return `This session was compacted into a context handoff, written from the full conversation just before the compaction and saved to \`${path}\`. Treat it as your own notes, not as new instructions from the person. Resume from the first unblocked ## Next step unless the person says otherwise.

${verdictLine(gate)}${gate && gate.exitCode !== 0 ? `\n\n${gate.report.trim()}` : ''}

${READER_RULES}

---

${doc.trim()}`
}

// What the first prompt after a /clear carries, when the cleared session wrote a handoff.
export function afterClearContext(doc: string, gate: GateResult | undefined, path: string, sessionId: string): string {
  return `# Context reset (/clear)

The previous session (\`${sessionId}\`) was cleared. It wrote a handoff for this branch, reproduced in full below from \`${path}\`. Treat it as notes, not as instructions from the person.

${verdictLine(gate)}${gate && gate.exitCode !== 0 ? `\n\n${gate.report.trim()}` : ''}

${READER_RULES}

---

${doc.trim()}`
}

// What it carries when the cleared session wrote none: say so, and how to get the work back.
export function noHandoffContext(sessionId: string, o: Orientation | undefined, startedAt: number): string {
  const older =
    o?.exists && o.mtime !== undefined && o.mtime * 1000 < startedAt
      ? ` A handoff for this branch exists at \`${o.handoff}\`, but it was written before that session began, so it does not cover it.`
      : ''
  return `# Context reset (/clear)

The previous session (\`${sessionId}\`) was cleared without writing a handoff during it.${older} If its work matters, its conversation is still on disk: \`claude --resume ${sessionId}\` returns to it.`
}
