#!/usr/bin/env bash
#
# Tests for hooks/handoff-fork-write.sh -- the fast, synchronous half only (guards, dedup lock,
# path resolution, prompt content). The detached half genuinely spawns a real `claude -p` call and
# there is no fake `claude` on PATH here deliberately -- `lib/handoff-store.test.sh` already
# decided against stubbing a command this bundle depends on for real (see its own "portable md5 /
# mtime" comment on why a stub proves the code calls a command, not that the real one behaves as
# assumed), and the same judgement applies more strongly to `claude` itself: a fake `claude` would
# prove this hook can invoke *a* command by that name, nothing about whether a real detached
# authoring turn works, which `docs/measured.md` findings #24-#30 already establish by actually
# running one. What IS deterministic and worth covering here -- every guard, and the dedup lock --
# is covered without ever letting a real turn run.
#
# Run it as:
#
#   bash hooks/handoff-fork-write.test.sh

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/handoff-fork-write.sh"

if [ ! -r "$subject" ]; then
    echo "handoff-fork-write.sh not found at $subject" >&2
    exit 2
fi

passed=0
failed=0
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

pass() { passed=$((passed + 1)); echo "ok   $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1 — $2"; }

assert_eq() {  # assert_eq <label> <expected> <actual>
    [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected [$2], got [$3]"
}

# ── Arrange: a fixture repo (TARGET), a fixture "transcript" (any readable file — the guards only
# check readability, never content), and a redirected HOME so the dedup lock and the fallback
# ~/.claude/lib probe both land in the fixture, never the real machine's store. XDG_DATA_HOME is
# cleared for the same isolation reason handoff-inject.test.sh's run() clears it.
repo="$fixture/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.invalid
git -C "$repo" config user.name  Test
echo hello > "$repo/file.txt"
git -C "$repo" add -A
git -C "$repo" commit -q -m init

transcript="$fixture/transcript.jsonl"
printf '{"type":"user","message":{"content":"hi"}}\n' > "$transcript"

home="$fixture/home"
mkdir -p "$home/.claude/state/handoff-fork"

run() {  # run <payload> [env...]
    local p="$1"; shift
    printf '%s' "$p" | env HOME="$home" XDG_DATA_HOME= "$@" bash "$subject" 2>/dev/null
}

lock_count() { find "$home/.claude/state/handoff-fork" -name '*.lock' 2>/dev/null | wc -l | tr -d ' '; }

# --- Guards: every one of these must decline (silent, exit 0) before ever reaching the dedup
# lock or the claude/gate/store/skill probes, so none of them can be masked by this machine's own
# real claude install or its own real plugin cache. ---------------------------------------------

payload() {  # payload <session_id> <transcript> <cwd>
    printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","trigger":"auto"}' "$1" "$2" "$3"
}

out=$(run "$(payload '' "$transcript" "$repo")")
assert_eq 'a payload with no session_id declines silently' '' "$out"
assert_eq '...and writes no lock' 0 "$(lock_count)"

out=$(run "$(payload guard-1 '' "$repo")")
assert_eq 'a payload with no transcript_path declines silently' '' "$out"

out=$(run "$(payload guard-2 "$fixture/does-not-exist.jsonl" "$repo")")
assert_eq 'an unreadable transcript path declines silently' '' "$out"

out=$(printf '' | env HOME="$home" bash "$subject" 2>/dev/null)
assert_eq 'empty stdin declines silently' '' "$out"

# --- Dedup lock: the actual load-bearing logic in the synchronous half. -------------------------
#
# These four DO pass every guard and reach the real `command -v claude` check, so on a machine
# with `claude` on PATH they genuinely launch a real detached turn -- not stubbed, per the file
# header. CTX_FORK_TIMEOUT_SECONDS=1 bounds every one of them to a near-instant, near-zero-cost
# kill (measured while building this: the timed-out child produces no output at all within 1s,
# consistent with `timeout` firing before the CLI finishes starting up). What these assertions
# check is the LOCK's effect (present vs. absent, fresh vs. expired), never the detached turn's
# own behaviour, so they hold regardless of what a real spawn then does or how long it runs for.
# On a machine with no `claude` on PATH, the guard above the lock declines first and every
# assertion below fails the same way -- a real, informative failure ("claude required"), not a
# silent skip.

sid="dedup-$$"
run "$(payload "$sid" "$transcript" "$repo")" CTX_FORK_TIMEOUT_SECONDS=1 >/dev/null
assert_eq 'a first firing for a session writes a lock' 1 "$(lock_count)"

first_lock_mtime=$(stat -c %Y "$home/.claude/state/handoff-fork/$sid.lock" 2>/dev/null \
    || stat -f %m "$home/.claude/state/handoff-fork/$sid.lock" 2>/dev/null)

run "$(payload "$sid" "$transcript" "$repo")" CTX_FORK_DEDUP_WINDOW_SECONDS=90 CTX_FORK_TIMEOUT_SECONDS=1 >/dev/null
second_lock_mtime=$(stat -c %Y "$home/.claude/state/handoff-fork/$sid.lock" 2>/dev/null \
    || stat -f %m "$home/.claude/state/handoff-fork/$sid.lock" 2>/dev/null)
assert_eq 'a second firing inside the dedup window does not touch the lock again' \
    "$first_lock_mtime" "$second_lock_mtime"

run "$(payload "$sid" "$transcript" "$repo")" CTX_FORK_DEDUP_WINDOW_SECONDS=0 CTX_FORK_TIMEOUT_SECONDS=1 >/dev/null
third_lock_mtime=$(stat -c %Y "$home/.claude/state/handoff-fork/$sid.lock" 2>/dev/null \
    || stat -f %m "$home/.claude/state/handoff-fork/$sid.lock" 2>/dev/null)
[ "$third_lock_mtime" -ge "$first_lock_mtime" ] \
    && pass 'a firing past an (artificially zeroed) dedup window re-touches the lock' \
    || fail 'a firing past an (artificially zeroed) dedup window re-touches the lock' \
        "mtime did not advance: first=$first_lock_mtime third=$third_lock_mtime"

# A different session_id must never be blocked by another session's lock.
out_count_before=$(lock_count)
run "$(payload "other-$$" "$transcript" "$repo")" CTX_FORK_TIMEOUT_SECONDS=1 >/dev/null
assert_eq 'a different session_id gets its own lock, unaffected by an unrelated one' \
    "$((out_count_before + 1))" "$(lock_count)"

# --- Cleanup: every spawn above that passed the guards genuinely launched a real detached
# `claude -p` call (this machine's own install, no stub). Give them a moment, then sweep whatever
# they left in the real HOME's own state dir and scratch space so this test suite does not leave
# fictional handoff-fork artifacts lying around -- matching lib/handoff-store.test.sh's own probe
# cleanup discipline, not left to the OS temp dir's own GC.
sleep 2
rm -rf /tmp/handoff-fork.* 2>/dev/null

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi
echo "OK: all $passed assertions passed"
