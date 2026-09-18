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
    printf '# Handoff — fixture\nbranch: %s\ncheckout: %s\ncompacted: no\nstatus: x\n' \
        "$branch" "$checkout" > "$path"
    if [ "$offset" -ne 0 ]; then
        touch -d "@$(( $(date +%s) - offset ))" "$path" 2>/dev/null \
            || touch -t "$(date -d "@$(( $(date +%s) - offset ))" +%Y%m%d%H%M.%S)" "$path"
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
    || touch -t "$(date -d "@$known_epoch" +%Y%m%d%H%M.%S)" "$mtime_fixture"
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

# --- D23 — the skeleton and the progress field ------------------------------
#
# handoff_store_write_skeleton is the WRITE leg's half of the compaction-race fix: called
# synchronously, before any detached authoring turn exists, so a reader arriving mid-write finds
# an honest placeholder rather than silence or a stale `complete` document. handoff_store_set_progress
# is the READ leg's half: it flips `progress:` after a document has actually been shown to someone.

skel="$fixture/skeleton.md"
printf '# Handoff — old real content\nbranch: old\ncheckout: /c/old\ncompacted: no\nstatus: ok\nprogress: complete\n\nstale body\n' > "$skel"
# Act
handoff_store_write_skeleton "$skel" /c/checkouts/target feature/x
# Assert
assert_eq 'the skeleton carries progress: writing' 'writing' "$(handoff_store_field "$skel" progress)"
assert_eq 'the skeleton carries the checkout it was given' '/c/checkouts/target' "$(handoff_store_field "$skel" checkout)"
assert_eq 'the skeleton carries the branch it was given' 'feature/x' "$(handoff_store_field "$skel" branch)"
case "$(cat "$skel")" in
    *'stale body'*) fail 'the skeleton replaces prior real content, not appends to it' 'old body survived' ;;
    *)              pass 'the skeleton replaces prior real content, not appends to it' ;;
esac
for label_pattern in '### Decisions' '### Dead ends' '### Traps' '## Next' '## Pointers'; do
    case "$(cat "$skel")" in
        *"$label_pattern"*) pass "the skeleton's required section '$label_pattern' is present" ;;
        *) fail "the skeleton's required section '$label_pattern' is present" 'missing from skeleton' ;;
    esac
done

# handoff_store_set_progress — replacing an existing field
f=$(put /c/checkouts/emmie EMMIE-0900 EMMIE-0900 /c/worktrees/emmie-900)
printf 'progress: complete\n' >> "$f"
# Act
handoff_store_set_progress "$f" consumed
# Assert
assert_eq 'set_progress replaces an existing progress: line' 'consumed' "$(handoff_store_field "$f" progress)"
assert_eq 'set_progress leaves the other envelope fields alone' 'EMMIE-0900' "$(handoff_store_field "$f" branch)"

# handoff_store_set_progress — inserting when the field is absent entirely (a pre-D23 handoff)
legacy=$(put /c/checkouts/kendo KENDO-1 KENDO-1 /c/checkouts/kendo)
assert_eq 'a pre-D23 fixture has no progress: field yet' '' "$(handoff_store_field "$legacy" progress)"
# Act
handoff_store_set_progress "$legacy" consumed
# Assert
assert_eq 'set_progress inserts the field when the envelope has none' 'consumed' "$(handoff_store_field "$legacy" progress)"

# Bounded to the head, same rule as handoff_store_field itself — a body that happens to contain
# a progress:-shaped line must never be mistaken for the document's own header.
hostile=$(put /c/checkouts/mc body-progress body-progress /c/checkouts/mc)
{ printf '\n\n'; for i in $(seq 30); do echo "- padding $i"; done; echo 'progress: complete'; } >> "$hostile"
body_before=$(tail -1 "$hostile")
# Act
handoff_store_set_progress "$hostile" consumed
# Assert
assert_eq 'set_progress does not touch a progress:-shaped line deep in the body' \
    "$body_before" "$(tail -1 "$hostile")"
assert_eq 'set_progress still inserted its own header field, ahead of the body decoy' \
    'consumed' "$(handoff_store_field "$hostile" progress)"

# The rest of the file, including hostile characters, must survive byte-for-byte.
hostile_body=$(put /c/checkouts/mc hostile-body hostile-body /c/checkouts/mc)
printf '\nA tab\tand a backslash \\ and a backtick ` and a "quote".\r\n' >> "$hostile_body"
# Act
handoff_store_set_progress "$hostile_body" consumed
# Assert
after_body=$(tail -1 "$hostile_body")
case "$after_body" in
    *'A tab'*'backslash \'*'backtick `'*'"quote".'*)
        pass 'set_progress preserves hostile body characters untouched' ;;
    *) fail 'set_progress preserves hostile body characters untouched' "got [$after_body]" ;;
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
