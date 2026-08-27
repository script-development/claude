#!/bin/bash
input=$(cat)

WT_NAME=$(echo "$input" | jq -r '.worktree.name // empty')
WT_BRANCH=$(echo "$input" | jq -r '.worktree.branch // empty')
# Resident context size in tokens — the only context figure shown. Despite the name,
# `total_input_tokens` is the CURRENT context, not a running total: it equals the sum of
# .current_usage's input components.
#
# `used_percentage` is deliberately NOT shown. It is denominated in `context_window_size`,
# so it measures distance to AUTO-COMPACTION — the ~1M ceiling this whole advisory exists to
# stop relying on. On a 1M window a session at the 200k reset threshold reads `20%`, which
# invites exactly the wrong conclusion at exactly the wrong depth. It is also an integer, so
# its granularity is 10k tokens per point. Tokens are the honest unit for both the threshold
# and the display.
TOKENS=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0' | cut -d. -f1)

# Used by the ports display only. The context gauge carries its own colours as function
# locals (see lib/context-gauge.sh): it has to render on a machine whose statusline defines
# none of these, and self-containment there is worth more than sharing an ANSI literal here.
GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

# Use worktree fields if available, otherwise derive from git
if [ -n "$WT_NAME" ]; then
  NAME="$WT_NAME"
  BRANCH="$WT_BRANCH"
else
  NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-branch")
fi

# Read dev server URL and ports from backend/.env if it exists
DEV_URL=""
PORTS_DISPLAY=""
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/backend/.env" ]; then
  ENV_FILE="$REPO_ROOT/backend/.env"

  # Extract APP_URL for display
  APP_URL=$(grep -m1 '^APP_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
  if [ -n "$APP_URL" ]; then
    DEV_URL="${APP_URL#http://}"
    DEV_URL="${DEV_URL#https://}"
    DEV_URL=" ${DEV_URL%/}"
  fi

  # Extract configured ports
  PORTS=()

  # Backend port from APP_URL
  BACKEND_PORT=$(echo "$APP_URL" | grep -oE ':[0-9]+' | tail -1 | tr -d ':')
  [ -n "$BACKEND_PORT" ] && PORTS+=("$BACKEND_PORT")

  # Frontend port from FRONTEND_URL
  FRONTEND_URL=$(grep -m1 '^FRONTEND_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
  FRONTEND_PORT=$(echo "$FRONTEND_URL" | grep -oE ':[0-9]+' | tail -1 | tr -d ':')
  [ -n "$FRONTEND_PORT" ] && PORTS+=("$FRONTEND_PORT")

  # Reverb port
  REVERB_PORT=$(grep -m1 '^REVERB_SERVER_PORT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
  [ -n "$REVERB_PORT" ] && PORTS+=("$REVERB_PORT")

  # MinIO port from AWS_ENDPOINT
  AWS_ENDPOINT=$(grep -m1 '^AWS_ENDPOINT=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
  MINIO_PORT=$(echo "$AWS_ENDPOINT" | grep -oE ':[0-9]+' | tail -1 | tr -d ':')
  [ -n "$MINIO_PORT" ] && PORTS+=("$MINIO_PORT")

  # Check which ports are actually listening
  if [ ${#PORTS[@]} -gt 0 ]; then
    LISTENING=$(netstat -ano 2>/dev/null | grep LISTENING)
    PORT_ITEMS=()
    for port in "${PORTS[@]}"; do
      if echo "$LISTENING" | grep -q ":${port} "; then
        PORT_ITEMS+=("${GREEN}${port}${RESET}")
      else
        PORT_ITEMS+=("${RED}${port}${RESET}")
      fi
    done
    PORTS_DISPLAY=" $(IFS=,; echo "${PORT_ITEMS[*]}")"
  fi
fi

# ── Context-reset advisory ──────────────────────
# Rendered by the gauge, sourced rather than reimplemented. This statusline is one CONSUMER
# of the gauge, not its owner: the two-stage rule, the thresholds it reads and the wording of
# the advisory all live in lib/context-gauge.sh, so a second statusline -- on another machine,
# in another repo -- gets the same gauge by sourcing one file instead of copying this block.
# What stays here is only what is genuinely this statusline's: where the token count comes
# from, and where in the line the segment goes.
#
# Located at ~/.claude/lib rather than relative to this script because neither relative path
# works from both places: installed, this file sits at ~/.claude/statusline.sh (so ../lib is
# wrong); in the repo it sits at plugins/context-economy/statusline/ (so ./lib is wrong). The
# override exists so the test suite can exercise the repo's copy rather than the installed one.
#
# A missing gauge silences the whole segment rather than falling back to a bare count. That is
# deliberate: a local fallback would be a second rendering of the gauge, which is the thing
# this extraction removed. It fails loudly rather than silently -- install.sh lists
# context-gauge.sh among its required libs and reports it MISSING.
CTX_GAUGE_FILE="${CTX_GAUGE_FILE:-$HOME/.claude/lib/context-gauge.sh}"
CTX_DISPLAY=""
if [ -f "$CTX_GAUGE_FILE" ]; then
  . "$CTX_GAUGE_FILE"
  CTX_DISPLAY=$(context_gauge "$TOKENS")
fi

echo -e "[$NAME:$BRANCH]${DEV_URL}${PORTS_DISPLAY}${CTX_DISPLAY:+ $CTX_DISPLAY}"
