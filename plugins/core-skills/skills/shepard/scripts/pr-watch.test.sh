#!/usr/bin/env bash
#
# Tests for pr-watch.sh.
#
# This script is a WATCHER, so its expensive failure is not a wrong line — it is
# NO line. /shepard reads silence as "nothing has happened on the PR yet". Every
# way the watcher can go quiet while still looking alive is pinned below:
#
#   - a producer that returns nothing must warn, never read as "all fields cleared"
#   - a bus outage must not silence the GitHub surface
#   - any exit that is not a PR outcome must say so on stdout
#
# The opposite direction costs real money too: a line per tick would make every
# Monitor notification worthless, so "no change emits nothing" is pinned as hard
# as "a change emits something".
#
# The fakes are `gh` and `curl` only. Both emit REAL JSON and the script runs
# REAL jq over it, so a fake cannot drift from the tool in a way that matters —
# what is under test is the script's change detection, not jq's parsing. Each
# fake reads a per-call counter file, so tick N can answer differently from
# tick N-1; that is how a change is staged.
#
# No framework by design, matching ci-failures.test.sh. Run it the same way:
#
#   bash <skill dir>/scripts/pr-watch.test.sh

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/pr-watch.sh"

[[ -f "$subject" ]] || { echo "pr-watch.sh not found at $subject" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
state="$tmp/state"
mkdir -p "$bin" "$state" "$tmp/emptybin"

passed=0
failed=0

# ------------------------------------------------------------------- the fakes

cat > "$bin/gh" <<'FAKE'
#!/usr/bin/env bash
# Answers only the two calls pr-watch.sh makes. Snapshot calls walk a counter so
# each tick can return a different fixture; the last fixture repeats forever.
args="$*"
case "$args" in
  *"--head no-such-branch"*)
    echo 'null'
    exit 0 ;;
  *"--json number,url,title"*)
    echo '{"number":42,"url":"https://github.com/acme/widget/pull/42","title":"a title"}'
    exit 0 ;;
esac
n=$(cat "$STATE/gh_n" 2>/dev/null || echo 0)
n=$((n + 1)); echo "$n" > "$STATE/gh_n"
f="$STATE/gh_$n.json"
[[ -f "$f" ]] || f=$(ls "$STATE"/gh_*.json 2>/dev/null | sort -V | tail -1)
[[ -f "${f:-}" ]] || { echo "fake gh: no fixture" >&2; exit 1; }
[[ -s "$f" ]] || exit 1     # an empty fixture means "the call failed"
cat "$f"
FAKE

cat > "$bin/curl" <<'FAKE'
#!/usr/bin/env bash
# Every invocation's argv is appended for the token-exposure assertion below —
# a fake that only served fixtures could not tell a leaked secret from a safe one.
printf '%s\0' "$@" >> "$STATE/curl_argv.log"
# Two routes: the open-ledger scan (id resolution) and one request row.
for a in "$@"; do case "$a" in *"status=open"*) mode=list ;; */api/review-requests/*) mode=show ;; esac; done
if [[ "${mode:-}" == "list" ]]; then
  cat "$STATE/bus_list.json" 2>/dev/null || echo '{"requests":[]}'
  exit 0
fi
n=$(cat "$STATE/bus_n" 2>/dev/null || echo 0)
n=$((n + 1)); echo "$n" > "$STATE/bus_n"
f="$STATE/bus_$n.json"
[[ -f "$f" ]] || f=$(ls "$STATE"/bus_[0-9]*.json 2>/dev/null | sort -V | tail -1)
[[ -f "${f:-}" ]] || exit 1
[[ -s "$f" ]] || exit 1
cat "$f"
FAKE

chmod +x "$bin/gh" "$bin/curl"
export STATE="$state"
export PATH="$bin:$PATH"

# --------------------------------------------------------------- fixture makers

gh_tick() {  # gh_tick <n> <state> <head> <reviews> <comments> <ci_fail_name>
  local checks='[{"name":"ci-passed","conclusion":"SUCCESS"}]'
  [[ -n "${6:-}" ]] && checks="[{\"name\":\"$6\",\"conclusion\":\"FAILURE\"},{\"name\":\"other\",\"conclusion\":\"SUCCESS\"}]"
  local reviews comments
  reviews=$(seq 1 "$4" 2>/dev/null | sed 's/.*/{}/' | paste -sd, -)
  comments=$(seq 1 "$5" 2>/dev/null | sed 's/.*/{}/' | paste -sd, -)
  cat > "$state/gh_$1.json" <<EOF
{"state":"$2","headRefOid":"$3","statusCheckRollup":$checks,
 "reviews":[${reviews}],"comments":[${comments}],"reviewDecision":""}
EOF
}

bus_tick() {  # bus_tick <n> <gate> <reviews> <findings_issue> <head>
  cat > "$state/bus_$1.json" <<EOF
{"status":"open","gate_state":"$2","trial_state":"cleared","merge_conflict_state":"clean",
 "last_reviewer":"crit","review_count":$3,"head_oid":"$5",
 "open_finding_counts":{"issue":$4,"nitpick":0},"locked_by":null}
EOF
}

bus_listed() {
  echo '{"requests":[{"id":2575,"pr_url":"https://github.com/acme/widget/pull/42"}]}' > "$state/bus_list.json"
}
bus_absent() { echo '{"requests":[]}' > "$state/bus_list.json"; }

reset() { rm -f "$state"/*.json "$state"/gh_n "$state"/bus_n "$state"/curl_argv.log; }

run() { TOWN_CRIER_TOKEN=fake-token TOWN_CRIER_URL=https://bus.test bash "$subject" 42 --interval 0 --heartbeat 0 "$@" 2>&1; }

check() {  # check <name> <expected-exit> <output> <actual-exit> <grep...>
  local name="$1" want_exit="$2" out="$3" got_exit="$4"; shift 4
  local ok=1 why=""
  [[ "$got_exit" == "$want_exit" ]] || { ok=0; why="exit $got_exit, wanted $want_exit"; }
  local pattern
  for pattern in "$@"; do
    if [[ "$pattern" == !* ]]; then
      grep -qF -- "${pattern:1}" <<<"$out" && { ok=0; why="unexpected: ${pattern:1}"; }
    else
      grep -qF -- "$pattern" <<<"$out" || { ok=0; why="missing: $pattern"; }
    fi
  done
  if [[ $ok -eq 1 ]]; then
    passed=$((passed + 1)); echo "  ok    $name"
  else
    failed=$((failed + 1)); echo "  FAIL  $name — $why"
    while IFS= read -r line; do echo "          | $line"; done <<<"$out"
  fi
}

# --------------------------------------------------------------------- the cases

echo "pr-watch.sh"

# A quiet PR must produce the two header lines and nothing else. Every extra line
# is a chat notification, so a per-tick status would make the watch unreadable.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
gh_tick 2 OPEN aaaaaaaa 0 0
gh_tick 3 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "no change emits no line" 0 "$out" $rc "[watch] PR #42" "[end] PR #42 MERGED" "!->"

# The signal /shepard exists for: a review landed. Once a bus row is attached it owns the
# review surface, so the GitHub review count must NOT be reported as well — that would be
# the same review announced twice, every round.
reset; bus_listed
gh_tick 1 OPEN aaaaaaaa 0 0; bus_tick 1 clear 0 0 aaaaaaaa
gh_tick 2 OPEN aaaaaaaa 1 0; bus_tick 2 blocked 1 2 aaaaaaaa
gh_tick 3 MERGED aaaaaaaa 1 0; bus_tick 3 blocked 1 2 aaaaaaaa
out=$(run); rc=$?
check "new bus review emits one line" 0 "$out" $rc \
  "[bus] review 1 by crit" "findings 2 issue/0 nit" "[bus] gate clear -> blocked" "[pr]  +1 GitHub review(s)"

# A verdict at a replaced head is not a result about the code now on the branch.
reset; bus_listed
gh_tick 1 OPEN bbbbbbbb 0 0; bus_tick 1 clear 0 0 bbbbbbbb
gh_tick 2 OPEN bbbbbbbb 0 0; bus_tick 2 blocked 1 1 aaaaaaaa
gh_tick 3 MERGED bbbbbbbb 0 0; bus_tick 3 blocked 1 1 aaaaaaaa
out=$(run); rc=$?
check "stale bus head is marked" 0 "$out" $rc "(STALE — bus read aaaaaaaa, PR head bbbbbbbb)"

# CI both ways: going red must speak, and so must clearing.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
gh_tick 2 OPEN aaaaaaaa 0 0 test-unit
gh_tick 3 OPEN aaaaaaaa 0 0
gh_tick 4 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "ci red then green both emit" 0 "$out" $rc "[ci]  FAILING: test-unit" "[ci]  all checks green"

# A bus outage must not take the GitHub surface down with it, and must announce
# itself rather than let the quiet read as "no reviews yet". GitHub's own comment
# lines keep firing through the outage — that is the whole point of never gating
# them on the bus — and the remembered bus fields must not flap to "—" every tick.
reset; bus_listed
gh_tick 1 OPEN aaaaaaaa 0 0; bus_tick 1 clear 0 0 aaaaaaaa
gh_tick 2 OPEN aaaaaaaa 0 1; : > "$state/bus_2.json"
gh_tick 3 OPEN aaaaaaaa 0 2 test-unit; : > "$state/bus_3.json"
gh_tick 4 OPEN aaaaaaaa 0 3; : > "$state/bus_4.json"
gh_tick 5 MERGED aaaaaaaa 0 3
out=$(run); rc=$?
check "bus outage warns, github keeps reporting" 0 "$out" $rc \
  "[warn] bus row #2575 unreadable for 3 ticks" "[ci]  FAILING: test-unit" \
  "[pr]  +1 comment(s)" "!-> —"

# GitHub itself unreadable: the watcher is blind and must say so. Silence here
# would be indistinguishable from a PR nobody has touched.
reset; bus_absent
: > "$state/gh_1.json"; : > "$state/gh_2.json"; : > "$state/gh_3.json"
gh_tick 4 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "github unreadable warns" 0 "$out" $rc "[warn] GitHub unreadable for 3 ticks"

# The producer-returns-nothing trap. A single unreadable tick must stay SILENT —
# one flaky call is not news — and must not clear the remembered state, which
# would emit a burst of bogus change lines on the tick after it. Three in a row
# is the point where quiet stops being acceptable; that threshold is pinned by
# the "github unreadable warns" case above.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
echo 'not json at all' > "$state/gh_2.json"
gh_tick 3 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "one unreadable tick is silent and keeps state" 0 "$out" $rc \
  "[end] PR #42 MERGED" "![warn]" "!head moved" "!->"

# A PR that closed without merging still ends the watch cleanly.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
gh_tick 2 CLOSED aaaaaaaa 0 0
out=$(run); rc=$?
check "closed PR ends the watch" 0 "$out" $rc "[end] PR #42 CLOSED — watch ends"

# Killed mid-flight, the trap must report — otherwise a dead watch looks calm.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
out=$(TOWN_CRIER_TOKEN=fake-token bash "$subject" 42 --interval 5 --heartbeat 0 2>&1 &
       pid=$!; sleep 1; kill -TERM $pid 2>/dev/null; wait $pid 2>/dev/null)
check "a killed watch says it stopped" 143 "$out" $? "[end] watch on PR #42 stopped"

# --source bus on a PR the bus never heard of must fail loudly, not silently
# degrade — the operator asked for the bus surface by name. Not at setup, though:
# the row appears at dispatch, after the PR opens, so the script retries the attach
# for 20 ticks first. Past that it exits 3 instead of watching GitHub forever.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
out=$(run --source bus); rc=$?
check "--source bus without a request exits 3" 3 "$out" $rc "no open town-crier request" "after 20 ticks" "!stopped (signal or timeout)"

# No token at all is the common case on a repo that is not on the bus. It is a
# degradation, not an error.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
gh_tick 2 MERGED aaaaaaaa 0 0
out=$(TOWN_CRIER_TOKEN="" TOWN_CRIER_ENV_FILE=/nonexistent bash "$subject" 42 --interval 0 --heartbeat 0 2>&1); rc=$?
check "no token degrades to github only" 0 "$out" $rc "[watch] github only"

# Every setup failure must reach stdout — Monitor never shows stderr, so a typo'd
# flag or PR number would otherwise look like a quiet, armed watch.
setup_run() { TOWN_CRIER_TOKEN=fake-token TOWN_CRIER_URL=https://bus.test bash "$subject" "$@" 2>/dev/null; }

reset; bus_absent
out=$(setup_run 42 --bogus); rc=$?
check "an unknown flag says so on stdout" 3 "$out" $rc "[end] setup failed: unknown flag '--bogus'"

out=$(setup_run no-such-branch); rc=$?
check "no PR for the target says so on stdout" 3 "$out" $rc \
  "[end] setup failed: no PR found for 'no-such-branch' — watch never started"

out=$(setup_run 42 --interval); rc=$?
check "--interval without a value says so on stdout" 3 "$out" $rc \
  "[end] setup failed: --interval needs seconds — watch never started"
out=$(setup_run 42 --heartbeat); rc=$?
check "--heartbeat without a value says so on stdout" 3 "$out" $rc \
  "[end] setup failed: --heartbeat needs minutes — watch never started"
out=$(setup_run 42 --source); rc=$?
check "--source without a value says so on stdout" 3 "$out" $rc \
  "[end] setup failed: --source needs gh|bus|auto — watch never started"

# A value `sleep` rejects would make the loop poll GitHub with no pause. `--once` keeps
# a regression from spinning forever here: it ends on the first tick instead.
out=$(setup_run 42 --interval abc --once); rc=$?
check "--interval that is not a whole number is refused" 3 "$out" $rc \
  "[end] setup failed: --interval needs seconds — watch never started"
out=$(setup_run 42 --heartbeat abc --once); rc=$?
check "--heartbeat that is not a whole number is refused" 3 "$out" $rc \
  "[end] setup failed: --heartbeat needs minutes — watch never started"
out=$(setup_run 42 --source github --once); rc=$?
check "--source with an unknown surface is refused" 3 "$out" $rc \
  "[end] setup failed: --source needs gh|bus|auto — watch never started"

out=$(TOWN_CRIER_TOKEN="" TOWN_CRIER_ENV_FILE=/nonexistent bash "$subject" 42 --source bus 2>/dev/null); rc=$?
check "--source bus without a token says so on stdout" 3 "$out" $rc \
  "[end] setup failed: --source bus, but no town-crier token is readable" "!stopped (signal or timeout)"

# A CheckRun that GitHub has sent back to the queue serialises `conclusion` as ""
# and carries its real state in `.status`. `.conclusion // .state` does not fall
# through an empty string, so bucketing on conclusion alone drops the job out of
# every bucket: it is not red, not pending, not passing. The watch then reports the
# red set as cleared while the job is still running, and /shepard reads that as
# progress. Bucketing on `.status` first is what keeps it pending.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0 test-unit
cat > "$state/gh_2.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"test-unit","status":"IN_PROGRESS","conclusion":""},
                      {"name":"other","status":"COMPLETED","conclusion":"SUCCESS"}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
gh_tick 3 MERGED aaaaaaaa 0 0 test-unit
out=$(run); rc=$?
check "a re-running red job is pending, never cleared" 0 "$out" $rc \
  "[ci]  FAILING: test-unit" "[ci]  red checks re-running, not green yet" "![ci]  all checks green"

# ACTION_REQUIRED and STARTUP_FAILURE block the merge exactly like FAILURE does.
# Leaving them out of the red bucket makes a blocked PR read green.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
cat > "$state/gh_2.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"deploy-gate","conclusion":"ACTION_REQUIRED"},
                      {"name":"boot","conclusion":"STARTUP_FAILURE"}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
gh_tick 3 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "every blocking conclusion counts as red" 0 "$out" $rc "[ci]  FAILING: boot,deploy-gate"

# --once has no later tick to speak on. Exiting 3 with an empty stdout is the exact
# silence this watcher must never produce: Monitor surfaces stdout only, so the
# caller sees a clean, quiet run rather than a failed one.
reset; bus_absent
: > "$state/gh_1.json"
out=$(run --once); rc=$?
check "--once says why it found nothing" 3 "$out" $rc "[warn] GitHub unreadable — nothing to report"

# A missing dependency is a setup failure, and setup failures are invisible on
# stderr: Monitor never shows it. The line has to land on stdout or an armed watch
# and a dead one look identical.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
bash_bin=$(command -v bash)
out=$(PATH="$tmp/emptybin" "$bash_bin" "$subject" 42 --once 2>/dev/null); rc=$?
check "a missing dependency speaks on stdout" 3 "$out" $rc "[end] setup failed:" "watch never started"

# A STALE conclusion means this required check's result does not apply to the
# current commit — it does not satisfy branch protection even with a passing
# sibling, so a passing sibling must never be enough to call the run green.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
cat > "$state/gh_2.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"required-check","conclusion":"STALE","workflowName":"CI"},
                      {"name":"other","conclusion":"SUCCESS","workflowName":"CI"}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
cat > "$state/gh_3.json" <<'EOF'
{"state":"MERGED","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"required-check","conclusion":"STALE","workflowName":"CI"},
                      {"name":"other","conclusion":"SUCCESS","workflowName":"CI"}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
out=$(run); rc=$?
check "a STALE check is never reported as green" 0 "$out" $rc \
  "[ci]  needs attention (neutral/stale): required-check" "![ci]  all checks green"

# NEUTRAL lands in neither ci_fail nor ci_pass nor ci_pending, and the classifier
# used to map that to a state the emitter had no case for — the watch went quiet
# instead of saying anything, which reads as "still the last thing I told you"
# rather than as the true, unclassified state.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
cat > "$state/gh_2.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"conditional-job","conclusion":"NEUTRAL","workflowName":"CI"}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
gh_tick 3 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "a NEUTRAL-only lane speaks instead of going quiet" 0 "$out" $rc \
  "[ci]  needs attention (neutral/stale): conditional-job"

# A SKIPPED lane is routine wherever a detect-changes job gates the matrix: kendo
# #2209 skipped 11 lanes and emmie #1386 skipped 10 on an ordinary PR. Counted as
# ATTN, every such PR read "needs attention" and none ever read green — the
# always-firing failure. A repo whose rollup requires every lane to report turns a
# skip into a red rollup, which is RED here already; ci-failures.sh names each
# skipped job. So a skip beside a passing sibling is green, and only a skip.
reset; bus_absent
cat > "$state/gh_1.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa","statusCheckRollup":[],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
cat > "$state/gh_2.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"Backend Unit Tests","conclusion":"SKIPPED","workflowName":"CI"},
                      {"name":"ci-passed","conclusion":"SUCCESS","workflowName":"CI"}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
gh_tick 3 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "a skipped lane beside a passing rollup is green" 0 "$out" $rc \
  "[ci]  all checks green" "![ci]  needs attention"

# An APP posts a check through the Checks API with no workflow behind it, and one
# that renders information rather than judging it never reaches a verdict: the
# `kendo` tracker card is NEUTRAL on every linked PR, forever. Counted as ATTN it
# made the state permanent, so the only ATTN ever seen was the harmless one —
# training the reader to scroll past the skipped lane the state is for. A
# never-firing gate and an always-firing one fail the same way.
reset; bus_absent
# Tick 1 reports no checks at all, so tick 2 landing GREEN is a real change: this
# watcher speaks only on change, and a first tick already green emits nothing.
cat > "$state/gh_1.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa","statusCheckRollup":[],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
cat > "$state/gh_2.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"ci-passed","conclusion":"SUCCESS","workflowName":"CI"},
                      {"name":"kendo","conclusion":"NEUTRAL","workflowName":""}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
gh_tick 3 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "an app check with no workflow is not ATTN" 0 "$out" $rc \
  "[ci]  all checks green" "![ci]  needs attention"

# The discrimination is per check, not per run: a neutral lane still speaks even
# while an app check sits NEUTRAL beside it, and only the lane is named.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
cat > "$state/gh_2.json" <<'EOF'
{"state":"OPEN","headRefOid":"aaaaaaaa",
 "statusCheckRollup":[{"name":"conditional-job","conclusion":"NEUTRAL","workflowName":"CI"},
                      {"name":"kendo","conclusion":"NEUTRAL","workflowName":""},
                      {"name":"other","conclusion":"SUCCESS","workflowName":"CI"}],
 "reviews":[],"comments":[],"reviewDecision":""}
EOF
gh_tick 3 MERGED aaaaaaaa 0 0
out=$(run); rc=$?
check "a neutral lane still speaks beside a neutral app check" 0 "$out" $rc \
  "[ci]  needs attention (neutral/stale): conditional-job" "!kendo"

# The header comment promises the token never appears in anything this script
# emits. That promise covers stdout; it does not by itself cover argv, which
# `ps`/procfs expose to any other local user for as long as the process runs.
reset; bus_listed
bus_tick 1 clean 0 0 aaaaaaaa
gh_tick 1 OPEN aaaaaaaa 0 0
run --once --source bus >/dev/null 2>&1
if grep -qzF 'fake-token' "$state/curl_argv.log" 2>/dev/null; then
  failed=$((failed + 1)); printf '  FAIL  %s\n' 'bus token never appears in a curl argv'
else
  passed=$((passed + 1)); printf '  ok    %s\n' 'bus token never appears in a curl argv'
fi
if grep -qzF -- '-K' "$state/curl_argv.log" 2>/dev/null; then
  passed=$((passed + 1)); printf '  ok    %s\n' 'bus auth travels via curl -K, not -H'
else
  failed=$((failed + 1)); printf '  FAIL  %s\n' 'bus auth travels via curl -K, not -H'
fi

echo
echo "passed: $passed   failed: $failed"
[[ $failed -eq 0 ]]
