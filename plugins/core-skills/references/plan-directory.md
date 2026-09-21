# Plan directory derivation

Canonical algorithm for resolving a work directory — `docs/plans/<slug>/`, or `docs/bugs/<slug>/`
for `review-branch` and `pr` — from the current git branch. `next` in this plugin uses it to
locate `TASKS.md`; `task-writer` uses it to find where `PLAN.md` already lives so it writes
`TASKS.md` alongside it, falling back to creating a new directory (see `task-writer`'s own Output
section) only when the algorithm finds nothing; `wireframe` uses it the same read-only way as
`next`, to find `PLAN.md` before writing `WIREFRAMES.md` alongside it; `implement-plan` uses it
the same read-only way to find `PLAN.md`, asking the user rather than guessing when it finds
nothing (see *Skill-specific fallbacks* below); `review-branch` and `pr` both use it read-only
too, against both roots (see *Which root* below).

## Algorithm

Steps 1-3 derive a slug; steps 4-6 resolve it against a directory root.

1. Run `git branch --show-current` to get the branch name.
2. Strip any prefix up to and including the first `/` (e.g. `claude/foo` → `foo`, `feature/foo` → `foo`).
3. Strip the trailing random suffix — the last `-XXXXX` segment where `X` is alphanumeric (e.g. `-0L8sI`, often appended by automated tooling).
4. Look for `<root>/<result>/`.
5. If that directory does not exist, extract any leading issue-key-shaped prefix (any
   `[A-Z]+-\d+` token, e.g. `KD-0461`) from the branch and search `<root>/` for a single
   directory whose name starts with it. If exactly one match is found, use it.
6. If still nothing matches, ask the user where the work lives — don't guess.

### Which root

`<root>` is `docs/plans/` for every consumer in this plugin **except `review-branch` and `pr`**,
which are the two skills that serve both pipelines. Each tries `docs/plans/` first, then
`docs/bugs/`, using the identical slug from steps 1-3 against each.

**If both exist for the same slug, `docs/plans/` wins** and the branch is treated as plan-driven.
That case means a branch carries both a plan and a bug investigation; the plan is the richer
artifact.

## Examples

| Branch | After step 2 | After step 3 | Resolves to |
|---|---|---|---|
| `KD-0461-listeners-apply-payload-directly` | (no prefix) | `KD-0461-listeners-apply-payload-directly` | `docs/plans/KD-0461-listeners-apply-payload-directly/` |
| `claude/claude-code-sdk-integration-0L8sI` | `claude-code-sdk-integration-0L8sI` | `claude-code-sdk-integration` | `docs/plans/claude-code-sdk-integration/` |
| `feature/KD-0530-english-user-stories-9k2Bx` | `KD-0530-english-user-stories-9k2Bx` | `KD-0530-english-user-stories` | `docs/plans/KD-0530-english-user-stories/` |
| `KD-0463-foo` (directory only contains `KD-0463-foo-bar-baz`) | `KD-0463-foo` | `KD-0463-foo` | `docs/plans/KD-0463-foo-bar-baz/` (via step 5 prefix match) |

## Skill-specific fallbacks

- **`next`** — falls back to `TASKS.md` in the repository root, then asks the user.
- **`implement-plan`** — asks the user where the plan lives; does not guess a fallback.
- **`review-branch`** — still spawns the always-on reviewers; neither requires `PLAN.md`. Per
  *Which root* above it resolves `docs/plans/` then `docs/bugs/` and reads whichever it found
  for context. It reports in chat on every branch shape and writes nothing, so a missing
  directory changes the context the reviewers get, not the deliverable.
- **`pr`** — skips the reviewer-pair check entirely on the `neither` row; the branch isn't
  plan-driven and `pr` proceeds without one. That row is scoped to the reviewer-pair prompt only:
  on a bug branch `pr` reads `bug-fix-verifier`'s verdict from `BUG.md` instead and never asks
  for `/review-branch`. The docs-accuracy gate is the exception — it's triggered by the diff's
  paths, not the branch's shape, so it runs on all three rows.

## Catchup variant (intentional)

`catchup`, elsewhere in this plugin, uses a simpler algorithm — issue key only (any `[A-Z]+-\d+`
token from the branch, no slug), and reads `plan_dir` for a project override. That's deliberate:
catchup just needs to find _any_ artefacts for the branch quickly and tolerate an imprecise
match. This algorithm exists because `next` needs the precise one — it executes tasks out of
whatever it finds, so a wrong directory is a wrong task list, not just a thinner summary. Don't
unify the two, and don't route this algorithm through `plan_dir` without checking that its
`{issue_key}`-substitution shape actually fits a non-issue-key slug like
`claude-code-sdk-integration` first.

## Catalog origin

This is a trimmed copy of `plan-feature/references/plan-directory.md` in the `claude-2` catalog
(the `{{ISSUE_KEY_PREFIX}}` placeholder token replaced with a generic regex description, and the
catalog's "Bug-side parallel" section trimmed out — `fix-bug` is converted into this plugin, but
it creates `docs/bugs/<slug>/` itself rather than resolving an existing one, so it was never a
consumer of this algorithm and needed no re-sync; `review-branch`'s, `pr`'s, and
`implement-plan`'s own behaviour and fallbacks were re-synced in as each converted). The only
remaining unconverted name this file's own catalog original mentions is `plan-feature` itself,
which — like `fix-bug` — creates its directory rather than resolving one, so it was never
expected to need this algorithm either.
