---
name: startup
description: "Full project setup for Laravel + Vue + MinIO projects: starts the Docker services (Redis, MinIO, optional MySQL), creates .env files, then runs backend, frontend, and MCP setup in parallel. Supports multiple worktrees with automatic port assignment."
argument-hint: "[worktree-number: optional, skips worktree selection question]"
arguments: [worktree]
allowed-tools: Bash(git *) Bash(docker *) Bash(docker-compose *) Bash(php *) Bash(composer *) Bash(npm *) Bash(node *) Bash(cp *) Bash(scoop *) Bash(gh *) Bash(claude *) Bash(winget *) Bash(powershell *) Bash(sed *) Bash(openssl *) Bash(grep *) Bash(ls *) Bash(which *) Bash(nc *) Agent AskUserQuestion Read Grep Glob Edit Write
---

Setup orchestrator for Laravel + Vue + MinIO projects. Scan the environment, collect user choices, then execute the appropriate setup flow.

> **Confirmation gate:** Setup has irreversible side effects (database resets, worktree creation, port-patching, dependency installs). Before running any step below, confirm with the user via `AskUserQuestion` that they want to proceed. If `/startup` was invoked directly by the user (typed `/startup` themselves), treat that as the confirmation. If invoked indirectly (delegated from another skill), ask explicitly before starting — even if the calling skill already collected related choices.

Optional argument: `$worktree` (worktree number, may be empty). When non-empty, skip the worktree
selection question and use it directly (`1` = primary, `2`+ = non-primary worktree). Still ask the
database migration question unless the worktree doesn't exist yet (new worktree → default to "Skip").

The detailed instructions for each setup domain live in `references/` files within this skill directory. The orchestrator runs trivial, no-judgement steps inline and delegates the rest to background agents, which read the relevant reference file and follow it.

## Project conventions

This skill is generic across Laravel + Vue + MinIO projects. A few project-specific behaviours are conditional and should be detected from the project itself:

- **Docker services**: the project ships a `docker-compose.yml` at the repo root that defines `redis` and `minio` services with health checks, a one-shot `minio-init` service that creates the app bucket, and a `mysql` service behind the `mysql` Compose profile (opt-in, so developers with a system MySQL are unaffected). If the project has no compose file, tell the user and stop — the rest of the flow assumes these services.
- **Multi-tenancy** (e.g. `stancl/tenancy`): check `backend/composer.json` for `stancl/tenancy`. If present, the project has a central database plus per-tenant databases and the alt-ports flow needs to register tenants. **Skip the tenant flow entirely** if the package isn't in use.
- **Laravel Passport**: check `backend/composer.json` for `laravel/passport`. If present, run `passport:keys` after `composer install`. Otherwise skip.
- **Custom dev-reset artisan command**: some projects ship a `dev:reset` (or similar) artisan command that wraps drop/migrate/seed for both central and tenant databases. Check `php ./backend/artisan list` or the project's `CLAUDE.md` for it. Otherwise fall back to the generic Laravel commands (`migrate:fresh --seed`, `migrate`).
- **Project MCP servers**: any project-specific MCP servers should be documented in the project's `CLAUDE.md` or `.mcp.json`. The MCP reference handles the generic CLI tooling; project-specific servers are a separate, optional step.

The placeholder `<app>` below stands for the value of `APP_NAME` in `backend/.env` (e.g. if `APP_NAME=Acme`, then `<app>` is `acme`, lowercased and slugified). Hostnames, tenant database names, and bucket names all derive from this.

## Pre-resolved context

- **Worktrees:** !`git worktree list`
- **Current branch:** !`git branch --show-current`
- **Docker:** !`docker compose ps 2>&1 | head -5 || echo "docker not available"`
- **Skill dir:** `${CLAUDE_SKILL_DIR}`

These values are available immediately — do not re-run these commands during the steps below.

## Step 1 — Use the pre-resolved worktree list

Parse the **Worktrees** value above to determine how many worktrees exist and their paths. Use this to build the list of options for the user.

## Step 2 — Collect choices

**If `$worktree` is non-empty**, skip the worktree selection question — use it directly:
- `$worktree = 1` → Mode A (primary)
- `$worktree >= 2` → check if that worktree exists in the pre-resolved list. If yes, use it. If no, create it (Mode B).

Then ask only the database migration question (Question 2 below) via `AskUserQuestion`, with
the recommendation based on N.

**If `$worktree` is empty**, use a **single** `AskUserQuestion` call with multiple questions to collect all choices at once:

### Question 1: Worktree selection

Build the options dynamically based on the scan:

- **Primary** — Full setup of the main worktree (backend + frontend + MCP in parallel). This is N=1, using default ports (3000 / 8000 / 6001).
- List any **existing non-primary worktrees** detected in Step 1 with their paths and assigned N values.
- **New worktree** — Create a new git worktree from the project's base branch (typically `development` or `main` — check the project's `CLAUDE.md`) and set it up. Assign the next available N.

Once the user picks a worktree (which determines N), include the recommendation in Question 2.

### Question 2: Database migration strategy

Present these options, with a **recommended** label based on N:

- **Full reset** — Drop the database, recreate, migrate, and seed. Use for a clean start. **(recommended for N=1)**
  - Default command: `php artisan migrate:fresh --seed`
  - **Project override**: if the project defines a custom dev-reset artisan command (e.g. `dev:reset --force`), prefer that — it usually handles central + tenant databases together.
- **Migrate only** — Run pending migrations without dropping data. Use when the schema needs updating but data should be preserved. **(recommended for N>=2)**
  - Default command: `php artisan migrate`
  - **Project override**: if the project uses multi-tenancy, also run `php artisan tenant:migrate` (or the project's equivalent) to update tenant schemas.
- **Skip** — Don't touch the database. Use when everything is already up to date.

The worktree number N determines port offsets (see port formula below). N=1 is primary (default ports), N=2 is the first additional worktree, N=3 the next, etc.

### Port formula

| Service | Default | Formula |
|---|---|---|
| Frontend (Vite) | 3000 | `3000 + N` (N>=2) |
| Backend (artisan serve) | 8000 | `8000 + N` (N>=2) |
| Reverb (WebSocket) | 6001 | `6001 + N - 1` (N>=2) |

Primary (N=1) uses default ports unchanged.

## Mode A: Primary setup (N=1)

### A0 — Start Docker services and create .env files (before background agents)

Check the **Docker** value in Pre-resolved context first. If it reads `docker not available`,
ask the user to start Docker Desktop (or the Docker daemon) and stop — there's no point continuing.

If Docker is available but `redis` / `minio` aren't already listed as `Up (healthy)`, start them:

```bash
docker compose up -d
docker compose ps
```

Expect `redis` and `minio` with status `Up (healthy)`. The `minio-init` one-shot service creates
the `<app>` bucket and exits — that is normal. If the project's compose file has no `minio-init`
service, create the bucket once, using the `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` values from
`docker-compose.yml`:

```bash
docker compose exec minio mc alias set local http://localhost:9000 <user> <password>
docker compose exec minio mc mb --ignore-existing local/<app>
```

**MySQL — opt-in Docker profile.** MySQL uses the `mysql` Compose profile so devs with a system
MySQL are unaffected. Check if port 3306 is reachable:

```bash
nc -z 127.0.0.1 3306 2>/dev/null && echo "reachable" || echo "unreachable"
```

- If **reachable** — MySQL is already running (system service or existing container). Skip. Note: the check only confirms that port 3306 responds — it does not verify credentials. If your system MySQL uses different credentials than the ones `docker-compose.yml` sets (`MYSQL_ROOT_PASSWORD`), update `DB_USERNAME`/`DB_PASSWORD` in `backend/.env` accordingly instead of starting the Docker container.
- If **unreachable** — start the Docker MySQL container:
  ```bash
  docker compose --profile mysql up -d mysql
  ```
  Then wait for it to be healthy before continuing (substitute the root password from `docker-compose.yml`):
  ```bash
  until docker compose exec mysql mysqladmin ping -h 127.0.0.1 -uroot -p<root-password> --silent 2>/dev/null; do sleep 3; done
  ```

Then follow the instructions in `references/env.md` **directly in the main conversation** (not in a background agent). This creates `backend/.env` from `.env.example` with local defaults applied. It requires file write permissions, which background agents cannot obtain.

Also copy the frontend `.env` if it doesn't exist:

```bash
cp ./frontend/.env.example ./frontend/.env
```

Wait for all to complete before proceeding.

### A1 — Run frontend inline, launch backend + MCP agents in parallel

> **Delegate only work with branching judgement.** A subagent spawn's fixed overhead (its own system prompt, the full `CLAUDE.md`, the tool catalog, a report) isn't worth a one-line install — run trivial steps inline, and keep agents for judgement (fresh-PC bootstrap, migration decisions) on the cheapest model that covers it.

**Frontend — run inline (no agent).** Frontend setup is a single deterministic command. Do it directly in the main conversation:

```bash
npm install --prefix ./frontend
```

If `npm` isn't found, Node.js isn't installed — follow `references/frontend.md` for the fresh-PC Node install, then retry. The frontend `.env` and the vite port are already handled by A0 / B3.

**Backend + MCP — launch as background agents in parallel**, each on a downgraded model (mechanical work — the top model is wasted here). Use the Agent tool's `model` parameter:

1. **Backend agent** (`model: sonnet` — touches the DB, keep some judgement for migration decisions) — "Read `${CLAUDE_SKILL_DIR}/references/backend.md` and follow those instructions. Migration strategy already chosen: {answer}. Skip asking and use this. The .env file has already been created by the orchestrator — skip Step 3."
2. **MCP agent** (`model: haiku` — pure CLI/tool installs, no judgement) — "Read `${CLAUDE_SKILL_DIR}/references/mcp.md` and follow those instructions. Do NOT touch backend/.env or run any backend/frontend setup."

The `${CLAUDE_SKILL_DIR}` placeholder is resolved by Claude Code before the agent prompt is sent, so the agent receives an absolute path.

**Important:** Each agent prompt must be explicit about scope. Background agents cannot obtain file write permissions, so they must not attempt to create or modify `.env` files.

Wait for the inline install and both agents to complete. If any fails, report which one failed and why.

> **Fresh PC note:** On a brand-new Windows PC where Scoop, PHP, and Node.js are not yet installed, run the MCP setup first (it installs Scoop, which the other agents may need). Once Scoop is available, run this orchestrator for the rest.

### Completion

```
Full setup complete! (primary, N=1)
  [x] Docker — Redis, MinIO (bucket "<app>"), and MySQL (Docker profile / system) running
  [x] Backend — PHP, Composer, .env, dependencies, migrations
  [x] Frontend — Node.js, dependencies, .env
  [x] MCP — gh CLI, claude CLI, project MCP servers (if any)
  Ports: 3000 / 8000 / 6001
```

## Mode B: Non-primary worktree setup (N>=2)

This mode is run **from the primary worktree**.

> **Docker is shared across worktrees.** Redis, MinIO, and MySQL bind fixed host ports (6379 / 9000 / 3306), so a non-primary worktree must reuse the primary's containers — do **not** run `docker compose up` in the worktree, it will fail to bind those ports. Confirm the primary's stack is healthy (`docker ps` shows `*-redis-1` and `*-minio-1` as `Up (healthy)`) and only start it from the primary if it isn't running. MySQL follows the same A0 opt-in logic (check port 3306, start `--profile mysql` if unreachable).

### B1 — Create the git worktree (new worktree only)

Skip this step if the user selected an existing worktree.

The worktree name uses a numeric suffix: `<repo-folder>-{N}` (e.g. `myapp-2`, `myapp-3`). Determine the repo folder name from the working directory.

If the project uses multi-tenancy, the suffix also matches the tenant naming convention (`<app>{N}`, `<app>-{N}`) — see `references/alt-ports.md`.

Create the worktree as a **sibling folder** next to the current repository, branching from the project's base branch (check the project's `CLAUDE.md` — typically `development` or `main`):

```bash
git worktree add ../<name> -b <name> <base-branch>
```

- The worktree is placed **outside** the repository, in the same parent directory.
- A new branch `<name>` is created from `<base-branch>`.
- If the branch already exists, use `git worktree add ../<name> <name>` instead (without `-b`).

After creation, **change the working directory** to the new worktree path for all subsequent steps.

### B2 — Create .env files (before background agents)

From inside the worktree, follow the instructions in `references/env.md` **directly in the main conversation** (not in a background agent). This creates `backend/.env` with local defaults.

Also copy the frontend `.env` if it doesn't exist:

```bash
cp ./frontend/.env.example ./frontend/.env
```

### B3 — Patch ports, run frontend inline and backend as an agent

Port patching (editing `backend/.env` and `frontend/vite.config.mts`) can run immediately — these files already exist from B2. Do this **directly in the main conversation** before launching agents, so the agents work with the correct ports from the start.

Follow `references/alt-ports.md` **Steps 1–3 only** (verify .env, patch backend .env, patch vite config). Skip Steps 4–5 (tenant DB setup and report) — those happen in B4.

> **Delegate only work with branching judgement** (see A1): inline the trivial frontend install, run the backend agent on a cheaper model.

**Frontend — run inline (no agent):**

```bash
npm install --prefix ./frontend
```

(`.env` and vite port already patched above. If `npm` is missing, see `references/frontend.md` for the fresh-PC Node install.)

**Backend — launch as a background agent on `model: sonnet`** (touches the DB; keep judgement for migration decisions, but the top model is wasted on mechanical setup):

- "Read `${CLAUDE_SKILL_DIR}/references/backend.md` and follow those instructions. Migration strategy already chosen: {answer}. Skip asking and use this. The .env file has already been created by the orchestrator — skip Step 3."

Wait for the inline install and the backend agent to complete before proceeding to B4.

### B4 — Set up tenant database

**Skip if** the project doesn't use multi-tenancy (no `stancl/tenancy` in `backend/composer.json`).

This must run **after** B3 because it needs `vendor/` dependencies installed by the backend agent.

Follow `references/alt-ports.md` **Steps 4–5** (register tenant in central DB, create and migrate tenant database, report).

### Completion

```
Worktree setup complete! (N={N})
  Worktree: ../<name>
  Branch:   <name> (from <base-branch>)
  [x] Docker — reusing the primary worktree's Redis / MinIO / MySQL
  [x] Backend — PHP, Composer, .env, dependencies, migrations
  [x] Frontend — Node.js, dependencies, .env
  [x] Ports patched for worktree N={N} ({3000+N} / {8000+N} / {6001+N-1})
  [x] Tenant database registered (if multi-tenancy)
```

## Final step — Start development servers (optional)

After all setup is complete (both Mode A and Mode B), use `AskUserQuestion` to ask:

> **Start the development servers now?**
>
> - **Yes** — Start frontend, backend, and Reverb in the background
> - **No** — Setup only, I'll start servers myself (e.g. via VS Code tasks)

If **Yes**, launch all three as **background** Bash commands in parallel:

| Service | Command (primary N=1) | Command (N>=2) |
|---|---|---|
| Frontend | `npm run dev --prefix frontend` | `npm run dev --prefix frontend` (port already patched in vite.config) |
| Backend | `php ./backend/artisan serve` | `php ./backend/artisan serve --port={8000+N}` |
| Reverb | `php ./backend/artisan reverb:start` | `php ./backend/artisan reverb:start --port={6001+N-1}` |

**Skip Reverb** if the project doesn't use Laravel Reverb (check `backend/composer.json` for `laravel/reverb`).

Report the running services and their URLs to the user.
