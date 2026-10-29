<!--
Browser reference template. Copy to `.claude/references/browser.md` in the consuming project
(or any path in the repo), fill in every section, and name the file in
`.claude/project-context.md` under `references.browser`. A project that holds checked-in
catalog skills names the same file wherever its copy of `/pr` reads `{{BROWSER_REFERENCE}}`.

Read by: pr (step 5, Screenshots). A skill that finds no browser reference takes no screenshot
and says so in the PR body; it never guesses a URL or an account.

Canonical source: templates/browser-reference-template.md in the claude-2 catalog. core-skills
ships an identical mirror at plugins/core-skills/references/browser-reference-template.md, since
an installed plugin's consumer never clones this catalog repo. The mirror is generated —
.githooks/pre-commit copies this file over it whenever this file changes. Edit only this copy;
never hand-edit a shipped mirror. Delete this comment block in the project's own copy.
-->

# Browser reference

How a session opens this project's running local app, logs in, and knows what it is looking at.
Write only what you verified on a local stack, with the source line each value comes from: a
seeder line or an `.env` key. A value without its source goes stale silently, and a session
follows it anyway.

**Local accounts only.** Every URL here is `localhost`, `*.localhost` or `127.0.0.1`, and every
account is one the local seeders create. No staging, demo or production URL, account, password
or 2FA secret belongs in this file: it is checked into the repo, and every session that reads it
acts on it.

## URL

- The local URL of each app, and where it comes from (e.g. `APP_URL` in `backend/.env`:
  `http://localhost:8000`).
- Which port to open when there are two (the backend that serves the pages, or the dev server).
- How a second checkout's port differs, if it does (e.g. a worktree writes its own port into its
  `.env`). Leave this out when every checkout serves the same URL.
- How to tell the app is up: a text the start page shows, or a status code.

## Login

- The login page's path (e.g. `/login`).
- What a successful login shows: the page it lands on, and a text to wait for there.
- What a failed login shows, so a session can tell a wrong password from a page that never
  loaded.

## Accounts

One row per role a screen can need. Each password is the seeded local one.

| Role | App | Email | Password | Source |
|---|---|---|---|---|
| <role> | <app> | <email> | <password> | `<seeder file>:<line>`, or the `.env` key that overrides it |

When the seeders make the accounts from a factory or an `.env` key rather than fixed values, name
that file and key instead of a row per account.

## 2FA

Leave this section out when no local account is asked for a code. Otherwise:

- Which accounts the app asks for a code, and the setting or role that decides it.
- The command that prints the current code for a local account. It computes the code from the
  secret in the local database and prints only the code, never the secret, with no change to the
  app's own code. For a Laravel app on `pragmarx/google2fa`, for example:

  ```bash
  php artisan tinker --execute='echo app(PragmaRX\Google2FA\Google2FA::class)->getCurrentOtp(App\Models\User::where("email", "<email>")->first()->two_factor_secret);'
  ```

  Read the secret through the model, so its cast decrypts it. Run the command just before typing
  the code: a code lives about 30 seconds, and an app with a replay guard refuses one that was
  already used.
- What the app shows when an account has no secret yet (a setup screen). A session stops there
  and never enrolls a key: that leaves a key in the database that no phone holds.

The code stays in the session that typed it: never in a commit, a PR body or a comment.

## What the local stack cannot show

The features that fail or look different locally, each with the reason, so a session reports a
local gap instead of a defect:

- <feature>: <why> (e.g. file uploads: no S3 on a local stack).
- Console errors that are expected (e.g. a `401` from the session probe before login).
- Data the seeders do not make, so a screen shows empty.
