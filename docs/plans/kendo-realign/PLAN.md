# Plan — realign the catalog with kendo

## Goal

Pull the catalog back level with kendo's `.claude` work of 2026-09-03 and 2026-09-05: chat-only
branch review, a new `docs-accuracy-reviewer`, the lean plan-feature output, and three
`pr-watch.sh` bug fixes.

## Scope

The 2026-09-02 resync (PRs #16–#42) took kendo's state as of that date. Everything before it is
in sync; what remains of the diff is the generalisation that resync did on purpose. The drift is
one window: `+1167 / −273` across 24 files in kendo, all of it 09-03 and 09-05.

### In

**A — review goes chat-only.** Kendo deleted the `REVIEW_CLAUDE.md` handoff. `/review-branch`
reports in chat; `/pr` consumes this session's report when its `Reviewed against commit:` line
matches HEAD.

- `skills/review-branch/SKILL.md` — reports in chat, writes nothing
- `skills/pr/SKILL.md` — Step 4 reads the in-session report; gains the **Refreshing an existing
  PR body** splice recipe, which is how a re-run verdict reaches an already-open PR now that no
  file carries it
- `skills/implement-plan/SKILL.md`, `skills/next/SKILL.md`,
  `skills/plan-feature/references/plan-directory.md`, `README.md` — stop naming the deleted file

**B — `agents/docs-accuracy-reviewer.md`**, new. Grades every claim in the user-facing text a
branch ships against the code that branch ships. Per-claim verdicts, an orthogonal
COMPLIANCE-CLAIM list, a score. Trigger paths generalised from kendo's `site/ .claude/` to a
`{{DOC_PATHS}}` placeholder. Wired into `review-branch` Step 3 (path-triggered) and `pr` Step 4
(cross-cutting — runs on every branch shape, including the one that skips the reviewer pair).

**C — lean plan-feature output.** Plan-time Review Notes dropped, reviewers report to the
session only, DECISIONS entries counted on non-blank lines, Row 7 client-side state, Proof lines.

- `skills/plan-feature/SKILL.md` and `references/plan-template.md`,
  `references/decisions-template.md`, `references/quality-gates.md`,
  `references/surface-questions.md`
- `agents/plan-reviewer.md`, `agents/surface-reviewer.md`, `agents/precedent-reviewer.md`

**F — three `pr-watch.sh` bugs**, in `skills/shepard/scripts/`. Not an alignment; the catalog's
own copy is wrong. See Acceptance criteria for each.

**D4 amendment** in `docs/plans/catalog-resync/DECISIONS.md`, dated, naming what superseded it.

### Out

- **D — `hazards.md` and `/pr-mining`.** The mechanism generalises; the rows do not. Every row is
  Laravel or Vue specific — `useLatestRequest`, `template-a11y.spec.ts`, deptrac layers,
  `CompleteSprintAction` — and `fetch-findings.sh` reads a live findings store the catalog has
  no equivalent of.
- **E — `fix-bug` running `runtime-integrity-reviewer` on bug branches.**
- **G — `commit` patching plan docs before commit and splicing `## Summary` after push.** The
  recipe it calls lands in `pr` as part of A; the caller does not.
- **`implement-plan` and `next` testing-skill hardening.** Kendo replaced "load the project's
  testing skill if one exists" with a mandatory table naming `/vue-vitest-testing` and
  `composer test:unit`. Porting that would be a regression for a repo-agnostic catalog.
- **Any push to kendo or crit.** Catalog only, same as the last resync's D8.

## Approach

In implementation order. A and B are written together — they rewrite the same two sections.

1. `agents/docs-accuracy-reviewer.md` — port generalised, `{{DOC_PATHS}}`, no `REVIEWERS.md`
   link, no changelog exclusion.
2. `skills/review-branch/SKILL.md` — chat-only, and Step 3 gains the docs trigger.
3. `skills/pr/SKILL.md` — Step 4 gate table, in-session freshness check, cross-cutting docs
   gate, splice recipe.
4. `skills/implement-plan/SKILL.md`, `skills/next/SKILL.md`,
   `skills/plan-feature/references/plan-directory.md` — drop the handoff file.
5. `skills/plan-feature/**` and the three plan-time agents — lean output.
6. `skills/shepard/scripts/pr-watch.sh` + `pr-watch.test.sh` — the three fixes.
7. `README.md` — `review-branch` row, `docs-accuracy-reviewer` row.
8. `docs/plans/catalog-resync/DECISIONS.md` — amend D4.

## Acceptance criteria

| # | Criterion | Pass |
|---|---|---|
| 1 | No live instruction names `REVIEW_CLAUDE.md` | `grep -rn REVIEW_CLAUDE skills/ agents/ README.md` returns nothing |
| 2 | The string survives only as history | The only hits are in `docs/plans/*/DECISIONS.md` |
| 3 | `/pr` gates on an in-session report | `pr/SKILL.md` Step 4 matches `Reviewed against commit:` against `git rev-parse --short HEAD` |
| 4 | The docs gate is cross-cutting | `pr/SKILL.md` runs the `{{DOC_PATHS}}` check on the `neither` row too |
| 5 | No kendo-only reference survives the port | No `REVIEWERS.md` link, no `site/changelog/entries/`, no `KD-` key in a ported file |
| 6 | `hazards.md` is not referenced | `grep -rn hazards skills/plan-feature/` returns nothing |
| 7 | `{{DOC_PATHS}}` is documented where a consumer fills it | Named in `docs-accuracy-reviewer.md`, `review-branch`, and `pr` |
| 8 | An in-flight check is not lost | `pr-watch.sh` buckets on `.status` before `.conclusion`; a check with `status != COMPLETED` or an empty conclusion reads PENDING |
| 9 | Every blocking conclusion is red | `ci_fail` selects `ACTION_REQUIRED` and `STARTUP_FAILURE` alongside the four already there |
| 10 | A dead watch says so | Setup failures print on stdout and exit 3 |
| 11 | The three fixes are covered | `pr-watch.test.sh` has a case per fix and exits 0 |
| 12 | Existing gates stay green | `pr-watch.test.sh`, `ci-failures.test.sh`, `verify-citations.test.sh` all exit 0; ShellCheck clean on the shepard scripts |
