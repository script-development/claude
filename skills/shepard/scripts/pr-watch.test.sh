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
#   bash ~/.claude/skills/shepard/scripts/pr-watch.test.sh

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/pr-watch.sh"

[[ -f "$subject" ]] || { echo "pr-watch.sh not found at $subject" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
state="$tmp/state"
mkdir -p "$bin" "$state"

passed=0
failed=0

# ------------------------------------------------------------------- the fakes

cat > "$bin/gh" <<'FAKE'
#!/usr/bin/env bash
# Answers only the two calls pr-watch.sh makes. Snapshot calls walk a counter so
# each tick can return a different fixture; the last fixture repeats forever.
args="$*"
case "$args" in
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
  local reviews=$(seq 1 "$4" 2>/dev/null | sed 's/.*/{}/' | paste -sd, -)
  local comments=$(seq 1 "$5" 2>/dev/null | sed 's/.*/{}/' | paste -sd, -)
  cat > "$state/gh_$1.json" <<EOF
{"state":"$2","headRefOid":"$3","statusCheckRollup":$checks,
 "reviews":[${reviews}],"comments":[${comments}],"reviewDecision":""}
EOF
}

bus_tick() {  # bus_tick <n> <gate> <reviews> <findings_blocker> <head>
  cat > "$state/bus_$1.json" <<EOF
{"status":"open","gate_state":"$2","trial_state":"cleared","merge_conflict_state":"clean",
 "last_reviewer":"crit","review_count":$3,"head_oid":"$5",
 "open_finding_counts":{"blocker":$4,"major":0,"minor":0,"nit":0},"locked_by":null}
EOF
}

bus_listed() {
  echo '{"requests":[{"id":2575,"pr_url":"https://github.com/acme/widget/pull/42"}]}' > "$state/bus_list.json"
}
bus_absent() { echo '{"requests":[]}' > "$state/bus_list.json"; }

reset() { rm -f "$state"/*.json "$state"/gh_n "$state"/bus_n; }

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
    sed 's/^/          | /' <<<"$out"
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

# The signal /shepard exists for: a review landed.
reset; bus_listed
gh_tick 1 OPEN aaaaaaaa 0 0; bus_tick 1 clear 0 0 aaaaaaaa
gh_tick 2 OPEN aaaaaaaa 1 0; bus_tick 2 blocked 1 2 aaaaaaaa
gh_tick 3 MERGED aaaaaaaa 1 0; bus_tick 3 blocked 1 2 aaaaaaaa
out=$(run); rc=$?
check "new bus review emits one line" 0 "$out" $rc \
  "[bus] review 1 by crit" "findings 2/0/0/0" "[bus] gate clear -> blocked" "[pr]  +1 GitHub review(s)"

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
check "ci red then green both emit" 0 "$out" $rc "[ci]  FAILING: test-unit" "[ci]  all red checks cleared"

# A bus outage must not take the GitHub surface down with it, and must announce
# itself rather than let the quiet read as "no reviews yet".
reset; bus_listed
gh_tick 1 OPEN aaaaaaaa 0 0; bus_tick 1 clear 0 0 aaaaaaaa
gh_tick 2 OPEN aaaaaaaa 0 1; : > "$state/bus_2.json"
gh_tick 3 OPEN aaaaaaaa 0 2; : > "$state/bus_3.json"
gh_tick 4 OPEN aaaaaaaa 0 3; : > "$state/bus_4.json"
gh_tick 5 MERGED aaaaaaaa 0 3
out=$(run); rc=$?
check "bus outage warns, github keeps reporting" 0 "$out" $rc \
  "[warn] bus row #2575 unreadable for 3 ticks" "[pr]  +1 comment(s)"

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

# --source bus on a PR the bus never heard of must fail loudly at setup, not
# silently degrade — the operator asked for the bus surface by name.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
out=$(run --source bus); rc=$?
check "--source bus without a request exits 3" 3 "$out" $rc "no open town-crier request"

# No token at all is the common case on a repo that is not on the bus. It is a
# degradation, not an error.
reset; bus_absent
gh_tick 1 OPEN aaaaaaaa 0 0
gh_tick 2 MERGED aaaaaaaa 0 0
out=$(TOWN_CRIER_TOKEN="" TOWN_CRIER_ENV_FILE=/nonexistent bash "$subject" 42 --interval 0 --heartbeat 0 2>&1); rc=$?
check "no token degrades to github only" 0 "$out" $rc "[watch] github only"

echo
echo "passed: $passed   failed: $failed"
[[ $failed -eq 0 ]]
