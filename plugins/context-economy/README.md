# Context economy

Handoffs that survive a context reset. When a session compacts, or you `/clear` it, the next
conversation starts from a **handoff**: a short document holding the decisions, dead ends and
traps that would otherwise be lost and re-derived at full price, plus pointers to the evidence
that can be re-read on demand.

The plugin bundles:

- a hooks module ([`hooks/register.ts`](hooks/register.ts)) built on Claude Code's function hooks
  ("mods"), which writes and delivers handoffs automatically;
- the [`/handoff`](skills/handoff/SKILL.md) skill, which writes and reads them by hand;
- a sourceable statusline gauge ([`lib/context-gauge.sh`](lib/context-gauge.sh)) that says when a
  manual reset is worth it.

**Requires** a Claude Code build with function hooks: 2.1.287 or later. The hooks API is early
access. v1's command-hook implementation is gone; see [`CHANGELOG.md`](CHANGELOG.md) for what
changed in 2.0.0.

## Install

```
/plugin marketplace add script-development/claude
/plugin install context-economy@script-development-plugins
```

## How it works

### Compaction becomes a handoff

Every compaction of the main conversation, automatic or `/compact`, is answered by the plugin's
`session.compact` hook:

1. It forks the live session (mostly served from the prompt cache) and asks the fork for a
   handoff, written only from what is already in context.
2. It runs the format gate ([`lib/verify-handoff.sh`](lib/verify-handoff.sh)) on the draft. A draft
   that fails gets one corrected retry.
3. It saves the gated document to the store and returns it as the compacted conversation,
   **in place of** Claude Code's own summary.

The session carries on from the handoff. Nothing runs in the background and there is nothing to
wait for. A toast names the file and the checkout it was written for.

If no handoff can be written (not in a git checkout, the fork returned nothing, or the draft broke
the format twice), the toast says why and the compaction falls back to Claude Code's own summary.
Subagent compactions are left to core.

**The plugin has no threshold of its own.** Choose when handoffs happen by setting the auto-compact
threshold, with `claude --autocompact <auto|100k–1M>` or `/autocompact` in a session.

### `/clear` hands over

When you `/clear`, the plugin remembers which session ended and where its handoff is. The first
prompt of the next conversation then carries that handoff, gate verdict included, and marks it
`progress: consumed` so it is never presented as news twice.

If the cleared session wrote no handoff newer than its own start, the prompt says so instead and
gives the `claude --resume <id>` line to get the cleared conversation back.

### Writing one by hand

`/handoff` writes a handoff from the current context and ends by telling you to `/clear`; the next
prompt picks it up as above. Use it instead of `/compact` when you want to reset proactively.

`/handoff --read [file]` verifies a handoff's citations, then reads it. You rarely need it after a
`/clear`, but it is how you pick up a handoff from another checkout or another session.

An orchestrator can ask a subagent or background run to `/handoff`. The run cannot reset itself, so
it answers "Ready for reset", and the orchestrator kills and relaunches it against the handoff.

## The handoff

```
# Handoff — <task>
branch: / checkout: / status: / progress:
## Do not re-derive
### Decisions        what was chosen, and what it beat
### Dead ends        what was tried, and why it was abandoned
### Traps            what will bite the next session
## Next              1–5 concrete steps
## Pointers          fenced block: path:line | expected substring
## Unverifiable      optional: real files the gate cannot resolve
```

The document is deliberately lopsided. Decisions, dead ends and traps cannot be recovered from the
tree, so they get the words. Anything with a `path:line` can be, so it is reduced to a pointer, and
the gate checks every pointer still holds its expected substring (MISSING / CHANGED). A failed
citation only demotes that pointer; it never reopens a decision.

`progress:` is `complete` when written and `consumed` once shown to a reader. The full contract,
including the gate's exit codes, is in [`skills/handoff/SKILL.md`](skills/handoff/SKILL.md).

### Where handoffs live

```
${XDG_DATA_HOME:-~/.local/share}/context-economy/handoffs/<repo>-<branch>-<hash8>.md
```

A machine-local store outside every checkout, one file per repository and branch. Handoffs are
never committed: they hold candid notes about a project's tooling, and they have to survive the
throwaway worktree they were written in.

The handoff is keyed to **the checkout the work is in**, which need not be the session's cwd (a
run that drives a sibling worktree with `git -C`, for example). The checkout is, in order:

1. `CONTEXT_ECONOMY_CHECKOUT`, if whatever launched the run set it and it is a git checkout;
2. the checkout the fork names in its handoff, if it is one;
3. the session's cwd.

The toast and the debug log say which one chose. `/handoff` honours the same variable, so a run's
manual and automatic handoffs share one slot.

## Statusline gauge

[`lib/context-gauge.sh`](lib/context-gauge.sh) renders resident context size and escalates to a
reset advisory at two thresholds, `CTX_NOTICE_TOKENS` (200k) and `CTX_URGE_TOKENS` (300k), defined
once in [`lib/context-economy/context-thresholds.sh`](lib/context-economy/context-thresholds.sh).
Source it from your own statusline rather than copying the numbers:

```bash
. /path/to/context-gauge.sh
gauge=$(context_gauge "$resident_tokens")
```

The thresholds are advisory only. They never trigger anything; compaction does.

## Known gaps

- A handoff `/handoff` wrote by hand to a sibling checkout is looked for in the cwd after a
  `/clear`, if the session neither compacted nor had `CONTEXT_ECONOMY_CHECKOUT` set.
- A resumed process that compacts before its first response has nothing to fork; that compaction
  uses core's summary.
- A hot reload between a `/clear` and the next prompt loses that handoff delivery.

## Repository layout

| Path              | What it is                                                                                                                                      |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `hooks/`          | The function-hooks module: `register.ts` (events), `handoff-text.ts` (prompts and messages)                                                     |
| `skills/handoff/` | The `/handoff` skill                                                                                                                            |
| `lib/`            | Shell library: gate, citation verifier, store paths, orientation, gauge, thresholds. Each has a `*.test.sh` suite                               |
| `tests/`          | `gate.sh` (structural checks over the suites) and `register.test.ts` (runs under `claude plugin test`)                                          |
| `tools/`          | Transcript analysis behind the design: `context-audit.js`, `context-billing.js`, `context-calibrate.js`                                         |
| `types/`          | The module's `$.state` contract                                                                                                                 |
| `docs/`           | [`design.md`](docs/design.md) (decisions; v2 is D29–D34), [`measured.md`](docs/measured.md) (findings), [`calibration.md`](docs/calibration.md) |

Releases: [`RELEASING.md`](RELEASING.md).
