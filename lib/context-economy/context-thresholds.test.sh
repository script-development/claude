#!/usr/bin/env bash
#
# Tests for context-thresholds.sh.
#
# This file is DATA, not logic, so most of it is deliberately untested: the numbers are findings
# and are meant to be retuned, and a suite that pinned them would just be a second copy of the
# values — exactly what the file exists to prevent. Asserting `CTX_URGE_TOKENS == 200000` here
# would mean every retune breaks a test that knows nothing the file does not already say.
#
# What IS tested is the small amount of real machinery that crept in, and one trap it introduced:
#
#   t1  THE ORDERING TRAP. `CTX_COMPACT_THRESHOLD_TOKENS` is declared as a REFERENCE to
#       `CTX_1M_COMPACT_THRESHOLD_TOKENS` rather than as a repeated literal, so it must be assigned
#       AFTER the constant it names. Move it above and it expands to the empty string — which is not
#       a syntax error, not a warning, and not nothing: empty is a MEANING in this file ("no ceiling
#       declared"), so the consumer silently falls back to detection and the write trigger stops
#       arming. A feature would revert with every test still green and no symptom until someone
#       noticed handoffs had quietly stopped happening.
#
#   t2  every variable a consumer reads must be non-empty and numeric. `handoff-write.sh` requires
#       four of them and goes SILENT if any is missing, which is the correct degradation but an
#       invisible one — a typo in a name here disables the hook and reports nothing.
#
# Run it as:
#
#   bash lib/context-economy/context-thresholds.test.sh

set -uo pipefail

# Arrange
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/context-thresholds.sh"

if [ ! -r "$subject" ]; then
    echo "context-thresholds.sh not found at $subject" >&2
    exit 2
fi

passed=0
failed=0

pass() { passed=$((passed + 1)); echo "ok   $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1 — $2"; }

# Act
#
# Sourced in a subshell so the suite's own environment cannot leak in. An exported
# CTX_COMPACT_THRESHOLD_TOKENS in the developer's shell would otherwise make t1 pass for entirely
# the wrong reason — the file could be broken and this would still be green.
# shellcheck source=/dev/null
values=$(env -u CTX_COMPACT_THRESHOLD_TOKENS bash -c '
    . "$1" || exit 1
    for v in CTX_NOTICE_TOKENS CTX_URGE_TOKENS CTX_LARGE_REQUEST_TOKENS CTX_AUTHORING_TURN_TOKENS \
             CTX_1M_COMPACT_THRESHOLD_TOKENS CTX_COMPACT_THRESHOLD_TOKENS \
             CTX_GROWTH_TOKENS_PER_TURN HANDOFF_TARGET_TOKENS HANDOFF_CEILING_TOKENS \
             CTX_CHARS_PER_TOKEN_X100 CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS; do
        printf "%s=%s\n" "$v" "${!v-<UNSET>}"
    done' _ "$subject" 2>/dev/null)

# Assert
if [ -z "$values" ]; then
    echo "FAIL the file could not be sourced at all"
    exit 1
fi
pass 'the file sources cleanly'

get() { printf '%s\n' "$values" | grep "^$1=" | cut -d= -f2-; }

# --- t2 — every consumer-visible variable resolves -------------------------

for v in CTX_NOTICE_TOKENS CTX_URGE_TOKENS CTX_LARGE_REQUEST_TOKENS CTX_AUTHORING_TURN_TOKENS \
         CTX_1M_COMPACT_THRESHOLD_TOKENS CTX_GROWTH_TOKENS_PER_TURN \
         HANDOFF_TARGET_TOKENS HANDOFF_CEILING_TOKENS CTX_CHARS_PER_TOKEN_X100 \
         CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS; do
    got=$(get "$v")
    case "$got" in
        ''|'<UNSET>'|*[!0-9]*) fail "$v is a non-empty integer" "got [${got:-<empty>}]" ;;
        *) pass "$v is a non-empty integer" ;;
    esac
done

# --- t1 — the ordering trap ------------------------------------------------

declared=$(get CTX_COMPACT_THRESHOLD_TOKENS)
case "$declared" in
    ''|'<UNSET>')
        fail 'the declared ceiling resolves to a value' \
             'it is EMPTY — if the declaration was moved above CTX_1M_COMPACT_THRESHOLD_TOKENS it now expands to nothing, and the write trigger has silently stopped arming' ;;
    *[!0-9]*)
        fail 'the declared ceiling resolves to a value' "got a non-integer [$declared]" ;;
    *)
        pass 'the declared ceiling resolves to a value' ;;
esac

# It must resolve to the constant it references, not to a literal that drifted away from it. This
# is what makes "one number, one definition" checkable rather than merely intended.
onem=$(get CTX_1M_COMPACT_THRESHOLD_TOKENS)
if [ "$declared" = "$onem" ]; then
    pass 'the declared ceiling equals the constant it references, not a copy of it'
else
    fail 'the declared ceiling equals the constant it references, not a copy of it' \
         "declared=[$declared] constant=[$onem] — a second copy has drifted"
fi

# And the reference must be written as one: a literal that merely happens to match today would pass
# the check above while reintroducing exactly the duplication it was meant to remove.
if grep -qE '^CTX_COMPACT_THRESHOLD_TOKENS=\$\{?CTX_1M_COMPACT_THRESHOLD_TOKENS\}?$' "$subject"; then
    pass 'the declaration is written as a reference, not as a repeated literal'
else
    fail 'the declaration is written as a reference, not as a repeated literal' \
         'no `CTX_COMPACT_THRESHOLD_TOKENS=$CTX_1M_COMPACT_THRESHOLD_TOKENS` line found'
fi

# --- Coherence the consumers rely on ---------------------------------------

notice=$(get CTX_NOTICE_TOKENS); urge=$(get CTX_URGE_TOKENS)
[ "$notice" -lt "$urge" ] && pass 'NOTICE is below URGE, so the two-stage advisory can stage' \
                          || fail 'NOTICE is below URGE' "notice=$notice urge=$urge"

target=$(get HANDOFF_TARGET_TOKENS); ceiling=$(get HANDOFF_CEILING_TOKENS)
[ "$target" -lt "$ceiling" ] && pass 'the handoff target is below its ceiling' \
                             || fail 'the handoff target is below its ceiling' "target=$target ceiling=$ceiling"

# --- D18: the derived trigger has to land somewhere usable -----------------
#
# These replace a single pre-D18 check ('a session at exactly URGE has room to hand off under the
# declared ceiling'), which asserted an invariant the design no longer has: URGE is not the trigger
# any more, so its headroom under the ceiling says nothing about whether anything can arm.

large=$(get CTX_LARGE_REQUEST_TOKENS); auth=$(get CTX_AUTHORING_TURN_TOKENS)
trigger=$(( declared - 2 * large - auth ))

# The floor, which is also what hooks/handoff-write.sh enforces at runtime. Under the declared
# ceiling the trigger must land at a depth where a handoff has something to record; if it does not,
# the automatic path is off for every session on this machine and that should fail here rather than
# be discovered by its silence months later.
if [ "$trigger" -ge "$notice" ]; then
    pass 'the derived trigger lands at or above NOTICE under the declared ceiling'
else
    fail 'the derived trigger lands at or above NOTICE under the declared ceiling' \
         "ceiling-2*fat-authoring=$trigger is below notice=$notice — nothing can ever arm here"
fi

# The trigger must sit strictly BELOW the gate, or firing fails its own headroom check on arrival
# and the hook declines every time it fires. The margin between them is exactly one large_request
# by construction; asserting it catches an edit that changes one expression without the other.
gate=$(( declared - large - auth ))
if [ "$trigger" -lt "$gate" ] && [ "$(( gate - trigger ))" -eq "$large" ]; then
    pass 'the trigger sits exactly one large_request below the gate, so firing can pass it'
else
    fail 'the trigger sits exactly one large_request below the gate, so firing can pass it' \
         "trigger=$trigger gate=$gate band=$(( gate - trigger )) large=$large"
fi

# D18's own finding (corrected for Route 5, 2026-09-16), asserted so it cannot regress into an
# accident: an automatically written handoff lands up to `2*large_request + authoring_turn` below
# the ceiling -- the true worst case of the reserved band, matching what
# hooks/handoff-write.sh's sidecar actually records, not `2*large_request` alone -- which is FAR
# above the acceptable-gap constant. That is expected, not a defect — but it is exactly why the
# writer records `expected_gap_tokens` and the reader takes the larger of the two. If these two
# ever became comparable, that plumbing would be dead weight and this check is where to notice.
okgap=$(get CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS)
if [ "$(( 2 * large + auth ))" -gt "$okgap" ]; then
    pass "an auto-written handoff's reserved gap exceeds the manual-path acceptable gap, as D18 found"
else
    fail "an auto-written handoff's reserved gap exceeds the manual-path acceptable gap, as D18 found" \
         "2*large_request+authoring=$(( 2 * large + auth )) no longer exceeds $okgap — the expected_gap_tokens plumbing may be redundant"
fi

# And URGE, now advisory-only, must still be reachable as a *display* threshold on the window this
# machine declares — a gauge that can never render its second stage is a broken gauge.
if [ "$urge" -lt "$declared" ]; then
    pass 'URGE is reachable under the declared ceiling, so the gauge can render its second stage'
else
    fail 'URGE is reachable under the declared ceiling' "urge=$urge declared=$declared"
fi

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
