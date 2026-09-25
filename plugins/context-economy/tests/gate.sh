#!/usr/bin/env bash
#
# The structural gate for this bundle's own test suites.
#
# This is the analogue of Kendo's tests/Arch/FeatureTestsTest.php, re-derived rather than ported.
# That file enforces nine conventions on PHP feature tests through Pest `arch()`, and none of its
# mechanism survives the trip to a bundle made of bash. What survives is the IDEA -- that the shape
# of a test suite is worth enforcing mechanically, because a convention nobody checks is one that
# drifts -- plus exactly one of its nine rules, which generalises (g1).
#
# WHY A GATE RATHER THAN A NOTE IN A README. Every failure caught here is SILENT. A suite that stops
# matching the glob does not error, it stops being run. A suite whose subject was renamed still
# passes, against nothing. A suite that aborts on a missing dependency without printing a reason is
# indistinguishable from one that passed. In every case a green run stays green while the coverage
# quietly leaves. That is the same class of failure as planning from a stale baseline file, and it
# is why every check below prints a line on every path -- PASS, FAIL, or SKIP with the cause that
# actually applies -- so "nothing was reported" can never read as "everything passed".
#
#   g1  DISCOVERY IS NON-EMPTY. The one rule taken in substance from Kendo's file, whose every
#       check opens with `expect($files)->not->toBeEmpty('No feature test files found')`. Zero
#       suites is the most dangerous possible result: every per-suite check below then passes
#       vacuously and the gate reports success having verified nothing.
#   g2  Suites are DISCOVERED, never listed. Found by the `*.test.sh` marker, because a manifest
#       naming where tests live is a snapshot of a past layout -- it goes stale, it carries
#       absolute paths, and it fails silently. install.sh already paid for that lesson with five
#       committed symlink stubs; this file does not repeat it.
#   g3  Every suite PARSES. Cheap, and it catches the suite broken badly enough that running it
#       aborts before its first assertion -- which prints little and exits nonzero, and so reads
#       like an ordinary test failure.
#   g4  Every suite has a SUBJECT beside it. `X.test.sh` requires `X.sh`. A suite whose subject
#       moved out from under it still runs, still passes, and tests nothing.
#   g5  Every suite carries AAA LABELS -- the convention Kendo and Emmie both practise:
#       `# Arrange` / `# Act` / `# Assert`, combined where one statement covers two sections.
#       Note the regex: it ACCEPTS the combined forms. Kendo's does not, which is why its own
#       `// Act & Assert` (250 occurrences, 234 of them under tests/Unit) satisfies its $hasAct
#       check and fails its $hasAssert one. That defect is logged in mission_control's
#       upstream-feedback/kendo.md (2026-08-28); this gate ships with the fix, not the bug.
#   g6  Every case has a NON-EMPTY LABEL. An assertion labelled '' reports as `ok` followed by
#       nothing, which is unreadable in a passing run and useless in a failing one.
#   g7  Every suite prints a FINAL TALLY. The anti-silence rule turned on the suites themselves: a
#       run that emits no summary cannot be told apart from a run that did nothing.
#
# Run it as:
#
#   bash tests/gate.sh                 # structure only, over this bundle
#   bash tests/gate.sh --run           # structure, then execute every discovered suite
#   bash tests/gate.sh --root DIR      # the same checks, over a different tree
#
# WHY --root EXISTS. mission_control's personal/ side has suites too (statusline.test.sh,
# compaction-capture.test.sh) and they deserve the same shape checks. The alternative was a second
# copy of this file over there, and two copies of one gate in one repo drift -- which is the exact
# failure the g2 comment describes install.sh already paying for. So the tree is a parameter and
# there is one implementation. personal/tests/gate.sh is a delegation to this file, not a fork.
#
# The default is unchanged and must stay that way: this bundle ships as its own repository, where
# `bash tests/gate.sh` with no arguments is the only invocation that exists. --root is additive.

set -uo pipefail

run_suites=0
root=""

while [ $# -gt 0 ]; do
    case "$1" in
        --run)
            run_suites=1
            shift
            ;;
        --root)
            # Fail loudly on a missing or bad tree. A gate that quietly gates nothing is the
            # failure mode this whole file exists to prevent, and --root is the one input that
            # can point it at a directory that is not there.
            if [ -z "${2:-}" ]; then
                printf 'FAIL  --root given with no directory\n' >&2
                exit 2
            fi
            if [ ! -d "$2" ]; then
                printf 'FAIL  --root %s is not a directory\n' "$2" >&2
                exit 2
            fi
            root=$(cd "$2" && pwd)
            shift 2
            ;;
        *)
            printf 'FAIL  unknown argument: %s\n' "$1" >&2
            printf '      usage: gate.sh [--root DIR] [--run]\n' >&2
            exit 2
            ;;
    esac
done

[ -n "$root" ] || root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }
skip() { printf 'SKIP  %s\n      cause: %s\n' "$1" "$2"; }

# --- g1 + g2 -- discover, and refuse an empty discovery ---------------------
#
# `find` rather than a shell glob, so a nested suite is reached: lib/context-economy/ holds one.
# Sorted, so the report reads identically on every machine and under every shell.
suites=$(find "$root" -name '*.test.sh' -type f | sed "s|^$root/||" | sort)

if [ -z "$suites" ]; then
    printf 'FAIL  g1 discovery\n'
    printf '      no *.test.sh found under %s. Every check below would have passed\n' "$root"
    printf '      vacuously, so an empty discovery is a failure and not an empty run.\n'
    exit 1
fi

n=$(printf '%s\n' "$suites" | grep -c .)
ok "g1 discovery -- $n suites found"

# Name the tree, always. Now that --root exists, every verdict below is relative to a tree the
# reader cannot see from the output otherwise -- and a clean run over the WRONG tree reads exactly
# like a clean run over the right one. verify-handoff.sh prints its checkout for the same reason.
printf '      root: %s\n' "$root"

# --- Per-suite structure ---------------------------------------------------

# The two AAA patterns. The leading group is the part Kendo's regex lacks: it allows any number of
# other section names to precede the one being matched, so `# Act & Assert` counts as an Assert
# label and `# Arrange & Act & Assert` counts as all three. Separators &, + and / are all in use
# across the two reference projects, so all three are accepted here.
arrange_re='^[[:space:]]*#[[:space:]]*([A-Za-z]+[[:space:]]*[&+/][[:space:]]*)*Arrange\b'
assert_re='^[[:space:]]*#[[:space:]]*([A-Za-z]+[[:space:]]*[&+/][[:space:]]*)*Assert\b'

while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    f="$root/$rel"

    if bash -n "$f" 2>/dev/null; then
        ok "g3 parses         $rel"
    else
        bad "g3 parses         $rel" "bash -n rejected it; it would abort before its first assertion"
    fi

    subject="${f%.test.sh}.sh"
    if [ -r "$subject" ]; then
        ok "g4 subject        $rel"
    else
        bad "g4 subject        $rel" "no subject at ${subject#$root/} -- a suite whose subject moved still passes, against nothing"
    fi

    n_arrange=$(grep -cE "$arrange_re" "$f")
    n_assert=$(grep -cE "$assert_re" "$f")
    if [ "$n_arrange" -gt 0 ] && [ "$n_assert" -gt 0 ]; then
        ok "g5 AAA labels     $rel  ($n_arrange arrange, $n_assert assert)"
    else
        missing=""
        if [ "$n_arrange" -eq 0 ]; then missing="Arrange"; fi
        if [ "$n_assert" -eq 0 ]; then
            if [ -n "$missing" ]; then missing="$missing or Assert"; else missing="Assert"; fi
        fi
        bad "g5 AAA labels     $rel" "carries no $missing label; combined forms such as '# Act & Assert' count"
    fi

    empty_labels=$(grep -cE "^[[:space:]]*(assert|pass|fail)[A-Za-z_]*[[:space:]]+(''|\"\")" "$f")
    if [ "$empty_labels" -eq 0 ]; then
        ok "g6 case labels    $rel"
    else
        bad "g6 case labels    $rel" "$empty_labels assertion(s) carry an empty label"
    fi

    if grep -qE '(passed|OK:|[0-9]+ of [0-9]+)' "$f"; then
        ok "g7 final tally    $rel"
    else
        bad "g7 final tally    $rel" "no summary line; a silent run cannot be told from a run that did nothing"
    fi
done <<< "$suites"

# --- Optional: actually run them -------------------------------------------
#
# Off by default. The structural checks above are fast and need nothing installed; the suites
# themselves need jq or git. A machine without those must be able to run this gate and be TOLD what
# it could not run, rather than shown a failure that is really about the machine.
#
# The dependency check is scoped per suite rather than applied as a blanket skip, because only the
# suites that parse a JSON payload or build a git fixture need those binaries -- a blanket skip
# would silently give up the ones that do not. A skip naming a cause that does not apply is a small
# lie that costs a real signal.
if [ "$run_suites" = 1 ]; then
    echo
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        f="$root/$rel"

        needs=""
        if grep -q 'jq ' "$f"; then needs="jq"; fi
        if grep -q 'git ' "$f"; then needs="${needs:+$needs }git"; fi

        unmet=""
        for dep in $needs; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                unmet="${unmet:+$unmet and }$dep"
            fi
        done

        if [ -n "$unmet" ]; then
            skip "run               $rel" "$unmet not installed, and this suite uses it"
        elif bash "$f" >/dev/null 2>&1; then
            ok "run               $rel"
        else
            bad "run               $rel" "the suite exited nonzero; run it directly for the detail"
        fi
    done <<< "$suites"
fi

echo
if [ "$fail" -gt 0 ]; then
    echo "FAILED: $fail of $((pass + fail)) checks"
    exit 1
fi

echo "OK: all $pass checks passed"
