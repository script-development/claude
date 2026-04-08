# Alternate Ports & Tenant Setup

Configure a non-primary worktree to run the development stack on alternate ports with its own tenant database alongside other worktrees.

This is called by the orchestrator with a worktree number **N** (N=2 for secondary, N=3 for tertiary, etc.). Primary (N=1) uses default ports and does not need this.

## Reference

### Port formula

| Service | Default port | Formula | N=2 | N=3 |
|---|---|---|---|---|
| Frontend (Vite) | 3000 | `3000 + N` | 3002 | 3003 |
| Backend (artisan serve) | 8000 | `8000 + N` | 8002 | 8003 |
| Reverb (WebSocket) | 6001 | `6001 + N - 1` | 6002 | 6003 |

### Tenant naming

| | Primary (N=1) | N=2 | N=3 |
|---|---|---|---|
| Subdomain | `script` | `script2` | `script3` |
| Tenant name | `Script` | `Script-2` | `Script-3` |
| Tenant database | `script` | `script-2` | `script-3` |
| Host | `script.localhost` | `script2.localhost` | `script3.localhost` |

## Step 1 — Verify backend .env exists

Check that `backend/.env` exists. If not, stop and tell the user to run backend setup first.

## Step 2 — Patch backend .env

Read `backend/.env` and update the following variables. If a variable doesn't exist yet, add it.

### Ports

| Variable | Value |
|---|---|
| `REVERB_SERVER_PORT` | `6001 + N - 1` (e.g. `6002` for N=2) |
| `REVERB_PORT` | `6001 + N - 1` (e.g. `6002` for N=2) |
| `SERVER_PORT` | `8000 + N` (e.g. `8002` for N=2) |

### Domain and URLs

Replace `script.localhost` with `script{N}.localhost` **and** `central.localhost` with `central{N}.localhost` in all occurrences:

| Variable | Value (example N=2) |
|---|---|
| `APP_URL` | `http://script2.localhost:8002` |
| `FRONTEND_URL` | `http://script2.localhost:3002` |
| `REVERB_HOST` | `script2.localhost` |
| `CORS_ALLOWED_ORIGINS` | `http://script2.localhost:3002,http://script2.localhost:8002` |
| `SANCTUM_STATEFUL_DOMAINS` | `script2.localhost:8002,script2.localhost:3002,central2.localhost:8002,central2.localhost:3002` |

Leave all other variables unchanged.

## Step 3 — Patch frontend dev server port

In `frontend/vite.config.mts`, find the `server` config object and change the `port` value from `3000` to `3000 + N`.

## Step 4 — Set up tenant database

The worktree shares the central database (`kendo-central`) with the primary worktree but gets its own tenant database.

### 4a — Register the tenant in the shared central database

Using the worktree's artisan (so it connects to the shared `kendo-central`), insert a new tenant and domain if they don't already exist.

**Important:** The `Tenant` and `Domain` models do **not** have `$fillable` set, so `firstOrCreate` / `create` will throw `MassAssignmentException`. Use manual property assignment instead:

```bash
php ./backend/artisan tinker --execute="
    \$tenant = \App\Models\Central\Tenant::where('database', 'script-{N}')->first();
    if (!\$tenant) {
        \$tenant = new \App\Models\Central\Tenant();
        \$tenant->name = 'Script-{N}';
        \$tenant->database = 'script-{N}';
        \$tenant->save();
    }
    \$domain = \App\Models\Central\Domain::where('domain', 'script{N}')->first();
    if (!\$domain) {
        \$domain = new \App\Models\Central\Domain();
        \$domain->domain = 'script{N}';
        \$domain->tenant_id = \$tenant->id;
        \$domain->save();
    }
    echo 'Tenant: ' . \$tenant->name . ' (ID: ' . \$tenant->id . '), domain: script{N}';
"
```

Replace `{N}` with the actual worktree number.

### 4b — Create and migrate the tenant database

```bash
php ./backend/artisan tenant:migrate --tenant={tenant_id}
```

Use the tenant ID returned in step 4a. This creates the `script-{N}` database and runs all tenant migrations.

### 4c — Seed the tenant database

If this is a **new tenant database** (created in 4a/4b), always seed it — a new database has no data:

```bash
php ./backend/artisan tenant:seed --tenant={tenant_id}
```

If the tenant already existed (4a found an existing record), seeding is only needed if the user
chose "Tenant migrate only" — ask whether to seed. Skip if the user chose "Full reset" (already
seeded) or "Skip" (user wants no DB changes).

## Step 5 — Report

Tell the user the worktree is configured:

| | Primary | This worktree (N={N}) |
|---|---|---|
| Frontend | 3000 | **{3000 + N}** |
| Backend | 8000 | **{8000 + N}** |
| Reverb | 6001 | **{6001 + N - 1}** |
| Tenant host | `script.localhost` | **`script{N}.localhost`** |
| Central host | `central.localhost` | **`central{N}.localhost`** |
| Tenant DB | `script` | **`script-{N}`** |
| Central DB | `kendo-central` | `kendo-central` (shared) |
