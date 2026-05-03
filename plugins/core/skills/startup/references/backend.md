# Backend Setup

Walk through each check below **in order**, one at a time.
After each step, confirm it passed before moving on. If a step fails, fix it before continuing.

All commands should be run from the `./backend` directory.

Use `AskUserQuestion` whenever user interaction is needed.

## Step 1: Verify PHP is installed and on PATH

```bash
php --version
```

- If not installed:
  - **Windows**: `scoop install php` or download from https://windows.php.net/download
  - **macOS**: `brew install php`
  - **Linux**: `sudo apt install php` (Debian/Ubuntu) or equivalent
- Verify the version meets the project's requirement in `backend/composer.json` (`require.php`). If outdated, advise the user to upgrade.
- Confirm `php` resolves to the latest installed version (not an old one shadowed on PATH):
  ```bash
  which php
  ```
- Verify `php.ini` has no outdated or problematic settings:
  ```bash
  php --ini
  ```
  Then read the loaded `php.ini` and check that:
  - Common Laravel extensions are enabled: `openssl`, `pdo`, `mbstring`, `tokenizer`, `xml`, `ctype`, `json`, `bcmath`, `curl`, `fileinfo`
  - `memory_limit` is at least `256M`
  - There are no deprecated settings for the current PHP version
  - If any extensions are missing, advise the user how to enable them in `php.ini`.

## Step 2: Verify Composer is installed globally

```bash
composer --version
```

- If not installed:
  - **Windows**: `scoop install composer` or download from https://getcomposer.org/download/
  - **macOS**: `brew install composer`
  - **Linux**: Follow https://getcomposer.org/download/ (global install)
- Confirm `composer` is callable globally (not just a local `composer.phar`).
- Verify Composer version is **2.x**.

## Step 3: Set up .env and verify APP_KEY

Check if `backend/.env` already exists:

```bash
ls ./backend/.env
```

- **If it exists**: Print "`.env` already exists — skipping creation." The orchestrator creates `.env` before launching background agents.
- **If it does not exist**: Follow the env setup instructions (copy `.env.example` to `.env` and apply local defaults). Wait for it to complete before continuing.

Then verify `APP_KEY` is set (required before `composer install` — its post-install hook bootstraps the app):

```bash
grep '^APP_KEY=base64:' ./backend/.env
```

- If the key is present, continue to Step 4.
- If `APP_KEY` is empty or missing, follow Step 2 of the [env setup instructions](env.md) to generate it.

## Step 4: Install dependencies

```bash
composer install --working-dir=./backend
```

- If this fails, read the error output carefully. Common issues:
  - Missing PHP extensions — go back to Step 1 and enable them.
  - Platform requirements — may need `--ignore-platform-reqs` as a last resort, but prefer fixing the platform.
- Verify it completes successfully.

## Step 5: Generate Passport keys (conditional)

**Skip if** the project doesn't use Laravel Passport. Detect by checking `backend/composer.json` for `laravel/passport`:

```bash
grep -q 'laravel/passport' ./backend/composer.json && echo "passport" || echo "no passport"
```

If Passport is in use:

```bash
php ./backend/artisan passport:keys
```

- This generates the OAuth encryption keys needed by Laravel Passport.
- Confirm the keys are created successfully.

## Step 6: Run migrations and seed the database

If the migration strategy was **already provided** by the orchestrator (passed as context when this agent was launched), use that choice directly. Otherwise, use `AskUserQuestion` to ask:

> **How should the database be set up?**
>
> - **Full reset** — Drop the database, recreate, migrate, and seed. Use for a clean start.
> - **Migrate only** — Run pending migrations without dropping data. Use when the schema needs updating but data should be preserved.
> - **Skip** — Don't touch the database. Use when everything is already up to date.

Pick the right command based on project conventions:

### Default (generic Laravel)

- **Full reset**: `php ./backend/artisan migrate:fresh --seed`
- **Migrate only**: `php ./backend/artisan migrate`
- **Skip**: Do nothing, proceed to Completion.

### Project override (custom dev-reset)

If the project defines a custom artisan command for dev resets (commonly `dev:reset`), use it instead — it usually wraps central + tenant database setup. Detect by:

```bash
php ./backend/artisan list | grep -E '^\s*dev:reset'
```

If present:

- **Full reset**: `php ./backend/artisan dev:reset --force` (or whatever the project documents in its `CLAUDE.md`)
- **Migrate only**: `php ./backend/artisan migrate` plus `php ./backend/artisan tenant:migrate` if multi-tenancy is in use

### Multi-tenancy override

If the project uses `stancl/tenancy`, "Migrate only" should also run tenant migrations:

```bash
php ./backend/artisan tenant:migrate
```

If migrations fail due to database connection issues, check that the database configured in `./backend/.env` is running and accessible.
Ask the user to verify their database credentials if needed.
Confirm migrations complete successfully (or were skipped).

## Completion

Once all steps pass, print a summary:

```
Backend setup complete!
  [x] PHP installed and up-to-date (per composer.json)
  [x] php.ini verified — extensions enabled, no deprecated settings
  [x] Composer installed globally (2.x)
  [x] .env file present with APP_KEY set
  [x] Dependencies installed (composer install)
  [x] Passport keys generated (if applicable)
  [x] Database migrated and seeded (or skipped)
```
