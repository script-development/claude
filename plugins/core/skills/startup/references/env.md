# Environment File Setup

Create the backend `.env` file from `.env.example` and apply local development defaults.

## Step 1 — Copy .env.example to .env

**Always** copy `.env.example` over `.env`, even if `.env` already exists. This ensures new variables (like `SESSION_CONNECTION=tenant`) are never missing from a stale `.env` file.

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

Read `backend/.env` and set the following database variables:

- `DB_USERNAME=root`
- `DB_PASSWORD=root`

**Edit hint:** Only modify active (uncommented) lines. Never touch commented-out lines (starting with `#`). When a variable name like `DB_PASSWORD` also appears in a commented block, include enough surrounding context (e.g. the line above) to uniquely match the active one.

The multi-tenancy databases are:
- **Central**: `CENTRAL_DB_DATABASE=kendo-central` (tenant registry)
- **Tenant**: The tenant database name is resolved per-tenant from the central `tenants` table (no `DB_DATABASE` variable needed)

The `.env.example` ships with `CENTRAL_DB_DATABASE=issue-tracker-central`. Replace it with `kendo-central`.

## Step 4 — Set cache store to array

Set `CACHE_STORE=array` to avoid needing the central cache table during local development:

```
CACHE_STORE=array
```

This stores cache in-memory per request (not persisted). It avoids the "cache table not found" error that occurs with `CACHE_STORE=database` when the central database migration hasn't been run yet.

## Step 5 — Apply local AWS/MinIO block

Replace the entire AWS configuration block (all lines starting with `AWS_`) with:

```
AWS_ACCESS_KEY_ID=minioadmin
AWS_SECRET_ACCESS_KEY=minioadmin
AWS_DEFAULT_REGION=eu-central-1
AWS_BUCKET=${APP_NAME}
AWS_ENDPOINT=http://localhost:9000
AWS_URL=http://localhost:9000/${APP_NAME}
AWS_USE_PATH_STYLE_ENDPOINT=true
```

## Step 6 — Report

Print the values that were set:

- `DB_USERNAME`, `DB_PASSWORD`
- `CENTRAL_DB_DATABASE`
- `CACHE_STORE`
- AWS block (summarize)

Confirm `.env` is ready.
