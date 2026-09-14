#!/usr/bin/env bash
#
# Tests for verify-citations.sh.
#
# Every case below is a regression. The resolver shipped twice with a bug that
# a two-line fixture would have caught for free:
#
#   v1  passed all four KD-0789 phantoms, because a path-shaped citation fell
#       back to the symbol grep and .claude/ was in the search roots — so
#       anti-patterns.md, the file recording those citations as fabricated,
#       vouched for them.
#   v2  reported real files as MISSING when the citation carried a line range,
#       because the strip rule only handled `:42` and not `:233-234`.
#   v3  reported real files as MISSING when that line range was wrapped in
#       prose punctuation — `(api.php:233-234)` — because the strip rules ran
#       in an order that let the `)` block the line rule's anchor.
#   v4  would have reported every line-referenced citation as MISSING on macOS,
#       because the line rule used GNU-only BRE `\+`. Note the shape: v4 is the
#       first entry no fixture below can catch, since CI's sed is the one that
#       works. It is pinned statically under "Portability" instead.
#   v5  reported a real, unchanged line in a MARKDOWN target as CHANGED whenever
#       the cited fragment had to cross a backtick the target actually has —
#       the fragment gets its own backticks stripped (so a citation author can
#       write `` `foo` `` for readability without the literal match caring),
#       but the target line never got the same treatment, so the two could not
#       line up. Invisible against every fixture above because none of them are
#       markdown: this repo's own docs (`docs/design.md`, `docs/measured.md`)
#       are cited from handoffs constantly and are exactly the shape that hits
#       it. Fixed by stripping backticks from the target side too, in both the
#       per-line and whole-file checks.
#
# Both directions matter and both are pinned here. A missed phantom costs a
# reviewer round; a false MISSING teaches the author the gate is wrong and can
# be worked around, which costs every future catch.
#
# No framework by design — this repo has no bats and no shell test harness, and
# scripts here run as plain `bash <path>`. Run it the same way:
#
#   bash lib/verify-citations.test.sh
#
# One divergence from the Kendo suite: its OK cases resolve against the real repo
# tree, which is a layout dependency the ported script exists not to have. A
# suite anchored on its host passes here and fails in the next repo. So the tree
# is a throwaway git repo built below, reproducing every condition the original
# assertions relied on; the assertions themselves are unchanged in substance.

set -uo pipefail

# Arrange — the subject, the throwaway fixture repo below, and the harness helpers
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/verify-citations.sh"

if [ ! -x "$subject" ]; then
    echo "verify-citations.sh not found or not executable at $subject" >&2
    exit 2
fi

passed=0
failed=0

# --- Fixture ---------------------------------------------------------------
#
# A layout matching nothing the script hardcodes. `packages/` is a top-level
# source tree no whitelist would have named, so it is only searched if the
# derivation really is a denylist.

fixture=$(mktemp -d) || { echo "cannot create fixture directory" >&2; exit 2; }
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture"/backend/routes \
         "$fixture"/backend/app/Helpers \
         "$fixture"/backend/app/Actions \
         "$fixture"/backend/app/Events \
         "$fixture"/frontend/src/shared \
         "$fixture"/packages/core/src \
         "$fixture"/mobile/src/shared \
         "$fixture"/docs \
         "$fixture"/site \
         "$fixture"/assets

# 300 lines, with the two cited ones carrying known content.
{
    n=1
    while [ "$n" -le 300 ]; do
        case "$n" in
            233) echo "    Route::get('/issues', [IssueController::class, 'index']);" ;;
            234) echo "    Route::post('/issues', [IssueController::class, 'store']);" ;;
            *)   echo "// filler line $n" ;;
        esac
        n=$((n + 1))
    done
} > "$fixture/backend/routes/api.php"

# 150 lines. Line 5 carries the KD-0789 phantom path as a literal string in a
# *searched, non-markdown* file — stronger than Kendo's fixture, which put it in
# a doc tree where the assertion passes even with is_path_shaped deleted.
{
    n=1
    while [ "$n" -le 150 ]; do
        case "$n" in
            5)   echo "// ranking rules live in app/Support/Rank.php" ;;
            93)  echo "        \$pattern = '/@[a-z]+/';" ;;
            109) echo "        return \$matches[1];" ;;
            *)   echo "// filler line $n" ;;
        esac
        n=$((n + 1))
    done
} > "$fixture/backend/app/Helpers/Mention.php"

cat > "$fixture/backend/app/Actions/StartWorkOnIssueAction.php" <<'PHP'
<?php

namespace App\Actions;

class StartWorkOnIssueAction
{
    public function handle(): void {}
}
PHP

cat > "$fixture/backend/app/Events/IssueMoved.php" <<'PHP'
<?php

namespace App\Events;

class IssueMoved {}
PHP

# Markdown inside a *searched* root: not in docs/ or site/, so only the extension
# exclusion keeps its phantom MISSING. Pins that guard independently.
cat > "$fixture/backend/app/NOTES.md" <<'MD'
Do not cite PhantomOnlyInMarkdownNote — it does not exist.
MD

echo "export const shared = true" > "$fixture/frontend/src/shared/index.ts"

# A second tree with the same subpath — a collision only a derived list can hit.
echo "export const shared = true" > "$fixture/mobile/src/shared/index.ts"

# A top-level tree no whitelist would have named. Pins the derivation.
cat > "$fixture/packages/core/src/thing.rs" <<'RUST'
pub fn derived_root_only_symbol() -> u32 { 0 }
RUST

# The prose tree that made the v1 phantoms pass.
cat > "$fixture/docs/anti-patterns.md" <<'MD'
Fabricated in KD-0789 and recorded here so nobody cites them again:
app/Support/Rank.php
App\Broadcasting\Events\IssuePositionEvent
MD

# Non-markdown prose: `--exclude='*.md'` misses .html, so only the directory
# denylist keeps this phantom MISSING.
cat > "$fixture/site/legacy.html" <<'HTML'
<p>The old docs mentioned PhantomInGeneratedProse.</p>
HTML

# v5 fixture: a markdown target whose real content has literal backticks. Line 1
# is the one under test; line 2 exists only so the file has more than one line.
cat > "$fixture/docs/markdown-with-backticks.md" <<'MD'
The write trigger checks `fat_turn` before firing.
Second line, unrelated.
MD

printf 'PK\003\004\000\000binary\000payload\000' > "$fixture/assets/logo.bin"
: > "$fixture/backend/app/Empty.php"

git -C "$fixture" init --quiet >/dev/null 2>&1
git -C "$fixture" add -A >/dev/null 2>&1

# --- Harness ---------------------------------------------------------------

# run <citation>...  — the subject, executed inside the fixture repo.
run() {
    (cd "$fixture" && printf '%s\n' "$@" | "$subject" 2>&1)
}

# assert_verdict <OK|CHANGED|MISSING> <citation> <description>
assert_verdict() {
    local expected=$1 citation=$2 description=$3 output actual
    output=$(run "$citation")
    actual=$(printf '%s' "$output" | awk 'NR==1 {print $1}')

    if [ "$actual" = "$expected" ]; then
        passed=$((passed + 1))
        printf '  ok    %s\n' "$description"
    else
        failed=$((failed + 1))
        printf '  FAIL  %s\n        expected %s, got %s\n' \
            "$description" "$expected" "${actual:-<no output>}"
    fi
}

# assert_exit <expected code> <description> <citation>...
assert_exit() {
    local expected=$1 description=$2 actual
    shift 2
    (cd "$fixture" && printf '%s\n' "$@" | "$subject" >/dev/null 2>&1)
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

# assert_output <substring> <description> <citation>...
assert_output() {
    local expected=$1 description=$2 output
    shift 2
    output=$(run "$@")

    if printf '%s' "$output" | grep -qF -- "$expected"; then
        passed=$((passed + 1))
        printf '  ok    %s\n' "$description"
    else
        failed=$((failed + 1))
        printf '  FAIL  %s\n        expected output containing: %s\n        got:\n%s\n' \
            "$description" "$expected" "$output"
    fi
}

echo "Resolving real citations"
# Act & Assert — assert_verdict runs the subject inside the fixture repo and compares the
# first-column verdict. Each case's arrange is its citation string; the sections below all
# share this shape unless they label their own.
assert_verdict OK 'backend/routes/api.php'   'path from repo root'
assert_verdict OK 'app/Helpers/Mention.php'  'path relative to a derived prefix'
assert_verdict OK 'src/shared/'              'directory relative to a derived prefix'
assert_verdict OK 'StartWorkOnIssueAction'   'bare symbol'
assert_verdict OK 'App\Events'               'PHP namespace'

echo
echo "Rejecting the KD-0789 phantoms"
# Path-shaped and MISSING even though the literal string appears on line 5 of
# backend/app/Helpers/Mention.php, a searched source file — pins "a path-shaped
# citation never falls back to the symbol grep".
assert_verdict MISSING 'app/Support/Rank.php' 'phantom path is not rescued by the symbol grep'
# Symbol-shaped and present ONLY in docs/ — pins the doc-tree exclusion.
assert_verdict MISSING 'App\Broadcasting\Events\IssuePositionEvent' \
    'phantom namespace documented in prose stays MISSING'
assert_verdict MISSING 'ThisSymbolDoesNotExistAnywhere' 'unknown symbol'
assert_verdict MISSING 'backend/routes/does-not-exist.php' 'unknown path'
# Prose lives in two places, each with its own guard.
assert_verdict MISSING 'PhantomOnlyInMarkdownNote' \
    'phantom in markdown inside a searched root stays MISSING'
assert_verdict MISSING 'PhantomInGeneratedProse' \
    'phantom in a non-markdown prose tree stays MISSING'

echo
echo "Deriving the layout instead of hardcoding it"
# Both fail if the derivation reverts to selecting known roots.
assert_verdict OK 'derived_root_only_symbol' 'symbol in an unanticipated top-level source tree'
assert_verdict OK 'core/src/thing.rs'        'path relative to an unanticipated top-level prefix'
# The override has to actually override: restricted to backend/app, packages/ goes.
# Act
output=$(cd "$fixture" && printf '%s\n' 'derived_root_only_symbol' \
    | VERIFY_CITATIONS_SEARCH_ROOTS='backend/app' "$subject" 2>&1)
# Assert
if printf '%s' "$output" | awk 'NR==1 {print $1}' | grep -qx MISSING; then
    passed=$((passed + 1))
    printf '  ok    %s\n' 'VERIFY_CITATIONS_SEARCH_ROOTS narrows the symbol search'
else
    failed=$((failed + 1))
    printf '  FAIL  %s\n        got:\n%s\n' \
        'VERIFY_CITATIONS_SEARCH_ROOTS narrows the symbol search' "$output"
fi
# The only verdict the derivation can be wrong about, so the only one that shows
# which roots it searched.
assert_output 'symbol search roots:' 'a missing symbol names the roots that were searched' \
    'ThisSymbolDoesNotExistAnywhere'
# Allowed — the citation is real either way — but it may not be silent.
assert_output 'also resolves to mobile/src/shared/' \
    'a citation resolving under two derived prefixes reports both' 'src/shared/'

echo
echo "Tolerating line references on a real path"
assert_verdict OK 'backend/routes/api.php:233'         'single line'
assert_verdict OK 'backend/routes/api.php:233-234'     'line range'
assert_verdict OK 'app/Helpers/Mention.php:93,109'     'line set'
assert_verdict OK 'app/Helpers/Mention.php:12-40,55'   'mixed range and set'
# A line reference wrapped in prose punctuation — the shape that regressed when
# the strip rules ran in the wrong order. Neither half is exercised by the
# plain-punctuation or plain-line-reference cases above; only the combination
# is, so it needs its own fixtures.
assert_verdict OK 'backend/routes/api.php:233-234)'    'line range followed by a closing paren'
assert_verdict OK '(backend/routes/api.php:233-234)'   'line range wrapped in parens'
assert_verdict OK 'app/Helpers/Mention.php:93,109.'    'line set ending a sentence'

echo
echo "Checking the cited line, not just the path"
assert_verdict OK "backend/routes/api.php:233 | Route::get('/issues'" \
    'cited content still on the cited line'
assert_verdict CHANGED "backend/routes/api.php:233 | Route::delete('/issues'" \
    'cited content no longer on the cited line'
# The row path-only checking gets wrong: file still there, cited line gone.
assert_verdict CHANGED 'backend/routes/api.php:9999' \
    'line reference past the end of the file'
assert_verdict CHANGED 'backend/routes/api.php:290-310' \
    'line range running off the end of the file'
# Any line of a set counts; here it is the second.
assert_verdict OK 'app/Helpers/Mention.php:93,109 | return $matches[1];' \
    'cited content on the second line of a set'
# No line reference: the fragment is checked against the whole file.
assert_verdict OK "backend/routes/api.php | Route::post('/issues'" \
    'cited content without a line reference'
assert_verdict CHANGED 'backend/routes/api.php | Route::patch(' \
    'absent content without a line reference'
# The v3 combination with a fragment attached: punctuation stripping still runs
# before the reference is captured, and neither may eat the fragment.
assert_verdict OK "(backend/routes/api.php:233-234) | Route::get('/issues'" \
    'wrapped line range with cited content'
# Trailing punctuation is stripped from the citation half only.
assert_verdict OK 'app/Helpers/Mention.php:109 | return $matches[1];' \
    'fragment keeps its own trailing punctuation'
# Nothing to read a line from, in three different ways.
assert_verdict OK 'src/shared/:42'      'line reference on a directory is not checked'
assert_verdict OK 'assets/logo.bin:42'  'line reference into a binary file is not checked'
assert_verdict CHANGED 'app/Empty.php:1' 'line reference into an empty file'

echo
echo "Backticks in the cited target itself (v5)"
# The target's real line is: The write trigger checks `fat_turn` before firing.
# Fragment crosses both backticks -- CHANGED before the fix, since only the
# fragment's own backticks were stripped and the target's were not.
assert_verdict OK 'docs/markdown-with-backticks.md:1 | checks fat_turn before' \
    'fragment spanning a backtick-quoted word, line-referenced'
# Same fragment, no line reference -- exercises the whole-file grep branch,
# which needed its own fix independent of lines_contain.
assert_verdict OK 'docs/markdown-with-backticks.md | checks fat_turn before' \
    'fragment spanning a backtick-quoted word, whole-file'
# A fragment that never touches a backtick worked even before the fix --
# pins that the fix did not change this case.
assert_verdict OK 'docs/markdown-with-backticks.md:1 | write trigger checks' \
    'fragment not touching a backtick still resolves'
# A genuinely absent fragment must still report CHANGED -- pins that stripping
# backticks did not turn the check into a no-op.
assert_verdict CHANGED 'docs/markdown-with-backticks.md:1 | checks slow_turn before' \
    'a real content change is still caught after stripping backticks'

echo
echo "Normalising how citations get pasted"
# The literal backticks are the fixture: these two cases assert the resolver
# strips them off a citation pasted out of markdown. Single quotes are required
# to keep them literal, so SC2016 is inverted here.
# shellcheck disable=SC2016
assert_verdict OK '`backend/routes/api.php`'    'backtick-wrapped'
# shellcheck disable=SC2016
assert_verdict OK '- `backend/routes/api.php`'  'markdown list item'
assert_verdict OK '  backend/routes/api.php  '  'surrounding whitespace'
assert_verdict OK 'backend/routes/api.php.'     'trailing sentence punctuation'
# shellcheck disable=SC2016
assert_verdict OK "- \`backend/routes/api.php:233\` | \`Route::get('/issues'\`" \
    'markdown list item with a backticked fragment'

echo
echo "Skipping blanks and comments"
assert_output 'All 1 citations resolve.' 'comments and blank lines are not counted' \
    '# a comment' '' 'backend/routes/api.php'

echo
echo "Portability"
# Static rather than behavioural, deliberately. GNU sed accepts `\+`, so every
# assertion above passes on CI and on any Linux box while the same strip rule
# matches nothing under POSIX BRE — BSD sed, which macOS ships and which
# README.md supports as a dev platform. Reproducing that needs a sed the runner
# does not have, so the check that runs everywhere is "the script never relies
# on the extension". Comment lines are excluded: one of them names `\+` in
# order to explain this.
# Act & Assert — static, against the subject's text rather than the fixture
if grep -vE '^[[:space:]]*#' "$subject" | grep -qE '\\\+|\\\|'; then
    failed=$((failed + 1))
    printf '  FAIL  %s\n        found GNU-only BRE; the strip rules need sed -E\n' \
        'strip rules avoid GNU-only BRE'
else
    passed=$((passed + 1))
    printf '  ok    %s\n' 'strip rules avoid GNU-only BRE'
fi

# `mapfile`/`readarray` is bash 4+; macOS ships bash 3.2 and `env bash` finds it.
# Same platform trap as the sed one above, by a different route, equally
# invisible on CI.
# Act & Assert
if grep -vE '^[[:space:]]*#' "$subject" | grep -qE '\b(mapfile|readarray)\b'; then
    failed=$((failed + 1))
    printf '  FAIL  %s\n        found bash 4+ mapfile/readarray; macOS ships bash 3.2\n' \
        'array building avoids bash 4-only builtins'
else
    passed=$((passed + 1))
    printf '  ok    %s\n' 'array building avoids bash 4-only builtins'
fi

echo
echo "Exit codes"
assert_exit 0 'clean run exits 0' 'backend/routes/api.php' 'StartWorkOnIssueAction'
assert_exit 1 'any MISSING exits 1' 'backend/routes/api.php' 'app/Support/Rank.php'
assert_exit 1 'all MISSING exits 1' 'app/Support/Rank.php'
# CHANGED fails the gate too — treating it as a pass misses the whole point.
assert_exit 1 'a CHANGED citation alone exits 1' 'backend/routes/api.php:9999'
# Reports on every citation rather than bailing at the first failure.
assert_output '2 of 3 citations do not resolve.' 'reports all failures in one pass' \
    'app/Support/Rank.php' 'backend/routes/api.php' 'ThisSymbolDoesNotExistAnywhere'
# Never merged: the two need different work to resolve.
assert_output '1 of 2 citations do not resolve.' 'missing and changed are counted separately' \
    'app/Support/Rank.php' 'backend/routes/api.php:9999'
assert_output '1 of 2 citations resolve but no longer say what they were cited for.' \
    'changed citations get their own line' \
    'app/Support/Rank.php' 'backend/routes/api.php:9999'

echo
echo
echo "Input contract guard"
#
# v5 would have been: piping a document in and reading 219 of 227 MISSING as rot.
# Not a resolver bug -- a caller mistake the script did nothing to distinguish
# from the real thing. Both directions are pinned, because a guard that refuses a
# real citation list is the same class of error it exists to prevent.

# A document is refused outright, with a distinct exit code and nothing checked.
assert_exit 2 'a prose document is refused rather than reported as rot' \
    '# Context economy -- skills design' \
    'This document exists because the reasoning that produced it cannot be recovered.' \
    'Cost per turn *is* the resident context size, so total cost is quadratic.' \
    'The mechanism is not the problem. The trigger is.' \
    'Each records the alternative it beat, because no citation can recover that.' \
    'Auto-compaction already compresses well, so replacing it solves a solved problem.'

assert_output 'ONE CITATION PER LINE' \
    'the refusal explains the contract rather than just failing' \
    '# Context economy -- skills design' \
    'This document exists because the reasoning that produced it cannot be recovered.' \
    'Cost per turn *is* the resident context size, so total cost is quadratic.' \
    'The mechanism is not the problem. The trigger is.' \
    'Each records the alternative it beat, because no citation can recover that.' \
    'Auto-compaction already compresses well, so replacing it solves a solved problem.'

assert_output 'First lines that are not citation-shaped:' \
    'the refusal shows which lines tripped it' \
    '# Context economy -- skills design' \
    'This document exists because the reasoning that produced it cannot be recovered.' \
    'Cost per turn *is* the resident context size, so total cost is quadratic.' \
    'The mechanism is not the problem. The trigger is.' \
    'Each records the alternative it beat, because no citation can recover that.' \
    'Auto-compaction already compresses well, so replacing it solves a solved problem.'

# --- The guard must not fire on real input --------------------------------

# Fragments after the bar are prose by design and must not count against it.
# Asserted on a verdict line rather than on exit 0: whether these particular
# fragments still match is the resolver's business and is covered above. What
# matters here is that verdicts were produced at all, which a refusal prevents.
assert_output 'backend/routes/api.php:233' \
    'fragment-carrying citations are checked, not refused as prose' \
    'backend/routes/api.php:233 | Route::get' \
    'backend/routes/api.php:234 | Route::post' \
    'app/Helpers/Mention.php:93 | public function render' \
    'src/shared/ | the shared frontend tree' \
    'StartWorkOnIssueAction | the action under test' \
    'App\Events | the events namespace'

# A stray prose line among good citations must be checked, not abort the run. It
# resolves MISSING, which is correct -- it is not a citation.
assert_exit 1 'one stray prose line does not abort a real list' \
    'backend/routes/api.php' \
    'app/Helpers/Mention.php' \
    'StartWorkOnIssueAction' \
    'this line is prose and should simply fail to resolve' \
    'src/shared/' \
    'App\Events'

assert_output 'OK' \
    'a real list with one stray line still reports its real verdicts' \
    'backend/routes/api.php' \
    'app/Helpers/Mention.php' \
    'StartWorkOnIssueAction' \
    'this line is prose and should simply fail to resolve' \
    'src/shared/' \
    'App\Events'

# Below the 5-candidate floor the guard never fires, so a legal path containing a
# space is still checked rather than refused sight-unseen.
assert_exit 1 'a short prose input is checked, not refused' \
    'this is prose but there are only two lines' \
    'so the guard must not fire here'

# Blanks and comments are not candidates, so they cannot tip the majority.
assert_exit 0 'blanks and comments do not count toward the guard' \
    '# a comment' \
    '' \
    'backend/routes/api.php' \
    '# another comment' \
    '' \
    'app/Helpers/Mention.php' \
    'StartWorkOnIssueAction' \
    'src/shared/' \
    'App\Events'

if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
