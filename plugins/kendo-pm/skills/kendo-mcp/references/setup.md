# Kendo MCP Setup

Instructions for setting up the Kendo MCP server in Claude Code.

## Contents

1. [Prerequisites](#prerequisites)
2. [Add MCP Server](#add-mcp-server)
3. [Authenticate](#authenticate)
4. [Verify Connection](#verify-connection)

---

## Prerequisites

- Access to a Kendo tenant (e.g., `yourteam.kendo.dev`)
- Claude Code CLI installed

## Add MCP Server

Run this command in your terminal, replacing the URL with your tenant:

```bash
claude mcp add kendo --transport http https://<your-tenant>.kendo.dev/mcp/kendo
```

### Scope Options

| Scope | Location | Use Case |
|-------|----------|----------|
| `--scope user` | `~/.claude.json` | Available in all projects |
| `--scope local` | `.mcp.json` in project | Project-specific only |

## Authenticate

Authentication uses **OAuth 2.1 with PKCE** (no tokens to manage manually).

1. Start a new Claude Code session — it will detect the MCP server
2. Claude Code opens your browser to the kendo authorization page
3. Log in (if not already) and click **Authorize**
4. The browser redirects back and Claude Code receives the token automatically

> **Note**: You must be logged into your Kendo tenant in your browser
> for the authorization page to work. If you're not logged in, you'll be
> redirected to the login page first.

Tokens are valid for 15 days. Refresh tokens last 30 days. Claude Code handles
token refresh automatically.

## Verify Connection

After adding, verify the MCP server is connected:

1. Start a new Claude Code session
2. Run `/mcp` to check the connection status
3. The kendo tools should be available
4. Test by asking Claude to list your projects

### Troubleshooting

| Issue | Solution |
|-------|----------|
| "Protected resource does not match" | `APP_URL` must use `https://` and trusted proxies must be configured |
| 500 on `/oauth/authorize` | Check Passport keys are configured |
| "Invalid key supplied" | Passport RSA keys missing — run `php artisan passport:keys` or set env vars |
| Browser shows login page | Log into your Kendo tenant first, then retry |
| Connection errors | Verify URL is correct and OAuth discovery endpoints work |

Test OAuth discovery:
```bash
curl https://<your-tenant>.kendo.dev/.well-known/oauth-authorization-server
curl https://<your-tenant>.kendo.dev/.well-known/oauth-protected-resource
```

Both should return JSON with `https://` URLs.

## Manual Configuration

Alternatively, add to `~/.claude.json`:

```json
{
  "mcpServers": {
    "kendo.dev": {
      "type": "http",
      "url": "https://<your-tenant>.kendo.dev/mcp/kendo"
    }
  }
}
```
