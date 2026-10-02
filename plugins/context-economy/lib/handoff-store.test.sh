#!/usr/bin/env bash
#
# Tests for lib/handoff-store.sh.
#
# What is left of the store after v2.0.0 is naming and reading, so the interesting case is:
#
#   s1  the filename is a CONTRACT. The skill's Step 1 and lib/handoff-orient.sh (for
#       hooks/register.ts) both compute it and must agree. Two repositories sharing a basename must
#       not share a filename, or one project's handoff silently answers for another's.
#
# No framework, matching the hook suites. Run it as:
#
#   bash lib/handoff-store.test.sh

set -uo pipefail

# Arrange
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/handoff-store.sh"

if [ ! -r "$subject" ]; then
    echo "handoff-store.sh not found at $subject" >&2
    exit 2
fi

passed=0
failed=0
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

export HANDOFF_STORE_DIR="$fixture/store"
mkdir -p "$HANDOFF_STORE_DIR"

# shellcheck source=handoff-store.sh
. "$subject"

pass() { passed=$((passed + 1)); echo "ok   $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1 — $2"; }

assert_eq() {  # assert_eq <label> <expected> <actual>
    [ "$2" = "$3" ] && pass "$1" || fail "$1" "expected [$2], got [$3]"
}

# put <target-main> <slug> <branch> <checkout> [mtime-offset-seconds]
# Writes a minimal handoff and back-dates it, so ordering is deterministic rather than dependent
# on how fast the suite runs -- two files written in the same second would tie, and a tie makes the
# recency test pass or fail by luck.
put() {
    local target=$1 slug=$2 branch=$3 checkout=$4 offset=${5:-0} path
    path="$(handoff_store_path "$target" "$slug")"
    printf '# Handoff — fixture\nbranch: %s\ncheckout: %s\nstatus: x\n' \
        "$branch" "$checkout" > "$path"
    if [ "$offset" -ne 0 ]; then
        touch -d "@$(( $(date +%s) - offset ))" "$path" 2>/dev/null \
            || touch -t "$(date -d "@$(( $(date +%s) - offset ))" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$(( $(date +%s) - offset ))" +%Y%m%d%H%M.%S)" "$path"
    fi
    printf '%s' "$path"
}

# --- portable md5 / mtime ---------------------------------------------------
#
# Smoke tests only, on whichever implementation this machine actually has (md5sum/`stat -c` on
# every platform this suite has run on so far). They do not exercise the BSD/macOS fallback branch
# -- reliably forcing `command -v md5sum` to fail while leaving the rest of this script's own
# tooling (cut, cat, mkdir...) on PATH is not worth the fragility it would add, and a stub `md5`
# would only prove this code calls a command named `md5`, not that BSD's actually behaves the way
# the comment above handoff_store_md5 assumes. That assumption is implemented, not measured --
# see handoff_store_md5's and handoff_store_mtime's own comments in the subject.

# Act & Assert
hash_out=$(printf '%s' fixture-string | handoff_store_md5)
case "$hash_out" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
        pass 'handoff_store_md5 returns 32 lowercase hex characters' ;;
    *) fail 'handoff_store_md5 returns 32 lowercase hex characters' "got [$hash_out]" ;;
esac

assert_eq 'handoff_store_md5 is deterministic for the same input' \
    "$hash_out" "$(printf '%s' fixture-string | handoff_store_md5)"

# Arrange — a file whose mtime is known exactly, not merely recent.
mtime_fixture="$fixture/mtime-probe"
: > "$mtime_fixture"
known_epoch=$(( $(date +%s) - 12345 ))
touch -d "@$known_epoch" "$mtime_fixture" 2>/dev/null \
    || touch -t "$(date -d "@$known_epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$known_epoch" +%Y%m%d%H%M.%S)" "$mtime_fixture"
# Act & Assert
assert_eq 'handoff_store_mtime reads back a known mtime' "$known_epoch" "$(handoff_store_mtime "$mtime_fixture")"
assert_eq 'handoff_store_mtime is empty, not fabricated, for a missing file' \
    '' "$(handoff_store_mtime "$fixture/does-not-exist")"

# --- s1 — the filename contract --------------------------------------------

# Act & Assert — the subject is called inline; each case's arrange is its arguments.
#
# The oracle goes through handoff_store_md5 too, not a hardcoded `md5sum` call: the subject now
# tries `md5` as a BSD/macOS fallback when `md5sum` is absent (see handoff_store_md5's own
# comment), and a test that computed its expected value a different way than the code under test
# would silently stop meaning anything on a machine that takes the fallback branch.
name=$(handoff_store_name /c/checkouts/emmie EMMIE-0477)
assert_eq 'the name carries the repo basename, the slug and a hash' \
    "emmie-EMMIE-0477-$(printf '%s' /c/checkouts/emmie | handoff_store_md5 | cut -c1-8).md" "$name"

a=$(handoff_store_name /c/one/emmie main)
b=$(handoff_store_name /c/two/emmie main)
[ "$a" != "$b" ] && pass 'two checkouts sharing a basename get different filenames' \
                 || fail 'two checkouts sharing a basename get different filenames' "both [$a]"

# A path is not a filename and a branch is not either. Unslugged, a space splits an argument
# downstream and a slash creates a directory that nothing looks in.
spacey=$(handoff_store_name '/c/my checkouts/the repo' 'fix-a b')
case "$spacey" in
    *' '*) fail 'spaces in a repo or branch name are slugged out' "got [$spacey]" ;;
    *)     pass 'spaces in a repo or branch name are slugged out' ;;
esac

assert_eq 'the store root honours HANDOFF_STORE_DIR' "$fixture/store" "$(handoff_store_dir)"

# --- Envelope reading ------------------------------------------------------

# Arrange
f=$(put /c/checkouts/emmie EMMIE-0477 EMMIE-0477 /c/worktrees/emmie-477)
# Act & Assert
assert_eq 'branch: is read from the envelope' 'EMMIE-0477' "$(handoff_store_field "$f" branch)"
assert_eq 'checkout: is read from the envelope' '/c/worktrees/emmie-477' \
    "$(handoff_store_field "$f" checkout)"

# Bounded to the head of the document on purpose: a `checkout:` further down is body text -- a
# quoted example, a field note about another run -- and treating it as this document's own header
# would aim the gate at whatever tree that prose happened to mention.
# Arrange
{ printf '\n\n'; for i in $(seq 30); do echo "- padding $i"; done; echo 'checkout: /c/decoy'; } >> "$f"
# Act & Assert
assert_eq 'a checkout: far down the body is not mistaken for the header' \
    '/c/worktrees/emmie-477' "$(handoff_store_field "$f" checkout)"

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi
echo "OK: all $passed assertions passed"
