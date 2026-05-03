# MCP Setup

Walk through each check below **in order**, one at a time.
After each step, confirm it passed before moving on. If a step fails, fix it before continuing.

Use `AskUserQuestion` whenever user interaction is needed (e.g. authentication flows).

## Step 1: Check if `gh` (GitHub CLI) is installed and authenticated

```bash
gh --version
gh auth status
```

- If not installed:
  - **Windows**: `winget install --id GitHub.cli`
  - **macOS**: `brew install gh`
  - **Linux**: Follow https://github.com/cli/cli/blob/trunk/docs/install_linux.md
- If not authenticated, run `gh auth login` and ask the user to complete the browser-based auth flow.
- Verify both pass before continuing.

## Step 2: Check if Scoop is installed (Windows only)

Skip this step on macOS/Linux.

```bash
scoop --version
```

- If not installed, install it:
  ```bash
  powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression"
  ```
- Verify with `scoop --version` before continuing.

## Step 3: Check if `claude` CLI is installed

```bash
claude --version
```

- If not found, install it:
  - **Windows**: `scoop install claude-code` (preferred) or `npm install -g @anthropic-ai/claude-code`
  - **macOS/Linux**: `npm install -g @anthropic-ai/claude-code`
- If not on PATH, check `npm config get prefix` and advise accordingly.
- Verify it works before continuing.

## Step 4: Configure project-specific MCP servers (conditional)

**Skip if** the project doesn't define any MCP servers.

Check the project's documentation for MCP server configuration:

1. **`.mcp.json`** at the project root — project-scoped MCP server definitions.
2. **The project's `CLAUDE.md`** — usually documents which MCP servers to add and the URLs / auth flows.

If the project documents one or more MCP servers, register each user-scoped (so they're available across all worktrees):

```bash
claude mcp add --scope user --transport <transport> <name> <url>
```

Replace `<transport>`, `<name>`, and `<url>` with the values from the project's docs.

**Note**: `--scope user` makes the MCP server available for ALL projects on this PC.

## Step 5: Verify project MCP servers are authenticated

**Skip if** no project MCP servers were configured in Step 4.

For each project MCP server, try calling a simple tool or resource.

- If it returns data, setup is complete.
- If it returns an auth error (typically OAuth-based):
  1. Surface the auth URL provided in the error.
  2. Ask the user to complete authentication in their browser.
  3. Re-test the MCP connection after they confirm.

**Note**: MCP authentication is per-PC. Once authenticated, it works for all repositories.

## Completion

Once all steps pass, print a summary:

```
MCP setup complete!
  [x] gh CLI installed and authenticated
  [x] Scoop package manager installed (Windows)
  [x] claude CLI installed and on PATH
  [x] Project MCP servers configured and authenticated (if any)
```
