# crit — repo reference

Solo repo (`~/Code/crit`): automated PR review — Node/TS backend daemon, Vue 3 frontend
dashboard, `crit-shared` wire contract. Architecture and rulings live in the repo's `CLAUDE.md`.

## Scope check

A crit checkout has `backend/`, `frontend/`, and `shared/` side by side at the repo root, and
one lockfile at the root (three npm workspaces, one install).

## Base and branch names

`origin/development`. Branch names carry a type prefix: `feat/`, `fix/`, `refactor/`, or
`chore/`, then the issue key when there is one — `feat/CRIT-0003-target-context`. Kendo
auto-links a branch containing `CRIT-####`; keep the full key.

## Worktree location

`$REPO/.claude/worktrees/<slug>` — already ignored in crit's `.gitignore` (the
`.claude/worktrees/` line), so no `info/exclude` entry is needed.

## Setup

```bash
npm install --prefix "$WT"
```

One install at the root covers all three workspaces — never install per workspace. Copy the
gitignored `.env` if the primary has one (`.env.example` carries the schema).

## House rules once you are in there

- **Style** (enforced or reviewed): no classes — factories returning object literals; arrow
  functions everywhere; no default exports in the backend; explicit `.ts` extensions on
  imports; comments only where they name a constraint the identifiers cannot say.
- **Gates** — the `CLAUDE.md` gate block, per workspace touched: `npm run format:check`, then
  `lint` / `check` / `test` / `knip` for `backend` and `shared`, and `lint` / `lint:styles` /
  `lint:inline-styles` / `build` / `test:unit -- --run` / `knip` for `frontend`. Judge a test
  run by exit code + the `Test Files` line, never the test count.
- **Plan docs are functional.** crit's reviewer honours current `docs/plans/**` records
  (`DECISIONS.md`, `FINDINGS.md`, deferral lists) as waivers — an out-of-scope decision
  recorded there stops the finding from being filed on the PR. Record only what was actually
  decided.
- **Shipping** — the repo's `/commit` skill from `$WT`, then a PR to `development`, adding the
  repo's review label if the repo or the user's settings name one. Never target `main`.
