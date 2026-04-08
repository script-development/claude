---
name: startup
description: "Full project setup: runs backend, frontend, and MCP in parallel. Supports multiple worktrees with automatic port assignment."
---

Setup orchestrator. Scan the environment, collect user choices, then execute the appropriate setup flow.

Optional argument: `N` (worktree number). When provided, skip the worktree selection question
and use N directly (`1` = primary, `2`+ = non-primary worktree). Still ask the database migration
question unless the worktree doesn't exist yet (new worktree → default to "Skip").

The detailed instructions for each setup domain live in `references/` files within this skill directory. Background agents read the relevant reference file and follow those instructions.

## Step 1 — Scan existing worktrees

Run:

```bash
git worktree list
```

Parse the output to determine how many worktrees exist and their paths. Use this to build the list of options for the user.

## Step 2 — Collect choices

**If N was provided as an argument**, skip the worktree selection question — use N directly:
- `N=1` → Mode A (primary)
- `N>=2` → check if worktree N exists in scan results. If yes, use it. If no, create it (Mode B).

Then ask only the database migration question (Question 2 below) via `AskUserQuestion`, with
the recommendation based on N.

**If N was omitted**, use a **single** `AskUserQuestion` call with multiple questions to collect all choices at once:

### Question 1: Worktree selection

Build the options dynamically based on the scan:

- **Primary** — Full setup of the main worktree (backend + frontend + MCP in parallel). This is N=1, using default ports (3000 / 8000 / 6001).
- List any **existing non-primary worktrees** detected in Step 1 with their paths and assigned N values.
- **New worktree** — Create a new git worktree from development and set it up. Assign the next available N.

Once the user picks a worktree (which determines N), include the recommendation in Question 2.

### Question 2: Database migration strategy

Present these options, with a **recommended** label based on N:

- **Full reset (dev:reset --force)** — Drop all databases (central + tenant), recreate, migrate, and seed. Use for a clean start. **(recommended for N=1)**
- **Tenant migrate only (tenant:migrate)** — Run pending migrations on all tenant databases. Use when the central database is fine but tenant schemas need updating. **(recommended for N>=2)**
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

### A0 — Create .env files (before background agents)

Follow the instructions in `references/env.md` **directly in the main conversation** (not in a background agent). This creates `backend/.env` from `.env.example` with local defaults applied. It requires file write permissions, which background agents cannot obtain.

Also copy the frontend `.env` if it doesn't exist:

```bash
cp ./frontend/.env.example ./frontend/.env
```

Wait for both to complete before proceeding.

### A1 — Launch parallel setup agents

Launch all three as **background agents in parallel** using the Agent tool. Each agent prompt must include the path to the relevant reference file so it can read the instructions:

1. **Backend agent** — "Read `<skill-path>/references/backend.md` and follow those instructions. Migration strategy already chosen: {answer}. Skip asking and use this. The .env file has already been created by the orchestrator — skip Step 3."
2. **Frontend agent** — "Read `<skill-path>/references/frontend.md` and follow those instructions. Do NOT touch backend/.env or run any backend setup. The frontend .env file has already been created by the orchestrator — skip Step 4."
3. **MCP agent** — "Read `<skill-path>/references/mcp.md` and follow those instructions. Do NOT touch backend/.env or run any backend/frontend setup."

Replace `<skill-path>` with the absolute path to this skill's directory.

**Important:** Each agent prompt must be explicit about scope. Background agents cannot obtain file write permissions, so they must not attempt to create or modify `.env` files.

Wait for all three to complete. If any fails, report which one failed and why.

> **Fresh PC note:** On a brand-new Windows PC where Scoop, PHP, and Node.js are not yet installed, run the MCP setup first (it installs Scoop, which the other agents may need). Once Scoop is available, run this orchestrator for the rest.

### Completion

```
Full setup complete! (primary, N=1)
  [x] Backend — PHP, Composer, .env, dependencies, migrations
  [x] Frontend — Node.js, dependencies, .env
  [x] MCP — gh CLI, claude CLI, kendo MCP server
  Ports: 3000 / 8000 / 6001
```

Proceed to **MinIO setup** (below).

## Mode B: Non-primary worktree setup (N>=2)

This mode is run **from the primary worktree**.

### B1 — Create the git worktree (new worktree only)

Skip this step if the user selected an existing worktree.

The worktree name uses a numeric suffix: `<repo-folder>-{N}` (e.g. `issue-tracker-2`, `issue-tracker-3`). This matches the tenant naming convention (`script2`, `script-2`). Determine the repo folder name from the working directory.

Create the worktree as a **sibling folder** next to the current repository:

```bash
git worktree add ../<name> -b <name> development
```

- The worktree is placed **outside** the repository, in the same parent directory.
- A new branch `<name>` is created from `development`.
- If the branch already exists, use `git worktree add ../<name> <name>` instead (without `-b`).

After creation, **change the working directory** to the new worktree path for all subsequent steps.

### B2 — Create .env files (before background agents)

From inside the worktree, follow the instructions in `references/env.md` **directly in the main conversation** (not in a background agent). This creates `backend/.env` with local defaults.

Also copy the frontend `.env` if it doesn't exist:

```bash
cp ./frontend/.env.example ./frontend/.env
```

### B3 — Patch ports, run backend and frontend setup in parallel

Port patching (editing `backend/.env` and `frontend/vite.config.mts`) can run immediately — these files already exist from B2. Do this **directly in the main conversation** before launching agents, so the agents work with the correct ports from the start.

Follow `references/alt-ports.md` **Steps 1–3 only** (verify .env, patch backend .env, patch vite config). Skip Steps 4–5 (tenant DB setup and report) — those happen in B4.

Then launch both setup agents as **background agents in parallel**:

1. **Backend agent** — "Read `<skill-path>/references/backend.md` and follow those instructions. Migration strategy already chosen: {answer}. Skip asking and use this. The .env file has already been created by the orchestrator — skip Step 3."
2. **Frontend agent** — "Read `<skill-path>/references/frontend.md` and follow those instructions. Do NOT touch backend/.env or run any backend setup. The frontend .env file has already been created by the orchestrator — skip Step 4."

Wait for both to complete before proceeding to B4.

### B4 — Set up tenant database

This must run **after** B3 because it needs `vendor/` dependencies installed by the backend agent.

Follow `references/alt-ports.md` **Steps 4–5** (register tenant in central DB, create and migrate tenant database, report).

### Completion

```
Worktree setup complete! (N={N})
  Worktree: ../<name>
  Branch:   <name> (from development)
  [x] Backend — PHP, Composer, .env, dependencies, migrations
  [x] Frontend — Node.js, dependencies, .env
  [x] Ports & tenant — patched for worktree N={N} ({3000+N} / {8000+N} / {6001+N-1}), tenant script{N}
```

Proceed to **MinIO setup** (below).

## MinIO setup (best-effort)

After all setup completes (both Mode A and Mode B), attempt to set up MinIO for local S3-compatible file storage. This is best-effort — if any step fails, print a manual reminder and continue.

Read `APP_NAME` from `backend/.env` to use as the bucket name (e.g. `kendo`).

### 1 — Install MinIO server and client

Check if `minio` and `mc` are on PATH:

```bash
which minio
which mc
```

If either is missing, install them via Scoop (Windows):

#### Check for Scoop

```bash
which scoop 2>/dev/null || powershell -Command "Get-Command scoop" 2>/dev/null
```

#### Scoop not found — install it first

Scoop requires no admin rights, making it reliable from non-elevated shells (like Claude Code):

```bash
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression"
```

Verify with `scoop --version` before continuing. If Scoop installation fails, print a manual reminder and skip the remaining MinIO steps.

#### Install MinIO packages via Scoop

```bash
scoop install minio minio-client
```

### 2 — Start MinIO server (if not already running)

Check if MinIO is already running on port 9000:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:9000/minio/health/live
```

If the health check returns `200`, MinIO is already running — skip to step 3.

If not running, start it in the background:

```bash
minio server ~/minio-data --console-address :9001 &
```

Wait a few seconds, then re-check the health endpoint. If it still doesn't respond, print a manual reminder and skip step 3.

### 3 — Create the bucket

Configure the MinIO Client alias and create the bucket:

```bash
mc alias set local http://localhost:9000 minioadmin minioadmin
mc mb local/{APP_NAME} --ignore-existing
```

Replace `{APP_NAME}` with the value from `backend/.env`.

If this succeeds, report:

```
  [x] MinIO — server running on :9000, bucket "{APP_NAME}" ready
```

### Fallback

If any MinIO step fails, print:

```
  MinIO: Could not fully automate MinIO setup. Please complete manually:
    1. Install Scoop (if needed): powershell -Command "irm get.scoop.sh | iex"
    2. Install MinIO: scoop install minio minio-client
    3. Start the server: minio server ~/minio-data --console-address :9001
    4. Create the bucket: mc alias set local http://localhost:9000 minioadmin minioadmin
                          mc mb local/{APP_NAME} --ignore-existing
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

Report the running services and their URLs to the user.
