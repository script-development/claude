#!/usr/bin/env bash
#
# Tests for handoff-urge.sh.
#
# The suite is lopsided on purpose: most cases assert that the hook stays SILENT. That is the
# correct bias for this subject. A hook that fails to fire costs one handoff the human writes by
# hand; a hook that fires wrongly interrupts every turn of a session it has no business touching,
# and the first thing anyone does about that is delete it. So every "should not fire" path gets a
# case, and the fire path gets three.
#
# Cases that are regressions rather than specification:
#
#   h1  the raw-grep trap. A transcript is full of the session TALKING about token fields --
#       this repo's own thresholds file and statusline get read into context constantly. A hook
#       that matched `cache_read_input_tokens` as a substring would read a number out of a code
#       block. The fixture puts a fake 999999 inside a user message's text and asserts the hook
#       reads the real, smaller, parsed value.
#   h2  `message.model` drops the `[1m]` suffix while modelUsage keys keep it. Detecting on the
#       former makes a 1M session look like a 200k one -- the unsafe direction, since that is
#       exactly the case where arming is safe. Fixture carries both, disagreeing.
#   h3  an older thresholds file. install.sh symlinks it from a sibling checkout, so a file
#       predating this hook by one commit is a normal state, not an exotic one. Missing a
#       variable must read as "no opinion" and stay silent, never as a threshold of zero -- which
#       is what ${VAR:-0} would have produced, firing on every session instantly.
#   h4  the latch. `stop_hook_active` covers only the continuation this hook itself caused; a
#       background task waking the session later arrives with it false and the threshold still
#       crossed. Without the on-disk latch that is a nag on every wake.
#   h5  a DECLINE must latch too. It was silent-but-unlatched in the first draft, which meant the
#       "ceiling unknown" message reappeared at every turn boundary for the rest of the session --
#       the exact nag-fatigue the fire path was careful to avoid.
#
# No framework, matching the sibling verify-*.test.sh suites. Run it as:
#
#   bash hooks/handoff-urge.test.sh

set -uo pipefail

# Arrange
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/handoff-urge.sh"

if [ ! -r "$subject" ]; then
    echo "handoff-urge.sh not found at $subject" >&2
    exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

passed=0
failed=0

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# --- Fixtures --------------------------------------------------------------
#
# A thresholds file rather than the real one: the suite must not change its verdict when the
# real numbers are retuned, and it must be able to express an OLD file (h3) that the real one
# cannot be.

write_thresholds() {  # write_thresholds <path> [compact_threshold_value]
    cat > "$1" <<EOF
CTX_NOTICE_TOKENS=120000
CTX_URGE_TOKENS=200000
CTX_COMPACT_THRESHOLD_TOKENS=${2:-}
CTX_FAT_TURN_TOKENS=50000
CTX_AUTHORING_TURN_TOKENS=30000
CTX_1M_COMPACT_THRESHOLD_TOKENS=887000
EOF
}

thresholds="$fixture/thresholds.sh"
write_thresholds "$thresholds"

# A transcript line carrying a usage record. Split across the three input components because the
# hook must SUM them -- reading only input_tokens would report ~2 on every real session, since
# almost everything is cached.
usage_line() {  # usage_line <input> <cache_creation> <cache_read> [model]
    jq -nc --argjson i "$1" --argjson cc "$2" --argjson cr "$3" --arg m "${4:-claude-opus-5}" \
        '{type: "assistant", message: {model: $m, usage: {input_tokens: $i, cache_creation_input_tokens: $cc, cache_read_input_tokens: $cr, output_tokens: 400}}}'
}

# A cost-state line, the ONLY place modelUsage appears. Sporadic in real transcripts, which is
# why the decline path is the common one and gets as much coverage as the fire path.
cost_state_line() {  # cost_state_line <model-key>
    jq -nc --arg k "$1" '{type: "cost-state", modelUsage: {($k): {inputTokens: 22, outputTokens: 4667}}}'
}

make_transcript() {  # make_transcript <name> <resident-total> [model-key-for-cost-state]
    local path="$fixture/$1.jsonl"
    {
        usage_line 2 1000 5000
        # A user turn quoting token-field names in prose. This is what h1 defends against.
        jq -nc '{type: "user", message: {role: "user", content: "the statusline reads cache_read_input_tokens: 999999 and input_tokens from the payload"}}'
        usage_line 2 3000 "$(( $2 - 3002 ))"
        [ -n "${3:-}" ] && cost_state_line "$3"
    } > "$path"
    printf '%s' "$path"
}

# Each case gets its OWN session id unless it names one, because the subject's latch is keyed by
# session_id and that is therefore the natural unit of isolation. The suite originally shared one
# id and relied on `reset_latches` (an `rm -rf`) between all 26 cases -- which made every
# assertion depend on a filesystem delete succeeding. On Windows that is not a safe assumption:
# a transient handle or scanner can defer the delete, the stale latch silences the next case, and
# it reports as "expected a block, got nothing" in a suite that passes on the very next run. A
# flake in a test suite is worse than a plain failure -- it teaches the reader to re-run rather
# than to look -- and the fix is structural isolation, not a more determined delete.
#
# A file-backed counter rather than $RANDOM: `payload` is invoked inside `$(...)`, and bash
# re-seeds RANDOM per subshell, so successive calls can return the same value.
counter_file="$fixture/session-counter"
echo 0 > "$counter_file"
next_session_id() {
    local n
    n=$(( $(cat "$counter_file" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$counter_file"
    printf 'sess-auto-%s' "$n"
}

payload() {  # payload <transcript> [session_id] [stop_hook_active] [extra-jq-object]
    # `extra` is assigned rather than defaulted inline: `${4:-{}}` splits at the first `}`, so
    # the default closes early and every caller that DID pass an object got a stray brace
    # appended. It failed loudly here, but the same expression in the subject would have been a
    # silent malformed payload.
    local extra='{}'
    [ $# -ge 4 ] && extra="$4"
    local sid="${2:-}"
    [ -n "$sid" ] || sid=$(next_session_id)
    jq -nc --arg t "$1" --arg s "$sid" --argjson a "${3:-false}" \
        '{session_id: $s, transcript_path: $t, hook_event_name: "Stop", stop_hook_active: $a}' \
        | jq -c ". + ($extra)"
}

# --- Runner ----------------------------------------------------------------
#
# HOME is redirected so the on-disk latch lands in the fixture. Without that the first run would
# latch the developer's real ~/.claude/state and every subsequent case would silently pass by
# hitting the latch instead of the logic under test -- a green suite testing nothing.
run() {  # run <payload-json> [env assignments...]
    local p="$1"; shift
    printf '%s' "$p" | env HOME="$fixture/home" CTX_THRESHOLDS_FILE="$thresholds" "$@" bash "$subject" 2>/dev/null
}

assert_silent() {  # assert_silent <label> <payload> [env...]
    local label="$1" p="$2"; shift 2
    local out; out=$(run "$p" "$@")
    if [ -z "$out" ]; then
        passed=$((passed + 1)); echo "ok   $label"
    else
        failed=$((failed + 1)); echo "FAIL $label — expected no output, got: $out"
    fi
}

assert_field() {  # assert_field <label> <jq-filter> <expected> <payload> [env...]
    local label="$1" filter="$2" want="$3" p="$4"; shift 4
    local out got; out=$(run "$p" "$@")
    got=$(printf '%s' "$out" | jq -r "$filter" 2>/dev/null)
    if [ "$got" = "$want" ]; then
        passed=$((passed + 1)); echo "ok   $label"
    else
        failed=$((failed + 1)); echo "FAIL $label — expected [$want], got [${got:-<no output>}]"
    fi
}

assert_contains() {  # assert_contains <label> <jq-filter> <needle> <payload> [env...]
    local label="$1" filter="$2" needle="$3" p="$4"; shift 4
    local out got; out=$(run "$p" "$@")
    got=$(printf '%s' "$out" | jq -r "$filter" 2>/dev/null)
    case "$got" in
        *"$needle"*) passed=$((passed + 1)); echo "ok   $label" ;;
        *) failed=$((failed + 1)); echo "FAIL $label — expected to contain [$needle], got [${got:-<no output>}]" ;;
    esac
}

reset_latches() { rm -rf "$fixture/home/.claude/state"; }

# --- Below the threshold ---------------------------------------------------

# Arrange — four transcripts, reused by the cases below
shallow=$(make_transcript shallow 90000)
deep=$(make_transcript deep 250000)
deep_1m=$(make_transcript deep1m 250000 'claude-opus-5[1m]')
deep_no1m=$(make_transcript deepno1m 250000 'claude-opus-5')

# Arrange & Act & Assert — the shape of every case below: reset_latches arranges, and the
# assert_* helper both acts (runs the hook) and asserts on its output. Each case's own
# arrange is its payload and env assignments. Sections that add a fixture label it.
reset_latches
assert_silent 'a shallow session is left alone' "$(payload "$shallow")" \
    CTX_COMPACT_THRESHOLD_TOKENS=900000

# h1 — the raw-grep trap: the prose 999999 must not be mistaken for a usage record, and the
# LAST usage record must win rather than the first or the largest.
reset_latches
assert_contains 'resident size is parsed, not grepped, and taken from the last record' \
    '.reason' 'reached 250k' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=900000

# --- The fire path ---------------------------------------------------------

reset_latches
assert_field 'a deep session with a declared ceiling and room is blocked' \
    '.decision' 'block' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=900000

reset_latches
assert_contains 'the block instruction names the skill to run' \
    '.reason' '/handoff' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=900000

reset_latches
assert_contains 'the block instruction carries the no-reading rule' \
    '.reason' 'do not read, grep or list' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=900000

# h2 — modelUsage keeps the [1m] suffix that message.model drops. Both are present in the
# fixture and they disagree; detecting on the wrong one under-reads the window.
reset_latches
assert_field 'the 1M beta is detected from modelUsage, not message.model' \
    '.decision' 'block' "$(payload "$deep_1m")"

reset_latches
assert_contains 'a detected ceiling says so, so the basis of the decision is legible' \
    '.reason' '1M beta' "$(payload "$deep_1m")"

# --- Declines --------------------------------------------------------------

reset_latches
assert_field 'no declared ceiling and no [1m] declines rather than guessing' \
    '.decision' 'null' "$(payload "$deep_no1m")"

reset_latches
assert_contains 'the decline names the signal that was missing' \
    '.systemMessage' 'ceiling is unknown' "$(payload "$deep_no1m")"

# A 200k-window session: compaction fires ~187k, below the 200k threshold, so the trigger is
# dead code there. It must say so rather than arm into a race it loses every time.
reset_latches
assert_contains 'a ceiling below the threshold declines on headroom' \
    '.systemMessage' 'declined to arm' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=187000

reset_latches
assert_field 'a headroom decline never blocks' \
    '.decision' 'null' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=187000

# The boundary: need = 250000 + 50000 + 30000 = 330000. Equal must decline, not arm.
reset_latches
assert_field 'headroom exactly equal to the ceiling declines' \
    '.decision' 'null' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=330000

reset_latches
assert_field 'one token of headroom above the ceiling arms' \
    '.decision' 'block' "$(payload "$deep")" CTX_COMPACT_THRESHOLD_TOKENS=330001

# --- The env override ------------------------------------------------------
#
# The thresholds file assigns CTX_COMPACT_THRESHOLD_TOKENS unconditionally, so a hook that
# sourced before capturing would clobber the environment value and decline forever.

reset_latches
assert_field 'an environment ceiling survives sourcing the file that blanks it' \
    '.decision' 'block' "$(payload "$deep_no1m")" CTX_COMPACT_THRESHOLD_TOKENS=900000

# And the file wins when the environment says nothing.
# Arrange
declared="$fixture/thresholds-declared.sh"
write_thresholds "$declared" 900000
reset_latches
assert_field 'a ceiling declared in the file alone is honoured' \
    '.decision' 'block' "$(payload "$deep_no1m")" CTX_THRESHOLDS_FILE="$declared"

# --- Latching --------------------------------------------------------------

# h4 — fire once per session, keyed on session_id and not on stop_hook_active.
# Arrange
reset_latches
# Act — fire once, so the latch is set
run "$(payload "$deep" sess-latch)" CTX_COMPACT_THRESHOLD_TOKENS=900000 >/dev/null
# Act & Assert
assert_silent 'a second Stop in the same session does not fire again' \
    "$(payload "$deep" sess-latch)" CTX_COMPACT_THRESHOLD_TOKENS=900000

assert_field 'a different session is unaffected by that latch' \
    '.decision' 'block' "$(payload "$deep" sess-other)" CTX_COMPACT_THRESHOLD_TOKENS=900000

# h5 — a decline latches too, or its message repeats at every turn boundary thereafter.
# Arrange
reset_latches
# Act — decline once, so the decline latch is set
run "$(payload "$deep_no1m" sess-decline)" >/dev/null
# Act & Assert
assert_silent 'a decline is said once, not at every subsequent turn' \
    "$(payload "$deep_no1m" sess-decline)"

# The harness's own re-entry flag: we are already inside the continuation this hook caused.
reset_latches
assert_silent 'stop_hook_active falls through rather than blocking again' \
    "$(payload "$deep" sess-1 true)" CTX_COMPACT_THRESHOLD_TOKENS=900000

# --- Background work -------------------------------------------------------
#
# Backgrounded work survives a /clear and reports into the FRESH session, which has no idea what
# it was for. The instruction has to name it or the handoff will not record its disposition.

reset_latches
assert_contains 'in-flight background tasks are named in the instruction' \
    '.reason' 'phpstan sweep' "$(payload "$deep" sess-bg false '{background_tasks:[{id:"t1",type:"shell",status:"running",description:"phpstan sweep"}]}')" \
    CTX_COMPACT_THRESHOLD_TOKENS=900000

reset_latches
assert_contains 'session crons are read as well as background tasks' \
    '.reason' 'scheduled: check CI' "$(payload "$deep" sess-cron false '{session_crons:[{schedule:"*/5 * * * *",recurring:true,prompt:"check CI"}]}')" \
    CTX_COMPACT_THRESHOLD_TOKENS=900000

reset_latches
assert_contains 'with nothing in flight the instruction says nothing about it' \
    '.reason' 'once per session' "$(payload "$deep" sess-nobg)" CTX_COMPACT_THRESHOLD_TOKENS=900000

# --- The written_at_tokens sidecar ------------------------------------------
#
# Once this session's own latch is set, the hook watches for the handoff it demanded actually
# landing on disk and records the resident size AT THAT MOMENT into a sidecar beside the latch --
# the figure the `compact` read leg needs to measure how much grew between the write and an
# eventual auto-compaction. Exercised against a REAL scratch git repo and a real handoff store
# directory, because git-worktree resolution and store lookup are the mechanism under test here,
# not something worth faking.

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 2; }

# shellcheck source=../lib/handoff-store.sh
. "$script_dir/../lib/handoff-store.sh"

sidecar_repo="$fixture/sidecar-repo"
mkdir -p "$sidecar_repo"
git -C "$sidecar_repo" init -q -b main
git -C "$sidecar_repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
sidecar_store="$fixture/sidecar-store"
mkdir -p "$sidecar_store"

HANDOFF_STORE_DIR="$sidecar_store"
sidecar_main=$(git -C "$sidecar_repo" worktree list | head -1 | awk '{print $1}')
sidecar_handoff=$(handoff_store_path "$sidecar_main" main)
unset HANDOFF_STORE_DIR

sidecar_payload() {  # sidecar_payload <session-id> [stop_hook_active] [cwd]
    payload "$deep" "$1" "${2:-false}" "$(jq -nc --arg c "${3:-$sidecar_repo}" '{cwd:$c}')"
}

sidecar_file() { printf '%s/.claude/state/handoff-trigger/%s.written' "$fixture/home" "$1"; }

# Arrange — arm, so the latch exists for the rest of this section.
reset_latches
run "$(sidecar_payload sess-sc-1)" CTX_COMPACT_THRESHOLD_TOKENS=900000 HANDOFF_STORE_DIR="$sidecar_store" >/dev/null

# Act & Assert — nothing has been written to the store yet, so the next Stop must stay silent
# AND must not manufacture a sidecar out of no evidence.
assert_silent 'the Stop right after arming is itself silent' \
    "$(sidecar_payload sess-sc-1 true)" CTX_COMPACT_THRESHOLD_TOKENS=900000 HANDOFF_STORE_DIR="$sidecar_store"
if [ ! -e "$(sidecar_file sess-sc-1)" ]; then
    passed=$((passed + 1)); echo "ok   no sidecar is written before the handoff exists"
else
    failed=$((failed + 1)); echo "FAIL no sidecar is written before the handoff exists — one was written anyway"
fi

# Arrange — the handoff lands, necessarily after the latch (this write happens second).
mkdir -p "$(dirname "$sidecar_handoff")"
printf -- '---\nbranch: main\ncheckout: %s\n---\n\nbody\n' "$sidecar_repo" > "$sidecar_handoff"

# Act
run "$(sidecar_payload sess-sc-1 true)" CTX_COMPACT_THRESHOLD_TOKENS=900000 HANDOFF_STORE_DIR="$sidecar_store" >/dev/null

# Assert
if [ -e "$(sidecar_file sess-sc-1)" ]; then
    passed=$((passed + 1)); echo "ok   the sidecar appears once the handoff's mtime moves past the latch"
    got=$(jq -r '.written_at_tokens' "$(sidecar_file sess-sc-1)" 2>/dev/null)
    if [ "$got" = "250000" ]; then
        passed=$((passed + 1)); echo "ok   written_at_tokens is the resident size at that Stop"
    else
        failed=$((failed + 1)); echo "FAIL written_at_tokens is the resident size at that Stop — got [$got]"
    fi
else
    failed=$((failed + 1)); echo "FAIL the sidecar appears once the handoff's mtime moves past the latch — none written"
fi

# An unrelated repo shares the same branch name but resolves to a DIFFERENT store filename (the
# hash half of `handoff_store_name` is keyed on the worktree path), so the only handoff in the
# store is a "recent" pick for it, never "exact". A recent pick must never populate the sidecar --
# misattributing someone else's write would poison the coverage check with the wrong figure.
reset_latches
other_repo="$fixture/sidecar-repo-other"
mkdir -p "$other_repo"
git -C "$other_repo" init -q -b main
git -C "$other_repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
run "$(sidecar_payload sess-sc-2 false "$other_repo")" \
    CTX_COMPACT_THRESHOLD_TOKENS=900000 HANDOFF_STORE_DIR="$sidecar_store" >/dev/null
run "$(sidecar_payload sess-sc-2 true "$other_repo")" \
    CTX_COMPACT_THRESHOLD_TOKENS=900000 HANDOFF_STORE_DIR="$sidecar_store" >/dev/null
if [ ! -e "$(sidecar_file sess-sc-2)" ]; then
    passed=$((passed + 1)); echo "ok   a recent (not exact) pick never populates the sidecar"
else
    failed=$((failed + 1)); echo "FAIL a recent (not exact) pick never populates the sidecar — one was written"
fi

# --- Degrading -------------------------------------------------------------
#
# Every one of these is "capability, never execution": the hook goes quiet, and the session
# proceeds exactly as it would with no hook installed.

reset_latches
assert_silent 'a missing thresholds file disables the hook entirely' \
    "$(payload "$deep")" CTX_THRESHOLDS_FILE="$fixture/nonexistent.sh" CTX_COMPACT_THRESHOLD_TOKENS=900000

# h3 — a thresholds file older than this hook.
# Arrange
old="$fixture/thresholds-old.sh"
printf 'CTX_NOTICE_TOKENS=120000\nCTX_URGE_TOKENS=200000\nCTX_COMPACT_THRESHOLD_TOKENS=\n' > "$old"
reset_latches
assert_silent 'a thresholds file predating the headroom terms stays silent, not zero' \
    "$(payload "$deep")" CTX_THRESHOLDS_FILE="$old"

reset_latches
assert_silent 'an unreadable transcript disables the hook' \
    "$(payload "$fixture/no-such-transcript.jsonl")" CTX_COMPACT_THRESHOLD_TOKENS=900000

# Arrange
empty="$fixture/empty.jsonl"
: > "$empty"
reset_latches
assert_silent 'a transcript with no usage record disables the hook' \
    "$(payload "$empty")" CTX_COMPACT_THRESHOLD_TOKENS=900000

# Arrange
garbage="$fixture/garbage.jsonl"
printf 'not json at all\n{"partial":\n' > "$garbage"
reset_latches
assert_silent 'a malformed transcript disables the hook rather than erroring' \
    "$(payload "$garbage")" CTX_COMPACT_THRESHOLD_TOKENS=900000

reset_latches
assert_silent 'a payload with no session_id disables the hook' \
    "$(jq -nc --arg t "$deep" '{transcript_path: $t, hook_event_name: "Stop"}')" \
    CTX_COMPACT_THRESHOLD_TOKENS=900000

reset_latches
assert_silent 'a payload with no transcript_path disables the hook' \
    '{"session_id":"s","hook_event_name":"Stop"}' CTX_COMPACT_THRESHOLD_TOKENS=900000

reset_latches
assert_silent 'empty stdin disables the hook' '' CTX_COMPACT_THRESHOLD_TOKENS=900000

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
