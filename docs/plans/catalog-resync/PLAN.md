# Catalog resync — 2026-09-02

## Goal

Re-sync the catalog to kendo, crit and the personal skills, one PR per skill, catalog only.

Audit basis: every catalog skill and agent diffed against `kendo/.claude`, `crit/.claude` and
`~/.claude/skills` on 2026-09-02. Generalisation-only differences are not drift. Everything below
is substantive.

## Scope

### In

Ordered. Each row is one PR. Tick the box when its PR merges.

**Agents first — every roster rewrite depends on them.**

- [x] `agents/runtime-integrity-reviewer.md`, `agents/precedent-reviewer.md`,
      `agents/surface-reviewer.md` — lifted from kendo (`79e77d0b`, `KD-0711`), generalised.
      This PR.

**Roster rewrites — old five-agent pipeline → the always-on pair.**

- [x] `review-branch` — spawn `runtime-integrity-reviewer` + `precedent-reviewer` always; add
      `docs/bugs/<slug>/` support and the no-directory fallback; inline the review-file format;
      drop the `REVIEWERS.md` citation.
- [x] `pr` — add `git fetch` first, the branch-type gate table (bug branch reads BUG.md
      `## Verification`, exact `PASS`, never prompt `/review-branch` on a bug branch), the
      Bug Fix Verification block. Remove the multi-runner `REVIEW_<RUNNER>.md` glob.
- [x] `implement-plan` — Step 7 runs `/review-branch` and gates on both reviewers ≥ 7; drop the
      `/ci --quick` step.
- [x] `task-writer` — Phase 4 becomes a self-administered coverage checklist with an inline
      Review Notes template; `verification.md` says review runs once per branch.
- [x] `wireframe` — new `references/wireframes-template.md`, `issue-board.md`,
      `anti-patterns.md`; Step 1a zero-UI guard; Step 1b resume-vs-restart; Step 5 self-gate
      with `wireframe-reviewer`.
- [x] `plan-feature` — Phase 1.4 citation pre-flight (`scripts/verify-citations.sh` + test),
      Phase 1.6 Security & Cost Surface gate (`references/surface-questions.md`), Phase 2
      interview-with-hypotheses, Phase 5 spawns `plan-reviewer` + `surface-reviewer` then hands
      off to `/wireframe`. Generalise the `CONTEXT.md` glossary read.
- [x] `agents/wireframe-reviewer.md` — Step 9 appends review notes; sole gate; arch-test checks
      generalised.
- [x] `agents/bug-fix-verifier.md` — labels 3a/3b/3c; preserve prior verification; Score/Verdict
      table with PARTIAL; sole default gate.

**Plain lifts.**

- [x] `triage-reports` — four verdicts (Promote / Combine / Dismiss-with-reason / Park), Step 0
      product-fit check, `docs/triage/decisions.md` log with declined patterns. Generalise the
      company-docs hook and the log path.
- [x] `fix-bug` — Phase 8.5 visual-risk gate; "not a bug / duplicate" stop after Phase 4; `/pr`
      gate on the BUG.md verdict.
- [x] `prepare-issue` — `argument-hint` / `allowed-tools` frontmatter, `$issue` URL form,
      pre-resolved `!` context, parallel gather, `evals/evals.json`.
- [x] `kendo-mcp` — kendo base: `unlink-branch` + `get-sprints` rows, @mention pre-processing,
      Task template + AC principles. Plus crit's four rows: `search-issues`, `type: 0-2`,
      link-branch guard, prefer `prepare-issue-context` when the key is known.
- [x] `newbranch` — parallel gather, members from the bundle.
- [x] `board-sync` — lanes from `prepare-project-context`. Keep Step 1 and key matching.
- [x] `kendo-cli` — issue descriptions must follow `issue-templates.md`.
- [x] `commit` — crit's rule: never hardcode a model name in the trailer.
- [x] `agents/plan-reviewer.md` — Step 2b module-shape re-check (FAIL caps at 6), surface
      delegation, `### Plan Review` notes. Drop the kendo Repo Quick Reference.
- [x] `startup` — four generic patterns only: Docker Compose for redis/minio, pre-resolved `!`
      context, confirmation gate, inline-frontend / agent-backend split.

**New skills.**

- [x] `shepard` (personal, with `references/crit.md` as the house-rules example). README row for
      `babysit` marked "superseded by shepard"; folder stays.
- [x] `worktree`, `grill-me`, `build-it` (personal).
- [x] `lint-issues` + `agents/issue-linter.md`, `memory-hygiene`, `sync-worktrees` (kendo,
      each generalised).

**Deletions.**

- [x] `agents/acceptance-reviewer.md`, `simplicity-reviewer.md`, `silent-failure-hunter.md`,
      `efficiency-hunter.md`, `task-alignment-reviewer.md`. Remove after every roster rewrite
      above has merged, so no catalog skill points at a missing agent.

**Finish.**

- [x] README catalog tables reflect every row above.

### Out

- Pushing anything back to kendo or crit. Later pass.
- Kendo's `.claude/REVIEWERS.md`. The pair agents carry their own calibration.
- `drive-pr`, `pr-herald`, `refactor`, `improve-codebase-architecture`, `changelog-entry`,
  `changelog-accuracy-reviewer`, and every crit-only skill.
- The stale kendo submodule pin in mission-control (`bf7f0c2` vs kendo HEAD `53b0530`).
- `release-cli`, `catchup`, `review-mcp-descriptions`, `nightwatch-mcp`, `next`: catalog is
  newer, generalisation only, nothing to do.

## Approach

1. This PR: the three agents plus these docs. Nothing else references them yet.
2. Roster rewrites next, one PR each, in the order listed. `review-branch` first because `pr`,
   `implement-plan` and `task-writer` cite it.
3. `plan-feature` before `agents/plan-reviewer.md` and `wireframe`: both cite files
   `plan-feature` ships (`surface-questions.md`, the Phase 5 handoff).
4. Plain lifts in any order.
5. New skills in any order.
6. Deletions last, then README.

Every lift ships its own reference files in the same PR so no PR leaves a dangling link.

Patterns to follow: PR #14 (`1a4893b`) and PR #15 (`b52c539`) for generalisation style and
commit shape. `templates/agent-template.md` for new agents. Placeholders in use:
`{{ISSUE_KEY_PREFIX}}`, `{{PROJECT_ID}}`, `{{DEFAULT_BRANCH}}`, `{{TENANT}}`.

## Acceptance criteria

| # | Criterion | Pass when |
|---|-----------|-----------|
| 1 | No catalog skill cites an agent the catalog does not ship | `grep -rho '[a-z-]*-reviewer\|[a-z-]*-hunter\|[a-z-]*-verifier\|[a-z-]*-linter' skills` names only files in `agents/` |
| 2 | No catalog file names kendo, crit, or a kendo issue key outside a placeholder | `grep -rn 'kendo\|KD-[0-9]\|CRIT-' skills agents` hits only `kendo-*` skills, `board-sync`, `prepare-issue`, `triage-reports`, and prose that explains a placeholder |
| 3 | README tables list every folder in `skills/` and every file in `agents/`, and nothing else | manual check per PR |
| 4 | The five deleted agents are gone and nothing links to them | `grep -rn 'acceptance-reviewer\|simplicity-reviewer\|silent-failure-hunter\|efficiency-hunter\|task-alignment-reviewer' .` is empty outside `docs/plans/` |
| 5 | `pr` no longer globs `REVIEW_*.md` | `grep -n 'REVIEW_\*' skills/pr/SKILL.md` is empty |
