#!/usr/bin/env bash
#
# Tests for verify-handoff.sh.
#
# Every case is a regression, and the first two were found by running the script
# against a real handoff before it had any tests:
#
#   v1  reported "section is empty: Do not re-derive" on every correctly-formed
#       handoff. That heading is a container — the first thing after it is
#       `### Decisions` — so the generic "section must have text" rule ended the
#       section immediately and found nothing. A false refusal of a valid document,
#       which is the expensive direction: it teaches the author the gate is wrong.
#   v2  swallowed the `## Unverifiable` section's cross-repo paths into the coverage
#       set, demanding they be listed in Pointers, where they resolve MISSING by
#       construction. The section exists precisely to declare them unchecked (O6),
#       so the check was manufacturing the false positive it should prevent.
#   v3  treated any backticked token containing `/` as a citation. Run on the first
#       real handoff it produced eight failures, every one of them wrong: `/clear`,
#       `/compact` and `/handoff` (slash commands), `~/.claude/lib/` (not
#       repo-relative), `(T + H)/2` (arithmetic), `/` alone, and two paths the plan
#       was proposing to CREATE. Fixed by splitting evidence (carries a line
#       reference; fails) from a mention (path-shaped; warns), and by excluding
#       `## Next` from the prose zone — a plan is not a claim about the tree.
#   v4  warned that a Pointer was unreferenced when `## Next` referred to it twice,
#       because the dead-weight check reused v3's narrowed zone. "Should this demand
#       a Pointers entry" and "does anything refer to this" are opposite questions
#       and need opposite zones. A wrong warning is worse than a missing one: it is
#       the whole reason anyone stops reading warnings.
#   v5  warned that `$HOME/.claude/lib/verify-handoff.sh` was an unchecked mention.
#       True but useless: a shell expression cannot resolve as written, so there is
#       no action the warning could prompt. Same lesson as v4 in a smaller key --
#       the cost of a warning is not whether it is accurate but whether it is
#       actionable.
#
# Both directions matter. A missed unchecked claim costs one wrong conclusion in
# the resumed session; a false refusal costs the whole gate, because a handoff
# author under context pressure will simply stop running it.
#
# No framework, matching verify-citations.test.sh. Run it the same way:
#
#   bash lib/verify-handoff.test.sh

set -uo pipefail

# Arrange
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/verify-handoff.sh"

if [ ! -r "$subject" ]; then
    echo "verify-handoff.sh not found at $subject" >&2
    exit 2
fi

passed=0
failed=0

# --- Fixture ---------------------------------------------------------------
#
# A real git repo, because the subject resolves citations through
# verify-citations.sh, which anchors on `git rev-parse --show-toplevel`. Anchoring
# the suite on this repo's own tree instead would pass here and fail in the next
# checkout — the same objection verify-citations.test.sh records against Kendo's
# original suite.

fixture=$(mktemp -d) || { echo "cannot create fixture directory" >&2; exit 2; }
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/app/Mail" "$fixture/docs"

{
    n=1
    while [ "$n" -le 40 ]; do
        case "$n" in
            24) echo "    public function build(): Content" ;;
            *)  echo "// line $n" ;;
        esac
        n=$((n + 1))
    done
} > "$fixture/app/Mail/Invoice.php"

echo "prose that mentions PhantomAction without defining it" > "$fixture/docs/notes.md"

git -C "$fixture" init --quiet >/dev/null 2>&1
git -C "$fixture" add -A >/dev/null 2>&1
git -C "$fixture" -c user.email=t@example.com -c user.name=t \
    commit --quiet -m fixture >/dev/null 2>&1
branch=$(git -C "$fixture" rev-parse --abbrev-ref HEAD 2>/dev/null)

# --- Harness ---------------------------------------------------------------

# The canonical valid handoff. Every other case is this one with one thing wrong,
# so a test that fails names the single edit responsible.
canonical() {
    cat <<EOF
# Handoff — type the mailables
branch: $branch
checkout: $fixture
compacted: no
status: Invoice done; Reminder not started.

## Do not re-derive

### Decisions
- Type the builder return, not the caller — chosen over annotating each call site,
  because the loss is at the boundary. \`app/Mail/Invoice.php:24\`

### Dead ends
- Adding a docblock to the caller: still inferred mixed. \`app/Mail/\`

### Traps
- None.

## Next
1. Do Reminder the same way.

## Pointers
\`\`\`
# the boundary this whole ticket turns on
app/Mail/Invoice.php:24 | public function build
app/Mail/
\`\`\`
EOF
}

# run <file> [checkout] — the subject, with stdout and stderr merged so a contract
# violation (stderr) and a gate failure (stdout) are both visible to assertions.
run() {
    (cd "$fixture" && bash "$subject" "$1" "${2:-$fixture}" 2>&1)
}

run_code() {
    (cd "$fixture" && bash "$subject" "$1" "${2:-$fixture}" >/dev/null 2>&1)
}

# write <name> — canonical handoff, then apply a sed program from stdin.
write() {
    local path="$fixture/$1.md" program
    program=$(cat)
    if [ -z "$program" ]; then
        canonical > "$path"
    else
        canonical | sed "$program" > "$path"
    fi
    printf '%s' "$path"
}

assert_exit() {
    local expected=$1 description=$2 file=$3 actual
    run_code "$file"
    actual=$?
    if [ "$actual" = "$expected" ]; then
        passed=$((passed + 1))
        printf '  ok    %s\n' "$description"
    else
        failed=$((failed + 1))
        printf '  FAIL  %s\n        expected exit %s, got %s\n' \
            "$description" "$expected" "$actual"
    fi
}

assert_output() {
    local mode=$1 pattern=$2 description=$3 file=$4 output
    output=$(run "$file")
    if grep -qE -- "$pattern" <<< "$output"; then
        if [ "$mode" = present ]; then
            passed=$((passed + 1)); printf '  ok    %s\n' "$description"
        else
            failed=$((failed + 1))
            printf '  FAIL  %s\n        did not expect /%s/ in:\n%s\n' \
                "$description" "$pattern" "$output"
        fi
    else
        if [ "$mode" = absent ]; then
            passed=$((passed + 1)); printf '  ok    %s\n' "$description"
        else
            failed=$((failed + 1))
            printf '  FAIL  %s\n        expected /%s/ in:\n%s\n' \
                "$description" "$pattern" "$output"
        fi
    fi
}

echo "verify-handoff.sh"

# --- The happy path --------------------------------------------------------

# Arrange
good=$(write good </dev/null)
# Act & Assert — assert_exit and assert_output run the subject against a document and check
# its exit code or its output. Each case's arrange is the document built just above it.
assert_exit 0 'a well-formed handoff with resolving citations passes' "$good"
assert_output present 'contains the cited content' \
    'the fragment on a referenced line is actually checked' "$good"

# v1: the container heading must not be required to have text of its own.
assert_output absent 'section is empty: Do not re-derive' \
    'the container section is not treated as an empty section (v1)' "$good"

# A comment line in the Pointers block is the resolver's own convention and must
# not be mistaken for a citation, nor counted as uncovered dead weight.
assert_output absent 'nothing in the prose refers to it: #' \
    'a # comment in Pointers is not treated as a citation' "$good"

# --- Structure: every required section, and non-emptiness ------------------

# Arrange & Act & Assert — each variant is built inline by `write` from a sed script
assert_exit 2 'a missing title fails as a contract violation' \
    "$(write no_title <<<'s|^# Handoff.*|# Notes|')"
assert_exit 2 'a missing branch: field fails' \
    "$(write no_branch <<<'/^branch:/d')"
assert_exit 2 'a missing status: field fails' \
    "$(write no_status <<<'/^status:/d')"
# Ungated, this field is simply omitted -- and omission is the one answer that
# tells the reader nothing about whether the expensive half is first-hand.
assert_exit 2 'a missing compacted: field fails' \
    "$(write no_compacted <<<'/^compacted:/d')"
# Same argument one step further: compacted: says whether to trust the expensive
# half, checkout: says which tree the cheap half refers to at all. Omitted, the
# tool guesses $PWD and reports a page of MISSING that reads as citation rot.
assert_exit 2 'a missing checkout: field fails' \
    "$(write no_checkout <<<'/^checkout:/d')"
assert_exit 2 'a missing Do not re-derive heading fails' \
    "$(write no_container <<<'s|^## Do not re-derive|## Notes|')"
assert_exit 2 'a demoted Decisions heading counts as missing' \
    "$(write no_decisions <<<'s|^### Decisions|#### Decisions|')"
assert_exit 2 'a missing Dead ends heading fails' \
    "$(write no_deadends <<<'s|^### Dead ends|### Notes|')"
assert_exit 2 'a missing Traps heading fails' \
    "$(write no_traps <<<'s|^### Traps|### Gotchas|')"
assert_exit 2 'a missing Next heading fails' \
    "$(write no_next <<<'s|^## Next|## Later|')"
assert_exit 2 'a missing Pointers heading fails' \
    "$(write no_pointers <<<'s|^## Pointers|## Citations|')"

# Silence is not an answer; "None." is. This is the whole reason the subsections
# are required rather than optional -- an absent section cannot be distinguished
# from a run that never looked for one.
assert_exit 2 'an empty Traps section fails' \
    "$(write empty_traps <<<'s|^- None\.$||')"
assert_output present 'write "None."' \
    'the empty-section message says what to write instead' \
    "$(write empty_traps2 <<<'s|^- None\.$||')"
assert_exit 0 '"None." is a legitimate answer and passes' "$good"

# --- The Pointers fence ----------------------------------------------------

assert_exit 2 'an unfenced Pointers list fails' \
    "$(write unfenced <<<'/^```$/d')"
assert_exit 2 'an unclosed Pointers fence fails' \
    "$(write unclosed <<<'$d')"

# A task can legitimately rest on nothing citable. That must not read the same as
# a missing fence, which is why the fence state is tracked separately from its
# contents.
# Arrange
empty_ptr="$fixture/empty_ptr.md"
canonical | sed -e '/^app\/Mail\/Invoice.php:24 |/d' -e '/^app\/Mail\/$/d' \
    -e '/^# the boundary/d' \
    -e 's|`app/Mail/Invoice.php:24`|the builder|' \
    -e 's|`app/Mail/`|the directory|' > "$empty_ptr"
# Act & Assert
assert_exit 0 'an empty Pointers fence is legitimate' "$empty_ptr"
assert_output present 'no citations to check' \
    'an empty Pointers fence says so explicitly' "$empty_ptr"

# --- O7: path:symbol is refused, not resolved -----------------------------

# Arrange
sym="$fixture/sym.md"
canonical | sed 's|^app/Mail/Invoice[.]php:24 .*|app/Mail/Invoice.php:build|' > "$sym"
# Act & Assert
assert_exit 2 'a path:symbol anchor is a contract violation, not a gate failure' "$sym"
assert_output present 'known false MISSING' \
    'the path:symbol message names the inherited defect' "$sym"

# The point of exit 2 here: a contract violation must not let the resolver run and
# print MISSING beside it, because that output is what O8 records as unreadable.
assert_output absent '^MISSING' \
    'a contract violation suppresses the resolver entirely' "$sym"

# --- Coverage --------------------------------------------------------------

# Arrange
uncovered="$fixture/uncovered.md"
canonical | sed '/^app\/Mail\/Invoice\.php:24 |/d' > "$uncovered"
# Act & Assert
assert_exit 1 'a pointer cited in prose but absent from Pointers is a gate failure' "$uncovered"
assert_output present 'never checked' \
    'the coverage message says the claim was never checked' "$uncovered"

# Exemptions, all deliberately narrower than the resolver's own is_path_shaped:
# over-strict coverage refuses valid handoffs, and that is the expensive error.
# Arrange
exempt="$fixture/exempt.md"
canonical | sed 's|^- None\.$|- Per `CLAUDE.md`, and the template `<project>/.claude/handoff/<branch>.md`, and `SKILL.md`.|' \
    > "$exempt"
# Act & Assert
assert_exit 0 'a bare filename, a template path and a bare doc name need no Pointers entry' "$exempt"

# O6: cross-repo entries are declared unchecked on purpose, so they must not be
# pulled into coverage. This is v2.
# Arrange
unv="$fixture/unv.md"
{ canonical; printf '\n## Unverifiable\n- `claude-dotfiles/dotfiles/statusline/statusline.sh` — sibling checkout.\n'; } > "$unv"
# Act & Assert
assert_exit 0 'an Unverifiable cross-repo entry is not pulled into coverage (v2)' "$unv"

# Dead weight is a cost, not a risk: warn.
# Arrange
dead="$fixture/dead.md"
canonical | sed 's|^app/Mail/$|app/Mail/\ndocs/notes.md|' > "$dead"
# Act & Assert
assert_exit 0 'a Pointers entry nothing refers to warns but does not fail' "$dead"
assert_output present 'nothing in the prose refers to it' \
    'the unreferenced pointer is named' "$dead"

# Warn, not fail: the coverage rule is already the strict half.
# Arrange
stray="$fixture/stray.md"
# Deliberately NOT in `## Next`: that section is excluded from the prose zone (v3),
# because a plan names files it is about to create rather than facts about the tree.
canonical | sed 's|^- None\.$|- Watch app/Mail/Reminder.php:9, it looks the same but is not.|' > "$stray"
# Act & Assert
assert_exit 0 'an unbackticked citation warns rather than failing' "$stray"
assert_output present 'is not backticked' \
    'the unbackticked citation is named' "$stray"

# v3: none of these is a citation, and each one failed the first version.
# Arrange
notcites="$fixture/notcites.md"
canonical | sed 's|^- None\.$|- Ran `/clear` then `/compact`; `~/.claude/lib/` holds it; cost is `(T + H)/2`; see `/`.|' \
    > "$notcites"
# Act & Assert
assert_exit 0 'slash commands, home-relative paths and arithmetic are not citations (v3)' "$notcites"
assert_output absent 'never checked' \
    'none of them is reported as an unchecked claim (v3)' "$notcites"

# v3: a plan names files it is about to create. Demanding they resolve reports
# MISSING on work not yet done -- the false-refusal direction.
# Arrange
plan="$fixture/plan.md"
canonical | sed 's|^1\. Do Reminder.*|1. Write `app/Mail/Reminder.php` and `docs/plan/new.md`, neither of which exists yet.|' \
    > "$plan"
# Act & Assert
assert_exit 0 'files a plan proposes to create need no Pointers entry (v3)' "$plan"

# The middle tier: path-shaped, no line reference. Visible, never fatal.
# Arrange
mention="$fixture/mention.md"
canonical | sed 's|^- None\.$|- Also relevant: `app/Mail/Reminder.php`.|' > "$mention"
# Act & Assert
assert_exit 0 'a bare-path mention warns rather than failing' "$mention"
assert_output present 'mentioned in prose but not in Pointers' \
    'the bare-path mention is named' "$mention"

# v4: a pointer referred to only from `## Next` is not dead weight, even though
# `## Next` is excluded from the coverage zone.
# Arrange
next_ref="$fixture/next_ref.md"
canonical | sed 's|^1\. Do Reminder.*|1. Do Reminder, following `app/Mail/Invoice.php:24`.|' > "$next_ref"
# Act & Assert
assert_output absent 'nothing in the prose refers to it' \
    'a pointer referred to only from Next is not reported as dead weight (v4)' "$next_ref"

# v5: a shell expression is not a path, at any position in the token.
# Arrange
shellvar="$fixture/shellvar.md"
canonical | sed 's|^- None\.$|- Installed at `$HOME/.claude/lib/x.sh`, or `${XDG_DATA_HOME}/y.sh`.|' \
    > "$shellvar"
# Act & Assert
assert_exit 0 'a shell-expression path is not a citation (v5)' "$shellvar"
assert_output absent 'unchecked: \$' \
    'a shell-expression path raises no mention warning (v5)' "$shellvar"

# The anchored exclusions stay anchored: `/` and `~` mid-token are ordinary.
# Arrange
midtoken="$fixture/midtoken.md"
canonical | sed 's|^- None\.$|- Also `app/Mail/Reminder.php`.|' > "$midtoken"
# Act & Assert
assert_output present 'mentioned in prose but not in Pointers' \
    'a mid-token slash is still a path (v5)' "$midtoken"

# --- The gate itself -------------------------------------------------------

# Arrange
changed="$fixture/changed.md"
canonical | sed 's|public function build$|public function handle|' > "$changed"
# Act & Assert
assert_exit 1 'a CHANGED citation fails the gate' "$changed"

# Arrange
missing="$fixture/missing.md"
canonical | sed -e 's|app/Mail/Invoice\.php|app/Mail/Phantom.php|g' > "$missing"
# Act & Assert
assert_exit 1 'a MISSING citation fails the gate' "$missing"

# --- Checkout reporting ----------------------------------------------------

# Act & Assert
assert_output present 'checkout .*HEAD' \
    'the checkout and its HEAD are always reported' "$good"

# Arrange
mismatch="$fixture/mismatch.md"
canonical | sed 's|^branch: .*|branch: some-other-branch|' > "$mismatch"
# Act & Assert
assert_exit 0 'a branch mismatch warns rather than failing' "$mismatch"
assert_output present 'citations resolve against' \
    'the mismatch says which branch the verdicts belong to' "$mismatch"

# --- Checkout resolution order ---------------------------------------------
#
# The harness's `run` always passes an explicit checkout, so none of the cases
# above exercises the path the hooks actually take: no argument, and a cwd that is
# a DIFFERENT repository from the one the citations describe. That is the whole
# reason the header field exists, so it gets tested from outside the fixture.
#
# `outside` is a real git repo rather than a temp directory, so a regression that
# silently falls back to $PWD resolves in a valid-but-wrong tree and reports
# MISSING -- which is exactly the failure mode being guarded, and it would be
# invisible if the fallback simply errored "not a git repository" instead.
# Arrange
outside="$fixture-outside"
rm -rf "$outside"
mkdir -p "$outside"
git -C "$outside" init --quiet
git -C "$outside" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m outside >/dev/null 2>&1

from_outside() { (cd "$outside" && bash "$subject" "$@" 2>&1); }

# Act
out=$(from_outside "$good"); code=$?
# Assert
if [ "$code" = 0 ] && grep -q 'from checkout: header' <<< "$out"; then
    passed=$((passed + 1))
    printf '  ok    %s\n' 'with no argument, checkout: resolves the tree from a foreign cwd'
else
    failed=$((failed + 1))
    printf '  FAIL  %s\n        expected exit 0 and a header-sourced checkout, got exit %s:\n%s\n' \
        'with no argument, checkout: resolves the tree from a foreign cwd' "$code" "$out"
fi

# Act
out=$(from_outside "$good" "$fixture")
# Assert
if grep -q 'from argument' <<< "$out" && ! grep -q 'OVERRIDING' <<< "$out"; then
    passed=$((passed + 1))
    printf '  ok    %s\n' 'an argument matching the header is reported as the argument'
else
    failed=$((failed + 1))
    printf '  FAIL  %s\n%s\n' 'an argument matching the header is reported as the argument' "$out"
fi

# The override is announced, because a deliberate cross-tree verification and the
# accident this field prevents produce the same shape of verdict block.
# Act
out=$(from_outside "$good" "$outside")
# Assert
if grep -q 'OVERRIDING checkout:' <<< "$out"; then
    passed=$((passed + 1))
    printf '  ok    %s\n' 'an argument that overrides the header says so'
else
    failed=$((failed + 1))
    printf '  FAIL  %s\n%s\n' 'an argument that overrides the header says so' "$out"
fi

# --- Size is advisory, always ---------------------------------------------

# Act & Assert
assert_output present 'turns of work' \
    'size is reported in turns of work, not only tokens' "$good"

# Arrange
big="$fixture/big.md"
{
    canonical
    printf '\n## Notes\n'
    n=1
    while [ "$n" -le 700 ]; do
        echo "- padding line $n, of no interest to anyone, present only to exceed the ceiling."
        n=$((n + 1))
    done
} > "$big"
# Act & Assert
assert_exit 0 'a handoff over the ceiling still passes — size can never fail the gate' "$big"
assert_output present 'over the ceiling' 'the ceiling breach is reported' "$big"
assert_output present 'never a decision' \
    'the size warning says which half to cut' "$big"

# Degrade capability, never execution: no thresholds file means no size line, and
# never a guessed default.
# Act
nothresh=$( (cd "$fixture" && CTX_THRESHOLDS_FILE=/nonexistent/thresholds.sh \
    bash "$subject" "$good" "$fixture" 2>&1); echo "exit=$?" )
# Assert
if grep -q 'no thresholds file' <<< "$nothresh" && grep -q 'exit=0' <<< "$nothresh"; then
    passed=$((passed + 1))
    printf '  ok    %s\n' 'a missing thresholds file drops the size report and nothing else'
else
    failed=$((failed + 1))
    printf '  FAIL  %s\n%s\n' \
        'a missing thresholds file drops the size report and nothing else' "$nothresh"
fi

# --- Platform --------------------------------------------------------------
#
# CRLF is not cosmetic here. verify-citations.sh survives it by accident, since
# its trailing-whitespace rule eats the CR; this script anchors on whole lines,
# where a CR makes every required section report absent. Windows is a supported
# platform for this repo, so a handoff written by an editor there is the normal
# case, not an edge one.
# Arrange
crlf="$fixture/crlf.md"
canonical | sed 's/$/\r/' > "$crlf"
# Act & Assert
assert_exit 0 'a CRLF handoff passes' "$crlf"

# --- Misuse ----------------------------------------------------------------

# Act & Assert
assert_exit 2 'an unreadable path fails as a contract violation' "$fixture/nope.md"

# Arrange
prose="$fixture/prose.md"
#
# The document is generated here rather than copied out of the tree. The
# previous fixture did `cp "$script_dir/../README.md"` against a path that has
# never existed, so it fell through to `echo "not a handoff"` and the case
# tested "refuse a three-word file" -- which the subject would refuse for the
# wrong reason. It has to be plausible to be worth anything: headings, a fenced
# block, and a backticked path carrying a line reference, so that the refusal is
# about the missing contract sections and not about there being nothing to read.
cat > "$prose" <<'PROSEEOF'
# context-economy

A bundle of hooks, a statusline gauge and two skills.

## Install

Run `install.sh` from the primary checkout. It symlinks `~/.claude` into the
working tree, so a branch checkout swaps live code under every session on the
machine.

## Layout

- `lib/verify-handoff.sh:1` -- the format gate
- `hooks/handoff-inject.sh` -- the SessionStart briefing

```sh
bash lib/verify-handoff.test.sh
```
PROSEEOF
# Act & Assert
assert_exit 2 'an arbitrary document is refused as malformed, not reported as rot' "$prose"

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
