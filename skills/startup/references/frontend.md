# Frontend Setup

Walk through each check below **in order**, one at a time.
After each step, confirm it passed before moving on. If a step fails, fix it before continuing.

All commands should be run from the `./frontend` directory.

Use `AskUserQuestion` whenever user interaction is needed.

## Step 1: Verify the frontend directory exists

```bash
ls ./frontend/package.json
```

- If the directory or `package.json` does not exist, stop and ask the user to confirm the correct project path.

## Step 2: Verify Node.js is installed and on PATH

```bash
node --version
```

- If not installed:
  - **Windows**: `scoop install nodejs` or download from https://nodejs.org/
  - **macOS**: `brew install node`
  - **Linux**: `sudo apt install nodejs` (Debian/Ubuntu) or use https://github.com/nodesource/distributions
- Verify the version is **18 or higher**. If outdated, advise the user to upgrade.
- Confirm `node` resolves correctly:
  ```bash
  which node
  ```

## Step 3: Install dependencies

```bash
npm install --prefix ./frontend
```

- If this fails, read the error output carefully. Common issues:
  - Node version too old — go back to Step 2.
  - Network issues — ask the user to check their connection or proxy settings.
  - Permission errors — advise running from a normal (non-admin) shell.
- Verify it completes successfully.

## Step 4: Copy .env

If `frontend/.env` does not exist, copy it from the example:

```bash
cp ./frontend/.env.example ./frontend/.env
```

If `frontend/.env` already exists, skip this step.

## Completion

Once all steps pass, print a summary:

```
Frontend setup complete!
  [x] frontend/package.json found
  [x] Node.js installed and up-to-date (18+)
  [x] Dependencies installed (npm install)
  [x] .env file present
```
