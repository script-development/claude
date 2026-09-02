# kendo — repo reference

The other twelve developers run one session per checkout, and `/prepare-issue` + `/startup`
already serve them. This file is for the worktree flow only.

## Scope check

A kendo checkout has `backend/` and `frontend/` side by side at the repo root. If they are not
there, this file does not apply — you are in a different repo.

## Base

`origin/development`. Issue keys are `KD-####`; keep the full key first in the branch name
(`KD-1163-…`, not `KD-163-…`) so kendo auto-links the branch.

## Worktree location

`$REPO/.claude/worktrees/<slug>` — it is already ignored in kendo's `.gitignore`, so no
`info/exclude` entry is needed. Every test glob is rooted under `frontend/` or `backend/`
(vitest `include: tests/…`, phpstan `paths: app, bootstrap, config, database`), so a worktree at
the repo root is invisible to both toolchains. It also stops `~/Code` from growing another
`kendo-*` sibling.

## Setup — no ports, no tenant

```bash
cp "$REPO/backend/.env"         "$WT/backend/.env"
cp "$REPO/backend/.env.testing" "$WT/backend/.env.testing"
cp "$REPO/frontend/.env"        "$WT/frontend/.env"
composer install -d "$WT/backend"
npm install --prefix "$WT/frontend"
```

That is the whole setup. Explicitly do **not**:

- **No port patching.** Leave `frontend/vite.config.mts` alone — it is tracked, and patching it
  leaves a permanent dirty diff in `git status`.
- **No tenant provisioning.** Every worktree shares tenant `script` and the `script` database.
- **No `docker compose up`.** Redis, MinIO, and MySQL bind fixed host ports from the primary.

Ports and per-worktree tenants only buy concurrent stacks. You run one stack at a time, so they
buy nothing and cost a dirty tracked file plus a hand-maintained tinker script.

`.claude/hooks/ensure-deps.sh` runs on SessionStart, so a session opened *inside* the worktree
installs on its own.

## House rules once you are in there

**Working**
- Every file write goes to `$WT`. Never edit the checkout you came from.
- `require-vitest-skill.sh` **blocks** every `.spec.ts` edit until `/vue-vitest-testing` has been
  loaded. Load it before writing tests, not after the block fires.
- Formatters run on Edit/Write via `format-on-edit.sh`. Never run oxfmt or Pint by hand.
- Coverage is 100% on unit tests both sides. New Action → `/php-unit-test`. New Vue file →
  `/vue-vitest-testing`.

**Gates** — for the side you touched, judged by exit code:

| Touched | Commands (from `$WT`) |
|---|---|
| Frontend | `npm run test:pipeline`, `npm run vue-tsc` |
| Backend | `composer test`, `composer phpstan` |

Test scripts must end in `:pipeline`. The base scripts use `vitest watch` and hang forever.

**Running the app** — one stack at a time. Kill the primary's servers, then start from `$WT` on
default ports (`npm run dev --prefix "$WT/frontend"`, `php "$WT/backend/artisan" serve`,
`php "$WT/backend/artisan" reverb:start`). Most sessions never need this.

**Tenant migrations** — `php "$WT/backend/artisan" tenant:migrate` mutates the shared `script`
database, so the primary sees the new schema too. An extra column is harmless to a branch that
does not know it. A migration that **drops or renames** a column breaks the other branch — reseed
with `php backend/artisan dev:reset --force` when you switch back.

**Plan docs** — the convention is `docs/plans/<slug>/` holding `PLAN.md`, `DECISIONS.md`, and
optionally `TASKS.md` / `WIREFRAMES.md`. The `<slug>` is derived **from the branch name** (strip
any `type/` prefix and any trailing `-XXXXX` tooling suffix) by `/implement-plan`, `/next`, and
`/pr` — the algorithm is `.claude/skills/plan-feature/references/plan-directory.md`. So docs for
branch `KD-1163-foo` must live at `docs/plans/KD-1163-foo/`. `DECISIONS.md` format:
`.claude/skills/plan-feature/references/decisions-template.md`. kendo's `/implement-plan`
refuses to run without a `PLAN.md`.

**Shipping** — `cd "$WT"` first, because `/commit` and `/pr` both act on the *current* branch.
Then `/commit` → `/pr` → add the repo's review label if the repo or the user's settings name one
→ `/drive-pr`. A personal review label is deliberately not in the repo's `/pr`: encoding it there
would opt in every other developer.
