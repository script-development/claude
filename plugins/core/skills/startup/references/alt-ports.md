# Alternate Ports & Tenant Setup

Configure a non-primary worktree to run the development stack on alternate ports alongside other worktrees.

This is called by the orchestrator with a worktree number **N** (N=2 for secondary, N=3 for tertiary, etc.). Primary (N=1) uses default ports and does not need this.

## Reference

### Port formula

| Service | Default port | Formula | N=2 | N=3 |
|---|---|---|---|---|
| Frontend (Vite) | 3000 | `3000 + N` | 3002 | 3003 |
| Backend (artisan serve) | 8000 | `8000 + N` | 8002 | 8003 |
| Reverb (WebSocket) | 6001 | `6001 + N - 1` | 6002 | 6003 |

### Tenant naming (multi-tenancy only)

**Skip the entire tenant section** if the project doesn't use `stancl/tenancy` (check `backend/composer.json`).

Let `<app>` be `APP_NAME` from `backend/.env`, lowercased and slugified. Then:

| | Primary (N=1) | N=2 | N=3 |
|---|---|---|---|
| Subdomain | `<app>` | `<app>2` | `<app>3` |
| Tenant name | `<App>` (titlecase) | `<App>-2` | `<App>-3` |
| Tenant database | `<app>` | `<app>-2` | `<app>-3` |
| Tenant host | `<app>.localhost` | `<app>2.localhost` | `<app>3.localhost` |
| Central host | project default (e.g. `<central>.localhost`) | `<central>2.localhost` | `<central>3.localhost` |

Confirm the actual subdomain, host, and DB-naming conventions in the project's `CLAUDE.md` — some projects may differ.

## Step 1 — Verify backend .env exists

Check that `backend/.env` exists. If not, stop and tell the user to run backend setup first.

## Step 2 — Patch backend .env

Read `backend/.env` and update the following variables. If a variable doesn't exist yet, add it.

### Ports (always)

| Variable | Value |
|---|---|
| `REVERB_SERVER_PORT` | `6001 + N - 1` (e.g. `6002` for N=2) |
| `REVERB_PORT` | `6001 + N - 1` (e.g. `6002` for N=2) |
| `SERVER_PORT` | `8000 + N` (e.g. `8002` for N=2) |

`REVERB_*` only applies if the project uses Laravel Reverb — skip those keys if it doesn't.

### Domain and URLs

Replace the primary tenant subdomain with the worktree-suffixed variant in all occurrences. The exact tokens depend on the project — typically:

- `<app>.localhost` → `<app>{N}.localhost`
- `<central>.localhost` → `<central>{N}.localhost` (multi-tenancy projects with a central host — the central hostname is project-specific; check the project's `CLAUDE.md`)

| Variable | Value (example, N=2, `APP_NAME=Acme`) |
|---|---|
| `APP_URL` | `http://acme2.localhost:8002` |
| `FRONTEND_URL` | `http://acme2.localhost:3002` |
| `REVERB_HOST` | `acme2.localhost` |
| `CORS_ALLOWED_ORIGINS` | `http://acme2.localhost:3002,http://acme2.localhost:8002` |
| `SANCTUM_STATEFUL_DOMAINS` | `acme2.localhost:8002,acme2.localhost:3002,central2.localhost:8002,central2.localhost:3002` |

Leave all other variables unchanged.

## Step 3 — Patch frontend dev server port

In `frontend/vite.config.mts` (or `vite.config.ts` / `vite.config.js`), find the `server` config object and change the `port` value from `3000` to `3000 + N`.

## Step 4 — Set up tenant database

**Skip this entire step** if the project doesn't use `stancl/tenancy` multi-tenancy.

The worktree shares the central database with the primary worktree but gets its own tenant database.

### 4a — Register the tenant in the shared central database

Using the worktree's artisan (so it connects to the shared central DB), insert a new tenant and domain if they don't already exist.

The exact model paths and fields depend on the project — check `backend/app/Models/` for the `Tenant` and `Domain` models, and the project's `CLAUDE.md` for the canonical tenant-creation snippet. Most `stancl/tenancy` projects have models without `$fillable` set, so `firstOrCreate` / `create` will throw `MassAssignmentException` — use **manual property assignment** instead.

Example template (adjust namespaces to match the project — `App\Models\Central\Tenant`, `App\Models\Tenant`, etc., based on what exists):

```bash
php ./backend/artisan tinker --execute="
    \$tenant = \App\Models\Central\Tenant::where('database', '<app>-{N}')->first();
    if (!\$tenant) {
        \$tenant = new \App\Models\Central\Tenant();
        \$tenant->name = '<App>-{N}';
        \$tenant->database = '<app>-{N}';
        \$tenant->save();
    }
    \$domain = \App\Models\Central\Domain::where('domain', '<app>{N}')->first();
    if (!\$domain) {
        \$domain = new \App\Models\Central\Domain();
        \$domain->domain = '<app>{N}';
        \$domain->tenant_id = \$tenant->id;
        \$domain->save();
    }
    echo 'Tenant: ' . \$tenant->name . ' (ID: ' . \$tenant->id . '), domain: <app>{N}';
"
```

Replace `<app>` with the lowercased `APP_NAME`, `<App>` with the titlecased version, and `{N}` with the actual worktree number.

### 4b — Create and migrate the tenant database

```bash
php ./backend/artisan tenant:migrate --tenant={tenant_id}
```

Use the tenant ID returned in step 4a. This creates the `<app>-{N}` database and runs all tenant migrations.

### 4c — Seed the tenant database

If this is a **new tenant database** (created in 4a/4b), always seed it — a new database has no data:

```bash
php ./backend/artisan tenant:seed --tenant={tenant_id}
```

If the tenant already existed (4a found an existing record), seeding is only needed if the user
chose "Migrate only" — ask whether to seed. Skip if the user chose "Full reset" (already
seeded) or "Skip" (user wants no DB changes).

## Step 5 — Report

Tell the user the worktree is configured. Use the project's actual `<app>` placeholder (from `APP_NAME`) when filling in the table:

| | Primary | This worktree (N={N}) |
|---|---|---|
| Frontend | 3000 | **{3000 + N}** |
| Backend | 8000 | **{8000 + N}** |
| Reverb | 6001 | **{6001 + N - 1}** |
| Tenant host (multi-tenancy) | `<app>.localhost` | **`<app>{N}.localhost`** |
| Central host (multi-tenancy) | project default | **`<central>{N}.localhost`** |
| Tenant DB (multi-tenancy) | `<app>` | **`<app>-{N}`** |
| Central DB (multi-tenancy) | `<app>-central` | `<app>-central` (shared) |

Omit the multi-tenancy rows for projects that don't use `stancl/tenancy`.
