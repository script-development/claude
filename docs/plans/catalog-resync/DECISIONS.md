# Decisions — catalog resync

Settled in a `/grill-me` session on 2026-09-02. Each entry: what was chosen, why, and the
rejected alternative.

## D1 — Reviewer roster: adopt kendo's pair, delete the five retired agents

**Chosen.** Catalog skills encode the always-on pair `runtime-integrity-reviewer` +
`precedent-reviewer` (PR-time) and `surface-reviewer` (plan-time). The five agents kendo retired
in `79e77d0b` (KD-1061) are deleted: `acceptance-reviewer`, `simplicity-reviewer`,
`silent-failure-hunter`, `efficiency-hunter`, `task-alignment-reviewer`.

**Why.** Kendo's audit of 134 review files is the only evidence on what the reviewers catch.
`acceptance-reviewer`'s sole catch in 131 runs was a red test suite CI already reports.
`simplicity-reviewer` had 0 unique catches in 130 runs. `task-alignment-reviewer` never scored
below 8 in 26 runs. The hunters' scope moved into `runtime-integrity-reviewer`.

**Rejected.** Keeping the five listed as standalone entries (the "catalog never removes"
default). Rejected because a catalog entry nothing spawns is dead weight that will drift again.
Also rejected: keeping the five-agent pipeline, which leaves six skills permanently disagreeing
with kendo.

## D2 — Drop the `REVIEWERS.md` citation

**Chosen.** Catalog `review-branch` does not cite kendo's 33 KB `.claude/REVIEWERS.md`. The two
pair agents carry their own calibration text.

**Why.** The catalog has no repo-level file slot, only `skills/<name>/references/`. A 33 KB
kendo-specific calibration doc generalises badly and would drift fast.

**Rejected.** Lifting it as `review-branch/references/reviewers.md`.

## D3 — `shepard` replaces `babysit`; `babysit` stays, marked superseded

**Chosen.** Add the personal `shepard` skill (repo-agnostic port of kendo's `drive-pr`, with
`pr-watch.sh` and `references/<repo>.md`). `babysit` keeps its folder; its README row says
"superseded by shepard".

**Why.** `shepard` is already generic and already carries the per-repo house-rules pattern.
`drive-pr` has 37 kendo references to abstract and no live PR watch.

**Rejected.** Lifting `drive-pr` (a third fork of the same skill). Updating `babysit` in place
with only the CI half (ignores the review-findings half kendo merged in).

## D4 — `pr` follows kendo: multi-runner glob removed

**Chosen.** `pr` reads `REVIEW_CLAUDE.md` only and gains the bug-branch gate on BUG.md's
`## Verification` verdict. The `REVIEW_<RUNNER>.md` glob and cross-runner staleness check go.

**Why.** No consumer produces a second `REVIEW_*.md`. Kendo deleted its Codex runner sentence on
2026-07-27. Unused generality is what drifts.

**Rejected.** Keeping the glob for a hypothetical second runner.

## D5 — `startup`: lift the four generic patterns only

**Chosen.** Docker Compose for redis/minio, the pre-resolved `!` context block, the confirmation
gate, and the inline-frontend / agent-backend split come in. Reverb preflight, tenant vars, the
Stripe skip stay in kendo.

**Why.** The catalog pins the stack (Laravel + Vue + MinIO), not the project.

**Rejected.** Lifting kendo's whole `startup`. Leaving the Scoop / MinIO-binary flow as is.

## D6 — `kendo-mcp`: kendo copy is the base, plus crit's four generic rows

**Chosen.** Kendo's tool table is authoritative. Add crit's `search-issues` row, `type: 0-2`,
the link-branch guard, and the prefer-`prepare-issue-context` note. Crit's stack-specific
issue templates stay in crit.

**Why.** Kendo owns the MCP server. Crit's copy was ported from Harness-OS and its templates
point at `/grill` and crit workspace gates.

**Rejected.** Crit as the base.

## D7 — Additions in this pass

**Chosen.** Three review agents (required by D1). Personal `worktree`, `grill-me`, `build-it`.
Kendo `lint-issues` + `issue-linter`, `memory-hygiene`, `sync-worktrees`.

**Why.** All are already generic in shape. `lint-issues` pairs with the issue-templates rule
`kendo-cli` now makes mandatory.

**Rejected.** Drift-only pass with additions deferred to the librarian.

## D8 — Delivery: one PR per skill, catalog only

**Chosen.** One PR per row in PLAN.md. Nothing is pushed to kendo or crit in this pass.

**Why.** PR #14 and #15 already follow the one-skill-per-PR shape and the review label works per
PR. Kendo is mid-flight on `53b0530`; touching its working skills now doubles the work.

**Rejected.** One `gh stack`. Pushing catalog → consumers in the same pass.

## D9 — `bug-fix-verifier` label fix is a catalog bug regardless

The catalog agent says repro paths 4a/4b/4c while the catalog's own `fix-bug` says 3a/3b/3c.
Fixed as part of the roster rewrite, but it would be fixed either way.
