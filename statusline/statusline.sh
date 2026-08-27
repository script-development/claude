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

# Hoisted out of the ports block below so the ports display and the context advisory
# share one definition instead of two.
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BOLD='\033[1m'
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

# ── Context-reset advisory ─────────────────────────────
# Two stages: NOTICE is informational, URGE is actionable. Below NOTICE only the bare token
# count shows — no colour, no denominator. This statusline re-renders several times per tool
# call (measured: ~4), so a marker that is always on goes blind, and the threshold is only
# worth naming once it is close enough to act on.
#
# The denominator is CTX_URGE_TOKENS, printed rather than hardcoded, so a yellow
# `152k/200k` explains itself without the reader having to know the rule. It cannot drift
# from the comparison beside it: both read the same sourced variable.
#
# The thresholds are sourced, never restated here. If the file is missing (mission_control
# not checked out beside claude-dotfiles, or install.sh not re-run) the advisory does not
# render and the token count still does — degrade capability, never execution. Restating the
# numbers as a local fallback would recreate the second copy that file exists to prevent.
# Note the -n guards rather than ${CTX_*:-0}: a :-0 default would make every session
# instantly URGE if the file ever loaded empty, so this fails OPEN (never advise).
CTX_THRESHOLDS_FILE="${CTX_THRESHOLDS_FILE:-$HOME/.claude/lib/context-thresholds.sh}"
CTX_DISPLAY="ctx:$((TOKENS / 1000))k"
if [ "${TOKENS:-0}" -gt 0 ] 2>/dev/null && [ -f "$CTX_THRESHOLDS_FILE" ]; then
  . "$CTX_THRESHOLDS_FILE"
  if [ -n "$CTX_URGE_TOKENS" ] && [ "$TOKENS" -ge "$CTX_URGE_TOKENS" ]; then
    # `handoff?` names a command that actually exists now: /handoff is reachable from any
    # session through the ~/.claude/skills/handoff symlink (see mission_control's README link
    # table). It stayed `reset?` until that was true, and must go back to a blunter word if
    # that link ever goes: a statusline advertising a command the reader cannot run is worse
    # than one naming a coarser action they can.
    CTX_DISPLAY="${BOLD}${RED}ctx:$((TOKENS / 1000))k/$((CTX_URGE_TOKENS / 1000))k handoff?${RESET}"
  elif [ -n "$CTX_NOTICE_TOKENS" ] && [ "$TOKENS" -ge "$CTX_NOTICE_TOKENS" ]; then
    CTX_DISPLAY="${YELLOW}ctx:$((TOKENS / 1000))k/$((CTX_URGE_TOKENS / 1000))k${RESET}"
  fi
fi

echo -e "[$NAME:$BRANCH]${DEV_URL}${PORTS_DISPLAY} ${CTX_DISPLAY}"
