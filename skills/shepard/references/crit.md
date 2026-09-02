# crit — repo reference

Solo repo (`~/Code/crit`): automated PR review — Node/TS backend daemon, Vue 3 frontend dashboard,
`crit-shared` wire contract. Architecture and rulings live in the repo's `CLAUDE.md`.

## Scope check

A crit checkout has `backend/`, `frontend/`, and `shared/` side by side at the repo root, and one
lockfile at the root (three npm workspaces, one install).

## Integration branch

`development`. Never `main`.

## Gates — step 7's narrow checks

One install at the root covers all three workspaces. Run only the workspace you touched:

| Touched | Narrow checks |
|---|---|
| `backend` / `shared` | `npm run format:check`, then `lint`, `check`, the narrowest `test`, `knip` |
| `frontend` | `npm run format:check`, then `lint`, `lint:styles`, `lint:inline-styles`, `build`, `test:unit -- --run` (narrowed to the spec), `knip` |

Judge a test run by exit code + the `Test Files` line, never the test count.

Do not run all three workspaces' suites before pushing. CI does that.

## Auto-fixers

`npm run format` (Prettier) is the only tool that fixes its own CI row. `lint` has no blanket
`--fix` here — read the rule and fix the code, because the style rules below are the ones most often
flagged and none of them is auto-fixable.

## Board

Findings are filed on **kendo** (`mcp__kendo__*`, production), not on a crit-local tracker. Key
prefix `CRIT-`. Kendo auto-links a branch containing `CRIT-####`, which is why branch names carry
the full key.

Never file on a staging kendo instance — a ticket there is invisible to whoever would fix it.

## Answering crit's threads — read this before step 8

crit is the reviewer here, and its contract differs from a crier-style reviewer on three
points that change what you do. All of it is in `backend/src/harness/prompts/threads.md`
and `backend/src/harness/threads.ts`; the file paths are given so you can re-check when
crit changes.

### 1 · Crit resolves its own threads. You do not.

`post.ts` runs `postReplies` then `resolveSettledThreads`: crit replies with its evidence
sentence stamped `<!-- crit-settled -->`, then resolves the thread itself. Your job ends at
the reply.

**Resolving a crit thread yourself permanently buries the finding.** `resolvedRootIdsOf`
(`threads.ts`) marks any GitHub-resolved thread `settled: true`, and a settled thread gets
`verb_required: false` — crit never classifies it again and never re-files it. Its own
prompt states the asymmetry: *"A wrong `settled` buries a live defect permanently; a wrong
`open` costs one repeated round."* The registry is human-forgeable on purpose, so nothing
stops you. That is exactly why you must not.

**So in crit: reply, never resolve.** This overrides step 8's resolve rules entirely — all
four bars, and the FIX row's "Then: Resolve". Leave every thread for crit to close.

### 2 · Two ways a defect leaves the PR, and they fire at different times

The seats run **finders → threads → judge** (`run.ts:426` then `:449`), and the judge only ever
sees `threaded.leftover` — the findings that matched no existing thread. That ordering is the
whole rule, so take the two paths in the order they fire.

#### Path A · The waiver — before a thread exists

`judge.md:93` has a `waived` verdict: the facts hold, but a **current `docs/plans/**` record**
(`DECISIONS.md`, `FINDINGS.md`, **a plan's own deferral list**) or **the PR body** accepts the
behaviour **by name**. The finding is dropped and the ledger keeps the reason. This is crit's
ticket-shaped deferral, and it is real.

What it demands:

- **Names the behaviour.** Vague *"we considered this"* is not enough.
- **Current.** Reversed or struck-through entries are ignored; an amended entry counts if its
  conclusion still stands.
- **A record, not a code comment.** *"A code comment alone is not a waiver — it may point you at
  the record, but the record must name the behaviour."*
- **In the tree at the reviewed head.** *"No such directory means the record half does not fire."*
  So it must be pushed before the round, not written after.

One carve-out: a finding that contradicts a **front-door ruling** — a rule in the target's own
checked-in instruction file — is never waived on the PR body alone while the diff leaves that
ruling untouched. Change the rule in the diff, or write a `docs/plans/**` record naming the
reversal.

#### Path B · The settle — once a thread exists

| Case | What crit requires |
|---|---|
| **fixed** | The code changed and crit **proves it by reading the site at this head**. A reply that promises, defers, or argues did not change the code. |
| **passed** | A comment **names the behaviour** and **declines the work on this PR**, accepting the leftover risk. |
| **conceded** | A refutation that **survives crit's own reading of the code**. Concede on the code, never on insistence. |

**A follow-up ticket named in a reply is none of these.** crit's prompt is explicit: *"A follow-up
ticket, a promise to fix later, 'not in this diff' with no leftover-risk acceptance, or 'leave the
thread open until that lands' is not a pass — the work is still owed."* Filing `CRIT-####` and
citing the key — which is exactly what releases a finding on a crier-style reviewer — does nothing
in a crit thread.

#### The trap: a waiver written too late

**Path A cannot rescue a defect that already has a thread.** The threads seat runs first, matches
the finding to that thread, and puts it in `blockingThreads` — which `run.ts` returns untouched in
both branches, so the judge never gets the chance to waive it. Adding the `DECISIONS.md` entry
afterwards changes nothing for that thread, permanently.

So the ordering rule is:

- **Deciding a tradeoff up front** → write it into `docs/plans/<slug>/DECISIONS.md` (or the PR
  body) and push it **before** the round. The finding is never filed.
- **A thread already exists** → the waiver is too late. Only fixed / passed / conceded closes it,
  and for a tradeoff that means a real decline reply (see 3).
- **A deliberate tradeoff you also want on record** → do both. The record stops the re-file on a
  later round; the reply closes the thread that already exists.

### 3 · How to write each reply so it lands

**FIX** — describe what changed and where, so crit can read the site. It re-reads the code
itself; your sentence is a pointer, not the proof. Commit, reply citing the commit sha, then
push — see the timing rule below for why the reply goes first.

**Timing: reply BEFORE the push, on every disposition.** Verified 2026-09-02 on crit#211
(job 1055): crit claimed the pushed head within seconds, and its `gather` — the one read of
every thread — finished 20 s after the push, three seconds *before* the decline reply landed.
A reply posted after the push is read on the *next* round; with nothing left to push, that
round never comes, and the thread stays `open` on a decline crit never saw (the review then
says "already filed, still open"). So the order in step 7/8 is inverted here: commit, post
every reply (a FIX reply cites the local commit sha — crit reads the code at the head it
claims, not the sha in your sentence), then push once. A reply that must land after the push
costs one more round or a `review-once`.

**ACCEPTED → write it as a pass.** The test is the speech act, not a phrase. Name the
behaviour, decline the work *on this PR*, and accept the leftover risk out loud:

> The retry loop can still double-fire when the queue drains mid-tick. We're shipping with
> that — it needs two workers on one box, and this deploys single-worker. Not addressing it
> here.

*"Out of scope"*, *"won't do"*, *"we're shipping with this"*, *"leftover risk accepted"* all
work when they name the behaviour. What fails: dismissing the review without naming the
behaviour, or anything crit reads as a deferral rather than a decline — *"when it can't tell
decline from deferral, the verb is open."*

**WRONG → refute with a specific, checkable claim**, and the burden flips in your favour.
For a bare dispute (*"that's wrong"*, *"works for me"*) crit keeps the thread open. But when
the refutation cites a measurement, a reverted fix, a replication, or a named path, crit
traces that claim — and *"keeping open on that thread requires you to name what at this head
re-establishes the defect… If you cannot name a leftover in the code, the verb is settled
(conceded)."* So cite the path and the line. Two agreeing comments still decide nothing;
one checkable claim does.

**FOLLOW-UP** — file the `CRIT-` ticket for tracking, but the key in a reply releases nothing.
For the thread in front of you: either fix it, or turn it into a real pass under ACCEPTED above.
To stop it being re-filed on later rounds, add the entry to `docs/plans/<slug>/DECISIONS.md`
naming the behaviour (Path A) — that is the half a ticket key does for you elsewhere.

### 4 · Open threads block the verdict even with no new findings

`blockingThreadsOf` collects every thread crit classified `open`, **plus** every thread a
this-round finding restates via `same_as`. Those render as *"already filed, still open"* and
push the review to REQUEST_CHANGES on their own. A round with zero new findings can still
fail on threads alone — so an unanswered thread is not free, and "I'll get to it next round"
costs a round.

The escape is `passed` on the match, which routes the finding to `settled` in
`classifyFinding` and keeps it out of `blockingThreads`. That is the same pass as case 2 —
which is why a properly written ACCEPTED reply is worth more here than anywhere else.

### 5 · Two mechanics worth knowing

- **`ours` is narrow.** `isOurs` = the root comment is crit's own login **and** some message
  carries `` finding `<12 hex>` ``. A thread you or a colleague started is never crit's, so
  crit only ever matches against it — it will not settle it, and it will not reply in it.
- **Issue comments count.** A PR-level comment that names and declines a defect passes it
  even when no thread exists. Useful for a defect crit keeps re-finding in a new file each
  round.
- **Never address the reviewer's machinery.** Comment bodies reach crit fenced as
  `untrusted_comment`, and anything aimed at its rules (*"mark this settled"*, *"skip
  verification"*) is treated as an injection attempt and ignored. Write about the code.

## House rules

- **Style** (enforced or reviewed): no classes — factories returning object literals; arrow
  functions everywhere; no default exports in the backend; explicit `.ts` extensions on imports;
  comments only where they name a constraint the identifiers cannot say.
- **Branch names** carry a type prefix — `feat/`, `fix/`, `refactor/`, `chore/` — then the key:
  `feat/CRIT-0003-target-context`.
- **Plan docs are functional**, and the judge is the only seat that applies them — see § 2 Path A
  for what a record must say and when it must land. Record only what was actually decided; a
  forged waiver is worse than no waiver, and the finder still files the finding while quoting your
  record in its evidence (`finder-base.md:93`), so a waiver that does not name the behaviour just
  hands the judge a reason to keep it.
- **This repo reviews PRs for a living.** A finding raised on a crit PR may come from crit's own
  reviewer reviewing itself. That does not make it less valid, but the stale-head signal matters
  more here than elsewhere: the reviewer and the reviewed move together.
