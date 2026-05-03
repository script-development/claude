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

## Step 4: Check if the kendo MCP server is configured (user-scoped)

Check `~/.claude.json` for a top-level `mcpServers` entry for `kendo`.

Expected (at the root level of `~/.claude.json`):

```json
{
  "mcpServers": {
    "kendo": {
      "type": "http",
      "url": "https://script.kendo.dev/mcp/kendo"
    }
  }
}
```

- If not configured, add it:
  ```bash
  claude mcp add --scope user --transport http kendo https://script.kendo.dev/mcp/kendo
  ```

**Note**: `--scope user` makes the MCP server available for ALL projects on this PC.

## Step 5: Check if the kendo MCP server is authenticated

Try calling an MCP tool or resource from the kendo server (e.g. list projects).

- If it returns data, setup is complete.
- If it returns an auth error:
  1. The MCP server uses OAuth. The user needs to visit the auth URL provided in the error.
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
  [x] kendo MCP server configured (user-scoped) and authenticated
```
