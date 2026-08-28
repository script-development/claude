#!/usr/bin/env bash
#
# Tests for lib/handoff-store.sh.
#
# This file decides WHICH handoff a fresh session is handed, and it has to make that decision from
# almost nothing: a SessionStart hook knows its cwd and no more. So the interesting cases are not
# "does it find a file" but the two ways it can be confidently wrong:
#
#   s1  the filename is a CONTRACT. The write leg computes it, handoff-inject.sh looks for it, and
#       session-end-marker.sh measures it. Two repositories sharing a basename must not share a
#       filename, or one project's handoff silently answers for another's.
#   s2  the pick must prefer an EXACT match over a newer stranger. Recency is the fallback, not the
#       rule -- a session standing in a repository that has its own handoff must get that one, or
#       the ordinary same-repo case regresses in favour of the exotic cross-repo one.
#   s3  the candidates NOT picked must come back. This is the entire advantage over a pointer file,
#       which resolves ambiguity by overwriting and cannot report what it discarded.
#
# No framework, matching the hook suites. Run it as:
#
#   bash plugins/context-economy/lib/handoff-store.test.sh

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
    printf '# Handoff — fixture\nbranch: %s\ncheckout: %s\ncompacted: no\nstatus: x\n' \
        "$branch" "$checkout" > "$path"
    if [ "$offset" -ne 0 ]; then
        touch -d "@$(( $(date +%s) - offset ))" "$path" 2>/dev/null \
            || touch -t "$(date -d "@$(( $(date +%s) - offset ))" +%Y%m%d%H%M.%S)" "$path"
    fi
    printf '%s' "$path"
}

# --- s1 — the filename contract --------------------------------------------

# Act & Assert — the subject is called inline; each case's arrange is its arguments.
name=$(handoff_store_name /c/checkouts/emmie EMMIE-0477)
assert_eq 'the name carries the repo basename, the slug and a hash' \
    "emmie-EMMIE-0477-$(printf '%s' /c/checkouts/emmie | md5sum | cut -c1-8).md" "$name"

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

# --- s2 — the pick ---------------------------------------------------------

# Arrange
rm -f "$HANDOFF_STORE_DIR"/*.md
# Act
handoff_store_resolve /c/checkouts/mc main
# Assert
assert_eq 'an empty store resolves to nothing' '' "$HANDOFF_FILE"

# Exact match, and a NEWER stranger alongside it. Recency must lose here.
# Arrange
exact=$(put /c/checkouts/mc main main /c/checkouts/mc 600)
newer=$(put /c/checkouts/emmie EMMIE-0477 EMMIE-0477 /c/worktrees/emmie-477 0)
# Act
handoff_store_resolve /c/checkouts/mc main
# Assert
assert_eq 'an exact match beats a more recent stranger' "$exact" "$HANDOFF_FILE"
assert_eq 'and it is labelled exact' 'exact' "$HANDOFF_PICK"

# No exact match: now recency decides, and the pick must say it was a guess.
# Act
handoff_store_resolve /c/checkouts/mc some-other-branch
# Assert
assert_eq 'with no exact match the most recent candidate wins' "$newer" "$HANDOFF_FILE"
assert_eq 'and it is labelled a guess' 'recent' "$HANDOFF_PICK"
assert_eq 'the pick carries the branch it belongs to' 'EMMIE-0477' "$HANDOFF_BRANCH"
assert_eq 'the pick carries the tree it describes' '/c/worktrees/emmie-477' "$HANDOFF_CHECKOUT"

# --- s3 — the rejected candidates ------------------------------------------

# Assert — on the state the previous act left behind
case "$HANDOFF_OTHERS" in
    *"$exact"*) pass 'a rejected candidate is reported' ;;
    *)          fail 'a rejected candidate is reported' "OTHERS was [$HANDOFF_OTHERS]" ;;
esac
case "$HANDOFF_OTHERS" in
    *"$newer"*) fail 'the pick itself is not listed among the others' "OTHERS contained the pick" ;;
    *)          pass 'the pick itself is not listed among the others' ;;
esac

# An older third candidate is still a candidate. The listing is the reader's only cheap correction,
# so it must be complete rather than a top-one runner-up.
# Arrange
third=$(put /c/checkouts/kendo KENDO-73 KENDO-73 /c/checkouts/kendo 9000)
# Act
handoff_store_resolve /c/checkouts/mc some-other-branch
# Assert
n=$(printf '%s' "$HANDOFF_OTHERS" | grep -c . )
assert_eq 'every rejected candidate is listed, not just the runner-up' '2' "$n"

# --- Degrading -------------------------------------------------------------

# An empty file is not a handoff. Skipped rather than picked, or a truncated write would shadow a
# perfectly good older document and inject a header with nothing under it.
# Arrange
: > "$third"
# Act
handoff_store_resolve /c/checkouts/mc some-other-branch
# Assert
assert_eq 'an empty candidate is skipped' "$newer" "$HANDOFF_FILE"
case "$HANDOFF_OTHERS" in
    *"$third"*) fail 'an empty candidate is not listed either' "OTHERS contained it" ;;
    *)          pass 'an empty candidate is not listed either' ;;
esac

# A store that does not exist at all is the state of every machine before the first handoff.
# Act
HANDOFF_STORE_DIR="$fixture/no-such-store" handoff_store_resolve /c/checkouts/mc main
# Assert
assert_eq 'a nonexistent store resolves to nothing rather than erroring' '' "$HANDOFF_FILE"

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi
echo "OK: all $passed assertions passed"
