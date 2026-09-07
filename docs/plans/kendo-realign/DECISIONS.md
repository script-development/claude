# Decisions — realign the catalog with kendo

Settled in a `/grill-me` session on 2026-09-07. Each entry: what was chosen, why, and the
rejected alternative. This pass supersedes part of
[`../catalog-resync/DECISIONS.md`](../catalog-resync/DECISIONS.md) § D4 — see D1 below.

## D1 — Port kendo's chat-only review outright, with no file fallback

**Chosen.** `REVIEW_CLAUDE.md` stops existing in the catalog. `/review-branch` reports in chat.
`/pr` consumes this session's report when its `Reviewed against commit:` sha matches
`git rev-parse --short HEAD`.

**Why.** The catalog was keeping a mechanism its own source repo had abandoned. The file's
failure mode is silent: one left over from an earlier branch reads as a gate that ran, and the
sha line only catches it if the reader looks. An in-session report cannot be stale in that way —
there either is one for this HEAD or there is not.

**Rejected.** Chat-only *plus* the file as a cross-session fallback, so a worker could review and
an orchestrator could open the PR. Rejected because two mechanisms kept in step is exactly what
drifted between 2026-09-02 and now. Also rejected: leaving the catalog as it was, which makes
D2's `docs-accuracy-reviewer` wiring and D3's splice recipe harder to land, since both sit in
the sections chat-only rewrites.

**Supersedes** catalog-resync D4's premise that `/pr` reads `REVIEW_CLAUDE.md`. D4's other half
— the `REVIEW_<RUNNER>.md` glob stays removed — still holds and is not reopened.

## D2 — Lift `docs-accuracy-reviewer`, generalised behind `{{DOC_PATHS}}`

**Chosen.** The agent comes in. Kendo's hardcoded `site/` and `.claude/` become a
`{{DOC_PATHS}}` placeholder that a consumer fills with its own prefixes and exclusions.

**Why.** The shape is generic — grade each claim in shipped user-facing text against the code
the branch ships, return per-claim verdicts and a score. Only the trigger is repo-specific. The
catalog already runs on this convention: `{{ISSUE_KEY_PREFIX}}` appears 81 times,
`{{DEFAULT_BRANCH}}` 22, `{{PROJECT_ID}}` 18, `{{TENANT}}` twice. And `.claude/` is the wrong
literal here anyway — this repo has no `.claude/` prefix, its skills sit at the root.

**Rejected.** Lifting it verbatim, which gives every consumer without a `site/` directory a
reviewer that never fires. A `references/text-paths.md` file, which is a second convention for a
job the placeholders already do.

**Consequence.** `README.md` needs a line separating it from `docs-auditor`. The two names read
alike and do different jobs: `docs-auditor` hunts drift in repo documentation on demand;
`docs-accuracy-reviewer` grades one branch's shipped text at a review gate.

## D3 — The `pr` splice recipe comes with A; the `commit` caller does not

**Chosen.** `pr/SKILL.md` gains kendo's **Refreshing an existing PR body** section. Kendo's
`commit` § 5b, which calls it after a push, stays out.

**Why.** With no file on disk, a re-run verdict has no way to reach an already-open PR except
the PR body. The recipe is load-bearing for A. The `commit` caller is a separate convenience and
was not selected for this pass.

**Rejected.** Taking both, which widens the pass into a skill the grill scoped out. Taking
neither, which leaves A with a gate that cannot report a second verdict.

## D4 — Take the lean plan output, leave `hazards.md` and `/pr-mining`

**Chosen.** Cluster C only: slimmer PLAN.md, plan-time Review Notes dropped, DECISIONS counted
on non-blank lines, Row 7 client-side state, Proof lines. `hazards.md` and `/pr-mining` stay in
kendo.

**Why.** C is pure shape and generalises with no edits. D's mechanism generalises too, but its
rows do not — all ten are Laravel or Vue specifics no other consumer can act on, and
`fetch-findings.sh` reads a findings store the catalog has no equivalent of. Verified cheap to
separate: `hazards.md` is cited in exactly two places inside the lean plan-feature,
`plan-template.md:177` and `surface-questions.md:164`. Both are stripped on the way in, leaving
no dangling reference.

**Rejected.** Shipping `hazards.md` with kendo's rows as worked examples — the same
carry-the-consumer's-specifics move the last resync's D6 pushed back on. Shipping the mechanism
with an empty table, which puts a file in the repo that nothing fills. Skipping C as well.

## D5 — One PR, not three

**Chosen.** Everything in this pass ships as a single PR against `main`.

**Why.** A and B rewrite the same two sections — `review-branch` Step 3 and `pr` Step 4.
Splitting them writes those twice and reviews the second write against a body about to change.

**Rejected.** Three PRs (`[A+B]`, `[C]`, `[F]`), and four with B stacked on A. Both are closer
to catalog-resync D8's one-concern-per-PR shape, but A alone spans six skills with no working
intermediate state, so D8's unit does not survive contact with this pass.

**Cost accepted.** F — three shell bugs with their own tests — rides in a diff that is otherwise
prose.

## D6 — Amend catalog-resync D4 in place

**Chosen.** Add a dated supersession note to the existing entry rather than leaving it or
writing a replacement.

**Why.** It is kendo's own pattern — commit `38043be90` amended D6 in place when reality moved
past it. The original decision and its reasoning stay readable, and a reader who greps
`REVIEW_CLAUDE.md` lands on the amendment instead of on an instruction that is now wrong.

**Rejected.** Leaving it untouched as history, which lets the dead string survive with no marker.
Recording the reversal only here, which means the wrong entry is the one people find first.

## D7 — Catalog only; nothing is pushed to kendo

**Chosen.** No kendo or crit changes in this pass.

**Why.** Nothing was found that kendo is missing. Its `pr-watch.sh` is the newer copy — the
catalog's is the one with the bugs. The catalog's extra town-crier bus surface is crit-specific,
and kendo does not announce there.

**Rejected.** Pushing the generalised `docs-accuracy-reviewer` back so both copies match the
baseline — a kendo PR whose only effect is swapping two working literals for a filled
placeholder. Filing a kendo issue for the push-back still owed, which was not needed once the
search turned up nothing owed.

## D8 — What the port drops on the way in

Not a fork in the road, but recorded because each is a deliberate deletion a future resync would
otherwise read as drift:

- **The `REVIEWERS.md` citation.** Kendo's `review-branch:34` links `.claude/REVIEWERS.md` §
  Calibration history. Catalog-resync D2 already rejected lifting that 33 KB file, so the link
  cannot come with it.
- **The changelog exclusion.** Kendo excludes `site/changelog/entries/` because
  `changelog-accuracy-reviewer` owns those. The catalog has no such agent. `{{DOC_PATHS}}` is
  documented as accepting exclusion pathspecs instead, so a consumer that has one can express it.
- **Issue keys.** `KD-1336`, `KD-1357` and the rest are stripped; the behaviour they document
  stays.

The `**` glob warning is **kept** and re-grounded on a catalog-real path. Git requires an
intervening directory for `.claude/**/*.md`, so that pattern silently misses every file sitting
directly under the prefix. That is git behaviour, not kendo trivia, and a trigger that answers
"no text changed" when text changed is the failure the whole gate exists to prevent.
