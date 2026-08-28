#!/usr/bin/env bash
#
# Resolve every path and symbol a document is about to cite, and check that the
# cited line still says what it was cited for.
#
# Fabricated citations are the failure mode that cost KD-0789 three reviewer
# rounds: a phantom directory, a phantom namespace, and a route precedent that
# did not exist — each one a two-second lookup. This script makes the lookup
# mechanical so the author cannot self-report their way past it.
#
# Usage:
#   verify-citations.sh <file>          # one citation per line
#   printf '%s\n' a b | verify-citations.sh
#
# Each line is a path (`app/Helpers/Mention.php`, `frontend/src/shared/`) or a
# bare symbol (`StartWorkOnIssueAction`, `useFieldError`), optionally carrying
# the content it was cited for after a `|`:
#
#   tools/context-audit.js:42 | const REQUESTS_DIR
#
#   OK       path resolves and the cited line still contains the fragment
#   CHANGED  path resolves but that line does not — the claim may now be false
#   MISSING  path or symbol does not resolve at all — it moved, or never existed
#
# Exits 0 when every citation is intact, 1 on any MISSING or CHANGED, 2 when the
# input is not a citation list at all (see the input contract guard below).
#
# Paths resolve against the repo root and each top-level tracked directory;
# symbols are grepped across the tracked tree minus dependency and prose trees.
# Backticks, list markers and wrapping punctuation are stripped first. A trailing
# line reference (`:42`, `:233-234`, `:93,109`) is stripped off the path and then
# USED — with no `|` fragment it is still checked for existence, which catches a
# citation pointing past the end of a file that has since shrunk.
#
# Ported from <kendo>/.claude/skills/plan-feature/scripts/verify-citations.sh.
# Per D3 in docs/design.md: mechanism verbatim,
# layout derived (D9), process not ported, three outcomes added (D5).
#
# The long comments that remain are Kendo's, and they stay. Each records a bug
# already paid for and none is recoverable by reading what the code does — the
# strip-rule ordering, the `sed -E` requirement, `is_path_shaped`, the absence of
# `set -e`. Everything about *why the design is this way* lives in the design doc,
# not here; comments in this file say only what someone editing it needs.

# -e is deliberately absent: every citation must be reported in one pass, so a
# failed lookup has to fall through to the next line rather than kill the run.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "verify-citations: not inside a git repository" >&2
    exit 2
}

# --- Layout: derived by EXCLUSION, never selected (D9) ---------------------
#
# Everything git tracks, minus dependency and prose trees. The rule a future
# editor needs: both knobs below err toward the LARGER set on purpose. Narrowing
# either one to suppress a false OK trades the cheap error for the expensive one.
#
# Overrides, for a layout the derivation gets wrong:
#   VERIFY_CITATIONS_PREFIXES="backend/ frontend/"
#   VERIFY_CITATIONS_SEARCH_ROOTS="backend/app frontend/src"   # repo-relative

# The prose exclusions are load-bearing, per Kendo's comment: a document that
# *discusses* a phantom symbol contains its name, so grepping docs would make
# anti-patterns.md vouch for the very citations it records as fabricated.
# `--exclude='*.md'` below is the generic form — markdown is where prose lives
# whatever the directory is called; these names catch the rest.
excluded_trees=".git .github .claude docs doc documentation site website wiki
               reports notes adr vendor node_modules dist build target
               coverage .venv venv __pycache__"

# `git ls-files`, not a glob, so .gitignore does the first pass for free —
# vendor/ and node_modules/ are usually ignored already and the names above are
# belt-and-braces for the projects where they are not.
tracked_top_level() {
    git -C "$root" ls-files | sed -E 's#/.*##' | sort -u
}

is_excluded() {
    local candidate=$1 excluded
    for excluded in $excluded_trees; do
        [ "$candidate" = "$excluded" ] && return 0
    done
    return 1
}

# Prefixes a citation may be relative to, in resolution order. Root first, so a
# repo-relative citation never resolves through a sub-root by accident.
prefixes=("")
if [ -n "${VERIFY_CITATIONS_PREFIXES:-}" ]; then
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        prefixes+=("$entry")
    done < <(printf '%s\n' $VERIFY_CITATIONS_PREFIXES)
else
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        [ -d "$root/$entry" ] || continue
        is_excluded "$entry" && continue
        prefixes+=("$entry/")
    done < <(tracked_top_level)
fi

# Trees worth grepping for a bare symbol.
search_roots=()
if [ -n "${VERIFY_CITATIONS_SEARCH_ROOTS:-}" ]; then
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        [ -d "$root/$entry" ] && search_roots+=("$root/$entry")
    done < <(printf '%s\n' $VERIFY_CITATIONS_SEARCH_ROOTS)
else
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        [ -d "$root/$entry" ] || continue
        is_excluded "$entry" && continue
        search_roots+=("$root/$entry")
    done < <(tracked_top_level)
fi

# EVERY prefix the citation resolves under, not just the first. A derived list is
# larger than a hand-written one, so it can match twice (Kendo's `src/shared/`
# exists under both `extension/` and `frontend/`). Verdict stays OK — the citation
# is real — but the alternatives get printed, so ambiguity is never silent.
resolve_path() {
    local citation=$1 prefix found=1
    for prefix in "${prefixes[@]}"; do
        if [ -e "$root/$prefix$citation" ]; then
            printf '%s\n' "$prefix$citation"
            found=0
        fi
    done
    return "$found"
}

resolve_symbol() {
    local citation=$1
    [ ${#search_roots[@]} -eq 0 ] && return 1
    grep -rIqF --exclude-dir=node_modules --exclude-dir=vendor --exclude-dir=.git \
        --exclude='*.md' \
        -- "$citation" "${search_roots[@]}" 2>/dev/null
}

# A citation that names a file or directory is resolved as a path and never
# falls back to the symbol grep. `app/Support/Rank.php` appearing as a string
# somewhere is not evidence that the file exists — that fallback is exactly how
# a phantom path earns an OK.
#
# `*/*` does nearly all the work; the extension arm is only a backstop for a bare
# root-level filename (`README.md`). Keep it modest — a symbol wrongly called
# path-shaped reports MISSING, the expensive error, so every extension added here
# trades the cheap error for the dear one.
is_path_shaped() {
    case "$1" in
        */*) return 0 ;;
        *.php | *.ts | *.tsx | *.vue | *.js | *.jsx | *.mjs | *.go | *.py \
            | *.rb | *.rs | *.java | *.kt | *.cs | *.md | *.yaml | *.yml \
            | *.json | *.toml | *.sh | *.css | *.scss | *.sql | *.neon)
            return 0 ;;
        *) return 1 ;;
    esac
}

# --- Line-reference checking (D5) ------------------------------------------

# Largest line a reference names, without expanding it: `12-40,55` is 55.
max_referenced_line() {
    printf '%s' "$1" | tr ',-' '\n\n' | sort -n | tail -1
}

# Every line a reference names. Which one carries the fragment is not knowable
# from the citation, so a hit on any of them counts. The 500 cap is a runaway
# guard for a malformed `:1-9999999`.
referenced_lines() {
    local part start end n emitted=0
    local IFS=,
    for part in $1; do
        case "$part" in
            *-*)
                start=${part%%-*}
                end=${part##*-}
                n=$start
                while [ "$n" -le "$end" ] && [ "$emitted" -lt 500 ]; do
                    printf '%s\n' "$n"
                    n=$((n + 1))
                    emitted=$((emitted + 1))
                done
                ;;
            *)
                printf '%s\n' "$part"
                emitted=$((emitted + 1))
                ;;
        esac
    done
}

# A binary blob has no line to read, and feeding one to sed prints its bytes into
# the report. The zero-byte case must answer "text": grep finds no line to match
# in an empty file and calls it binary, which hands a citation into a
# truncated-to-nothing file a free OK. Answering "text" drops it through to the
# line-existence check, where 0 lines correctly fails.
is_text_file() {
    [ -s "$1" ] || return 0
    grep -Iq . "$1" 2>/dev/null
}

total_lines() {
    # Not `wc -l`: it counts newlines, so it is off by one on a file with no
    # trailing newline — precisely the file whose last line someone cites.
    awk 'END { print NR }' "$1"
}

lines_contain() {
    local file=$1 fragment=$2 spec=$3 n content
    while IFS= read -r n; do
        content=$(sed -n "${n}p" "$file")
        case "$content" in *"$fragment"*) return 0 ;; esac
    done < <(referenced_lines "$spec")
    return 1
}

# --- Input contract guard --------------------------------------------------
#
# One citation per line is a contract, and violating it produces the loudest
# possible false positive: piping a markdown document in reports every prose
# sentence as MISSING. Measured on this repo's own design doc, 219 of 227 lines
# "failed" -- output identical in shape to catastrophic citation rot, and read
# that way. That is the expensive error this whole script is built to avoid,
# manufactured wholesale by a caller mistake the script did nothing to catch.
#
# Reporting it as MISSING also collapses two different outcomes into one, which
# is the bug D5 exists to fix, one level up: "your input was wrong" and "your
# citations rotted" need different work and must not share a verdict.
#
# The discriminator is whitespace where a path or symbol should be. A citation's
# pre-bar half never contains a space; a prose line almost always does. Measured
# gap: ~0% against ~95%, so the majority test below cannot realistically
# misfire. The fragment half after `|` is excluded, since it is prose by design.
#
# Two deliberate conservatisms, both because a false refusal of a real list
# would be its own version of the error above:
#   - at least 5 candidate lines, so a short list can never trip it. A real path
#     containing a space is legal and rare; on a small input it now runs anyway.
#   - a strict majority, not a fixed count, so one stray line among good ones
#     still gets checked rather than aborting the run.
#
# Exit 2, not 1. A caller doing `if ! verify-citations.sh` still sees failure,
# so the binary contract the exit-code comment at the bottom describes is intact
# -- but a caller that cares can tell a misuse from a gate failure.
input=$(cat -- "${1:-/dev/stdin}")

guard_total=0
guard_prose=0
guard_examples=()

while IFS= read -r line; do
    # Mirror the main loop's cleaning, minus sed: leading whitespace, one list
    # marker, then whitespace again. A guard that cleaned differently from the
    # loop could refuse input the loop would have handled.
    candidate=${line%%|*}
    candidate=${candidate#"${candidate%%[![:space:]]*}"}
    case $candidate in
        [-*+]*) candidate=${candidate#?} ;;
    esac
    candidate=${candidate#"${candidate%%[![:space:]]*}"}
    candidate=${candidate%"${candidate##*[![:space:]]}"}

    [ -z "$candidate" ] && continue
    case $candidate in "#"*) continue ;; esac

    guard_total=$((guard_total + 1))
    case $candidate in
        *[[:space:]]*)
            guard_prose=$((guard_prose + 1))
            [ "${#guard_examples[@]}" -lt 3 ] && guard_examples+=("$candidate")
            ;;
    esac
done <<< "$input"

if [ "$guard_total" -ge 5 ] && [ $((guard_prose * 2)) -gt "$guard_total" ]; then
    {
        echo "ERROR: this does not look like a citation list, so nothing was checked."
        echo
        echo "$guard_prose of $guard_total input lines contain whitespace where a path or"
        echo "symbol should be. This script takes ONE CITATION PER LINE, not a document:"
        echo "piping prose in reports every sentence as MISSING, which is indistinguishable"
        echo "from real citation rot. Extract the citations first, then pipe those."
        if [ "${#guard_examples[@]}" -gt 0 ]; then
            echo
            echo "First lines that are not citation-shaped:"
            for guard_example in "${guard_examples[@]}"; do
                echo "  $guard_example"
            done
        fi
    } >&2
    exit 2
fi

missing=0
changed=0
checked=0
symbols_missing=0

while IFS= read -r line || [ -n "$line" ]; do
    # Split off the expected content before any stripping. The strip rules trim
    # trailing punctuation, which a code fragment may legitimately end in, so
    # they must not run over the fragment half. Splitting on the FIRST bar is
    # safe in both directions: a path or symbol never contains one, and the
    # fragment may contain as many as it likes.
    case "$line" in
        *"|"*)
            citation_part=${line%%|*}
            fragment=${line#*|}
            ;;
        *)
            citation_part=$line
            fragment=""
            ;;
    esac

    # The fragment gets whitespace and backticks removed and nothing else.
    fragment=$(printf '%s' "$fragment" \
        | sed -E -e 's/`//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    # Strip list markers, backticks, surrounding whitespace and wrapping
    # punctuation, then separate the trailing line reference.
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
    # macOS ships, and README.md lists macOS as a supported dev platform — the
    # rule does not fire and every line-referenced citation resolves MISSING.
    # CI runs GNU sed, so the suite stays green while the gate misfires on half
    # the team's laptops. sed -E is also what the repo's other scripts use.
    #
    # The port keeps that ordering exactly and only splits the last rule in two,
    # capturing the reference in a separate pass before removing it. Rearranging
    # anything above re-earns v2 or v3.
    cleaned=$(printf '%s' "$citation_part" \
        | sed -E -e 's/^[[:space:]]*[-*+][[:space:]]*//' \
              -e 's/`//g' \
              -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
              -e 's/^[([]*//' \
              -e 's/[.,;)]*$//')

    lineref=$(printf '%s' "$cleaned" | sed -nE 's/.*:([0-9]+([,-][0-9]+)*)$/\1/p')
    citation=$(printf '%s' "$cleaned" | sed -E 's/:[0-9]+([,-][0-9]+)*$//')

    [ -z "$citation" ] && continue
    case "$citation" in \#*) continue ;; esac

    checked=$((checked + 1))

    # Echo the citation as given, reference included, so a reader can see which
    # line was checked rather than trusting that one was.
    display=$citation
    [ -n "$lineref" ] && display="$citation:$lineref"

    if matches=$(resolve_path "$citation"); then
        resolved=$(printf '%s\n' "$matches" | head -1)
        target="$root/$resolved"

        if [ -d "$target" ]; then
            printf 'OK       %-58s → %s\n' "$display" "$resolved"
        elif ! is_text_file "$target"; then
            printf 'OK       %-58s → %s (not a text file; no line checked)\n' \
                "$display" "$resolved"
        elif [ -n "$lineref" ] \
            && [ "$(max_referenced_line "$lineref")" -gt "$(total_lines "$target")" ]; then
            printf 'CHANGED  %-58s → %s has %s lines; line %s does not exist\n' \
                "$display" "$resolved" "$(total_lines "$target")" \
                "$(max_referenced_line "$lineref")"
            changed=$((changed + 1))
        elif [ -z "$fragment" ]; then
            if [ -n "$lineref" ]; then
                printf 'OK       %-58s → %s (line %s exists; content not given)\n' \
                    "$display" "$resolved" "$lineref"
            else
                printf 'OK       %-58s → %s\n' "$display" "$resolved"
            fi
        elif [ -n "$lineref" ]; then
            if lines_contain "$target" "$fragment" "$lineref"; then
                printf 'OK       %-58s → %s:%s contains the cited content\n' \
                    "$display" "$resolved" "$lineref"
            else
                printf 'CHANGED  %-58s → %s:%s no longer contains: %s\n' \
                    "$display" "$resolved" "$lineref" "$fragment"
                changed=$((changed + 1))
            fi
        elif grep -qF -- "$fragment" "$target" 2>/dev/null; then
            printf 'OK       %-58s → %s contains the cited content\n' \
                "$display" "$resolved"
        else
            printf 'CHANGED  %-58s → %s no longer contains: %s\n' \
                "$display" "$resolved" "$fragment"
            changed=$((changed + 1))
        fi

        # Its own line, so a verdict stays the first field of its own line.
        printf '%s\n' "$matches" | tail -n +2 | while IFS= read -r alternative; do
            [ -n "$alternative" ] && printf '         %-58s   also resolves to %s\n' \
                "" "$alternative"
        done
    elif is_path_shaped "$citation"; then
        printf 'MISSING  %-58s → no such file or directory\n' "$display"
        missing=$((missing + 1))
    elif resolve_symbol "$citation"; then
        printf 'OK       %-58s → symbol found in source\n' "$display"
    else
        printf 'MISSING  %-58s → symbol not found in source\n' "$display"
        missing=$((missing + 1))
        symbols_missing=$((symbols_missing + 1))
    fi
done <<< "$input"

echo

# The one verdict the derived layout can be wrong about, so the one that shows
# its work — this line is what stops derivation failing silently.
if [ "$symbols_missing" -gt 0 ] && [ ${#search_roots[@]} -gt 0 ]; then
    printf 'symbol search roots:'
    for entry in "${search_roots[@]}"; do
        printf ' %s' "${entry#"$root"/}"
    done
    printf '\n'
fi

# Counts stay separate — "it moved" and "the claim may now be false" need
# different work — while the exit code stays binary, so no caller learns a new
# contract. CHANGED fails the gate: it is the row that reads as verified.
if [ "$missing" -gt 0 ]; then
    echo "$missing of $checked citations do not resolve."
fi
if [ "$changed" -gt 0 ]; then
    echo "$changed of $checked citations resolve but no longer say what they were cited for."
fi
if [ "$missing" -gt 0 ] || [ "$changed" -gt 0 ]; then
    exit 1
fi

echo "All $checked citations resolve."
