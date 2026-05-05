# Plan directory derivation

Canonical algorithm for resolving the `docs/plans/<slug>/` directory from the current git branch. Used by `/next`, `/implement-plan`, `/review-branch`, and `/pr` to locate `PLAN.md`, `DECISIONS.md`, `WIREFRAMES.md`, `TASKS.md`, and `REVIEW_*.md` for the work in progress.

`/plan-feature` itself doesn't need this algorithm — it creates the directory, so it knows the slug — but it documents the algorithm here because it owns the directory's naming convention.

## Algorithm

1. Run `git branch --show-current` to get the branch name.
2. Strip any prefix up to and including the first `/` (e.g. `claude/foo` → `foo`, `feature/foo` → `foo`).
3. Strip the trailing random suffix — the last `-XXXXX` segment where `X` is alphanumeric (e.g. `-0L8sI`, often appended by automated tooling).
4. Look for `docs/plans/<result>/`.
5. If that directory does not exist, extract any leading issue-key prefix (`KD-XXXX`) from the branch and search `docs/plans/` for a single directory whose name starts with that key. If exactly one match is found, use it.
6. If still nothing matches, ask the user where the plan lives — don't guess.

## Examples

| Branch | After step 2 | After step 3 | Resolves to |
|---|---|---|---|
| `KD-0461-listeners-apply-payload-directly` | (no prefix) | `KD-0461-listeners-apply-payload-directly` | `docs/plans/KD-0461-listeners-apply-payload-directly/` |
| `claude/claude-code-sdk-integration-0L8sI` | `claude-code-sdk-integration-0L8sI` | `claude-code-sdk-integration` | `docs/plans/claude-code-sdk-integration/` |
| `feature/KD-0530-english-user-stories-9k2Bx` | `KD-0530-english-user-stories-9k2Bx` | `KD-0530-english-user-stories` | `docs/plans/KD-0530-english-user-stories/` |
| `KD-0463-foo` (directory only contains `KD-0463-foo-bar-baz`) | `KD-0463-foo` | `KD-0463-foo` | `docs/plans/KD-0463-foo-bar-baz/` (via step 5 prefix match) |

## Skill-specific fallbacks

Each consuming skill decides what to do when no plan directory is found:

- **`/next`** — falls back to `TASKS.md` in the repository root, then asks the user.
- **`/implement-plan`** — asks the user where the plan lives; does not guess a fallback.
- **`/review-branch`** — skips the reviewer pipeline entirely (no plan = no plan-aware review). Drops to its lightweight chat-only review path.
- **`/pr`** — skips review-file lookup; the branch isn't plan-driven and `/pr` proceeds without a review summary.

## Bug-side parallel

`/fix-bug` uses the same naming convention but a different parent: `docs/bugs/<slug>/BUG.md`. The slug derivation rules are identical; only the directory root differs. `/fix-bug` documents this directly because the bug pipeline is separate from the plan pipeline.

## Catchup variant (intentional)

`/catchup` uses a simpler algorithm — issue key only (`KD-XXXX` from the branch, no slug). This is deliberate: catchup just needs to find _any_ artefacts for the branch quickly and tolerate the imprecise match. Don't unify it with this algorithm.
