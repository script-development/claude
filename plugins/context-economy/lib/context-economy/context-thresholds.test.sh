#!/usr/bin/env bash
#
# Tests for context-thresholds.sh.
#
# This file is DATA, not logic, so most of it is deliberately untested: the numbers are findings
# and are meant to be retuned, and a suite that pinned them would just be a second copy of the
# values — exactly what the file exists to prevent. Asserting `CTX_URGE_TOKENS == 200000` here
# would mean every retune breaks a test that knows nothing the file does not already say.
#
# What IS tested is the small amount of real machinery that crept in:
#
#   t2  every variable a consumer reads must be non-empty and numeric. A typo in a name here
#       disables its consumer and reports nothing, which is the correct degradation but an
#       invisible one.
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
# Sourced in a subshell so the suite's own environment cannot leak in.
# shellcheck source=/dev/null
values=$(bash -c '
    . "$1" || exit 1
    for v in CTX_NOTICE_TOKENS CTX_URGE_TOKENS \
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

for v in CTX_NOTICE_TOKENS CTX_URGE_TOKENS CTX_GROWTH_TOKENS_PER_TURN \
         HANDOFF_TARGET_TOKENS HANDOFF_CEILING_TOKENS CTX_CHARS_PER_TOKEN_X100 \
         CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS; do
    got=$(get "$v")
    case "$got" in
        ''|'<UNSET>'|*[!0-9]*) fail "$v is a non-empty integer" "got [${got:-<empty>}]" ;;
        *) pass "$v is a non-empty integer" ;;
    esac
done

# --- Coherence the consumers rely on ---------------------------------------

notice=$(get CTX_NOTICE_TOKENS); urge=$(get CTX_URGE_TOKENS)
[ "$notice" -lt "$urge" ] && pass 'NOTICE is below URGE, so the two-stage advisory can stage' \
                          || fail 'NOTICE is below URGE' "notice=$notice urge=$urge"

target=$(get HANDOFF_TARGET_TOKENS); ceiling=$(get HANDOFF_CEILING_TOKENS)
[ "$target" -lt "$ceiling" ] && pass 'the handoff target is below its ceiling' \
                             || fail 'the handoff target is below its ceiling' "target=$target ceiling=$ceiling"

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
