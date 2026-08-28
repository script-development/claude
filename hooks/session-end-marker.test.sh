#!/usr/bin/env bash
#
# Tests for session-end-marker.sh.
#
# What this hook exists to prevent is a SILENCE: a /clear typed before the write trigger fired
# discards the session, and nothing anywhere says so, which makes an undocumented reset and a
# properly handed-off one look identical. So the assertions split two ways — the marker must
# appear when a clear really happened, and must NOT appear for the session endings that lose
# nothing, because a marker that cries wolf gets ignored and the silence returns by another route.
#
# Cases that are the point rather than routine:
#
#   m1  the resident figure must be real. F9 established that SessionEnd is awaited and runs
#       BEFORE the messages are emptied, which is the only reason a true depth is readable here.
#       This is what separates "cleared a shallow session, nothing lost" from "discarded 300k of
#       work", and the surface needs the distinction to decide whether to say anything urgent.
#   m2  the handoff MTIME, captured at clear time, is the whole basis of the one judgement the
#       surface makes: does the handoff on disk describe the session just thrown away, or an
#       older one? Without it a stale handoff gets injected as though it were coverage.
#   m3  `urge_fired` distinguishes two different mistakes — the clear beat the threshold (trigger
#       never armed) versus the human cleared past a handoff that had been asked for. Recording
#       only "no handoff" would conflate them.
#   m4  the key is the MAIN worktree, not the cwd. A clear inside a linked worktree must file
#       under main+branch or the surface, which resolves main the same way, will never find it.
#   m5  the newest clear replaces the older one. A marker is news about one reset; accumulating
#       them would let an old loss be reported against a new event.
#
# No framework, matching the sibling hook suites. Run it as:
#
#   bash hooks/session-end-marker.test.sh

set -uo pipefail

# Arrange
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/session-end-marker.sh"

if [ ! -r "$subject" ]; then
    echo "session-end-marker.sh not found at $subject" >&2
    exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

passed=0
failed=0

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

state="$fixture/state"
home="$fixture/home"

repo="$fixture/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name  Test
echo hello > "$repo/file.txt"
git -C "$repo" add -A
git -C "$repo" commit -q -m init

# The store, isolated by `run`'s HOME redirect. Same formula as handoff-inject.test.sh, written out
# by hand for the same reason: the filename is the CONTRACT between the write leg, that hook and
# this one, so a test that derived it from the function under test would ratify any change to it.
store="$home/.claude/context-economy/handoffs"
mkdir -p "$store"
main_git=$(git -C "$repo" worktree list | head -1 | awk '{print $1}')
store_name() {  # store_name <target-main> <slug>
    printf '%s-%s-%s.md' \
        "$(printf '%s' "$(basename "$1")" | tr -c 'A-Za-z0-9._-' '_')" \
        "$(printf '%s' "$2" | tr -c 'A-Za-z0-9._-' '_')" \
        "$(printf '%s' "$1" | md5sum | cut -c1-8)"
}

transcript="$fixture/t.jsonl"
{
    jq -nc '{type:"assistant",message:{usage:{input_tokens:2,cache_creation_input_tokens:1000,cache_read_input_tokens:5000}}}'
    jq -nc '{type:"assistant",message:{usage:{input_tokens:2,cache_creation_input_tokens:3000,cache_read_input_tokens:297000}}}'
} > "$transcript"

payload() {  # payload <reason> [cwd] [session_id]
    jq -nc --arg r "$1" --arg c "${2:-$repo}" --arg s "${3:-sess-1}" --arg t "$transcript" \
        '{session_id:$s, hook_event_name:"SessionEnd", reason:$r, cwd:$c, transcript_path:$t}'
}

run() {  # run <payload>
    printf '%s' "$1" | env HOME="$home" LAST_CLEAR_STATE_DIR="$state" bash "$subject" 2>/dev/null
}

# The hook keys on the MAIN worktree, resolved through git, so the expected filename is computed
# the same way rather than assumed from the shell's own path form (git reports C:/... on Windows
# where mktemp reports /tmp/..., and hardcoding either makes a correct hook look broken).
marker_for() {  # marker_for <repo-or-worktree-dir> <branch-slug>
    local m k
    m=$(git -C "$1" worktree list 2>/dev/null | head -1 | awk '{print $1}')
    k=$(printf '%s' "$m" | md5sum | cut -c1-32)
    printf '%s/%s-%s.json' "$state" "$k" "$2"
}

pass() { passed=$((passed + 1)); echo "ok   $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1 — $2"; }

marker_count() { ls -1 "$state"/*.json 2>/dev/null | wc -l | tr -d ' '; }
reset_state()  { rm -rf "$state"; }

assert_field() {  # assert_field <label> <marker-path> <jq-filter> <expected>
    local got; got=$(jq -r "$3" "$2" 2>/dev/null)
    [ "$got" = "$4" ] && pass "$1" || fail "$1" "expected [$4], got [${got:-<none>}]"
}

# --- Reasons that lose nothing must stay silent ----------------------------
#
# `resume` keeps its context. `logout` and `prompt_input_exit` end the session rather than
# resetting it, and the next one is a `startup`, where nothing is surfaced — a report about a
# session the human deliberately walked away from would be noise, not news.

# Arrange & Act & Assert — one reason per iteration: reset, run, count.
for r in resume logout prompt_input_exit other; do
    reset_state
    run "$(payload "$r")" >/dev/null
    [ "$(marker_count)" = "0" ] && pass "reason: $r writes no marker" \
                               || fail "reason: $r writes no marker" "wrote $(marker_count)"
done

# --- A real clear ----------------------------------------------------------

# Arrange
reset_state
# Act
out=$(run "$(payload clear)")
# Assert
[ -z "$out" ] && pass 'the hook prints nothing (SessionEnd cannot inject)' \
              || fail 'the hook prints nothing (SessionEnd cannot inject)' "got: $out"

m=$(marker_for "$repo" main)
[ -r "$m" ] && pass 'a clear writes a marker keyed by main worktree and branch' \
            || fail 'a clear writes a marker keyed by main worktree and branch' "no marker at $m"

jq -e . "$m" >/dev/null 2>&1 && pass 'the marker is valid JSON' \
                             || fail 'the marker is valid JSON' 'jq could not parse it'

assert_field 'the reason is recorded' "$m" '.reason' 'clear'
assert_field 'the session id is recorded' "$m" '.session_id' 'sess-1'
assert_field 'the branch is recorded' "$m" '.branch' 'main'

# m1 — summed across all three input components, and taken from the LAST usage record. Reading
# only input_tokens would report 2 on every real session, since almost everything is cached.
assert_field 'the resident depth at the clear is recorded' "$m" '.resident_tokens' '300002'

# The transcript path is the payload of this whole exercise: it survives the clear, and is the
# only remaining record of the discarded session. It must be recorded EXACTLY as supplied, because
# the surface hands it to the model, which will pass it to a file-reading tool that wants a native
# path -- `cygpath -u` would turn it into `/c/Users/...`, readable to bash and to nothing else.
#
# The expected value is read back OUT OF THE PAYLOAD rather than taken from `$transcript`, and that
# is not pedantry: MSYS rewrites POSIX-looking ARGV for native binaries, so `jq --arg t /tmp/x`
# hands jq `C:/Users/.../Temp/x` before jq ever sees it. The payload therefore already holds the
# Windows form, the hook records it faithfully, and comparing against the shell's own variable
# fails a hook that is behaving perfectly. (Production is unaffected: the harness delivers this
# path inside the stdin JSON, where nothing mangles it.)
expected_transcript=$(printf '%s' "$(payload clear)" | jq -r '.transcript_path')
assert_field 'the surviving transcript path is recorded verbatim' "$m" '.transcript_path' "$expected_transcript"

# --- m2 — the handoff mtime, which is what makes coverage answerable -------

# Arrange
reset_state
# Act
run "$(payload clear)" >/dev/null
# Assert
assert_field 'no handoff on the branch is recorded as absent' "$(marker_for "$repo" main)" '.handoff.present' 'false'
assert_field 'an absent handoff has a null mtime, not a zero one' "$(marker_for "$repo" main)" '.handoff.mtime' 'null'

# Arrange
exact="$store/$(store_name "$main_git" main)"
printf 'a handoff\n' > "$exact"
expected_mtime=$(stat -c %Y "$exact")
reset_state
# Act
run "$(payload clear)" >/dev/null
# Assert
m=$(marker_for "$repo" main)
assert_field 'a present handoff is recorded as present' "$m" '.handoff.present' 'true'
assert_field 'the handoff mtime at clear time is captured' "$m" '.handoff.mtime' "$expected_mtime"

# The path is recorded too, and it must be the STORE path. This is the pairing requirement: the
# mtime above is the sole basis of the coverage sentence handoff-inject.sh prints, and if the two
# hooks resolve different files then "written 2 minutes before that clear" gets attached to a
# document it was never measured from. Both go through handoff_store_resolve for exactly this.
# Expected value round-tripped through jq, not compared to the shell's own string. MSYS rewrites
# POSIX-looking argv for NATIVE binaries, and jq is native: `--arg p /tmp/x` hands jq
# `C:/Users/.../Temp/x`. The hook records through jq, so the only honest comparison is against
# what actually went in. Compared to `$exact` directly, this fails on a hook that is correct.
as_recorded() { jq -nr --arg p "$1" '$p'; }
assert_field 'the recorded path is the store path, not a repo-local one' \
    "$m" '.handoff.path' "$(as_recorded "$exact")"

# A handoff for a SIBLING checkout, with none for this session's own branch. Nothing derived from
# cwd can find it -- so a marker that still reports `present: false` here is the regression that
# would make every cross-repo clear look like undocumented work.
# Arrange
other="$fixture/other-repo"
mkdir -p "$other"
git -C "$other" init -q -b feature/other
git -C "$other" config user.email t@example.com
git -C "$other" config user.name  Test
git -C "$other" commit -q --allow-empty -m init
other_main=$(git -C "$other" worktree list | head -1 | awk '{print $1}')
cross="$store/$(store_name "$other_main" feature-other)"
rm -f "$exact"
printf 'a sibling handoff\n' > "$cross"
reset_state
# Act
run "$(payload clear)" >/dev/null
# Assert
m=$(marker_for "$repo" main)
assert_field 'a handoff for a sibling checkout is still found' "$m" '.handoff.present' 'true'
assert_field 'and it is the sibling one that gets recorded'     "$m" '.handoff.path' "$(as_recorded "$cross")"
rm -f "$cross"
printf 'a handoff\n' > "$exact"

# --- m3 — did the trigger ever arm? ---------------------------------------

# Arrange
reset_state
# Act
run "$(payload clear "$repo" sess-noarm)" >/dev/null
# Assert
assert_field 'a clear that beat the trigger records urge_fired false' \
    "$(marker_for "$repo" main)" '.urge_fired' 'false'

# Arrange
mkdir -p "$home/.claude/state/handoff-trigger"
: > "$home/.claude/state/handoff-trigger/sess-armed"
reset_state
# Act
run "$(payload clear "$repo" sess-armed)" >/dev/null
# Assert
assert_field 'a clear after the trigger fired records urge_fired true' \
    "$(marker_for "$repo" main)" '.urge_fired' 'true'

# --- Branch slugging and separation ---------------------------------------

# Arrange
git -C "$repo" checkout -q -b fix/foo
reset_state
# Act
run "$(payload clear)" >/dev/null
# Assert
[ -r "$(marker_for "$repo" fix-foo)" ] && pass 'a branch containing a slash slugs its marker filename' \
                                       || fail 'a branch containing a slash slugs its marker filename' 'not found'

# Two branches cleared in the same repo must not overwrite each other: they are separate threads
# of work and the surface is branch-scoped.
# Arrange
git -C "$repo" checkout -q main
# Act
run "$(payload clear)" >/dev/null
# Assert
[ "$(marker_count)" = "2" ] && pass 'markers for different branches coexist' \
                            || fail 'markers for different branches coexist' "found $(marker_count)"

# m5 — but a second clear on the SAME branch replaces the first.
# Arrange
before=$(jq -r '.session_id' "$(marker_for "$repo" main)" 2>/dev/null)
# Act
run "$(payload clear "$repo" sess-newer)" >/dev/null
# Assert
after=$(jq -r '.session_id' "$(marker_for "$repo" main)" 2>/dev/null)
if [ "$before" != "$after" ] && [ "$after" = "sess-newer" ] && [ "$(marker_count)" = "2" ]; then
    pass 'a newer clear on the same branch replaces the older marker'
else
    fail 'a newer clear on the same branch replaces the older marker' "before=$before after=$after count=$(marker_count)"
fi

# --- m4 — keyed by the MAIN worktree --------------------------------------
#
# The surface resolves `main` the same way. A marker filed under the linked worktree's own path
# would simply never be found, and the failure would be a silence — the exact thing this hook
# exists to eliminate.

# Arrange
wt="$fixture/wt"
git -C "$repo" worktree add -q -b feature/x "$wt" >/dev/null 2>&1
reset_state
# Act
run "$(payload clear "$wt")" >/dev/null
# Assert
[ -r "$(marker_for "$wt" feature-x)" ] && pass 'a clear inside a linked worktree files under the main worktree' \
                                       || fail 'a clear inside a linked worktree files under the main worktree' 'not found'
assert_field 'a worktree clear records its own branch, not the main one' \
    "$(marker_for "$wt" feature-x)" '.branch' 'feature/x'

# --- Degrading ------------------------------------------------------------

# Arrange
reset_state
# Act
run "$(payload clear "$fixture")" >/dev/null
# Assert
[ "$(marker_count)" = "0" ] && pass 'a clear outside a repo writes no marker' \
                            || fail 'a clear outside a repo writes no marker' "wrote $(marker_count)"

# Arrange
reset_state
# Act
run "$(payload clear "$fixture/no-such-dir")" >/dev/null
# Assert
[ "$(marker_count)" = "0" ] && pass 'a nonexistent cwd writes no marker' \
                            || fail 'a nonexistent cwd writes no marker' "wrote $(marker_count)"

# Arrange
reset_state
# Act
printf '%s' '{"hook_event_name":"SessionEnd"}' \
    | env HOME="$home" LAST_CLEAR_STATE_DIR="$state" bash "$subject" 2>/dev/null
# Assert
[ "$(marker_count)" = "0" ] && pass 'a payload with no reason writes no marker' \
                            || fail 'a payload with no reason writes no marker' "wrote $(marker_count)"

# Arrange
reset_state
# Act
printf '' | env HOME="$home" LAST_CLEAR_STATE_DIR="$state" bash "$subject" 2>/dev/null
# Assert
[ "$(marker_count)" = "0" ] && pass 'empty stdin writes no marker' \
                            || fail 'empty stdin writes no marker' "wrote $(marker_count)"

# An unreadable transcript must not discard the marker: the clear still happened, and the branch
# and handoff-coverage facts are still worth surfacing. Only the depth is unknown.
# Arrange
reset_state
# Act
printf '%s' "$(jq -nc --arg c "$repo" '{session_id:"s",hook_event_name:"SessionEnd",reason:"clear",cwd:$c,transcript_path:"/nope.jsonl"}')" \
    | env HOME="$home" LAST_CLEAR_STATE_DIR="$state" bash "$subject" 2>/dev/null
# Assert
[ "$(marker_count)" = "1" ] && pass 'an unreadable transcript still yields a marker' \
                            || fail 'an unreadable transcript still yields a marker' "wrote $(marker_count)"
assert_field 'an unknown depth is null rather than zero' \
    "$(marker_for "$repo" main)" '.resident_tokens' 'null'

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
