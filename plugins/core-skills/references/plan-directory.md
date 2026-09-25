# Plan directory derivation

Canonical algorithm for resolving a branch's work directory — `<plan-root>/<slug>/`, or
`<bug-root>/<slug>/` for `review-branch` and `pr` — from the current git branch. Every skill in
this plugin that *finds* an existing plan or bug directory uses it: `catchup` to summarise the
branch's artifacts; `next` to locate `TASKS.md`; `task-writer` to find where `PLAN.md` already
lives so it writes `TASKS.md` alongside it, falling back to creating a new directory (see
`task-writer`'s own Output section) only when the algorithm finds nothing; `implement-plan` the
same read-only way to find `PLAN.md`; `shepard` to find the branch's `DECISIONS.md`; and
`review-branch` and `pr` read-only too, against both roots (see *Which root* below).

## Roots

The root is the one thing a project can move. The folder name inside it is not configurable: it
is the slug the writing skills mint and steps 1-5 below derive, so writers and readers can't
disagree.

| Root | Field in `.claude/project-context.md` | Default when unset |
|---|---|---|
| `<plan-root>` | `plan_root` | `docs/plans` |
| `<bug-root>` | `bug_root` | `docs/bugs` |

Each field is a plain repo-relative path with no placeholders. A skill that reads this algorithm
reads these two fields through it; a skill that *writes* a directory (below) reads the same field
for its own root.

## Algorithm

Steps 1-3 derive a slug; steps 4-6 resolve it against a root.

1. Run `git branch --show-current` to get the branch name.
2. Strip any prefix up to and including the first `/` (e.g. `claude/foo` → `foo`, `feature/foo` → `foo`).
3. Strip the trailing random suffix — the last `-XXXXX` segment where `X` is alphanumeric (e.g. `-0L8sI`, often appended by automated tooling).
4. Look for `<root>/<result>/`.
5. If that directory does not exist, extract any leading issue-key-shaped prefix (any
   `[A-Z]+-\d+` token, e.g. `KD-0461`) from the branch and search `<root>/` for directories whose
   name starts with it. If exactly one match is found, use it. Several matches (one issue split
   across more than one plan folder) → don't pick one; go to step 6.
6. If still nothing matches, ask the user where the work lives — don't guess. (A skill's own
   fallback below can replace this step.)

### Which root

`<root>` is `<plan-root>` for every consumer in this plugin **except `review-branch` and `pr`**,
which are the two skills that serve both pipelines. Each tries `<plan-root>` first, then
`<bug-root>`, using the identical slug from steps 1-3 against each.

**If both exist for the same slug, the plan directory wins** and the branch is treated as
plan-driven. That case means a branch carries both a plan and a bug investigation; the plan is
the richer artifact.

## Examples

With both roots unset (`docs/plans`, `docs/bugs`):

| Branch | After step 2 | After step 3 | Resolves to |
|---|---|---|---|
| `KD-0461-listeners-apply-payload-directly` | (no prefix) | `KD-0461-listeners-apply-payload-directly` | `docs/plans/KD-0461-listeners-apply-payload-directly/` |
| `claude/claude-code-sdk-integration-0L8sI` | `claude-code-sdk-integration-0L8sI` | `claude-code-sdk-integration` | `docs/plans/claude-code-sdk-integration/` |
| `feature/KD-0530-english-user-stories-9k2Bx` | `KD-0530-english-user-stories-9k2Bx` | `KD-0530-english-user-stories` | `docs/plans/KD-0530-english-user-stories/` |
| `KD-0463-foo` (directory only contains `KD-0463-foo-bar-baz`) | `KD-0463-foo` | `KD-0463-foo` | `docs/plans/KD-0463-foo-bar-baz/` (via step 5 prefix match) |
| `KD-0444-foo` (directory contains `KD-0444-bar` and `KD-0444-baz`) | `KD-0444-foo` | `KD-0444-foo` | step 6 — two prefix matches, neither is picked |

## Skill-specific fallbacks

- **`catchup`** — replaces step 6: it summarises, it doesn't execute, so it never asks. Falls
  back to `PLAN.md` / `TASKS.md` in the repository root, then reports "no plan directory". Several
  step-5 matches → lists them all in the summary rather than reading one.
- **`next`** — falls back to `TASKS.md` in the repository root, then asks the user.
- **`implement-plan`** — asks the user where the plan lives; does not guess a fallback.
- **`shepard`** — only needs this when the repo keeps no ADRs; no directory found then → asks
  where the tradeoff record should go.
- **`review-branch`** — still spawns the three finders; none of them requires `PLAN.md`. Per
  *Which root* above it resolves the plan root then the bug root and reads whichever it found for
  context. It reports in chat on every branch shape and writes nothing, so a missing directory
  changes the context the finders get, not the deliverable.
- **`pr`** — on a plan-driven branch, asks whether to run `/core-skills:review-branch` (default no); a missing
  review does not block. On a bug branch it reads `bug-fix-verifier`'s verdict from `BUG.md`
  instead and never asks for `/core-skills:review-branch`. On the `neither` row it skips the finder check.

## Writers

`plan-feature` and `fix-bug` create their directory rather than resolve one — `<plan-root>/<slug>/`
and `<bug-root>/<slug>/` respectively — and `task-writer` does the same when the algorithm finds
nothing. They don't run this algorithm, but they read the same root field, and the slug they mint
(the issue key plus a short description, or just the description with no tracker) is the shape
step 4 or step 5 finds later. Naming the directory after the branch (as `newbranch` names it) makes
step 4 hit exactly.

## Catalog origin

This is an adapted copy of `plan-feature/references/plan-directory.md` in the `claude-2` catalog
(the `{{ISSUE_KEY_PREFIX}}` placeholder token replaced with a generic regex description, and the
catalog's "Bug-side parallel" section folded into *Roots* and *Writers*). It has since diverged
further: the roots became `plan_root` / `bug_root` fields, and `catchup` — which the catalog gives
its own issue-key-only lookup — uses this algorithm too, since that lookup looked for
`docs/plans/<issue-key>/` exactly and so missed every `<issue-key>-<description>/` folder this
plugin's own writers create.
