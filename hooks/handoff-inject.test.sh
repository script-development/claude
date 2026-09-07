#!/usr/bin/env bash
#
# Tests for handoff-inject.sh.
#
# The suite is built around one asymmetry. This hook injects text that the model will read as
# system-supplied fact, so the expensive failure is not silence -- it is injecting something
# WRONG or MISLABELLED. A missed injection costs one typed `/handoff --read`. A handoff injected
# under a "GATE: OK" banner it never earned poisons turn one of a fresh session with stale claims
# that now look authoritative. So the verdict-labelling cases are the heart of this file, and
# every gate exit status gets its own.
#
# Cases that are regressions or hard-won rather than specification:
#
#   i1  the two-trees split. The document lives in the machine-local store; its citations describe
#       a tree that is checked out somewhere else entirely. Resolve both against one tree and every
#       verdict comes back MISSING, indistinguishable from real rot. The tree is DECLARED in the
#       handoff's `checkout:` header, and the load-bearing case is the one where that header
#       disagrees with the session's cwd -- a regression to cwd inference fails only there.
#   i6  the cross-repo pick. Enumerating the store is what finds a handoff for a sibling checkout
#       at all, and is also how every clear anywhere could surface the newest handoff on the
#       machine. Both halves are asserted: found when corroborated by the /clear marker, and not
#       surfaced on recency alone.
#   i2  JSON escaping. A handoff is full of backticks, quotes, backslashes and `path:line`
#       strings, and may be CRLF. Hand-rolled escaping emits invalid JSON, which Claude Code
#       discards SILENTLY -- no error, no injection, and a human who concludes the hook "didn't
#       fire". The fixture handoff is deliberately hostile and the assertion is that the output
#       parses at all.
#   i3  a missing gate must still inject, under an UNVERIFIED banner. Degrade capability, never
#       execution -- but "verified clean" and "never checked" must never render alike, which is
#       the whole reason the banner is a distinct string rather than an omission.
#   i4  exit 2 is not exit 1. On a contract violation the citations were not checked AT ALL, so
#       the banner has to say that rather than report rot it never looked for.
#   i5  branch slugging. `fix/foo` becomes `fix-foo`, and a detached HEAD falls back to the short
#       SHA. Both are how the writer names the file, so a mismatch here means the reader silently
#       finds nothing on exactly the branches most likely to be mid-task.
#
# No framework, matching handoff-urge.test.sh. Run it as:
#
#   bash hooks/handoff-inject.test.sh

set -uo pipefail

# Arrange
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/handoff-inject.sh"

if [ ! -r "$subject" ]; then
    echo "handoff-inject.sh not found at $subject" >&2
    exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

passed=0
failed=0

fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

# --- Fixtures --------------------------------------------------------------

repo="$fixture/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name  Test
echo 'hello' > "$repo/file.txt"
git -C "$repo" add -A
git -C "$repo" commit -q -m init

# The store lives under the redirected HOME, so it is isolated for free -- but only because
# `run` redirects HOME. Stated rather than assumed: without that redirect these cases would
# enumerate the developer's real handoffs, and the suite's verdicts would depend on the machine.
store="$fixture/home/.claude/context-economy/handoffs"
mkdir -p "$store"

# Both asked of git rather than reused from `$repo`, for the reason spelled out at i1 below: on
# Windows they are the same directory in two notations, and the hook works in git's.
main_git=$(git -C "$repo" worktree list | head -1 | awk '{print $1}')
repo_top=$(git -C "$repo" rev-parse --show-toplevel)

# The store filename formula, written out by hand rather than sourced from lib/handoff-store.sh.
# Deliberate: the filename is a CONTRACT between the write leg, this hook and session-end-marker,
# and a test that derived it by calling the same function under test would agree with any change
# to it, including a wrong one.
store_name() {  # store_name <target-main> <slug>
    printf '%s-%s-%s.md' \
        "$(printf '%s' "$(basename "$1")" | tr -c 'A-Za-z0-9._-' '_')" \
        "$(printf '%s' "$2" | tr -c 'A-Za-z0-9._-' '_')" \
        "$(printf '%s' "$1" | md5sum | cut -c1-8)"
}

# i2 — a deliberately hostile document. Every character class that breaks hand-rolled JSON
# escaping is present, plus a CRLF line, because a handoff written on Windows has them.
#
# The envelope is printf'd and the BODY stays in a quoted heredoc. Not stylistic: the body exists
# to carry backslashes, quotes and a backtick, and an unquoted heredoc would run the backtick as
# a command substitution and eat the backslashes -- destroying the exact characters this fixture
# was built to test while still producing a plausible-looking document.
write_handoff() {  # write_handoff <slug> [target-main] [checkout] [branch]
    local slug=$1 target=${2:-$main_git} checkout=${3:-$repo_top} branch=${4:-main}
    local path="$store/$(store_name "$target" "$slug")"
    {
    printf '# Handoff — a hostile document\n\n'
    printf 'branch: %s\ncheckout: %s\ncompacted: no\nstatus: fixture\n' "$branch" "$checkout"
    cat <<'EOF'

## Do not re-derive

### Decisions
- Chose `jq -Rs` over hand-rolled escaping. It beat "quote it ourselves", which breaks on a
  path like C:\Users\Bart\file.txt and on a "quoted phrase" inside a claim.

### Dead ends
- None.

### Traps
- A tab	and a backslash \ and a lone " and a ` walk into a JSON string.

## Next
1. Assert this parses.

## Pointers

```
file.txt:1 | hello
```
EOF
    printf 'trailing CRLF line\r\n'
    } > "$path"
    printf '%s' "$path"
}

write_handoff main >/dev/null

# A stub gate, so exit codes are deterministic and the suite does not depend on (or pay for)
# verify-handoff.sh's own behaviour. Its real integration is covered by that script's own suite.
gate="$fixture/stub-gate.sh"
cat > "$gate" <<'EOF'
#!/bin/bash
echo "STUB GATE ran on: $1"
echo "STUB GATE checkout: $2"
exit "${STUB_GATE_EXIT:-0}"
EOF
chmod +x "$gate"

payload() {  # payload <source> [cwd] [session_id] [transcript_path]
    jq -nc --arg s "$1" --arg c "${2:-$repo}" --arg sid "${3:-sess-1}" --arg tp "${4:-}" \
        '{session_id: $sid, hook_event_name: "SessionStart", source: $s, cwd: $c}
         + (if $tp == "" then {} else {transcript_path: $tp} end)'
}

# HOME is redirected so the gate probe cannot find the developer's real installed copy and
# quietly pass the "no gate" case by using it.
run() {  # run <payload> [env...]
    local p="$1"; shift
    printf '%s' "$p" | env HOME="$fixture/home" "$@" bash "$subject" 2>/dev/null
}

assert_silent() {  # assert_silent <label> <payload> [env...]
    local label="$1" p="$2"; shift 2
    local out; out=$(run "$p" "$@")
    if [ -z "$out" ]; then
        passed=$((passed + 1)); echo "ok   $label"
    else
        failed=$((failed + 1)); echo "FAIL $label — expected no output, got ${#out} chars"
    fi
}

assert_context_has() {  # assert_context_has <label> <needle> <payload> [env...]
    local label="$1" needle="$2" p="$3"; shift 3
    local out got; out=$(run "$p" "$@")
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    case "$got" in
        *"$needle"*) passed=$((passed + 1)); echo "ok   $label" ;;
        *) failed=$((failed + 1)); echo "FAIL $label — injected context lacks [$needle]" ;;
    esac
}

assert_context_lacks() {  # assert_context_lacks <label> <needle> <payload> [env...]
    local label="$1" needle="$2" p="$3"; shift 3
    local out got; out=$(run "$p" "$@")
    got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    case "$got" in
        *"$needle"*) failed=$((failed + 1)); echo "FAIL $label — injected context wrongly contains [$needle]" ;;
        *) passed=$((passed + 1)); echo "ok   $label" ;;
    esac
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

# --- Source gating ---------------------------------------------------------
#
# Only `clear` and `compact` inject. The others are not oversights and each has a distinct
# reason, so each gets a case: silently widening this later would tax every session in the repo.

# Arrange & Act & Assert — one source per iteration
for s in startup resume fork; do
    assert_silent "source: $s does not inject" "$(payload "$s")" VERIFY_HANDOFF_GATE="$gate"
done

# Act & Assert — the assert_* helpers run the hook and inspect its injected context. Each
# case's arrange is its payload and env assignments.
assert_field 'source: clear injects, tagged as a SessionStart result' \
    '.hookSpecificOutput.hookEventName' 'SessionStart' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

assert_field 'source: compact injects, tagged as a SessionStart result' \
    '.hookSpecificOutput.hookEventName' 'SessionStart' "$(payload compact)" VERIFY_HANDOFF_GATE="$gate"

# --- COMPACT: the token-distance coverage check -----------------------------
#
# `hooks/handoff-urge.sh`'s own latch/sidecar files are the contract this branch reads. Written
# by hand here rather than by running that hook first -- this suite tests handoff-inject.sh's
# READ of the contract, not handoff-urge.sh's WRITE of it, which has its own suite.

usage_transcript() {  # usage_transcript <name> <resident-total>
    local path="$fixture/$1.jsonl"
    jq -nc --argjson t "$2" \
        '{type:"assistant", message:{model:"claude-opus-5",
          usage:{input_tokens:$t, cache_creation_input_tokens:0, cache_read_input_tokens:0, output_tokens:400}}}' \
        > "$path"
    printf '%s' "$path"
}

latch_dir="$fixture/home/.claude/state/handoff-trigger"
write_latch() { mkdir -p "$latch_dir"; : > "$latch_dir/$1"; }
write_sidecar() {  # write_sidecar <session-id> <written-at-tokens>
    mkdir -p "$latch_dir"
    jq -nc --argjson w "$2" '{written_at_tokens: $w, written_at_epoch: 0, handoff_path: "x"}' \
        > "$latch_dir/$1.written"
}
some_tr=$(usage_transcript compact-some 210000)

# The write trigger never armed this session at all: no latch.
rm -rf "$latch_dir"
assert_context_has 'compact: the write trigger never having armed is stated' \
    'never armed this session' "$(payload compact "$repo" sess-ct-1 "$some_tr")" VERIFY_HANDOFF_GATE="$gate"

# Armed, but the write was never confirmed (no sidecar) before this compaction hit.
rm -rf "$latch_dir"
write_latch sess-ct-2
assert_context_has 'compact: an armed-but-unconfirmed write says so' \
    'no record of the write' "$(payload compact "$repo" sess-ct-2 "$some_tr")" VERIFY_HANDOFF_GATE="$gate"

# Armed and confirmed, gap within CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS (default 10,350): covered.
rm -rf "$latch_dir"
write_latch sess-ct-3
write_sidecar sess-ct-3 205000
covered_tr=$(usage_transcript compact-covered 210000)   # gap = 5,000
assert_context_has 'compact: a small gap reads as likely covering the compaction' \
    'likely covers' "$(payload compact "$repo" sess-ct-3 "$covered_tr")" VERIFY_HANDOFF_GATE="$gate"

# Armed and confirmed, gap past the threshold: flagged, not silently trusted.
rm -rf "$latch_dir"
write_latch sess-ct-4
write_sidecar sess-ct-4 205000
stale_tr=$(usage_transcript compact-stale 260000)   # gap = 55,000
assert_context_has 'compact: a large gap is flagged as likely-undocumented' \
    'likely-undocumented' "$(payload compact "$repo" sess-ct-4 "$stale_tr")" VERIFY_HANDOFF_GATE="$gate"

# Armed, but no handoff exists for THIS branch at all -- must still surface (the early "nothing
# to say" exit must not fire just because the store's only handoff belongs to a different repo).
no_handoff_repo="$fixture/no-handoff-repo"
mkdir -p "$no_handoff_repo"
git -C "$no_handoff_repo" init -q -b main
git -C "$no_handoff_repo" config user.email t@example.com
git -C "$no_handoff_repo" config user.name  Test
git -C "$no_handoff_repo" commit -q --allow-empty -m init
rm -rf "$latch_dir"
write_latch sess-ct-5
assert_context_has 'compact: an armed session with no handoff for this branch still surfaces' \
    'No handoff exists' "$(payload compact "$no_handoff_repo" sess-ct-5)" VERIFY_HANDOFF_GATE="$gate"

# And a "recent" pick (the store's only handoff, for an unrelated repo) must never be surfaced
# as if it were this session's own -- unlike `clear`, `compact` trusts only an exact match.
assert_context_lacks 'compact: a recent (not exact) pick is never surfaced as this session'"'"'s own' \
    'a hostile document' "$(payload compact "$no_handoff_repo" sess-ct-5)" VERIFY_HANDOFF_GATE="$gate"

rm -rf "$latch_dir"

# --- i2 — the output must be valid JSON ------------------------------------

# Act
out=$(run "$(payload clear)" VERIFY_HANDOFF_GATE="$gate")
# Assert
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    passed=$((passed + 1)); echo "ok   a hostile handoff still produces valid JSON"
else
    failed=$((failed + 1)); echo "FAIL a hostile handoff produced invalid JSON"
fi

# Act & Assert
assert_context_has 'the document itself is carried through' \
    'Chose `jq -Rs` over hand-rolled escaping' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

assert_context_has 'backslashes and quotes survive the round trip' \
    'C:\Users\Bart\file.txt' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

assert_context_has 'the branch is named so the reader can tell which handoff this is' \
    '(`main`)' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

assert_context_has 'the age is stated' \
    'day(s) ago' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

# --- Verdict labelling: the heart of the suite -----------------------------

assert_context_has 'a clean gate is reported as OK' \
    'GATE: OK' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=0

assert_context_has 'the gate output travels with the document' \
    'STUB GATE ran on:' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=0

# i1 — the checkout argument is passed explicitly, never allowed to default.
#
# The expected path is asked of git rather than reused from `$repo`. On Windows the two are the
# same directory in different notations -- mktemp says /tmp/tmp.XXX, git says C:/Users/.../Temp/…
# -- and hardcoding the shell's form makes this assertion fail on a hook that is behaving
# perfectly. The subject passes through git's form, so the test must compare against git's form.
# Arrange
repo_top=$(git -C "$repo" rev-parse --show-toplevel)
# Act & Assert
assert_context_has 'the gate is handed the checkout explicitly' \
    "STUB GATE checkout: $repo_top" "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=0

assert_context_has 'exit 1 is reported as rot in the citations' \
    'GATE: FAILED (exit 1)' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=1

# Authoring-side WARN lines are dropped, because the reader can do nothing about them -- but the
# count is announced, since a silently trimmed verdict block is indistinguishable from a complete
# one and a reader who cannot tell has to distrust both.
# Arrange
warngate="$fixture/warn-gate.sh"
cat > "$warngate" <<'EOF'
#!/bin/bash
echo "WARN     in Pointers but nothing in the prose refers to it: a.md"
echo "WARN     in Pointers but nothing in the prose refers to it: b.md"
echo "OK       file.txt:1 → file.txt:1 contains the cited content"
echo "All 1 citations resolve."
exit 0
EOF
chmod +x "$warngate"

# Act & Assert
assert_context_lacks 'authoring-side WARN lines are not injected' \
    'nothing in the prose refers to it' "$(payload clear)" VERIFY_HANDOFF_GATE="$warngate"

assert_context_has 'the dropped WARN lines are counted, not silently discarded' \
    '(2 authoring-side WARN line(s) omitted' "$(payload clear)" VERIFY_HANDOFF_GATE="$warngate"

assert_context_has 'the verdicts that DO concern the reader survive the filter' \
    'OK       file.txt:1' "$(payload clear)" VERIFY_HANDOFF_GATE="$warngate"

assert_context_has 'the gate summary line survives the filter' \
    'All 1 citations resolve.' "$(payload clear)" VERIFY_HANDOFF_GATE="$warngate"

# i4 — exit 2 means the citations were never examined; saying "failed" would overstate what is
# known, and saying "OK" would be a lie. It gets its own wording.
assert_context_has 'exit 2 is reported as malformed, not as rot' \
    'GATE: MALFORMED (exit 2)' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=2

assert_context_has 'exit 2 says the citations were not checked at all' \
    'NOT checked at all' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=2

assert_context_lacks 'exit 2 never claims the gate passed' \
    'GATE: OK' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=2

assert_context_has 'an unexpected exit status degrades to unverified' \
    'unverified' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" STUB_GATE_EXIT=7

# i3 — no gate at all.
assert_context_has 'a missing gate still injects the document' \
    'Chose `jq -Rs` over hand-rolled escaping' "$(payload clear)" VERIFY_HANDOFF_GATE="$fixture/no-such-gate"

assert_context_has 'a missing gate is labelled NOT RUN, not OK' \
    'GATE: NOT RUN' "$(payload clear)" VERIFY_HANDOFF_GATE="$fixture/no-such-gate"

assert_context_lacks 'a missing gate never claims the gate passed' \
    'GATE: OK' "$(payload clear)" VERIFY_HANDOFF_GATE="$fixture/no-such-gate"

# --- The two read-side rules ----------------------------------------------
#
# These fire when the skill has NOT been invoked, so the model has no other copy of them. If they
# ever vanish the injection becomes a bare document and the "do not re-derive eagerly" discipline
# goes with it -- silently, since the injection would still look fine.

assert_context_has 'the reader is told a verdict demotes only pointers' \
    'demote the cheap half' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

assert_context_has 'the reader is told not to re-derive eagerly' \
    'Do not re-derive eagerly' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

assert_context_has 'the reader is pointed at the first unblocked Next item' \
    '**not** blocked on a task that has yet to report' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

assert_context_has 'the reader is told to check compacted:' \
    'compacted:' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

# --- i5 — branch slugging --------------------------------------------------

# Arrange
git -C "$repo" checkout -q -b fix/foo
# Act & Assert
assert_silent 'a branch with no handoff is silent' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

# Arrange
write_handoff fix-foo
# Act & Assert
assert_context_has 'a branch containing a slash resolves to its slugged filename' \
    'a hostile document' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

# Arrange
sha=$(git -C "$repo" rev-parse --short HEAD)
git -C "$repo" checkout -q --detach
# Act & Assert
assert_silent 'a detached HEAD with no handoff for its SHA is silent' \
    "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

# Arrange
write_handoff "$sha"
# Act & Assert
assert_context_has 'a detached HEAD falls back to the short SHA' \
    'a hostile document' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"

git -C "$repo" checkout -q main

# --- i1 — the two-trees split ----------------------------------------------
#
# The document and the tree its citations describe are separate facts, and conflating them turns
# every verdict into a MISSING indistinguishable from real rot. What carries the second fact has
# changed: the file used to live in the main worktree with the checkout inferred from cwd, and now
# it lives in the store with the checkout DECLARED in its `checkout:` header.
#
# So these cases assert the header is authoritative — including where it disagrees with cwd, which
# is the whole cross-repo case, and the one the old cwd inference got silently wrong.

# Arrange
wt="$fixture/wt"
git -C "$repo" worktree add -q -b feature/x "$wt" >/dev/null 2>&1
wt_top=$(git -C "$wt" rev-parse --show-toplevel)
write_handoff feature-x "$main_git" "$wt_top" 'feature/x' >/dev/null

# Act & Assert
assert_context_has 'a worktree session finds its handoff in the store' \
    'a hostile document' "$(payload clear "$wt")" VERIFY_HANDOFF_GATE="$gate"

assert_context_has 'a worktree session hands the gate the WORKTREE as checkout' \
    "STUB GATE checkout: $wt_top" "$(payload clear "$wt")" VERIFY_HANDOFF_GATE="$gate"

# The load-bearing one. Session standing in the MAIN tree, handoff declaring the WORKTREE: the
# gate must be aimed where the document says, not where the session happens to be. A regression
# to cwd inference passes every other case in this suite and fails only this one.
# Arrange
write_handoff main "$main_git" "$wt_top" >/dev/null
# Act & Assert
assert_context_has 'checkout: wins over the session cwd when they disagree' \
    "STUB GATE checkout: $wt_top" "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"
write_handoff main >/dev/null

assert_context_has 'a worktree session names its own branch' \
    '(`feature/x`)' "$(payload clear "$wt")" VERIFY_HANDOFF_GATE="$gate"

# --- Degrading -------------------------------------------------------------

# Act & Assert
assert_silent 'a non-git cwd is silent' \
    "$(payload clear "$fixture")" VERIFY_HANDOFF_GATE="$gate"

assert_silent 'a nonexistent cwd is silent' \
    "$(payload clear "$fixture/no-such-dir")" VERIFY_HANDOFF_GATE="$gate"

# Truncated IN THE STORE. Pointing this at the pre-store path would leave the real candidate
# intact and assert silence against a hook that was correctly injecting it.
# Arrange
: > "$store/$(store_name "$main_git" main)"
# Act & Assert
assert_silent 'an empty handoff file is silent rather than injecting a header alone' \
    "$(payload clear)" VERIFY_HANDOFF_GATE="$gate"
# Arrange — restore the handoff for the cases below
write_handoff main >/dev/null

# Act & Assert
assert_silent 'a payload with no source is silent' \
    '{"session_id":"s","hook_event_name":"SessionStart"}' VERIFY_HANDOFF_GATE="$gate"

assert_silent 'empty stdin is silent' '' VERIFY_HANDOFF_GATE="$gate"

# --- The /clear marker surface ---------------------------------------------
#
# The marker is written by session-end-marker.sh when a /clear discards a session. It is surfaced
# HERE rather than by its own hook because the only question worth answering needs both halves at
# once: does the handoff on disk describe the session just thrown away, or an older one? A stale
# handoff injected with no such note is worse than none — it reads as coverage.

# Arrange
state="$fixture/last-clear"
# `printf '%s'` and not a bare pipe from awk: awk terminates its output with a newline, md5sum
# hashes whatever it is given, and the subject hashes the path WITHOUT one. Piping straight from
# awk yields a different digest, a filename the hook never looks for, and nine failures that all
# read as "the feature does not work" rather than "the test computed the wrong key".
marker_key=$(printf '%s' "$(git -C "$repo" worktree list | head -1 | awk '{print $1}')" | md5sum | cut -c1-32)

write_marker() {  # write_marker <slug> <resident> <handoff_mtime> <ended_epoch> <urge_fired>
    mkdir -p "$state"
    jq -n --argjson r "$2" --argjson hm "$3" --argjson ee "$4" --argjson uf "$5" \
        --arg tp 'C:/Users/Bart/.claude/projects/x/prev.jsonl' \
        '{ended_at:"2026-08-26T10:00:00Z", ended_at_epoch:$ee, reason:"clear",
          session_id:"prev-sess", transcript_path:$tp, branch:"main",
          resident_tokens:$r, handoff:{present:true,path:"x",mtime:$hm}, urge_fired:$uf}' \
        > "$state/$marker_key-$1.json"
}

now_epoch=$(date +%s)

# A handoff written moments before the clear almost certainly covers it.
# Arrange
write_marker main 250000 "$now_epoch" "$((now_epoch + 60))" false
# Act & Assert — each case below re-writes the marker first, because a surfaced marker is
# CONSUMED by the run: without the re-write, every case after this one would be asserting
# against an empty state directory rather than against the marker it names.
assert_context_has 'a handoff written just before the clear is reported as covering it' \
    'very likely does' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# A handoff from days earlier does not, and saying so is the entire point.
write_marker main 250000 "$((now_epoch - 259200))" "$now_epoch" false
assert_context_has 'a handoff predating the clear is flagged as not covering it' \
    'predates that clear' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

write_marker main 250000 "$((now_epoch - 259200))" "$now_epoch" false
assert_context_has 'the staleness is quantified rather than merely asserted' \
    'day(s)' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

write_marker main 250000 "$((now_epoch - 259200))" "$now_epoch" false
assert_context_has 'the depth of the discarded session is stated' \
    '250k of resident context' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# The surviving transcript is the only remaining record of the lost session, so its path is the
# most valuable field in the marker — and it must arrive unmangled.
write_marker main 250000 "$((now_epoch - 259200))" "$now_epoch" false
assert_context_has 'the surviving transcript path is surfaced' \
    'C:/Users/Bart/.claude/projects/x/prev.jsonl' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

write_marker main 250000 "$((now_epoch - 259200))" "$now_epoch" false
assert_context_has 'the reader is warned off opening that transcript eagerly' \
    'ONLY if the work turns out to matter' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# Two different mistakes, two different sentences: the clear beat the threshold, versus the human
# cleared past a handoff that had already been asked for.
write_marker main 250000 "$now_epoch" "$now_epoch" false
assert_context_has 'a clear that beat the trigger says the trigger never armed' \
    'never armed' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

write_marker main 250000 "$now_epoch" "$now_epoch" true
assert_context_has 'a clear after the trigger fired says a handoff had been asked for' \
    'HAD already fired' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# --- The marker must fire even with no handoff at all ----------------------
#
# This is the case the whole hook exists for: cleared mid-work, nothing written down. Before the
# marker, this was indistinguishable from a clean start.

# Arrange
git -C "$repo" checkout -q -b orphan
orphan_key=$(printf '%s' "$(git -C "$repo" worktree list | head -1 | awk '{print $1}')" | md5sum | cut -c1-32)
mkdir -p "$state"
jq -n --argjson ee "$now_epoch" \
    '{ended_at:"2026-08-26T10:00:00Z", ended_at_epoch:$ee, reason:"clear", session_id:"prev",
      transcript_path:"C:/x/prev.jsonl", branch:"orphan", resident_tokens:310000,
      handoff:{present:false,path:"x",mtime:null}, urge_fired:false}' \
    > "$state/$orphan_key-orphan.json"

# Act & Assert
assert_context_has 'a clear with no handoff at all still surfaces' \
    'that work is undocumented' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"
git -C "$repo" checkout -q main

# --- Consumption -----------------------------------------------------------
#
# The marker is news about ONE reset. Reporting it again at the next clear would be noise, and
# worse, would attribute an old loss to a new event.

# Arrange
write_marker main 250000 "$now_epoch" "$now_epoch" false
# Act
run "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state" >/dev/null
# Assert
[ ! -e "$state/$marker_key-main.json" ] && pass_marker=1 || pass_marker=0
if [ "$pass_marker" = 1 ]; then
    passed=$((passed + 1)); echo "ok   the marker is consumed after being surfaced"
else
    failed=$((failed + 1)); echo "FAIL the marker is consumed after being surfaced — it is still on disk"
fi

# Act & Assert
assert_context_lacks 'a consumed marker does not resurface on the next clear' \
    'The session you just cleared' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# A corrupt marker must not take the handoff injection down with it: the handoff is still valuable
# on its own, and a malformed side-file is not a reason to lose it.
# Arrange
mkdir -p "$state"
printf 'not json at all\n' > "$state/$marker_key-main.json"
# Act & Assert
assert_context_has 'a malformed marker is ignored rather than fatal' \
    'a hostile document' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"
rm -f "$state/$marker_key-main.json"

# And a marker for a DIFFERENT branch must not be reported against this one.
# Arrange
write_marker other-branch 250000 "$now_epoch" "$now_epoch" false
# Act & Assert
assert_context_lacks 'a marker for another branch is not surfaced here' \
    'The session you just cleared' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# --- The cross-repo pick ---------------------------------------------------
#
# The capability the store exists for, and the one no case above exercises: the work happened in a
# DIFFERENT repository from the one the session is standing in. An orchestrating session drives a
# sibling checkout with `git -C` and never moves, so cwd names the wrong repo and the wrong branch,
# and no path derived from it can find the document. Only enumeration can.
#
# It is also the riskiest path, because the pick is a guess. Both halves are asserted: that it is
# found, and that it is not surfaced on recency alone.

# Arrange
other="$fixture/other-repo"
mkdir -p "$other"
git -C "$other" init -q -b feature/other
git -C "$other" config user.email t@example.com
git -C "$other" config user.name  Test
echo 'other' > "$other/other.txt"
git -C "$other" add -A
git -C "$other" commit -q -m init
other_main=$(git -C "$other" worktree list | head -1 | awk '{print $1}')
other_top=$(git -C "$other" rev-parse --show-toplevel)

# The session's own branch has no handoff, so no exact match exists and the resolver must guess.
git -C "$repo" checkout -q -b driving
rm -f "$state"/*.json

# Freshly written, and a marker saying the clear happened just after it: corroborated.
write_handoff other-work "$other_main" "$other_top" 'feature/other' >/dev/null
driving_key=$(printf '%s' "$main_git" | md5sum | cut -c1-32)
write_cross_marker() {  # write_cross_marker <handoff_mtime> <ended_epoch>
    mkdir -p "$state"
    jq -n --argjson hm "$1" --argjson ee "$2" \
        '{ended_at:"2026-08-26T10:00:00Z", ended_at_epoch:$ee, reason:"clear",
          session_id:"prev-sess", transcript_path:"C:/x/prev.jsonl", branch:"driving",
          resident_tokens:300000, handoff:{present:true,path:"x",mtime:$hm}, urge_fired:true}' \
        > "$state/$driving_key-driving.json"
}
h_mtime=$(stat -c %Y "$store/$(store_name "$other_main" other-work)")
write_cross_marker "$h_mtime" "$((h_mtime + 60))"

# Act & Assert — same consumption rule as above: write_cross_marker re-runs before each case.
assert_context_has 'a handoff for a sibling checkout is found by enumeration' \
    'a hostile document' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

write_cross_marker "$h_mtime" "$((h_mtime + 60))"
assert_context_has 'the cross-repo pick names the branch it belongs to' \
    'feature/other' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

write_cross_marker "$h_mtime" "$((h_mtime + 60))"
assert_context_has 'the cross-repo pick names the tree it describes' \
    "$other_top" "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# The pick is a guess and must SAY SO. Injected context reads as authoritative; a guess presented
# in the same voice as an exact match is the failure mode enumeration introduces.
write_cross_marker "$h_mtime" "$((h_mtime + 60))"
assert_context_has 'a guessed pick is labelled a guess' \
    'That is a GUESS' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

write_cross_marker "$h_mtime" "$((h_mtime + 60))"
assert_context_has 'the gate is aimed at the sibling checkout, not the session repo' \
    "STUB GATE checkout: $other_top" "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# The rejected candidates are listed. This is the pointer-file design's whole disadvantage made
# concrete: a pointer resolves ambiguity by overwriting, and cannot tell a reader what it discarded.
write_cross_marker "$h_mtime" "$((h_mtime + 60))"
assert_context_has 'the candidates not picked are listed for correction' \
    'Other handoffs in the store, not picked' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# --- ...and the corroboration requirement ----------------------------------
#
# Without these two cases the hook would surface the newest handoff on the machine at every clear
# anywhere — strictly worse than the derivation it replaced, which at least stayed silent.

# Arrange
rm -f "$state"/*.json
# Act & Assert
assert_silent 'a guessed pick with no marker is not surfaced at all' \
    "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# Marker present, but the handoff predates the clear by well over the window: it describes earlier
# work in another repository, which is the noise case, not the resume case.
# Arrange
write_cross_marker "$h_mtime" "$((h_mtime + 86400))"
# Act & Assert
assert_context_lacks 'a guessed pick older than the coverage window is not surfaced' \
    'a hostile document' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

# The marker itself still is — the session was cleared, and that stands on its own.
# Arrange
write_cross_marker "$h_mtime" "$((h_mtime + 86400))"
# Act & Assert
assert_context_has 'the clear is still reported when its guessed handoff was rejected' \
    'The session you just cleared' "$(payload clear)" VERIFY_HANDOFF_GATE="$gate" LAST_CLEAR_STATE_DIR="$state"

git -C "$repo" checkout -q main
rm -f "$store/$(store_name "$other_main" other-work)" "$state"/*.json

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
