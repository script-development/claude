#!/usr/bin/env bash
#
# Tests for ci-failures.sh.
#
# Every case below is a regression. The script shipped a Windows bug that a
# fixture would have caught for free, and the fix for it introduced a second:
#
#   v1  On Windows, a native jq.exe emits CRLF. `read` splits on \n only, so the
#       CR rode along on the trailing field and every literal `case` branch
#       missed it. `failure` never matched, so failed_jobs stayed empty and the
#       failure logs — the entire point of the script — were never fetched,
#       while the run-level guard flipped green runs to FAILING, exit 1. Both
#       symptoms, one cause. CI never saw it: ubuntu's jq emits LF.
#   v2  The first fix piped both producers through `tr -d '\r'`. A process
#       substitution's exit status is never seen by the consuming `while read`,
#       so an unavailable `tr` fed both loops zero records and the script
#       reported GREEN, exit 0 — the same false-green, through a new door, and
#       this time on every platform rather than just Windows.
#
# Both directions are pinned. A missed failure is the expensive one: /shepard
# reads exit 0 as "done" and stops. But a false FAILING is not free either — it
# sends /shepard into a fix loop with nothing to fix.
#
# The fakes: `gh` answers only the calls this script makes, and `jq` is a stub
# that pattern-matches the filter and emits a canned TSV fixture, optionally
# CRLF-terminated. It does not parse JSON, so it cannot drift from real jq in a
# way that matters here — what is under test is how the script handles CRLF
# records, not how jq produces them. Coverage is deliberately scoped to
# `--run <id>`: the PR-resolution path reads through gh's built-in `--jq`, which
# is Go and emits LF, which is why it was never affected.
#
# No framework by design — the repo has no bats and no shell test harness, and
# CI runs plain scripts with `bash <path>`. Run it the same way:
#
#   bash ~/.claude/skills/shepard/scripts/ci-failures.test.sh

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/ci-failures.sh"

if [ ! -f "$subject" ]; then
    echo "ci-failures.sh not found at $subject" >&2
    exit 2
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
fixtures="$tmp/fixtures"
mkdir -p "$bin" "$fixtures"
export FIXTURES="$fixtures"

passed=0
failed=0

# ---------------------------------------------------------------- fake gh ---
cat > "$bin/gh" <<'SHIM'
#!/usr/bin/env bash
# Answers only the four gh calls ci-failures.sh makes. Run/job payloads are
# markers, not JSON: the fake jq below resolves them to fixtures.
if [[ "$1" == "run" && "$2" == "view" ]]; then
    if [[ "$3" == "--job" ]]; then
        [[ -f "$FIXTURES/joblog-$4.txt" ]] && cat "$FIXTURES/joblog-$4.txt"
        exit 0
    fi
    if [[ "$*" == *"--json jobs"* ]]; then
        echo "JOBS:$3"
    else
        echo "RUNS:$3"
    fi
    exit 0
fi
echo "fake gh: unhandled call: $*" >&2
exit 64
SHIM

# ---------------------------------------------------------------- fake jq ---
cat > "$bin/jq" <<'SHIM'
#!/usr/bin/env bash
# Resolves a marker on stdin to a TSV fixture. FAKE_JQ_CRLF=1 terminates every
# record with CRLF, reproducing a Windows-native jq.exe writing stdout in text
# mode. Emission is pure bash so this shim stays usable when the test
# deliberately breaks an external.
filter=""
for arg in "$@"; do
    [[ "$arg" == -* ]] || filter="$arg"
done
payload=$(cat)

case "$filter" in
    *@tsv*) ;;
    *) echo "fake jq: unhandled filter: $filter" >&2; exit 64 ;;
esac

case "$payload" in
    JOBS:*) src="$FIXTURES/jobs-${payload#JOBS:}.tsv" ;;
    RUNS:*) src="$FIXTURES/runs-${payload#RUNS:}.tsv" ;;
    *) echo "fake jq: unhandled payload: $payload" >&2; exit 64 ;;
esac

[[ -f "$src" ]] || exit 0
while IFS= read -r line; do
    if [[ "${FAKE_JQ_CRLF:-0}" == "1" ]]; then
        printf '%s\r\n' "$line"
    else
        printf '%s\n' "$line"
    fi
done < "$src"
SHIM

chmod +x "$bin/gh" "$bin/jq"

# --------------------------------------------------------------- fixtures ---
# Green run: two successes and a skip. Pre-fix this reported FAILING, exit 1.
printf '100\tCI\tcompleted\tsuccess\n' > "$fixtures/runs-100.tsv"
{
    printf '201\tbackend\tcompleted\tsuccess\n'
    printf '202\tfrontend\tcompleted\tsuccess\n'
    printf '203\tcli\tcompleted\tskipped\n'
} > "$fixtures/jobs-100.tsv"

# Failing run with one failed job. Pre-fix this reported GREEN, exit 0.
printf '200\tCI\tcompleted\tfailure\n' > "$fixtures/runs-200.tsv"
{
    printf '301\tbackend (PHP 8.4)\tcompleted\tfailure\n'
    printf '302\tfrontend\tcompleted\tsuccess\n'
} > "$fixtures/jobs-200.tsv"
printf 'backend (PHP 8.4)\tRun Pest\t2026-08-19T10:00:00.0Z FAILED  Tests\\Feature\\FeatureTestsTest\n' \
    > "$fixtures/joblog-301.txt"

# Run-level failure with zero jobs — startup_failure has no job to name.
printf '300\tCI\tcompleted\tstartup_failure\n' > "$fixtures/runs-300.tsv"
: > "$fixtures/jobs-300.tsv"

# Still running, nothing failed yet: the conclusion field is empty, so the CR
# is the whole field and must still land on the "" branch, not the wildcard.
printf '400\tCI\tin_progress\t\n' > "$fixtures/runs-400.tsv"
printf '401\tbackend\tin_progress\t\n' > "$fixtures/jobs-400.tsv"

# ---------------------------------------------------------------- harness ---
out=""
rc=0

# invoke <crlf> <run-id> [extra-path-dir]
invoke() {
    local crlf=$1 run_id=$2 extra=${3:-}
    out=$(FAKE_JQ_CRLF="$crlf" PATH="${extra:+$extra:}$bin:$PATH" \
        bash "$subject" --run "$run_id" 2>&1)
    rc=$?
}

check() {
    local ok=$1 description=$2 detail=${3:-}
    if [ "$ok" = "1" ]; then
        passed=$((passed + 1))
        printf '  ok    %s\n' "$description"
    else
        failed=$((failed + 1))
        printf '  FAIL  %s\n' "$description"
        [ -n "$detail" ] && printf '        %s\n' "$detail"
        printf '        --- output ---\n%s\n        --------------\n' "$out"
    fi
}

expect_rc() {
    local want=$1 description=$2
    [ "$rc" = "$want" ] && check 1 "$description" || check 0 "$description" "exit $rc, want $want"
}

expect_contains() {
    local needle=$1 description=$2
    case "$out" in
        *"$needle"*) check 1 "$description" ;;
        *) check 0 "$description" "missing: $needle" ;;
    esac
}

expect_absent() {
    local needle=$1 description=$2
    case "$out" in
        *"$needle"*) check 0 "$description" "unexpectedly present: $needle" ;;
        *) check 1 "$description" ;;
    esac
}

# ------------------------------------------------------------------ cases ---
for mode in CRLF LF; do
    [ "$mode" = "CRLF" ] && crlf=1 || crlf=0
    echo
    echo "$mode records (jq on $([ "$crlf" = 1 ] && echo Windows || echo Linux))"

    invoke "$crlf" 100
    expect_rc 0 "green run exits 0"
    expect_contains "Status: GREEN" "green run reports GREEN"
    expect_contains "  ok    backend" "success renders as ok, not via the wildcard"
    expect_contains "  skip  cli" "skipped renders as skip, not via the wildcard"

    invoke "$crlf" 200
    expect_rc 1 "failing run exits 1"
    expect_contains "  FAIL  backend (PHP 8.4)" "the failed job is classified"
    expect_contains "FAILURE LOGS" "the failure log block is emitted"
    expect_contains "FAILED  Tests" "the failed step's log is actually fetched"
    expect_absent "<job-id>" "the footer names real job ids, not a placeholder"
    expect_contains "gh run view --job 301 --log-failed" "the footer command is executable as printed"

    invoke "$crlf" 300
    expect_rc 1 "run-level failure with no failed jobs exits 1"
    expect_contains "<job-id>" "no collected jobs falls back to the generic footer"

    invoke "$crlf" 400
    expect_rc 2 "in-progress run exits 2"
    expect_contains "Status: RUNNING" "in-progress reports RUNNING"
    expect_contains "...   backend (in_progress)" "an empty conclusion is pending, not a wildcard"
done

# The v2 regression, pinned by behaviour rather than by grepping the source: an
# external that cannot launch must not be able to empty the classification
# loops. A stub that exits 127 stands in for a missing binary.
echo
echo "Classification survives a broken external"
broken="$tmp/broken"
mkdir -p "$broken"
printf '#!/usr/bin/env bash\nexit 127\n' > "$broken/tr"
chmod +x "$broken/tr"

invoke 1 200 "$broken"
expect_rc 1 "a failing run is still FAILING when tr cannot launch"
expect_contains "  FAIL  backend (PHP 8.4)" "the failed job is still classified"

invoke 1 100 "$broken"
expect_rc 0 "a green run is still GREEN when tr cannot launch"

# ---------------------------------------------------------------- summary ---
echo
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ] || exit 1
