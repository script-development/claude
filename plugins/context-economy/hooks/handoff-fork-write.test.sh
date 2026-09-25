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

# --- D23: the synchronous skeleton write ---------------------------------------------------
#
# Written by hand, not sourced from lib/handoff-store.sh, for the same reason
# handoff-inject.test.sh's own store_name() is: an oracle that called the function under test
# would agree with any change to it, including a wrong one.
store_name() {  # store_name <target-main> <slug>
    printf '%s-%s-%s.md' \
        "$(printf '%s' "$(basename "$1")" | tr -c 'A-Za-z0-9._-' '_')" \
        "$(printf '%s' "$2" | tr -c 'A-Za-z0-9._-' '_')" \
        "$(printf '%s' "$1" | md5sum | cut -c1-8)"
}

store="$fixture/store"
mkdir -p "$store"
main_git=$(git -C "$repo" worktree list | head -1 | awk '{print $1}')
skeleton_path="$store/$(store_name "$main_git" main)"

# Snapshotted before firing, not read as "newest by mtime" afterward: several earlier cases in
# this file (the dedup-lock quartet) also pass every guard and each leave their own scratch dir
# behind, so a diff is the unambiguous way to name the ONE this specific firing created.
# Where the hook's own `mktemp -d "${TMPDIR:-/tmp}/handoff-fork.XXXXXX"` lands: /tmp on
# Linux, /var/folders/... on macOS, whose TMPDIR also ends in a slash.
tmp_root=${TMPDIR:-/tmp}; tmp_root=${tmp_root%/}
scratch_before=$(ls -d "$tmp_root"/handoff-fork.* 2>/dev/null)

# Act — passes every guard (real session_id, real transcript, real repo) and reaches the
# skeleton write. CTX_FORK_TIMEOUT_SECONDS=1 still bounds whatever real detached turn follows to
# a near-instant kill, exactly as the dedup-lock cases above rely on; HANDOFF_STORE_DIR isolates
# the skeleton from both the real store and the other cases' own $home/.local/share default.
run "$(payload "skel-$$" "$transcript" "$repo")" CTX_FORK_TIMEOUT_SECONDS=1 HANDOFF_STORE_DIR="$store" >/dev/null

# Assert
[ -s "$skeleton_path" ] && pass 'a firing that passes every guard writes a skeleton at the resolved store path' \
    || fail 'a firing that passes every guard writes a skeleton at the resolved store path' 'no file at expected path'

case "$(cat "$skeleton_path" 2>/dev/null)" in
    *'progress: writing'*) pass 'the skeleton carries progress: writing' ;;
    *) fail 'the skeleton carries progress: writing' "got [$(cat "$skeleton_path" 2>/dev/null)]" ;;
esac

case "$(cat "$skeleton_path" 2>/dev/null)" in
    *"checkout: $main_git"*) pass 'the skeleton declares the repo it was fired for as checkout:' ;;
    *) fail 'the skeleton declares the repo it was fired for as checkout:' "got [$(cat "$skeleton_path" 2>/dev/null)]" ;;
esac

case "$(cat "$skeleton_path" 2>/dev/null)" in
    *'branch: main'*) pass 'the skeleton declares the branch it was fired for' ;;
    *) fail 'the skeleton declares the branch it was fired for' "got [$(cat "$skeleton_path" 2>/dev/null)]" ;;
esac

# --- D28: the pinned write-session id, real on this machine (no `claude` stub, per the file
# header) -- so this is measuring the ACTUAL fallback chain a real firing takes, not a mock of it.
if command -v uuidgen >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1; then
    case "$(cat "$skeleton_path" 2>/dev/null)" in
        *write_session:\ ????????-????-????-????-????????????*)
            pass 'the skeleton carries a UUID-shaped write_session: on a machine with uuidgen or openssl' ;;
        *) fail 'the skeleton carries a UUID-shaped write_session: on a machine with uuidgen or openssl' \
            "got [$(cat "$skeleton_path" 2>/dev/null)]" ;;
    esac
else
    # The other half of the fallback: neither tool exists, so the field is correctly omitted
    # rather than left empty (lib/handoff-store.test.sh already covers the omitted-arg case
    # directly; this confirms the write leg's OWN detection reaches the same empty value).
    case "$(cat "$skeleton_path" 2>/dev/null)" in
        *'write_session:'*) fail 'write_session: is omitted with neither uuidgen nor openssl available' \
            'field present anyway' ;;
        *) pass 'write_session: is omitted with neither uuidgen nor openssl available' ;;
    esac
fi

# The id the skeleton recorded must be the EXACT one this same firing passed to `--session-id` --
# not merely "a plausible-looking value", which would pass even if the two had silently diverged.
# Checked against the async runner script itself (written synchronously, before its own nohup
# spawn -- no race to wait out) rather than the real detached turn's own behaviour, which
# docs/measured.md's own probes already cover directly.
new_scratch=$(comm -13 <(printf '%s\n' "$scratch_before" | sort) <(ls -d "$tmp_root"/handoff-fork.* 2>/dev/null | sort))
recorded_id=$(grep -m1 '^write_session: ' "$skeleton_path" 2>/dev/null | sed 's/^write_session: //')
if [ -n "$recorded_id" ] && [ -n "$new_scratch" ] && [ -r "$new_scratch/run.sh" ]; then
    case "$(cat "$new_scratch/run.sh")" in
        *"--session-id $recorded_id"*) pass 'the id recorded in the skeleton is the exact one passed to --session-id' ;;
        *) fail 'the id recorded in the skeleton is the exact one passed to --session-id' \
            "run.sh: $(cat "$new_scratch/run.sh")" ;;
    esac
elif [ -z "$recorded_id" ]; then
    pass 'the id recorded in the skeleton is the exact one passed to --session-id (skipped: no id was generated)'
else
    fail 'the id recorded in the skeleton is the exact one passed to --session-id' \
        "could not locate this firing's own scratch dir (before=[$scratch_before] new=[$new_scratch])"
fi

# Unconditional overwrite: a REAL, already-complete handoff sitting at this path must still be
# replaced by the placeholder on the next firing -- D23's whole point is that the reset cannot be
# contingent on anything, including what was there before.
printf '# Handoff — real work\nbranch: main\ncheckout: %s\nstatus: ok\nprogress: complete\n\nreal content nobody should lose silently, but D23 accepts they will\n' \
    "$main_git" > "$skeleton_path"
run "$(payload "skel2-$$" "$transcript" "$repo")" CTX_FORK_TIMEOUT_SECONDS=1 HANDOFF_STORE_DIR="$store" >/dev/null
case "$(cat "$skeleton_path" 2>/dev/null)" in
    *'progress: writing'*) pass 'a real, already-complete handoff is unconditionally reset to writing on the next firing' ;;
    *) fail 'a real, already-complete handoff is unconditionally reset to writing on the next firing' \
        "got [$(cat "$skeleton_path" 2>/dev/null)]" ;;
esac

# --- Portability: macOS's uuidgen, and a host with no `timeout` -------------------------------
#
# These cases run against STUBS, unlike the ones above: a `claude` that sleeps and a `uuidgen`
# that prints uppercase, as macOS's does, first on PATH. What is under test is what the hook
# writes into run.sh and how that runner behaves, not a real detached turn.
# Arrange
stubs="$fixture/stubs"
mkdir -p "$stubs"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$stubs/claude"
printf '#!/usr/bin/env bash\necho 3F2504E0-4F89-11D3-9A0C-0305E82C3301\n' > "$stubs/uuidgen"
chmod +x "$stubs/claude" "$stubs/uuidgen"
new_runner() {  # new_runner <before-snapshot> — the run.sh of the one firing since the snapshot
    local d
    d=$(comm -13 <(printf '%s\n' "$1" | sort) <(ls -d "$tmp_root"/handoff-fork.* 2>/dev/null | sort) | tail -n 1)
    [ -n "$d" ] && printf '%s/run.sh' "$d"
}

# macOS's uuidgen prints uppercase. The id is recorded in the skeleton and later matched against
# the transcript's filename, so it must reach both places lowercased and identical.
# Act
before=$(ls -d "$tmp_root"/handoff-fork.* 2>/dev/null)
run "$(payload "upper-$$" "$transcript" "$repo")" PATH="$stubs:$PATH" CTX_FORK_TIMEOUT_SECONDS=1 HANDOFF_STORE_DIR="$store" >/dev/null
runner=$(new_runner "$before")
recorded=$(grep -m1 '^write_session: ' "$skeleton_path" 2>/dev/null | sed 's/^write_session: //')
# Assert
assert_eq "an uppercase uuidgen is recorded lowercased" '3f2504e0-4f89-11d3-9a0c-0305e82c3301' "$recorded"
case "$(cat "$runner" 2>/dev/null)" in
    *"--session-id 3f2504e0-4f89-11d3-9a0c-0305e82c3301"*) pass '...and passed to --session-id lowercased' ;;
    *) fail '...and passed to --session-id lowercased' "run.sh: $(cat "$runner" 2>/dev/null)" ;;
esac
bash -n "$runner" 2>/dev/null && pass 'the runner written with timeout available parses' \
    || fail 'the runner written with timeout available parses' "$(bash -n "$runner" 2>&1)"

# No `timeout` and no `gtimeout` — stock macOS. The runner used to call `timeout` regardless and
# exit 127 before the turn started. `timeout` sits in the same directory as tools the hook needs,
# so it cannot be hidden by PATH; an exported `command` function, which the hook's bash inherits,
# reports the two as absent and passes every other lookup through.
#
# Not on bash 3.2: there, calling a function imported from the environment empties the caller's
# top-level BASH_SOURCE, so the hook's own `${BASH_SOURCE[0]}` trips `set -u` and it exits before
# writing any runner (the hook's own functions do not do this; only imported ones). The runner
# would then be empty and the timing check below would pass against nothing, so both are skipped.
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    pass 'with no timeout binary the runner uses a watchdog (skipped: bash 3.2 cannot run the exported-function stub)'
    pass 'the watchdog ends a turn that overruns its bound (skipped: bash 3.2, as above)'
else
    # Arrange
    command() {
        if [ "${1:-}" = -v ] && { [ "${2:-}" = timeout ] || [ "${2:-}" = gtimeout ]; }; then return 1; fi
        builtin command "$@"
    }
    export -f command
    # Act
    before=$(ls -d "$tmp_root"/handoff-fork.* 2>/dev/null)
    run "$(payload "notimeout-$$" "$transcript" "$repo")" PATH="$stubs:$PATH" CTX_FORK_TIMEOUT_SECONDS=1 HANDOFF_STORE_DIR="$store" >/dev/null
    unset -f command
    runner=$(new_runner "$before")
    # Assert
    case "$(cat "$runner" 2>/dev/null)" in
        *timeout\ 1\ *) fail 'with no timeout binary the runner uses a watchdog' "calls timeout anyway: $(cat "$runner")" ;;
        *'kill $turn_pid'*) pass 'with no timeout binary the runner uses a watchdog' ;;
        *) fail 'with no timeout binary the runner uses a watchdog' "run.sh: $(cat "$runner" 2>/dev/null)" ;;
    esac
    # The watchdog must actually bound the turn: the stub sleeps 30s, the bound is 1s. A missing
    # runner is a failure, not a fast pass.
    # Act
    start=$SECONDS
    [ -r "$runner" ] && env HOME="$home" PATH="$stubs:$PATH" bash "$runner" >/dev/null 2>&1
    elapsed=$((SECONDS - start))
    # Assert
    if [ ! -r "$runner" ]; then
        fail 'the watchdog ends a turn that overruns its bound' 'no runner was written'
    elif [ "$elapsed" -le 10 ]; then
        pass "the watchdog ends a turn that overruns its bound (${elapsed}s for a 1s bound)"
    else
        fail 'the watchdog ends a turn that overruns its bound' "took ${elapsed}s against a 1s bound"
    fi
fi

# --- Cleanup: every spawn above that passed the guards genuinely launched a real detached
# `claude -p` call (this machine's own install, no stub). Give them a moment, then sweep whatever
# they left in the real HOME's own state dir and scratch space so this test suite does not leave
# fictional handoff-fork artifacts lying around -- matching lib/handoff-store.test.sh's own probe
# cleanup discipline, not left to the OS temp dir's own GC.
sleep 2
rm -rf "$tmp_root"/handoff-fork.* 2>/dev/null

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi
echo "OK: all $passed assertions passed"
