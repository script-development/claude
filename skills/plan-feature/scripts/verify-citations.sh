#!/usr/bin/env bash
#
# Resolve every path and symbol a plan is about to cite.
#
# Fabricated citations are the failure mode that once cost a plan three
# reviewer rounds (see references/anti-patterns.md § Calibration): a phantom
# directory, a phantom namespace, and a route precedent that did not exist —
# each one a two-second lookup. This script makes the lookup mechanical so the
# planner cannot self-report its way past it.
#
# Usage:
#   verify-citations.sh <file>          # one citation per line
#   printf '%s\n' a b | verify-citations.sh
#
# Each line is a path (`app/Helpers/Slug.php`, `frontend/src/shared/`) or a
# bare symbol (`CreateWidgetAction`, `useFieldError`). Paths are resolved
# against the repo root and against each path prefix (default: backend/ and
# frontend/), because plans cite them the way layered CLAUDE.md files do.
# Symbols are grepped across the source trees. Backticks, list markers,
# wrapping punctuation and a trailing line reference (`:42`, `:233-234`,
# `:93,109`) are stripped before resolving.
#
# Configuration (optional, space-separated, relative to the repo root):
#   CITATION_PATH_PREFIXES   prefixes a path may be relative to
#                            (default: "" backend/ frontend/)
#   CITATION_SEARCH_ROOTS    trees to grep for a bare symbol
#                            (default: the common source trees that exist —
#                            see `default_search_roots` below; falls back to
#                            the whole repo minus prose and vendor trees)
#
# Exits 0 when every citation resolves, 1 when any is MISSING.

# -e is deliberately absent: every citation must be reported in one pass, so a
# failed lookup has to fall through to the next line rather than kill the run.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "verify-citations: not inside a git repository" >&2
    exit 2
}

# Path prefixes a citation may be relative to, in resolution order. The empty
# prefix (repo root) is always tried first.
prefixes=("")
if [ -n "${CITATION_PATH_PREFIXES:-}" ]; then
    # shellcheck disable=SC2206
    prefixes+=(${CITATION_PATH_PREFIXES})
else
    prefixes+=("backend/" "frontend/")
fi

# Trees worth grepping for a bare symbol. Three exclusions are load-bearing:
# vendor/ and node_modules/ (a framework-behaviour claim must cite a vendor
# file:line, which resolves through the path branch instead), and every prose
# tree — .claude/, docs/, site/ — because a document that *discusses* a phantom
# symbol contains its name. Grepping docs would make anti-patterns.md vouch for
# the very citations it records as fabricated.
default_search_roots="app routes config database tests src lib cmd cli
                      backend/app backend/routes backend/config backend/database backend/tests
                      frontend/src frontend/tests"

search_roots=()
for candidate in ${CITATION_SEARCH_ROOTS:-$default_search_roots}; do
    [ -d "$root/$candidate" ] && search_roots+=("$root/$candidate")
done
# No conventional source tree: grep the whole repo. The prose and vendor
# exclusions below keep that fallback honest.
[ ${#search_roots[@]} -eq 0 ] && search_roots=("$root")

resolve_path() {
    local citation=$1 prefix
    for prefix in "${prefixes[@]}"; do
        if [ -e "$root/$prefix$citation" ]; then
            printf '%s' "$prefix$citation"
            return 0
        fi
    done
    return 1
}

resolve_symbol() {
    local citation=$1
    grep -rIqF --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git \
        --exclude-dir=.claude --exclude-dir=docs --exclude-dir=site \
        --exclude='*.md' \
        -- "$citation" "${search_roots[@]}" 2>/dev/null
}

# A citation that names a file or directory is resolved as a path and never
# falls back to the symbol grep. `app/Support/Rank.php` appearing as a string
# somewhere is not evidence that the file exists — that fallback is exactly how
# a phantom path earns an OK.
is_path_shaped() {
    case "$1" in
        */*) return 0 ;;
        *.php | *.ts | *.vue | *.js | *.go | *.md | *.yaml | *.yml | *.json | *.sh | *.css)
            return 0 ;;
        *) return 1 ;;
    esac
}

missing=0
checked=0

while IFS= read -r line || [ -n "$line" ]; do
    # Strip list markers, backticks, surrounding whitespace, wrapping
    # punctuation, and a trailing line reference.
    #
    # The line reference has to cover ranges and sets, not just `:42`. Plans
    # cite `api.php:233-234` and `ManagesTransactions.php:93,109` — both shapes
    # appear in this skill's own reference files. Stripping only `:42` left the
    # rest attached to the path, which reported a real file as MISSING. A
    # false positive in a fail-closed gate is worse than a missed one: it
    # teaches the planner the script is wrong and can be ignored.
    #
    # Punctuation is stripped BEFORE the line reference, and that order is
    # load-bearing. Prose cites `(api.php:233-234)`; with the line rule first
    # the trailing `)` blocks its `$` anchor, the `:233-234` survives into the
    # path, and a real file comes back MISSING — the same false positive by a
    # different route. Both ends of the wrap have to go for the same reason.
    #
    # -E (extended regex) is required, not cosmetic. The line rule needs `+`,
    # and BRE `\+` is a GNU extension: under POSIX BRE — BSD sed, which is what
    # macOS ships — the rule does not fire and every line-referenced citation
    # resolves MISSING. CI runs GNU sed, so a suite stays green while the gate
    # misfires on half the team's laptops.
    citation=$(printf '%s' "$line" \
        | sed -E -e 's/^[[:space:]]*[-*+][[:space:]]*//' \
              -e 's/`//g' \
              -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              -e 's/^[([]*//' \
              -e 's/[.,;)]*$//' \
              -e 's/:[0-9]+([,-][0-9]+)*$//')

    [ -z "$citation" ] && continue
    case "$citation" in \#*) continue ;; esac

    checked=$((checked + 1))

    if resolved=$(resolve_path "$citation"); then
        printf 'OK       %-58s → %s\n' "$citation" "$resolved"
    elif is_path_shaped "$citation"; then
        printf 'MISSING  %-58s → no such file or directory\n' "$citation"
        missing=$((missing + 1))
    elif resolve_symbol "$citation"; then
        printf 'OK       %-58s → symbol found in source\n' "$citation"
    else
        printf 'MISSING  %-58s → symbol not found in source\n' "$citation"
        missing=$((missing + 1))
    fi
done < "${1:-/dev/stdin}"

echo
if [ "$missing" -gt 0 ]; then
    echo "$missing of $checked citations do not resolve."
    exit 1
fi

echo "All $checked citations resolve."
