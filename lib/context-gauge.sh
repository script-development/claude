#!/bin/bash
# The context-reset gauge: one function that renders resident context size and escalates
# it into a two-stage reset advisory as the session deepens.
#
# SOURCE THIS; DO NOT COPY IT, AND DO NOT DESCRIBE IT IN PROSE. This file exists because
# there are only three ways to give the gauge to someone else and two of them are worse:
#
#   * Ship them statusline.sh. Wrong unit -- it also renders repo, branch, dev URL and
#     listening ports, which are this machine's concerns and nobody else's. A reader who
#     wants the gauge has to dissect the file, and what they extract is a fork.
#   * Tell them the rule in prose ("go yellow at 120k, red at 200k"). This invites the
#     reader to restate the numbers in their own statusline, which is the exact second copy
#     context-thresholds.sh exists to prevent -- and it is the worst kind, because it is a
#     copy in someone else's repo where our correction can never reach it.
#   * This file. A sourceable unit that carries the rendering AND reaches the thresholds by
#     reference, so a threshold correction propagates to every consumer without any of them
#     editing anything.
#
# The contract is deliberately tiny, so that a foreign statusline can adopt it in two lines:
#
#     . /path/to/context-gauge.sh
#     gauge=$(context_gauge "$resident_tokens")
#
# `context_gauge` echoes a ready-to-print segment with ANSI escapes already resolved (real
# ESC bytes, not `\033` sequences needing `echo -e`), and prints nothing else. It never
# fails, never writes to stderr, and defines no global of its own beyond the function and
# CTX_GAUGE_DIR -- a consumer's own colour and layout variables are safe.
#
# WHAT IT DOES NOT DO: obtain the token count. That is the consumer's job, because the
# source differs per caller -- a statusline reads `.context_window.total_input_tokens` from
# its stdin payload, a hook sums the last `usage` record in the transcript. Guessing here
# would tie the gauge to one of them.

# Resolved at source time, not per call: this is a hot path (the statusline re-renders
# several times per tool call -- measured ~4), and BASH_SOURCE inside the function would
# name this same file anyway.
#
# Resolved from `dirname ${BASH_SOURCE[0]}` WITHOUT readlinking, and reaching the thresholds
# at the nested `context-economy/` subpath -- the same resolution verify-handoff.sh uses, for
# the same reason. Through the install symlink that dirname is ~/.claude/lib, where the
# installer's mirror has recreated the nested subpath verbatim; in the repo it is
# plugins/context-economy/lib. One expression, correct from both, no readlink and no
# checkout-path derivation. Do not "simplify" it to $HOME/.claude/lib: that would work only
# installed, and the test suite would then be testing the installed copy rather than the
# file under review.
CTX_GAUGE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

context_gauge() {
  local tokens=${1:-0}

  # Colours are function-locals, not globals, and are duplicated from statusline.sh rather
  # than shared with it. That duplication is deliberate and is the opposite of the
  # thresholds rule: `\033[31m` is red on every terminal ever built and cannot drift or go
  # stale, whereas 200000 is a research finding that can. What CAN break is a consumer that
  # sources this file and happens to render its own output with a variable named RED, so
  # self-containment wins here and hoisting does not.
  local yellow=$'\033[33m' red=$'\033[31m' bold=$'\033[1m' reset=$'\033[0m'

  # A non-numeric or empty count renders as 0k rather than erroring. The gauge is called
  # from display paths where a crash costs the caller its whole line, so every bad input has
  # to have a rendering -- and 0k with no advisory is the honest one, because an unreadable
  # count is not evidence of a deep session.
  case $tokens in '' | *[!0-9]*) tokens=0 ;; esac

  # Below NOTICE only the bare count shows -- no colour, no denominator. A marker that is
  # always on goes blind at ~4 renders per tool call, and the threshold is only worth naming
  # once it is close enough to act on.
  local plain="ctx:$((tokens / 1000))k"

  # Sourced, never restated. If the file is missing the advisory does not render and the
  # count still does -- degrade capability, never execution. Restating the numbers as a
  # local fallback would recreate the second copy that file exists to prevent.
  local thresholds="${CTX_THRESHOLDS_FILE:-$CTX_GAUGE_DIR/context-economy/context-thresholds.sh}"
  if [ "$tokens" -le 0 ] || [ ! -f "$thresholds" ]; then
    printf '%s' "$plain"
    return 0
  fi

  # In a subshell so a garbage thresholds file cannot leak assignments into the caller, and
  # so `set -e` / `exit` inside it cannot escape into a consumer's statusline.
  #
  # The result is captured rather than printed straight out, and falls back to the plain count
  # if it comes back EMPTY. Empty is what an `exit` or a syntax error in the sourced file
  # produces -- the subshell dies before reaching any printf -- and a consumer that interpolated
  # that would show a blank where its context figure belongs, with nothing to say why. The
  # fallback turns that into the same degradation as a missing file: advisory gone, count kept.
  # It cannot mask a real rendering, because every branch below prints a non-empty string.
  local rendered
  rendered=$(
    . "$thresholds" 2>/dev/null || true

    # Note the -n guards rather than ${CTX_*:-0}: a :-0 default would make every session
    # instantly URGE if the file ever loaded empty, so this fails OPEN (never advise).
    #
    # BOTH stages guard CTX_URGE_TOKENS, including NOTICE, because NOTICE *prints* it as the
    # denominator. Guarding only CTX_NOTICE_TOKENS there -- as the pre-extraction statusline
    # did -- would render `ctx:152k/0k` from a file that defined one constant and not the
    # other, which reads as a threshold of zero rather than as an absent one.
    if [ -z "${CTX_URGE_TOKENS:-}" ]; then
      printf '%s' "$plain"
    elif [ "$tokens" -ge "$CTX_URGE_TOKENS" ]; then
      # `handoff?` names a command that actually exists: /handoff is reachable from any
      # session because this bundle ships the skill -- as a plugin, through its own skills/
      # directory; under a symlink install, through ~/.claude/skills/handoff. It stayed
      # `reset?` until that was true, and must go back to a blunter word if BOTH of those
      # ever go: a statusline advertising a command the reader cannot run is worse than one
      # naming a coarser action they can.
      printf '%s' "${bold}${red}ctx:$((tokens / 1000))k/$((CTX_URGE_TOKENS / 1000))k handoff?${reset}"
    elif [ -n "${CTX_NOTICE_TOKENS:-}" ] && [ "$tokens" -ge "$CTX_NOTICE_TOKENS" ]; then
      # The denominator is CTX_URGE_TOKENS, printed rather than hardcoded, so a yellow
      # `152k/200k` explains itself without the reader having to know the rule. It cannot
      # drift from the comparison beside it: both read the same sourced variable.
      printf '%s' "${yellow}ctx:$((tokens / 1000))k/$((CTX_URGE_TOKENS / 1000))k${reset}"
    else
      printf '%s' "$plain"
    fi
  )
  printf '%s' "${rendered:-$plain}"
}
