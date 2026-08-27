#!/bin/bash
# Tests for statusline.sh's context segment -- its WIRING, not the gauge's rule.
#
# WHAT MOVED AND WHY. The threshold boundaries, the colour stages, the fail-open behaviour of a
# missing or garbage thresholds file: all of that is now lib/context-gauge.test.sh, asserted
# against the gauge directly. It used to be here because there was nowhere else to put it, which
# meant every boundary case paid for a whole statusline run -- a JSON payload in, a real git tree
# and a netstat call along the way, and a sed to cut the segment back out -- to assert something
# about a comparison. Duplicating those cases on both sides now would be worse than either place
# alone, because the copy nobody remembers to update is the one that drifts.
#
# WHAT REMAINS IS WHAT THE GAUGE CANNOT SEE, and each of these has failed in real life:
#   * that the segment reaches the rendered line at all, with its escapes intact and in the
#     right position -- a `$(...)` that silently returned nothing would pass every gauge test;
#   * that the token count is read from the right payload field, and that a payload without it
#     yields 0k rather than a reconstruction;
#   * that a missing gauge degrades the line instead of breaking it.
#
# Only the trailing ctx segment is matched: the rest of the statusline reads the real git tree
# and real listening ports, so it is environment-dependent by design.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.sh"

# Both resolved inside the repo, not under ~/.claude. The suite used to point at the installed
# ~/.claude/lib/context-thresholds.sh and SKIP-ALL when it was absent, which meant it tested the
# installed copy rather than the files under review and silently tested nothing on a machine
# where install.sh had not run. The bundle carries both, so neither indirection is needed.
GAUGE="$SCRIPT_DIR/../lib/context-gauge.sh"
THRESHOLDS="$SCRIPT_DIR/../lib/context-economy/context-thresholds.sh"

PASS=0
FAIL=0

# A minimal payload. Only context_window matters; the rest is present because statusline.sh
# reads it, not because these tests care about it.
payload() {
  printf '{"context_window":{"total_input_tokens":%s,"context_window_size":1000000},"workspace":{}}' "$1"
}

statusline() {
  local tokens="$1" gauge="${2-$GAUGE}"
  payload "$tokens" \
    | CTX_GAUGE_FILE="$gauge" CTX_THRESHOLDS_FILE="$THRESHOLDS" bash "$STATUSLINE" 2>/dev/null
}

# Run the statusline and return only the ctx segment, escapes made visible so a colour
# regression is an assertable string rather than an invisible one.
ctx_segment() {
  statusline "$@" \
    | sed 's/.*[] ]\(\(\x1b\[[0-9;]*m\)*ctx:\)/\1/' \
    | sed 's/\x1b\[1m/<BOLD>/g; s/\x1b\[31m/<RED>/g; s/\x1b\[33m/<YELLOW>/g; s/\x1b\[0m/<RESET>/g'
}

assert_ctx() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n      expected: %s\n      actual:   %s\n' "$desc" "$expected" "$actual"
  fi
}

[ -f "$GAUGE" ] || { echo "FAIL: gauge not found at $GAUGE"; exit 1; }
[ -f "$THRESHOLDS" ] || { echo "FAIL: thresholds not found at $THRESHOLDS"; exit 1; }

# Confirm the thresholds really are the 120k/200k pair, so a threshold change breaks a test
# rather than silently rewriting what the three wiring cases below mean.
( . "$THRESHOLDS"
  [ "$CTX_NOTICE_TOKENS" = "120000" ] || { echo "FAIL: CTX_NOTICE_TOKENS is $CTX_NOTICE_TOKENS, tests assume 120000"; exit 1; }
  [ "$CTX_URGE_TOKENS" = "200000" ]   || { echo "FAIL: CTX_URGE_TOKENS is $CTX_URGE_TOKENS, tests assume 200000"; exit 1; }
) || exit 1

# ── One case per stage, to prove the segment is actually rendered ──
# Not a boundary sweep -- that is the gauge's suite. These three exist because the escapes and
# the plain form travel different paths out of this file: the segment is interpolated into an
# `echo -e` line whose other fields still carry unresolved `\033` sequences, so a stage that
# renders correctly in the gauge can still arrive mangled here.
assert_ctx "below notice reaches the line bare"   "ctx:72k"                                  "$(ctx_segment 72346)"
assert_ctx "notice reaches the line yellow"       "<YELLOW>ctx:152k/200k<RESET>"              "$(ctx_segment 152400)"
assert_ctx "urge reaches the line bold red"       "<BOLD><RED>ctx:881k/200k handoff?<RESET>"  "$(ctx_segment 881000)"

# ── The segment is last, and separated by exactly one space ──────
# The separator moved into a `${CTX_DISPLAY:+ ...}` expansion when the gauge was extracted, so
# that an absent segment leaves no trailing space. That made the space conditional, and a
# conditional separator is worth asserting in both states.
line="$(statusline 72346)"
case "$line" in
  *'] ctx:72k') PASS=$((PASS + 1)) ;;
  *) FAIL=$((FAIL + 1)); printf 'FAIL: segment is not last with one space: %s\n' "$line" ;;
esac

# ── Degrade capability, never execution ──────────────────────────
# A missing gauge silences the context segment; the statusline still renders, with no dangling
# separator. This is the case that regresses if someone reintroduces a local `ctx:NNNk` fallback
# here -- which would be a second rendering of the gauge, the thing the extraction removed.
line="$(statusline 881000 "$SCRIPT_DIR/does-not-exist.sh")"
case "$line" in
  *ctx:*)  FAIL=$((FAIL + 1)); printf 'FAIL: missing gauge still rendered a count: %s\n' "$line" ;;
  *'] ')   FAIL=$((FAIL + 1)); printf 'FAIL: missing gauge left a trailing separator: %s\n' "$line" ;;
  '')      FAIL=$((FAIL + 1)); echo "FAIL: missing gauge produced no statusline at all" ;;
  *)       PASS=$((PASS + 1)) ;;
esac

# ── No percentage, ever ──────────────────────────────────────────
# used_percentage is denominated in the auto-compaction ceiling, which is the signal this
# advisory exists to replace: at the 200k reset threshold it reads 20% on a 1M window, which
# invites the wrong conclusion at exactly the wrong depth. Asserted at the statusline as well as
# at the gauge, because this file is where a "nice extra" would most plausibly be added -- it is
# the one with the payload in hand.
for t in 0 72346 152400 881000; do
  seg="$(ctx_segment "$t")"
  case "$seg" in
    *%*) FAIL=$((FAIL + 1)); echo "FAIL: percentage reappeared at $t tokens: $seg" ;;
    *)   PASS=$((PASS + 1)) ;;
  esac
done

# A payload carrying only used_percentage (older CLI, or a future field rename) must render
# 0k with no advisory, and must NOT reconstruct an estimate from the percentage -- that field
# is an integer against a 1M window, so a reconstruction has 10k granularity and would
# straddle the threshold.
assert_ctx "percentage-only payload: 0k, no advisory, no estimate" "ctx:0k" \
  "$(printf '{"context_window":{"used_percentage":88},"workspace":{}}' \
     | CTX_GAUGE_FILE="$GAUGE" CTX_THRESHOLDS_FILE="$THRESHOLDS" bash "$STATUSLINE" 2>/dev/null \
     | sed 's/.*[] ]\(ctx:\)/\1/')"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
