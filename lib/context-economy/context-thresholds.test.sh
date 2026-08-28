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
#   t2  every variable a consumer reads must be non-empty and numeric. `handoff-urge.sh` requires
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
    for v in CTX_NOTICE_TOKENS CTX_URGE_TOKENS CTX_FAT_TURN_TOKENS CTX_AUTHORING_TURN_TOKENS \
             CTX_1M_COMPACT_THRESHOLD_TOKENS CTX_COMPACT_THRESHOLD_TOKENS \
             CTX_GROWTH_TOKENS_PER_TURN HANDOFF_TARGET_TOKENS HANDOFF_CEILING_TOKENS \
             CTX_CHARS_PER_TOKEN_X100; do
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

for v in CTX_NOTICE_TOKENS CTX_URGE_TOKENS CTX_FAT_TURN_TOKENS CTX_AUTHORING_TURN_TOKENS \
         CTX_1M_COMPACT_THRESHOLD_TOKENS CTX_GROWTH_TOKENS_PER_TURN \
         HANDOFF_TARGET_TOKENS HANDOFF_CEILING_TOKENS CTX_CHARS_PER_TOKEN_X100; do
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

# The headroom check is `T + fat + authoring < ceiling`. If that sum can never clear URGE, the
# trigger is dead on arrival for every session — worth catching here rather than by wondering
# months later why no handoff has ever been written.
fat=$(get CTX_FAT_TURN_TOKENS); auth=$(get CTX_AUTHORING_TURN_TOKENS)
if [ "$(( urge + fat + auth ))" -lt "$declared" ]; then
    pass 'a session at exactly URGE has room to hand off under the declared ceiling'
else
    fail 'a session at exactly URGE has room to hand off under the declared ceiling' \
         "urge+fat+authoring=$(( urge + fat + auth )) is not below $declared — the trigger can never arm"
fi

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
