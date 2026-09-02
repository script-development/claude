#!/usr/bin/env bash
#
# Tests for verify-citations.sh.
#
# Every case below is a regression. The resolver shipped several times with a
# bug that a two-line fixture would have caught for free:
#
#   v1  passed every phantom from the calibration plan, because a path-shaped
#       citation fell back to the symbol grep and .claude/ was in the search
#       roots — so anti-patterns.md, the file recording those citations as
#       fabricated, vouched for them.
#   v2  reported real files as MISSING when the citation carried a line range,
#       because the strip rule only handled `:42` and not `:233-234`.
#   v3  reported real files as MISSING when that line range was wrapped in
#       prose punctuation — `(api.php:233-234)` — because the strip rules ran
#       in an order that let the `)` block the line rule's anchor.
#   v4  would have reported every line-referenced citation as MISSING on macOS,
#       because the line rule used GNU-only BRE `\+`. Note the shape: v4 is the
#       first entry no fixture below can catch, since CI's sed is the one that
#       works. It is pinned statically under "Portability" instead.
#
# Both directions matter and both are pinned here. A missed phantom costs a
# reviewer round; a false MISSING teaches the planner the gate is wrong and can
# be worked around, which costs every future catch.
#
# No framework by design — most repos have no bats and no shell test harness,
# and CI runs plain scripts with `bash <path>`. Run it the same way:
#
#   bash .claude/skills/plan-feature/scripts/verify-citations.test.sh
#
# The OK cases resolve against a throwaway fixture repository built in a temp
# directory, not against the repo the script ships in — so the suite passes in
# any consumer regardless of its layout. The fixture mirrors the layered
# monorepo shape the defaults target (backend/ + frontend/) plus a prose tree
# that mentions the phantoms, which is the trap v1 fell into.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/verify-citations.sh"

if [ ! -x "$subject" ]; then
    echo "verify-citations.sh not found or not executable at $subject" >&2
    exit 2
fi

# --- Fixture -----------------------------------------------------------------

fixture=$(mktemp -d "${TMPDIR:-/tmp}/verify-citations.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

build_fixture() {
    local dir=$1
    git -c init.defaultBranch=main init -q "$dir"
    mkdir -p "$dir/backend/routes" "$dir/backend/app/Helpers" \
             "$dir/backend/app/Actions/Widgets" "$dir/backend/app/Events" \
             "$dir/frontend/src/shared" \
             "$dir/.claude/skills/plan-feature/references" "$dir/docs/plans/example"
    printf '<?php\nRoute::put("{widget}", UpdateWidgetController::class);\n' \
        > "$dir/backend/routes/api.php"
    printf '<?php\nnamespace App\\Helpers;\nfinal class Slug {}\n' \
        > "$dir/backend/app/Helpers/Slug.php"
    printf '<?php\nnamespace App\\Actions\\Widgets;\nfinal readonly class CreateWidgetAction {}\n' \
        > "$dir/backend/app/Actions/Widgets/CreateWidgetAction.php"
    printf '<?php\nnamespace App\\Events;\nfinal class WidgetMoved {}\n' \
        > "$dir/backend/app/Events/WidgetMoved.php"
    : > "$dir/frontend/src/shared/index.ts"
    # The phantoms appear ONLY in prose. If the resolver ever greps these trees,
    # the phantoms come back OK and the v1 regression is back.
    printf 'Phantom path: `app/Support/Rank.php`\nPhantom namespace: `App\\Broadcasting\\Events\\WidgetMovedEvent`\n' \
        > "$dir/.claude/skills/plan-feature/references/anti-patterns.md"
    printf 'See app/Support/Rank.php and App\\Broadcasting\\Events\\WidgetMovedEvent\n' \
        > "$dir/docs/plans/example/PLAN.md"
}

# A repo with none of the conventional source trees — pins the whole-repo
# fallback and the prose exclusions that keep it honest.
build_flat_fixture() {
    local dir=$1
    git -c init.defaultBranch=main init -q "$dir"
    mkdir -p "$dir/packages/core" "$dir/.claude" "$dir/docs"
    printf '<?php\nfinal class FlatRepoThing {}\n' > "$dir/packages/core/Thing.php"
    printf 'OnlyInProse is a phantom\n' > "$dir/.claude/notes.md"
    printf 'OnlyInDocs is a phantom\n' > "$dir/docs/notes.txt"
}

build_fixture "$fixture/layered"
build_flat_fixture "$fixture/flat"
cd "$fixture/layered" || exit 2

# --- Harness -----------------------------------------------------------------

passed=0
failed=0

# assert_verdict <OK|MISSING> <citation> <description>
assert_verdict() {
    local expected=$1 citation=$2 description=$3 output actual
    output=$(printf '%s\n' "$citation" | "$subject" 2>&1)
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
    printf '%s\n' "$@" | "$subject" >/dev/null 2>&1
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
    output=$(printf '%s\n' "$@" | "$subject" 2>&1)

    if printf '%s' "$output" | grep -qF -- "$expected"; then
        passed=$((passed + 1))
        printf '  ok    %s\n' "$description"
    else
        failed=$((failed + 1))
        printf '  FAIL  %s\n        expected output containing: %s\n        got:\n%s\n' \
            "$description" "$expected" "$output"
    fi
}

# --- Cases -------------------------------------------------------------------

echo "Resolving real citations"
assert_verdict OK 'backend/routes/api.php'   'path from repo root'
assert_verdict OK 'app/Helpers/Slug.php'     'path relative to backend/'
assert_verdict OK 'src/shared/'              'directory relative to frontend/'
assert_verdict OK 'CreateWidgetAction'       'bare symbol'
assert_verdict OK 'App\Events'               'PHP namespace'

echo
echo "Rejecting the calibration phantoms"
# Path-shaped and MISSING even though the literal string appears in
# references/anti-patterns.md — pins "a path-shaped citation never falls back
# to the symbol grep".
assert_verdict MISSING 'app/Support/Rank.php' 'phantom path is not rescued by the symbol grep'
# Symbol-shaped and present ONLY in .claude/ and docs/ prose — pins the
# doc-tree exclusion.
assert_verdict MISSING 'App\Broadcasting\Events\WidgetMovedEvent' \
    'phantom namespace documented in prose stays MISSING'
assert_verdict MISSING 'ThisSymbolDoesNotExistAnywhere' 'unknown symbol'
assert_verdict MISSING 'backend/routes/does-not-exist.php' 'unknown path'

echo
echo "Tolerating line references on a real path"
assert_verdict OK 'backend/routes/api.php:233'         'single line'
assert_verdict OK 'backend/routes/api.php:233-234'     'line range'
assert_verdict OK 'app/Helpers/Slug.php:93,109'        'line set'
assert_verdict OK 'app/Helpers/Slug.php:12-40,55'      'mixed range and set'
# A line reference wrapped in prose punctuation — the shape that regressed when
# the strip rules ran in the wrong order. Neither half is exercised by the
# plain-punctuation or plain-line-reference cases above; only the combination
# is, so it needs its own fixtures.
assert_verdict OK 'backend/routes/api.php:233-234)'    'line range followed by a closing paren'
assert_verdict OK '(backend/routes/api.php:233-234)'   'line range wrapped in parens'
assert_verdict OK 'app/Helpers/Slug.php:93,109.'       'line set ending a sentence'

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

echo
echo "Skipping blanks and comments"
assert_output 'All 1 citations resolve.' 'comments and blank lines are not counted' \
    '# a comment' '' 'backend/routes/api.php'

echo
echo "Honouring configuration"
assert_verdict MISSING 'Helpers/Slug.php' 'a prefix outside the default list does not resolve'
CITATION_PATH_PREFIXES='backend/app/' \
    assert_verdict OK 'Helpers/Slug.php' 'CITATION_PATH_PREFIXES adds a prefix'
CITATION_SEARCH_ROOTS='frontend/src' \
    assert_verdict MISSING 'CreateWidgetAction' 'CITATION_SEARCH_ROOTS narrows the symbol grep'

echo
echo "Falling back to the whole repo when no conventional tree exists"
cd "$fixture/flat" || exit 2
assert_verdict OK 'FlatRepoThing'   'symbol found outside the conventional trees'
assert_verdict MISSING 'OnlyInProse' 'fallback still skips .claude/'
assert_verdict MISSING 'OnlyInDocs'  'fallback still skips docs/'
cd "$fixture/layered" || exit 2

echo
echo "Portability"
# Static rather than behavioural, deliberately. GNU sed accepts `\+`, so every
# assertion above passes on CI and on any Linux box while the same strip rule
# matches nothing under POSIX BRE — BSD sed, which macOS ships. Reproducing
# that needs a sed the runner does not have, so the check that runs everywhere
# is "the script never relies on the extension". Comment lines are excluded:
# one of them names `\+` in order to explain this.
if grep -vE '^[[:space:]]*#' "$subject" | grep -qE '\\\+|\\\|'; then
    failed=$((failed + 1))
    printf '  FAIL  %s\n        found GNU-only BRE; the strip rules need sed -E\n' \
        'strip rules avoid GNU-only BRE'
else
    passed=$((passed + 1))
    printf '  ok    %s\n' 'strip rules avoid GNU-only BRE'
fi

echo
echo "Exit codes"
assert_exit 0 'clean run exits 0' 'backend/routes/api.php' 'CreateWidgetAction'
assert_exit 1 'any MISSING exits 1' 'backend/routes/api.php' 'app/Support/Rank.php'
assert_exit 1 'all MISSING exits 1' 'app/Support/Rank.php'
# Reports on every citation rather than bailing at the first failure — the
# behaviour Phase 1.4's prose promises.
assert_output '2 of 3 citations do not resolve.' 'reports all failures in one pass' \
    'app/Support/Rank.php' 'backend/routes/api.php' 'ThisSymbolDoesNotExistAnywhere'

echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
