#!/bin/bash
# Tests for context-gauge.sh -- the gauge itself, not any statusline that renders it.
#
# THE BOUNDARY CASES LIVE HERE, NOT IN statusline.test.sh. Before the extraction they had
# nowhere else to go, so that suite drove them through a whole statusline: a payload in,
# a git tree and a netstat call along the way, and a sed to cut the segment back out. Now
# that the gauge is its own unit they are asserted against the unit, and the statusline
# suite keeps only what is genuinely about wiring. Do not put them back on both sides --
# duplicated boundary cases are the ones that drift, because the second copy is the one
# nobody remembers to update.
#
# The boundaries ARE the risk. An off-by-one at a threshold is invisible in normal use (a
# session sails past 200k in one turn and nobody notices which side of >= it landed on), so
# exact-value cases are asserted on both sides of both stages.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAUGE="$SCRIPT_DIR/context-gauge.sh"
REAL_THRESHOLDS="$SCRIPT_DIR/context-economy/context-thresholds.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n      expected: %s\n      actual:   %s\n' "$desc" "$expected" "$actual"
  fi
}

# Escapes made visible, so a colour regression is an assertable string rather than an
# invisible one.
visible() {
  sed 's/\x1b\[1m/<BOLD>/g; s/\x1b\[31m/<RED>/g; s/\x1b\[33m/<YELLOW>/g; s/\x1b\[0m/<RESET>/g'
}

# Each case runs in its own subshell so a leaked variable in one cannot mask a bug in the
# next, and so CTX_THRESHOLDS_FILE can be set per case without unsetting it afterwards.
gauge() {
  local tokens="$1" thresholds="${2-$REAL_THRESHOLDS}"
  ( CTX_THRESHOLDS_FILE="$thresholds"
    . "$GAUGE"
    context_gauge "$tokens" ) | visible
}

[ -f "$GAUGE" ] || { echo "FAIL: gauge not found at $GAUGE"; exit 1; }
[ -f "$REAL_THRESHOLDS" ] || { echo "FAIL: thresholds not found at $REAL_THRESHOLDS"; exit 1; }

# Confirm the file under test really is the 120k/200k pair, so a threshold change breaks a
# test rather than silently rewriting what these cases mean.
( . "$REAL_THRESHOLDS"
  [ "$CTX_NOTICE_TOKENS" = "120000" ] || { echo "FAIL: CTX_NOTICE_TOKENS is $CTX_NOTICE_TOKENS, tests assume 120000"; exit 1; }
  [ "$CTX_URGE_TOKENS" = "200000" ]   || { echo "FAIL: CTX_URGE_TOKENS is $CTX_URGE_TOKENS, tests assume 200000"; exit 1; }
) || exit 1

# ── Below NOTICE: bare token count, no colour, no denominator ─────
assert_eq "zero tokens is bare"             "ctx:0k"    "$(gauge 0)"
assert_eq "well below notice is bare"       "ctx:72k"   "$(gauge 72346)"
assert_eq "one token below notice is bare"  "ctx:119k"  "$(gauge 119999)"

# ── NOTICE stage: threshold named, because now it is close enough to act on ──
assert_eq "exactly at notice is yellow"     "<YELLOW>ctx:120k/200k<RESET>" "$(gauge 120000)"
assert_eq "mid-notice is yellow"            "<YELLOW>ctx:152k/200k<RESET>" "$(gauge 152400)"
assert_eq "one token below urge is yellow"  "<YELLOW>ctx:199k/200k<RESET>" "$(gauge 199999)"

# ── URGE stage ───────────────────────────────────────────────────
assert_eq "exactly at urge is red"          "<BOLD><RED>ctx:200k/200k handoff?<RESET>" "$(gauge 200000)"
assert_eq "deep session is red"             "<BOLD><RED>ctx:881k/200k handoff?<RESET>" "$(gauge 881000)"

# ── No percentage, ever ──────────────────────────────────────────
# used_percentage is denominated in the auto-compaction ceiling, which is the signal this
# advisory exists to replace: at the 200k reset threshold it reads 20% on a 1M window, which
# invites the wrong conclusion at exactly the wrong depth. Assert it never appears, so
# reintroducing it as a "nice extra" fails here rather than in a reader's head.
for t in 0 72346 152400 881000; do
  seg="$(gauge "$t")"
  case "$seg" in
    *%*) FAIL=$((FAIL + 1)); echo "FAIL: percentage reappeared at $t tokens: $seg" ;;
    *)   PASS=$((PASS + 1)) ;;
  esac
done

# ── Degrade capability, never execution ──────────────────────────
# A missing thresholds file must silence the ADVISORY while the token count still renders,
# and must NOT guess a threshold. This is the case that would regress if someone
# "helpfully" added a local default back into the gauge.
assert_eq "missing thresholds file: count renders, no advisory" \
  "ctx:881k" "$(gauge 881000 "$SCRIPT_DIR/does-not-exist.sh")"

# An empty/garbage thresholds file must fail OPEN. With ${CTX_*:-0} instead of -n guards,
# this case would render URGE for a 12k-token session.
EMPTY_THRESHOLDS="$(mktemp)"
: > "$EMPTY_THRESHOLDS"
assert_eq "empty thresholds file fails open, not to URGE" \
  "ctx:12k" "$(gauge 12000 "$EMPTY_THRESHOLDS")"
rm -f "$EMPTY_THRESHOLDS"

# A file defining NOTICE but not URGE must NOT render `ctx:152k/0k`. The pre-extraction
# statusline guarded only CTX_NOTICE_TOKENS on this branch while printing CTX_URGE_TOKENS as
# the denominator, so a half-written thresholds file would have advertised a threshold of
# zero -- which reads as a rule, not as an absent one.
HALF_THRESHOLDS="$(mktemp)"
echo 'CTX_NOTICE_TOKENS=120000' > "$HALF_THRESHOLDS"
assert_eq "notice without urge renders no denominator" \
  "ctx:152k" "$(gauge 152400 "$HALF_THRESHOLDS")"
rm -f "$HALF_THRESHOLDS"

# The mirror case: URGE alone is enough to render URGE, because it is its own denominator.
# Below it, with no NOTICE defined, the count stays bare rather than borrowing URGE's colour.
URGE_ONLY="$(mktemp)"
echo 'CTX_URGE_TOKENS=200000' > "$URGE_ONLY"
assert_eq "urge without notice still reaches URGE" \
  "<BOLD><RED>ctx:200k/200k handoff?<RESET>" "$(gauge 200000 "$URGE_ONLY")"
assert_eq "urge without notice leaves the notice band bare" \
  "ctx:152k" "$(gauge 152400 "$URGE_ONLY")"
rm -f "$URGE_ONLY"

# A thresholds file that aborts partway must not take the caller down with it, AND must not
# leave a blank where the count belongs. The gauge is called from display paths where a crash
# costs the consumer its whole line, so both halves matter: the subshell keeps the abort
# contained, the empty-result fallback keeps the segment readable.
ABORTING="$(mktemp)"
printf 'exit 1\nCTX_URGE_TOKENS=200000\n' > "$ABORTING"
assert_eq "a thresholds file that exits degrades to the plain count" \
  "ctx:881k" "$(gauge 881000 "$ABORTING")"
rm -f "$ABORTING"

# Same for one that will not parse at all.
BROKEN="$(mktemp)"
printf 'if [ \n' > "$BROKEN"
assert_eq "an unparseable thresholds file degrades to the plain count" \
  "ctx:881k" "$(gauge 881000 "$BROKEN")"
rm -f "$BROKEN"

# But a file that merely runs `false` under set -e still delivers what it defined: the source
# sits in an OR-list, where set -e does not apply, so it runs to completion. Asserted so the
# distinction from the two cases above is recorded rather than rediscovered by whoever next
# wonders why one broken thresholds file degrades and another does not.
NOISY="$(mktemp)"
printf 'set -e\nfalse\nCTX_URGE_TOKENS=200000\n' > "$NOISY"
assert_eq "a noisy but complete thresholds file is still honoured" \
  "<BOLD><RED>ctx:881k/200k handoff?<RESET>" "$(gauge 881000 "$NOISY")"
rm -f "$NOISY"

# ── Bad input has a rendering, never an error ────────────────────
assert_eq "no argument is 0k"        "ctx:0k" "$(gauge "")"
assert_eq "non-numeric is 0k"        "ctx:0k" "$(gauge "abc")"
assert_eq "a float is 0k, not 12k"   "ctx:0k" "$(gauge "12000.4")"

# ── The consumer's namespace is not the gauge's ──────────────────
# A foreign statusline may well have its own RED, or its own CTX_URGE_TOKENS. Sourcing the
# gauge and calling it must leave both untouched: the colours are function-locals and the
# thresholds are sourced inside a subshell. Before the extraction the statusline sourced the
# thresholds into its own scope, so this is a property the unit gained by moving.
leakage="$(
  RED='CONSUMER-RED'
  CTX_URGE_TOKENS='CONSUMER-URGE'
  CTX_THRESHOLDS_FILE="$REAL_THRESHOLDS"
  . "$GAUGE"
  context_gauge 881000 >/dev/null
  printf '%s|%s' "$RED" "$CTX_URGE_TOKENS"
)"
assert_eq "sourcing and calling clobbers neither colours nor thresholds" \
  "CONSUMER-RED|CONSUMER-URGE" "$leakage"

# ── The two-line adoption contract from the header ───────────────
# With no CTX_THRESHOLDS_FILE set at all, the gauge must still find the thresholds by its own
# BASH_SOURCE-relative path. This is the case a foreign consumer actually hits, and the one a
# "simplify it to $HOME/.claude/lib" change would silently break in the repo.
assert_eq "default resolution finds the nested thresholds unaided" \
  "<BOLD><RED>ctx:881k/200k handoff?<RESET>" \
  "$( ( unset CTX_THRESHOLDS_FILE; . "$GAUGE"; context_gauge 881000 ) | visible )"

# It emits no trailing newline, so a consumer can interpolate it mid-line.
raw_len=$( ( unset CTX_THRESHOLDS_FILE; . "$GAUGE"; context_gauge 72346 ) | wc -c | tr -d ' ')
assert_eq "no trailing newline" "7" "$raw_len"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
