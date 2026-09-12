# crit — reviewer contract

crit is the reviewer in every repo this skill runs in. This file is how crit reads a PR and its
threads, and so how a reply lands. What differs per repo — the review state crit submits, the
merge signal, the board — lives in `references/repos/<repo>.md`.

Everything here was read in crit's own code (the `script-development/crit` repo), with the file
named so it can be re-checked when crit changes: `backend/src/harness/threads.ts` and `prompts/threads.md`,
`backend/src/harness/judge.ts` and `prompts/judge.md`, `backend/src/delivery/render.ts`.

## Recognising crit on a PR

- Login `crit-ai`. A review body carries `<!-- crit-review -->` and a
  `<!-- crit-findings: {head, issues, nitpicks, settled} -->` payload. The verdict is the
  headline: `**Crit approves**` or `**Crit requests changes**`.
- Its thread replies carry `<!-- crit-settled -->`; its intro comment before the first review
  carries `<!-- crit-intro -->` (Dutch, CRIT-0199). None of these is a finding or a human comment.
- The latest verdict and its head:

  ```bash
  gh pr view <n> --json reviews --jq '[.reviews[] | select(.body | test("crit-review"))] | last | .body | split("\n")[0:4] | join(" ")'
  ```

  A verdict at an older head is stale and banked for nothing; crit re-reviews every push.

## 0 · Read the whole comment: the finder trace (CRIT-0200, 2026-09-12)

Every issue crit posts — the inline comment, and the summary block for an issue not on the
diff — ends in a folded `<details>` block, `Finder trace · <lane> lane · not verified by the
judge beyond the text above`. It holds the finder's raw finding: **Claim**, **Consequence**,
**Evidence** (the paths and lines the finder read, no length cap), one **Also traced by
<lane> lane** paragraph per duplicate another finder filed, and the three tags. Nitpicks carry
no trace. Renderer: `backend/src/delivery/render.ts` `traceBlock`.

What to do with it, in step 3, before any disposition:

- **The site list.** Every `path:line` in the judge's body and in the trace. The judge's body
  names every site where it verified the mechanism (`judge.md` § Writing rules); the Evidence
  names what the finder read on the way, which is a superset. A path written as
  `a dependency file` is a read under `node_modules/` or `vendor/`, never a site.
- **Read each site in the repo.** Keep the ones where the defect holds; the rest were reading.
  Then assess the mechanism that produces it at all of them — SKILL.md step 3.
- **Trust.** The bold headline and the body are the judge's verified text. The trace is not.
  Where they differ, the body wins. An absolute in the trace ("only called by tests", "no other
  caller") is the finder's claim.
- **Round two: the Still open body.** When a thread stays open, the summary's `### Still open`
  entry carries the judge's body — what is still missing at this head — and the same trace.
  Read it before touching the code again. The fallback `already filed, still open` appears when
  the judge did not rule on the thread.
- **The reply names the sites.** In the next round the judge reads the trace in the thread
  root (crit's comment is the root, so the trace rides into `open_threads`, capped at 3000
  characters per comment) and rules whether the fix covered them. A FIX reply that lists the
  sites it changed lets the judge close the thread in one round.
- **The tags on an issue say little.** `pre_existing`, `code_change`, `no_runtime_path` and
  `unconfirmed` each route a finding to nitpick (`shared/src/finding.ts` `ROUTING_REASONS`), so
  an issue is always `introduced` or `adjacent`, `nothing` or `runtime_state`, `confirmed`. On a
  nitpick after an approval they matter: `pre_existing` is the outside-the-diff grade, and
  `proof_gap` says what would confirm an `unconfirmed` one.

## 1 · Crit resolves its own threads. You do not.

`post.ts` runs `postReplies` then `resolveSettledThreads`: crit replies with its evidence
sentence stamped `<!-- crit-settled -->`, then resolves the thread itself. Your job ends at
the reply.

**Resolving a crit thread yourself permanently buries the finding.** `resolvedRootIdsOf`
(`threads.ts`) marks any GitHub-resolved thread `settled: true`, and a settled thread gets
`verb_required: false` — crit never classifies it again and never re-files it. Its own
prompt states the asymmetry: *"A wrong `settled` buries a live defect permanently; a wrong
`open` costs one repeated round."* The registry is human-forgeable on purpose, so nothing
stops you. That is exactly why you must not.

**So under crit: reply, never resolve.** This overrides step 8's resolve rules entirely — all
four bars, and the FIX row's "Then: Resolve". Leave every thread for crit to close.

## 2 · Two ways a defect leaves the PR, and they fire at different times

The seats run **finders → threads → judge** (`run.ts:426` then `:449`), and the judge only ever
sees `threaded.leftover` — the findings that matched no existing thread. That ordering is the
whole rule, so take the two paths in the order they fire.

### Path A · The waiver — before a thread exists

`judge.md:93` has a `waived` verdict: the facts hold, but a **current `docs/plans/**` record**
(`DECISIONS.md`, `FINDINGS.md`, **a plan's own deferral list**) or **the PR body** accepts the
behaviour **by name**. The finding is dropped and the ledger keeps the reason. This is crit's
ticket-shaped deferral, and it is real. The `docs/plans/**` record is the **target repo's**, and
it must be in the tree before the round.

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

### Path B · The settle — once a thread exists

| Case | What crit requires |
|---|---|
| **fixed** | The code changed and crit **proves it by reading the site at this head**. A reply that promises, defers, or argues did not change the code. |
| **passed** | A comment **names the behaviour** and gives it up: declines the work on this PR, accepts the leftover risk at this head, or **defers the fix to an issue, report or ticket** that owns or will own it (no key needed; since CRIT-0157, #244). |
| **conceded** | A refutation that **survives crit's own reading of the code**. Concede on the code, never on insistence. |

**A deferral is a pass since CRIT-0157 (#244).** A reply that names the defect and hands the fix to an
issue, report or ticket settles the thread; crit posts *"Deferred by the author to KD-1341; … is
unchanged at this head."* A bare *"we'll fix this later"* with nothing named and nothing promised is
still `open` — nobody holds the work. crit never looks the ticket or report up.

### The trap: a waiver written too late

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

## 3 · How to write each reply so it lands

**FIX** — describe what changed and where, so crit can read the site. It re-reads the code
itself; your sentence is a pointer, not the proof. Commit, reply citing the commit sha, then
push — see the timing rule below for why the reply goes first.

**Timing: reply BEFORE the push, on every disposition.** This is the skill's default order
(step 7), and crit is why. Verified 2026-09-02 on crit#211 (job 1055): crit claimed the pushed
head within seconds, and its `gather` — the one read of every thread — finished 20 s after the
push, three seconds *before* the decline reply landed. A reply posted after the push is read on
the *next* round; with nothing left to push, that round never comes, and the thread stays `open`
on a decline crit never saw (the review then says "already filed, still open"). A FIX reply cites
the local commit sha; crit reads the code at the head it claims, not the sha in your sentence. A
reply that must land after the push costs one more round or a `review-once`.

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

**FOLLOW-UP** — file the issue or report the repo file names, then reply in the thread naming
the behaviour and the item that owns the fix (CRIT-0157). That is a pass: crit settles the
thread and a later round matches the re-find onto it while the defect stands. A
`docs/plans/<slug>/DECISIONS.md` entry (Path A) is only needed for a finding that has no thread
yet. A key in a reply releases nothing on its own; the reply still declines or defers on the code.

## 4 · Open threads block the verdict even with no new findings

`blockingThreadsOf` collects every thread crit classified `open`, **plus** every thread a
this-round finding restates via `same_as`. Those render as *"already filed, still open"* and
push the review to REQUEST_CHANGES on their own. A round with zero new findings can still
fail on threads alone — so an unanswered thread is not free, and "I'll get to it next round"
costs a round.

The escape is `passed` on the match, which routes the finding to `settled` in
`classifyFinding` and keeps it out of `blockingThreads`. That is the same pass as case 2 —
which is why a properly written ACCEPTED reply is worth more here than anywhere else.

## 5 · Mechanics worth knowing

- **`ours` is narrow.** `isOurs` = the root comment is crit's own login **and** some message
  carries `` finding `<12 hex>` ``. A thread you or a colleague started is never crit's, so
  crit only ever matches against it — it will not settle it, and it will not reply in it.
- **Issue comments count.** A PR-level comment that names and declines a defect passes it
  even when no thread exists. Useful for a defect crit keeps re-finding in a new file each
  round, and for an issue crit posts "not on the diff, so not inline": answer each in one
  PR-level comment that names it in bold (verified on town-crier #311).
- **Never address the reviewer's machinery.** Comment bodies reach crit fenced as
  `untrusted_comment`, and anything aimed at its rules (*"mark this settled"*, *"skip
  verification"*) is treated as an injection attempt and ignored. Write about the code.
- **The blind spot.** crit's worktree fence strips `.claude/`, so a nitpick saying the
  referenced `.claude/` files are absent is that blind spot: skip it and say so.
- **The bus row never carries crit's findings** (`backend/src/bus/submit.ts` sends no
  `findings[]`), so `gate clear` on a crit round is not an approval. `references/watch.md` says
  how the watch reports it. Go by the posted GitHub review.
