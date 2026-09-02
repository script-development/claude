# Environment File Setup

Create the backend `.env` file from `.env.example` and apply local development defaults.

## Step 1 — Copy .env.example to .env

**Always** copy `.env.example` over `.env`, even if `.env` already exists. This ensures any new variables added to `.env.example` are never missing from a stale `.env` file.

```bash
cp ./backend/.env.example ./backend/.env
```

## Step 2 — Generate APP_KEY

Laravel needs `APP_KEY` set **before** `composer install` runs, because the post-install hook (`package:discover`) bootstraps the app. Generate one now using `openssl`, the same approach CI uses:

```bash
sed -i "s|^APP_KEY=$|APP_KEY=base64:$(openssl rand -base64 32)|" ./backend/.env
```

Verify the key was set:

```bash
grep '^APP_KEY=' ./backend/.env
```

- The value should start with `base64:` followed by a 44-character string.
- If `openssl` is not available, use `php -r "echo 'base64:' . base64_encode(random_bytes(32));"` to generate the value and set it manually.

## Step 3 — Apply local database defaults

Read `backend/.env` and set the following database variables to local-friendly values:

- `DB_USERNAME=root`
- `DB_PASSWORD=root`

**Edit hint:** Only modify active (uncommented) lines. Never touch commented-out lines (starting with `#`). When a variable name like `DB_PASSWORD` also appears in a commented block, include enough surrounding context (e.g. the line above) to uniquely match the active one.

### Multi-tenancy (conditional)

**Skip this sub-step if** the project doesn't use multi-tenancy (no `stancl/tenancy` in `backend/composer.json`).

Multi-tenant projects typically have:

- **Central database**: a single registry database — variable name is project-specific (commonly `CENTRAL_DB_DATABASE` or `DB_DATABASE`). Default it to `<app>-central` where `<app>` is `APP_NAME` lowercased/slugified.
- **Tenant databases**: usually resolved per-tenant from the central `tenants` table — no static `DB_DATABASE` variable needed.

If `.env.example` ships with a placeholder value for the central DB (e.g. `<something>-central`), replace it with `<app>-central` derived from this project's `APP_NAME`. Check the project's `CLAUDE.md` if you're unsure which variable controls the central DB.

## Step 4 — Set cache store to array

Set `CACHE_STORE=array` to avoid needing a cache table during local development:

```
CACHE_STORE=array
```

This stores cache in-memory per request (not persisted). It avoids "cache table not found" errors that occur with `CACHE_STORE=database` when migrations haven't been run yet — particularly useful in multi-tenant projects where the central cache table may not exist on first boot.

## Step 5 — Apply local AWS/MinIO block

Replace the entire AWS configuration block (all lines starting with `AWS_`) with the local MinIO defaults. The access key and secret must match the `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` values the `minio` service sets in the project's `docker-compose.yml` — read them from there, do not assume:

```
AWS_ACCESS_KEY_ID=<MINIO_ROOT_USER from docker-compose.yml>
AWS_SECRET_ACCESS_KEY=<MINIO_ROOT_PASSWORD from docker-compose.yml>
AWS_DEFAULT_REGION=eu-central-1
AWS_BUCKET=${APP_NAME}
AWS_ENDPOINT=http://localhost:9000
AWS_URL=http://localhost:9000/${APP_NAME}
AWS_USE_PATH_STYLE_ENDPOINT=true
```

`${APP_NAME}` is interpolated by Laravel at runtime from the same `.env` file, so the bucket name automatically matches the app.

## Step 6 — Report

Print the values that were set:

- `DB_USERNAME`, `DB_PASSWORD`
- Central DB variable (if multi-tenancy)
- `CACHE_STORE`
- AWS block (summarize)

Confirm `.env` is ready.
