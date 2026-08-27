#!/bin/bash
# Tests for statusline.sh's context segment and reset advisory.
#
# Only the context segment is covered. The rest of the statusline reads the real git tree and
# real listening ports, so it is environment-dependent by design and not usefully assertable
# here; every test therefore matches only the trailing ctx segment.
#
# The boundaries ARE the risk. An off-by-one at the threshold is invisible in normal use
# (a session sails past 200k in one turn and nobody notices which side of >= it landed on),
# so exact-value cases are asserted on both sides of both stages.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/statusline.sh"

PASS=0
FAIL=0

# A minimal payload. Only context_window matters; the rest is present because statusline.sh
# reads it, not because these tests care about it.
payload() {
  printf '{"context_window":{"total_input_tokens":%s,"context_window_size":1000000},"workspace":{}}' "$1"
}

# Run the statusline and return only the ctx segment, escapes made visible so a colour
# regression is an assertable string rather than an invisible one.
ctx_segment() {
  local tokens="$1" thresholds="$2"
  payload "$tokens" \
    | CTX_THRESHOLDS_FILE="$thresholds" bash "$STATUSLINE" 2>/dev/null \
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

REAL_THRESHOLDS="$HOME/.claude/lib/context-thresholds.sh"
if [ ! -f "$REAL_THRESHOLDS" ]; then
  echo "SKIP-ALL: $REAL_THRESHOLDS not present; run install.sh first"
  exit 0
fi

# Confirm the file under test really is the 120k/200k pair, so a threshold change breaks a
# test rather than silently rewriting what these cases mean.
( . "$REAL_THRESHOLDS"
  [ "$CTX_NOTICE_TOKENS" = "120000" ] || { echo "FAIL: CTX_NOTICE_TOKENS is $CTX_NOTICE_TOKENS, tests assume 120000"; exit 1; }
  [ "$CTX_URGE_TOKENS" = "200000" ]   || { echo "FAIL: CTX_URGE_TOKENS is $CTX_URGE_TOKENS, tests assume 200000"; exit 1; }
) || exit 1

# ── Below NOTICE: bare token count, no colour, no denominator ─────
assert_ctx "zero tokens is bare"             "ctx:0k"    "$(ctx_segment 0 "$REAL_THRESHOLDS")"
assert_ctx "well below notice is bare"       "ctx:72k"   "$(ctx_segment 72346 "$REAL_THRESHOLDS")"
assert_ctx "one token below notice is bare"  "ctx:119k"  "$(ctx_segment 119999 "$REAL_THRESHOLDS")"

# ── NOTICE stage: threshold named, because now it is close enough to act on ──
assert_ctx "exactly at notice is yellow"     "<YELLOW>ctx:120k/200k<RESET>" "$(ctx_segment 120000 "$REAL_THRESHOLDS")"
assert_ctx "mid-notice is yellow"            "<YELLOW>ctx:152k/200k<RESET>" "$(ctx_segment 152400 "$REAL_THRESHOLDS")"
assert_ctx "one token below urge is yellow"  "<YELLOW>ctx:199k/200k<RESET>" "$(ctx_segment 199999 "$REAL_THRESHOLDS")"

# ── URGE stage ───────────────────────────────────────────────────
assert_ctx "exactly at urge is red"          "<BOLD><RED>ctx:200k/200k handoff?<RESET>" "$(ctx_segment 200000 "$REAL_THRESHOLDS")"
assert_ctx "deep session is red"             "<BOLD><RED>ctx:881k/200k handoff?<RESET>" "$(ctx_segment 881000 "$REAL_THRESHOLDS")"

# ── No percentage, ever ──────────────────────────────────────────
# used_percentage is denominated in the auto-compaction ceiling, which is the signal this
# advisory exists to replace: at the 200k reset threshold it reads 20% on a 1M window, which
# invites the wrong conclusion at exactly the wrong depth. Assert it never appears, so
# reintroducing it as a "nice extra" fails here rather than in a reader's head.
for t in 0 72346 152400 881000; do
  seg="$(ctx_segment "$t" "$REAL_THRESHOLDS")"
  case "$seg" in
    *%*) FAIL=$((FAIL + 1)); echo "FAIL: percentage reappeared at $t tokens: $seg" ;;
    *)   PASS=$((PASS + 1)) ;;
  esac
done

# ── Degrade capability, never execution ──────────────────────────
# A missing thresholds file must silence the ADVISORY while the token count still renders,
# and must NOT guess a threshold. This is the case that would regress if someone
# "helpfully" added a local default back into statusline.sh.
assert_ctx "missing thresholds file: count renders, no advisory" \
  "ctx:881k" "$(ctx_segment 881000 "$SCRIPT_DIR/does-not-exist.sh")"

# An empty/garbage thresholds file must fail OPEN. With ${CTX_*:-0} instead of -n guards,
# this case would render URGE for a 12k-token session.
EMPTY_THRESHOLDS="$(mktemp)"
: > "$EMPTY_THRESHOLDS"
assert_ctx "empty thresholds file fails open, not to URGE" \
  "ctx:12k" "$(ctx_segment 12000 "$EMPTY_THRESHOLDS")"
rm -f "$EMPTY_THRESHOLDS"

# A payload carrying only used_percentage (older CLI, or a future field rename) must render
# 0k with no advisory, and must NOT reconstruct an estimate from the percentage — that field
# is an integer against a 1M window, so a reconstruction has 10k granularity and would
# straddle the threshold.
assert_ctx "percentage-only payload: 0k, no advisory, no estimate" "ctx:0k" \
  "$(printf '{"context_window":{"used_percentage":88},"workspace":{}}' \
     | CTX_THRESHOLDS_FILE="$REAL_THRESHOLDS" bash "$STATUSLINE" 2>/dev/null \
     | sed 's/.*[] ]\(ctx:\)/\1/')"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
