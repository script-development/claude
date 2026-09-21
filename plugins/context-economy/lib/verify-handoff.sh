#!/usr/bin/env bash
#
# Check a handoff file against the format contract, then hand its citation block
# to verify-citations.sh.
#
# Usage:
#   verify-handoff.sh <handoff-file> [checkout-dir]
#
# `checkout-dir` is the working tree the citations should resolve against — the
# checkout holding the branch the handoff was written on. The tool always prints
# which one it used together with that checkout's HEAD, because a handoff no
# longer lives anywhere near the tree it describes: it sits in a machine-local
# store outside every repository, and its citations belong to a branch checked
# out somewhere else entirely (see skills/handoff/SKILL.md, "Where the file
# goes").
#
# Resolution order, and the order matters:
#
#   1. `checkout-dir`, when given. An explicit argument always wins — verifying a
#      handoff against a different tree (a second checkout, the merged default
#      branch) is a legitimate thing to ask for.
#   2. the handoff's own `checkout:` header field. This is the normal path.
#   3. $PWD's git root. The last resort, and the one that used to be the default.
#
# $PWD is last for the reason the header field exists at all. Once the document
# stopped living inside the tree it describes, a cwd-derived checkout stopped
# being a reasonable guess and became a confident wrong answer: a caller in an
# orchestrating checkout, verifying a handoff about a sibling one, would resolve
# every citation against the orchestrator and report a page of MISSING verdicts
# indistinguishable from real rot. The document has to say which tree it means.
#
#   0  structure holds, every cited pointer is listed, every citation resolves
#   1  gate failure — a citation is MISSING/CHANGED, or a cited pointer is
#      absent from the Pointers block and so was never checked
#   2  contract violation — unreadable file, a required section absent, a
#      `path:symbol` anchor, or no Pointers fence
#
# Exit 2 is verify-citations.sh's own convention and is here for its reason: a
# malformed handoff and a rotted citation need different work from different
# people, so they must not share a verdict. Everything the tool only *reports* —
# size, an unbackticked citation, a Pointers line nothing refers to — is printed
# as WARN and cannot change the exit code. Which side of that line a check sits
# on is argued at each check below; it is the only design question in this file.
#
# Companion to verify-citations.sh, deliberately a separate script: that one
# checks whether a citation is true, this one checks whether the document put its
# citations somewhere the first script will actually see. Merging them would give
# the citation resolver a second job and a markdown parser, and O8 in
# docs/design.md is the record of what happens
# when a resolver is fed a document.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
verifier="$script_dir/verify-citations.sh"

# Sourced, never restated — same rule as lib/context-gauge.sh. Resolved
# relative to this script rather than through ~/.claude/lib/ because this tool
# lives in the same repo as the thresholds; the statusline needs the symlink only
# because it does not.
thresholds="${CTX_THRESHOLDS_FILE:-$script_dir/context-economy/context-thresholds.sh}"

usage() {
    sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
    "" | -h | --help) usage; exit 2 ;;
esac

handoff=$1
checkout_arg=${2:-}

[ -r "$handoff" ] || { echo "verify-handoff: cannot read $handoff" >&2; exit 2; }
[ -x "$verifier" ] || { echo "verify-handoff: verify-citations.sh not found at $verifier" >&2; exit 2; }

# CR is stripped once, here. verify-citations.sh survives CRLF by accident — its
# trailing-whitespace rule eats the CR, since CR is [[:space:]] — but this script
# anchors on whole lines (`^## Pointers$`), and there the CR is fatal rather than
# harmless: every required section reports absent on a file written by a Windows
# editor. Checked, not assumed: printf '%s\r\n' through verify-citations.sh does
# resolve.
content=$(tr -d '\r' < "$handoff")

# Resolved here, from `content`, because the header is the normal source and the
# argument is the override — see the resolution order at the top of this file.
# `~` is expanded by hand: the field is read out of a file, never through a shell,
# so a handoff that wrote `~/checkouts/emmie` would otherwise be handed to git as
# a literal directory named `~`.
declared_checkout=$(grep -m1 -E '^checkout:' <<< "$content" | sed -E 's/^checkout:[[:space:]]*//' | sed -E 's/[[:space:]]+$//')
case "$declared_checkout" in
    "~") declared_checkout=$HOME ;;
    "~/"*) declared_checkout=$HOME/${declared_checkout#\~/} ;;
esac
checkout=${checkout_arg:-${declared_checkout:-$PWD}}

errors=0     # -> exit 2
failures=0   # -> exit 1

fail_contract() { printf 'ERROR    %s\n' "$1" >&2; errors=$((errors + 1)); }
fail_gate()     { printf 'FAIL     %s\n' "$1"; failures=$((failures + 1)); }
warn()          { printf 'WARN     %s\n' "$1"; }

# --- Zones -----------------------------------------------------------------
#
# Three of them, and the split is what keeps this script off O8's rake. The
# Pointers fence is a citation list; everything else is prose. A check that ran
# over both would either report prose as a broken citation or exempt a real
# citation from the gate.
#
# `## Unverifiable` and `## Next` are both excluded from the prose zone, for the
# same reason arrived at from two directions: neither section makes claims about
# the tree as it stands.
#
# Unverifiable is cross-repo by definition (O6) — real files the resolver cannot
# see, declared unchecked on purpose. Counting them as body citations would demand
# they be listed in Pointers, where they would resolve MISSING, manufacturing
# exactly the false positive the section exists to avoid.
#
# Next names files the resumed session is about to CREATE. Found by running this
# script on the first real handoff: `skills/handoff/SKILL.md` in a numbered plan
# was demanded as evidence and would have resolved MISSING, because the whole
# point of listing it is that it does not exist yet. A plan is not a claim.

pointers_block() {
    awk '
        BEGIN { state = 0 }
        state == 0 && /^##[[:space:]]+Pointers[[:space:]]*$/ { state = 1; next }
        state == 1 && /^```/ { state = 2; next }
        state == 2 && /^```/ { state = 3; next }
        state == 2 { print }
    ' <<< "$content"
}

# Reported separately from the block's contents so that "no fence" (a contract
# violation) never reads as "no citations" (legitimate — a task can rest on
# nothing citable).
pointers_state() {
    awk '
        BEGIN { state = 0 }
        state == 0 && /^##[[:space:]]+Pointers[[:space:]]*$/ { state = 1; next }
        state == 1 && /^```/ { state = 2; next }
        state == 2 && /^```/ { state = 3; next }
        END { print state }
    ' <<< "$content"
}

prose_body() {
    awk '
        BEGIN { z = "body" }
        /^##[[:space:]]+Pointers[[:space:]]*$/ { z = "pre"; next }
        z == "pre" && /^```/ { z = "ptr"; next }
        z == "ptr" && /^```/ { z = "body"; next }
        z == "ptr" { next }
        /^##[[:space:]]/ {
            z = ($0 ~ /^##[[:space:]]+(Unverifiable|Next)/) ? "skip" : "body"; next
        }
        z == "skip" { next }
        { print }
    ' <<< "$content"
}

# Everything except the Pointers fence. NOT the same zone as prose_body(), and the
# difference is load-bearing in one direction only.
#
# prose_body() excludes `## Next` and `## Unverifiable` because neither makes a
# claim about the tree, so neither should be able to demand a Pointers entry. But
# "is this pointer dead weight" is the opposite question: a pointer the plan refers
# to is not dead weight, and answering it from prose_body() warns that
# `tools/verify-handoff.sh` is unreferenced while `## Next` refers to it twice.
#
# Found on the first real handoff, immediately after the v3 fix that introduced the
# exclusion. Worth its own extractor rather than a shared one: a warning that is
# wrong is worse than a warning that is missing, because it is the whole reason
# anyone stops reading warnings.
referring_text() {
    awk '
        BEGIN { z = "text" }
        /^##[[:space:]]+Pointers[[:space:]]*$/ { z = "pre"; next }
        z == "pre" && /^```/ { z = "ptr"; next }
        z == "ptr" && /^```/ { z = "text"; next }
        z == "ptr" { next }
        { print }
    ' <<< "$content"
}

# Lines of one section, up to the next heading of any level. Used for the
# is-it-empty checks; "None." is a legitimate body and passes deliberately.
section_body() {
    awk -v want="$1" '
        $0 ~ want { inside = 1; next }
        inside && /^#/ { inside = 0 }
        inside { print }
    ' <<< "$content"
}

has_heading() { grep -qE "$1" <<< "$content"; }

# --- Structure -------------------------------------------------------------
#
# Required, and required to be non-empty. The empty check is the point: an
# absent section cannot be distinguished from a run that never looked, and the
# three subsections under "Do not re-derive" are
# exactly the content D6 says a summariser drops. "None." is a real answer and
# passes; silence is not an answer and does not.

require_section() {
    local pattern=$1 label=$2
    if ! has_heading "$pattern"; then
        fail_contract "required section missing: $label"
        return
    fi
    if [ -z "$(section_body "$pattern" | tr -d '[:space:]')" ]; then
        fail_contract "section is empty: $label — write \"None.\" if that is the answer, so a reader can tell it was considered"
    fi
}

grep -qE '^#[[:space:]]+Handoff' <<< "$content" \
    || fail_contract 'first heading is not "# Handoff — <task>"'
grep -qE '^branch:' <<< "$content" || fail_contract 'header field missing: branch:'
grep -qE '^status:' <<< "$content" || fail_contract 'header field missing: status:'

# Gated: `checkout:` says which tree the cheap half even refers to. Once the
# document stopped living inside that tree, nothing else in the file identifies
# it: `branch:` names a ref, and the same ref name exists in every sibling
# checkout on this machine. Omitted, the tool falls back to $PWD and reports
# verdicts about whichever repository the caller happened to be standing in — a
# full page of MISSING that looks exactly like citation rot. That is the one
# failure this whole script exists to prevent, so the field is required rather
# than defaulted.
grep -qE '^checkout:' <<< "$content"      || fail_contract 'header field missing: checkout: (absolute path of the tree the citations resolve against)'

# Heading only: this one is a container, and its body is the three subsections
# below. Requiring text of its own would fail every correctly-formed handoff --
# the first thing after the heading is `### Decisions`, which ends the section.
has_heading '^##[[:space:]]+Do not re-derive'     || fail_contract 'required section missing: Do not re-derive'

require_section '^###[[:space:]]+Decisions'       'Decisions'
require_section '^###[[:space:]]+Dead ends'       'Dead ends'
require_section '^###[[:space:]]+Traps'           'Traps'
require_section '^##[[:space:]]+Next'             'Next'

state=$(pointers_state)
case "$state" in
    0) fail_contract 'required section missing: Pointers' ;;
    1) fail_contract 'Pointers section has no ``` fence — an unfenced list is prose to every tool that reads it' ;;
    2) fail_contract 'Pointers fence is never closed' ;;
esac

# --- The `path:symbol` guard (O7) ------------------------------------------
#
# `tools/context-audit.js:simulate` reports MISSING on a real file: the resolver's
# trailing-reference rule matches digits only, so a non-numeric anchor stays glued
# to the path. Inherited from Kendo's copy, and left unfixed there because D4 fixed
# the port's scope at three changes.
#
# It is refused here rather than fixed there, and refusing is the better answer
# anyway, not merely the cheaper one: `Foo.php:24 | someMethod` verifies that line
# 24 still holds the symbol, where `Foo.php:someMethod` could at best confirm the
# file exists. The format gives up nothing by banning the weaker form.
#
# Exit 2, not 1 — the citation may well be true; the document asked the wrong
# question. Reporting it as a gate failure would send the author hunting for rot
# that is not there.
while IFS= read -r line; do
    left=${line%%|*}
    left=$(printf '%s' "$left" | sed -E -e 's/`//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$left" ] && continue
    case "$left" in "#"*) continue ;; esac
    if [[ $left =~ ^[^[:space:]]*[./][^[:space:]]*:[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        fail_contract "path:symbol anchor is a known false MISSING (O7): $left — cite the line instead, as \`path:line | $(printf '%s' "${left##*:}")\`"
    fi
done < <(pointers_block)

# --- Coverage --------------------------------------------------------------
#
# A pointer cited in the prose but absent from the Pointers block is never seen by
# the gate, and reads as verified precisely because the rest of the document was.
# That is D5's row 3 one level up, so it fails (exit 1) rather than warning.
#
# Two tiers, because "cited" is not one thing. EVIDENCE carries a numeric line
# reference — that is what someone writes when pointing at a specific fact, and it
# is the shape D6's whole model is about (`AuditTest.php:756`). A bare path is a
# MENTION: usually a reference or a plan, occasionally evidence. So evidence must
# be covered (fail) and a mention is only reported (warn).
#
# The first version of this check treated any backticked token containing `/` as
# evidence. Running it on the first real handoff produced eight failures, every one
# of them wrong -- `/clear`, `/compact`, `/handoff` (slash commands), `~/.claude/lib/`
# (not repo-relative), `(T + H)/2` (arithmetic), `/` on its own, and two paths the
# plan was proposing to create. That is v3 in the test suite, and it is the same
# error class as everything else in this file: a false refusal in a fail-closed
# gate, which teaches the author the gate is wrong and can be skipped.
#
# Hence the exclusions, each for its own reason:
#   `[<>]`        template paths -- per O6 not citations at all, and keeping them
#                 out is this script's job rather than the resolver's
#   `$`           a shell expression, not a literal path: `$HOME/.claude/lib/x.sh`
#                 cannot resolve as written, so warning that it is unchecked tells
#                 the author nothing they can act on. Excluded ANYWHERE in the
#                 token rather than anchored, unlike the two below -- a `$` at any
#                 position means the token is expanded before it is a path, while a
#                 `/` or `~` mid-token is perfectly ordinary. v5.
#   `^[/~]`       a slash command or a home-relative path; a repo-relative
#                 citation never starts with either
#   whitespace    prose and arithmetic, never a path
#   `[+()=]`      arithmetic and calls; no path in this corpus contains them
#
# What remains uncovered on purpose: a bare-path evidence claim escapes the fail
# tier and gets a warn. Accepted deliberately -- the alternative is refusing
# handoffs over `README.md` and over files a plan has not written yet.
path_like() {
    grep -vE '[<>$[:space:]+()=]' | grep -vE '^[/~]' | sed -E 's/[.,;)]+$//'
}

backticked() {
    grep -oE '`[^`]+`' <<< "$(prose_body)" | tr -d '`'
}

# Evidence: a line reference. Coverage failures come only from here.
cited_pointers() {
    backticked | path_like | grep -E ':[0-9]+([,-][0-9]+)*$' | sort -u
}

# Mentions: path-shaped, no line reference. Reported, never fatal.
mentioned_pointers() {
    backticked | path_like | grep -E '/' | grep -vE ':[0-9]+([,-][0-9]+)*$' | sort -u
}

listed_pointers() {
    pointers_block \
        | sed -E -e 's/\|.*//' -e 's/`//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | grep -v '^#' | grep -v '^$' \
        | sort -u
}

cited=$(cited_pointers)
listed=$(listed_pointers)

if [ -n "$cited" ]; then
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        grep -qxF "$entry" <<< "$listed" \
            || fail_gate "cited in prose but not in Pointers, so never checked: $entry"
    done <<< "$cited"
fi

# A path-shaped mention with no line reference: report it, never fail. This is the
# tier that catches a real bare-path evidence claim without being able to refuse a
# handoff for naming README.md.
mentioned=$(mentioned_pointers)
if [ -n "$mentioned" ]; then
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        grep -qxF "$entry" <<< "$listed" \
            || warn "mentioned in prose but not in Pointers, so unchecked: $entry"
    done <<< "$mentioned"
fi

# The other direction is dead weight, not risk: a listed pointer nothing refers to
# costs tokens in a document whose whole purpose is to be small. Warn.
#
# Two deliberate loosenings, both because this direction is advisory and a false
# warning costs more here than a missed one:
#   - the whole document is searched, not prose_body() -- see referring_text()
#   - substring, not set membership, since a pointer can be referred to in a form
#     neither extractor produces (inside a longer backticked span, or with its line
#     reference written differently)
prose=$(referring_text)
if [ -n "$listed" ]; then
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        grep -qF "$entry" <<< "$prose" \
            || warn "in Pointers but nothing in the prose refers to it: $entry"
    done <<< "$listed"
fi

# A citation-shaped token outside backticks is invisible to the coverage check, so
# say so. Warn, not fail: the coverage rule is already the strict half, and a
# false refusal here would cost more than the unchecked claim it prevents.
while IFS= read -r stray; do
    [ -z "$stray" ] && continue
    grep -qxF "$stray" <<< "$cited" && continue
    warn "looks like a citation but is not backticked, so it is not checked: $stray"
done < <(prose_body | sed 's/`[^`]*`//g' \
    | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+([,-][0-9]+)*' | sort -u)

# --- Size ------------------------------------------------------------------
#
# Advisory, always. It cannot fail the gate, because a size gate makes cutting the
# non-citable half the cheapest way to pass — the exact inversion D6 exists to
# prevent. When over budget, the line to cut is a Pointer: those re-derive from
# the tree, and a decision does not re-derive at all.
#
# Denominated in turns because that is what a handoff actually spends. With the
# reset threshold fixed, a bigger handoff does not add a one-off cost; it buys
# fewer turns of work for the same money.
if [ -f "$thresholds" ]; then
    # shellcheck source=context-economy/context-thresholds.sh
    . "$thresholds"
fi

if [ -n "${CTX_CHARS_PER_TOKEN_X100:-}" ] && [ -n "${CTX_GROWTH_TOKENS_PER_TURN:-}" ]; then
    chars=$(printf '%s' "$content" | wc -c | tr -d ' ')
    tokens=$((chars * 100 / CTX_CHARS_PER_TOKEN_X100))
    turns_tenths=$((tokens * 10 / CTX_GROWTH_TOKENS_PER_TURN))
    printf 'size     %s chars ≈ %s tokens ≈ %s.%s turns of work\n' \
        "$chars" "$tokens" "$((turns_tenths / 10))" "$((turns_tenths % 10))"
    if [ -n "${HANDOFF_CEILING_TOKENS:-}" ] && [ "$tokens" -gt "$HANDOFF_CEILING_TOKENS" ]; then
        warn "over the ceiling of $HANDOFF_CEILING_TOKENS tokens by $((tokens - HANDOFF_CEILING_TOKENS)) — cut Pointers, never a decision, and say in the handoff why it had to be this long"
    elif [ -n "${HANDOFF_TARGET_TOKENS:-}" ] && [ "$tokens" -gt "$HANDOFF_TARGET_TOKENS" ]; then
        warn "over the target of $HANDOFF_TARGET_TOKENS tokens by $((tokens - HANDOFF_TARGET_TOKENS)) — cut Pointers, never a decision"
    fi
else
    # Degrade capability, never execution: no thresholds file means no size
    # report, and never a guessed default. A local fallback would be the second
    # copy the thresholds file exists to prevent.
    warn "no thresholds file at $thresholds — size not reported; citation checks are unaffected"
fi

# --- Which checkout, and is it the right one -------------------------------
#
# Reported unconditionally, and it is not bookkeeping: the handoff lives in the
# main working tree while its citations belong to a branch checked out elsewhere,
# so resolving them against the wrong tree produces MISSING and CHANGED verdicts
# that look exactly like rot. A mismatch warns rather than fails — verifying a
# handoff against a merged default branch is a legitimate thing to do, and it is
# the reader's call, not this script's.
checkout_root=$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null) || {
    echo "verify-handoff: $checkout is not inside a git repository" >&2
    exit 2
}
checkout_head=$(git -C "$checkout_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
declared=$(grep -m1 -E '^branch:' <<< "$content" | sed -E 's/^branch:[[:space:]]*//' | awk '{print $1}')

# WHERE the checkout came from is printed beside it, not just which one it is. All
# three sources produce the same shape of line, and a reader who cannot tell an
# argument from a header from a cwd guess cannot tell a deliberate cross-tree
# verification from the accident this field was added to stop.
if [ -n "$checkout_arg" ]; then
    if [ -n "$declared_checkout" ] && [ "$checkout_arg" != "$declared_checkout" ]; then
        origin="from argument, OVERRIDING checkout: $declared_checkout"
    else
        origin="from argument"
    fi
elif [ -n "$declared_checkout" ]; then
    origin="from checkout: header"
else
    origin="from \$PWD — the handoff declares no checkout:"
fi

printf 'checkout %s (HEAD %s) [%s]\n' "$checkout_root" "$checkout_head" "$origin"
if [ -n "$declared" ] && [ "$declared" != "$checkout_head" ]; then
    warn "handoff declares branch $declared but this checkout is on $checkout_head — citations resolve against $checkout_head"
fi

# Contract violations stop here. Running the resolver on a document whose shape is
# already known to be wrong is how O8 happened: the output would be shape-identical
# to citation rot and read that way.
if [ "$errors" -gt 0 ]; then
    echo
    echo "$errors contract violation(s); citations were not checked."
    exit 2
fi

# --- The gate --------------------------------------------------------------
echo
if [ -z "$(printf '%s' "$listed" | tr -d '[:space:]')" ]; then
    echo "no citations to check (Pointers is empty)"
else
    (cd "$checkout_root" && pointers_block | "$verifier")
    verdict=$?
    # 2 is propagated rather than folded into 1. The resolver only exits 2 when
    # its input is not a citation list -- which, reached from here, means this
    # script handed it something malformed, and that is a defect in the Pointers
    # extraction above, not citation rot for the author to chase.
    case "$verdict" in
        0) ;;
        2) exit 2 ;;
        *) failures=$((failures + 1)) ;;
    esac
fi

if [ "$failures" -gt 0 ]; then
    exit 1
fi
