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
# records, not how jq produces them. The CRLF cases enter through `--run <id>`:
# the PR-resolution path reads through gh's built-in `--jq`, which is Go and
# emits LF, so CRLF never reached it. That path has its own block at the end,
# run against real jq with a gh fake that serves JSON.
#
# No framework by design — the repo has no bats and no shell test harness, and
# CI runs plain scripts with `bash <path>`. Run it the same way:
#
#   bash <skill dir>/scripts/ci-failures.test.sh

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
        [[ -f "$FIXTURES/jobs-$3.unreadable" ]] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
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

# A path-filtered workflow completes with conclusion `skipped` and no failed job.
# It is not a failure: two workers misread the status line on 2026-09-08 because
# the wildcard swallowed it.
printf '500\tPR Comment\tcompleted\tskipped\n' > "$fixtures/runs-500.tsv"
printf '501\tannounce\tcompleted\tskipped\n' > "$fixtures/jobs-500.tsv"

# gh could not read the job list. The run concluded success, but without the
# per-job list nobody can see which lanes ran, so this must not read GREEN.
printf '600\tCI\tcompleted\tsuccess\n' > "$fixtures/runs-600.tsv"
: > "$fixtures/jobs-600.unreadable"

# The same on a failed run: the run conclusion still makes it FAILING.
printf '610\tCI\tcompleted\tfailure\n' > "$fixtures/runs-610.tsv"
: > "$fixtures/jobs-610.unreadable"

# A timed-out job while another job still runs: the run has no conclusion yet
# to fall back on, so the job itself must count as failed.
printf '700\tCI\tin_progress\t\n' > "$fixtures/runs-700.tsv"
{
    printf '701\tbackend\tcompleted\ttimed_out\n'
    printf '702\tfrontend\tin_progress\t\n'
} > "$fixtures/jobs-700.tsv"

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
    if [ "$rc" = "$want" ]; then check 1 "$description"; else check 0 "$description" "exit $rc, want $want"; fi
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

    invoke "$crlf" 500
    expect_rc 0 "a skipped run is not a failure"
    expect_contains "Status: GREEN" "a path-filtered workflow reports GREEN"
    expect_contains "  skip  announce" "the skipped job is classified as skipped"

    invoke "$crlf" 600
    expect_rc 3 "an unreadable job list exits 3"
    expect_contains "job list unreadable" "the unreadable job list is said out loud"
    expect_absent "Status: GREEN" "an unreadable job list is never GREEN"

    invoke "$crlf" 610
    expect_rc 1 "a failed run with an unreadable job list is still FAILING"

    invoke "$crlf" 700
    expect_rc 1 "a timed-out job fails the run while another job still runs"
    expect_contains "  TIME  backend" "the timed-out job is classified, not left to the wildcard"
    expect_contains "gh run view --job 701 --log-failed" "the timed-out job's log is named"
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

# A usage error is not a failed job: exit 1 would send /shepard into a fix loop.
echo
echo "Arguments"
invoke 0 ""
expect_rc 3 "--run without an id exits 3, not the failed-job code"
expect_contains "--run needs a run id" "the missing id is named"

# ---------------------------------------------------- default PR path ---
# Everything above enters through `--run <id>`. The normal invocation resolves
# a PR, reads its head SHA and lists every run on that SHA, so it runs here
# against real jq, with a gh fake that serves JSON and applies `--jq` as gh does.
json_bin="$tmp/json-bin"
mkdir -p "$json_bin" "$fixtures/json"
cat > "$json_bin/gh" <<'SHIM'
#!/usr/bin/env bash
filter=""
prev=""
for arg in "$@"; do
    [[ "$prev" == "--jq" ]] && filter="$arg"
    prev="$arg"
done
case "$1 $2" in
    "pr view")  src="$FIXTURES/json/pr.json" ;;
    "run list")
        [[ "$*" == *"--commit cafe1234"* ]] || { echo "fake gh: run list not scoped to the PR head: $*" >&2; exit 65; }
        [[ "$FAKE_RUNS" == "unlistable" ]] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
        src="$FIXTURES/json/runs-$FAKE_RUNS.json" ;;
    "run view")
        if [[ "$3" == "--job" ]]; then
            cat "$FIXTURES/json/joblog-$4.txt" 2>/dev/null
            exit 0
        fi
        src="$FIXTURES/json/jobs-$3.json" ;;
    *) echo "fake gh: unhandled call: $*" >&2; exit 64 ;;
esac
if [[ -n "$filter" ]]; then jq "$filter" "$src"; else cat "$src"; fi
SHIM
chmod +x "$json_bin/gh"

printf '{"number":77,"title":"a title","headRefOid":"cafe1234","headRefName":"a-branch","url":"https://example.test/pull/77"}\n' \
    > "$fixtures/json/pr.json"

# A PR reopened on one SHA: `cancel-in-progress` cancelled the first run and
# the second passed. Only the newest run per workflow and trigger counts.
cat > "$fixtures/json/runs-reopened.json" <<'JSON'
[{"databaseId":900,"workflowName":"CI","event":"pull_request","status":"completed","conclusion":"cancelled"},
 {"databaseId":901,"workflowName":"CI","event":"pull_request","status":"completed","conclusion":"success"}]
JSON
printf '{"jobs":[{"databaseId":9001,"name":"backend","status":"completed","conclusion":"cancelled"}]}\n' \
    > "$fixtures/json/jobs-900.json"
printf '{"jobs":[{"databaseId":9011,"name":"backend","status":"completed","conclusion":"success"}]}\n' \
    > "$fixtures/json/jobs-901.json"

# Another trigger on the same SHA is its own result, not an older attempt.
cat > "$fixtures/json/runs-dispatch.json" <<'JSON'
[{"databaseId":910,"workflowName":"CI","event":"workflow_dispatch","status":"completed","conclusion":"failure"},
 {"databaseId":911,"workflowName":"CI","event":"pull_request","status":"completed","conclusion":"success"}]
JSON
printf '{"jobs":[{"databaseId":9101,"name":"backend","status":"completed","conclusion":"failure"}]}\n' \
    > "$fixtures/json/jobs-910.json"
printf '{"jobs":[{"databaseId":9111,"name":"backend","status":"completed","conclusion":"success"}]}\n' \
    > "$fixtures/json/jobs-911.json"

# A run object with no jobs key: --jq '.jobs' prints the literal `null`, which is
# not an empty string, so the unreadable guard used to let it through and jq then
# iterated nothing — a successful run with no visible lanes read GREEN.
cat > "$fixtures/json/runs-nulljobs.json" <<'JSON'
[{"databaseId":920,"workflowName":"CI","event":"pull_request","status":"completed","conclusion":"success"}]
JSON
printf '{"jobs":null}\n' > "$fixtures/json/jobs-920.json"

# A run whose lanes gh did not hand back at all. Zero lanes proves nothing ran or
# nothing was read; either way there is no lane to call green.
cat > "$fixtures/json/runs-emptyjobs.json" <<'JSON'
[{"databaseId":921,"workflowName":"CI","event":"pull_request","status":"completed","conclusion":"success"}]
JSON
printf '{"jobs":[]}\n' > "$fixtures/json/jobs-921.json"

# invoke_pr <runs-fixture> — run from outside any checkout, so no HEAD warning
invoke_pr() {
    out=$(cd "$tmp" && FAKE_RUNS="$1" PATH="$json_bin:$PATH" bash "$subject" 77 2>&1)
    rc=$?
}

echo
echo "Default PR path (real jq)"

invoke_pr reopened
expect_contains "PR #77 — a title" "the PR is resolved from its number"
expect_rc 0 "a cancelled run replaced on the same SHA does not keep the PR failing"
expect_contains "Status: GREEN" "the replacement run decides the status"
expect_absent "(900)" "the superseded run is not reported"

invoke_pr dispatch
expect_rc 1 "a failed run from another trigger on the same SHA still fails the PR"
expect_contains "  FAIL  backend" "the other trigger's failed job is classified"

invoke_pr nulljobs
expect_rc 3 "a null job list is unreadable, not green"
expect_contains "job list unreadable" "the null job list is named"
expect_absent "Status: GREEN" "a null job list never lands on GREEN"

invoke_pr emptyjobs
expect_rc 3 "an empty job list is unreadable, not green"
expect_absent "Status: GREEN" "an empty job list never lands on GREEN"

invoke_pr unlistable
expect_rc 3 "a run listing gh could not produce exits 3"
expect_contains "could not list workflow runs" "the failed listing is named"
expect_absent "Status: GREEN" "a failed listing never lands on GREEN"

# ---------------------------------------------------------------- summary ---
echo
echo "passed: $passed  failed: $failed"
[ "$failed" -eq 0 ] || exit 1
