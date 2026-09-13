#!/usr/bin/env bash
# pr-watch.sh — live watch on ONE pull request. Built for /shepard's Monitor tool:
# every stdout line becomes one chat notification, so the script prints ONLY
# changes, never a running status.
#
# Two surfaces, one tick, with the bus first among them:
#   GitHub  — PR state, head SHA, per-job check rollup, reviews, comments, decision.
#             Always, whatever the bus says: a reviewer that posts on GitHub and never
#             reports to its bus row (emmie #1297) must still wake the watch.
#   The bus — town-crier's ledger row: gate, trial, findings, reviewer (when the
#             PR is announced there and a token is readable). The row is created at
#             DISPATCH, which always lands after the PR opens, so the watch attaches on
#             a later tick and says so with "[bus] attached #<id>". A round shows up
#             on both surfaces, as one [bus] line and one [pr] line.
#
# The bus is not crit-only. Every repo that announces on town-crier is covered by
# the same poll — lokalekeuze, emmie, kendo, crit, and the rest. A repo that is
# NOT on the bus degrades to the GitHub surface alone; nothing else changes.
#
# Usage:
#   pr-watch.sh                    PR for the current branch
#   pr-watch.sh 708                explicit PR number
#   pr-watch.sh some-branch        explicit head branch
#   pr-watch.sh --interval 60      seconds between ticks (default 30)
#   pr-watch.sh --heartbeat 30     minutes between "still alive" lines (0 = off)
#   pr-watch.sh --source gh|bus|auto   force a surface (default auto)
#   pr-watch.sh --once             one tick, print the snapshot, exit
#
# Exit codes:
#   0  the PR reached a terminal state (MERGED or CLOSED) — the watch is done
#   3  setup failure, said on stdout: no PR, missing dependency, bad flag value — or `--source bus`
#      with no town-crier row for this PR after 20 ticks
#
# The token is read from $TOWN_CRIER_TOKEN, else from the env file named by
# $TOWN_CRIER_ENV_FILE. Neither set means no bus surface — not an error, and no
# request leaves for town-crier. The token is never printed, no line this script
# emits contains it, and it never appears in a process's argv.
set -uo pipefail

# Setup failures speak on stdout too: Monitor surfaces only stdout, so a
# stderr-only exit here would look like an armed, quiet watch.
die() { ended=setup; echo "[end] setup failed: $1 — watch never started"; exit 3; }

command -v gh   >/dev/null || die "gh CLI required"
command -v jq   >/dev/null || die "jq required"

INTERVAL=30
HEARTBEAT_MIN=30
SOURCE=auto
ONCE=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    # Whole numbers only: a value `sleep` rejects makes it return at once, and the loop
    # would then poll GitHub with no pause.
    --interval)  [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--interval needs seconds"
                 INTERVAL="$2"; shift ;;
    --heartbeat) [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--heartbeat needs minutes"
                 HEARTBEAT_MIN="$2"; shift ;;
    --source)    [[ "${2:-}" =~ ^(gh|bus|auto)$ ]] || die "--source needs gh|bus|auto"
                 SOURCE="$2"; shift ;;
    --once)      ONCE=1 ;;
    -*)          die "unknown flag '$1'" ;;
    *)           TARGET="$1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- resolve the PR

if [[ -z "$TARGET" ]]; then
  TARGET=$(git branch --show-current 2>/dev/null) || true
  [[ -z "$TARGET" ]] && die "no PR/branch argument and not on a branch"
fi

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  pr_json=$(gh pr view "$TARGET" --json number,url,title 2>/dev/null)
else
  pr_json=$(gh pr list --head "$TARGET" --json number,url,title --jq '.[0]' 2>/dev/null)
fi
[[ -z "${pr_json:-}" || "$pr_json" == "null" ]] && die "no PR found for '$TARGET'"

PR_NUMBER=$(jq -r .number <<<"$pr_json")
PR_URL=$(jq -r .url <<<"$pr_json")
PR_TITLE=$(jq -r .title <<<"$pr_json")

# ------------------------------------------------------------------- bus access

read_env_key() {
  [[ -f "$1" ]] || return 1
  sed -n -E "s/^[[:space:]]*$2=[\"']?([^\"'#[:space:]]+).*/\1/p" "$1" | tail -1
}

# No default env file: a built-in path into one person's checkout made every other
# machine's auto mode look for a token it could never have, and made this watch send
# PR URLs to town-crier wherever that file happened to exist (emmie #1386 review).
BUS_ENV_FILE="${TOWN_CRIER_ENV_FILE:-}"
BUS_TOKEN="${TOWN_CRIER_TOKEN:-$(read_env_key "$BUS_ENV_FILE" TOWN_CRIER_TOKEN 2>/dev/null)}"
BUS_URL="${TOWN_CRIER_URL:-$(read_env_key "$BUS_ENV_FILE" TOWN_CRIER_URL 2>/dev/null)}"
BUS_URL="${BUS_URL:-https://town-crier-mcp.fly.dev}"
BUS_URL="${BUS_URL%/}"

# curl is the bus half's only dependency, so its absence costs the bus half and
# nothing else: a GitHub-only watch runs on gh and jq alone.
BUS_WHY=""
if [[ "$SOURCE" == "gh" ]]; then
  BUS_TOKEN=""; BUS_WHY="--source gh"
elif ! command -v curl >/dev/null; then
  [[ "$SOURCE" == "bus" ]] && die "--source bus needs curl"
  BUS_TOKEN=""; BUS_WHY="no curl"
elif [[ -z "$BUS_TOKEN" ]]; then
  BUS_WHY="no town-crier token"
fi

BUS_ID=""
bus_resolve_id() {
  # Scan the ACTIVE ledger for this PR's row. `open` alone is not enough: the row moves to
  # `in_review` the moment a reviewer claims it, and the status-filtered scan then stops
  # returning it — so an open-only scan could attach during one narrow window and never again.
  # The two states are scanned separately because the endpoint takes ONE status, not a list
  # (`status=open,in_review` returns zero rows), and an unfiltered scan is crowded out by the
  # `done` rows that dominate the ledger (184 of 200 when this was measured). Once the id is
  # known every later tick reads the row directly, which keeps working in every later state.
  # `done` is scanned last so a PR whose review already finished can still be re-watched; the
  # show route GET /api/review-requests/<id> answers in every status, only the LOOKUP is
  # status-bound. There is no lookup by pr_url or repo — the list route ignores both and
  # honours status, limit and offset alone, so scanning is the only way to the id.
  local body id status
  for status in open in_review "done"; do
    body=$(curl -sSf --max-time 20 --max-filesize 4194304 -K "$BUS_AUTH_CONFIG" \
      "$BUS_URL/api/review-requests?status=$status&limit=200" \
      -H 'accept: application/json' 2>/dev/null) || continue
    id=$(jq -r --arg url "$PR_URL" '.requests[]? | select(.pr_url == $url) | .id' <<<"$body" 2>/dev/null | head -1)
    [[ -n "$id" ]] && { echo "$id"; return 0; }
  done
  return 1
}

# --------------------------------------------------------------------- snapshots

# One compact JSON object per surface. Keys are stable; a missing surface
# contributes nothing, so a bus outage cannot look like a bus change.
#
# `gh`'s stderr is kept so a --once run can say *why* GitHub was unreadable
# instead of exiting 3 with an empty stdout.
GH_ERR=$(mktemp)

gh_snapshot() {
  local raw
  raw=$(gh pr view "$PR_NUMBER" --json state,headRefOid,statusCheckRollup,reviews,comments,reviewDecision 2>"$GH_ERR") || return 1
  [[ -z "$raw" ]] && return 1
  jq -c '
    ([.statusCheckRollup[]?
      | {n: (.name // .context // "?"), c: (.conclusion // .state // ""), s: (.status // "COMPLETED"),
         # Which workflow the check belongs to, or "" for one an APP posted directly
         # through the Checks API. `ci_attn` is the only consumer; see its comment.
         w: (.workflowName // "")}
      # A CheckRun in flight carries its state in .status and serialises conclusion
      # as "", which `//` does not fall through — bucket on status first so a
      # re-running red job counts as pending, never as nothing.
      | .c = (if .s != "COMPLETED" or .c == "" then "PENDING" else .c end)]) as $checks
    | {
        pr_state:   (.state // "?"),
        head:       ((.headRefOid // "") | .[0:8]),
        decision:   (if ((.reviewDecision // "") == "") then "NONE" else .reviewDecision end),
        reviews:    ((.reviews // []) | length),
        comments:   ((.comments // []) | length),
        ci_fail:    ([$checks[] | select(.c == "FAILURE" or .c == "TIMED_OUT" or .c == "CANCELLED" or .c == "ERROR" or .c == "ACTION_REQUIRED" or .c == "STARTUP_FAILURE") | .n] | sort | join(",")),
        ci_pending: ([$checks[] | select(.c == "PENDING" or .c == "IN_PROGRESS" or .c == "QUEUED" or .c == "EXPECTED")] | length),
        ci_pass:    ([$checks[] | select(.c == "SUCCESS")] | length),
        # NEUTRAL and STALE fall into none of the three buckets above — a completed
        # check with one of these conclusions is neither a failure nor a pass. Left
        # uncounted, it vanishes: with a passing sibling, ci_pass alone still selects
        # GREEN, reporting a check whose result does not apply to this commit (STALE)
        # or never reached a verdict (NEUTRAL) as clean.
        #
        # SKIPPED is deliberately NOT here. A repo that gates its matrix behind a
        # detect-changes job skips ten lanes on an ordinary PR (kendo #2209: 11,
        # emmie #1386: 10, measured 2026-09-13), so counting it made every such PR
        # ATTN and none ever green. A repo whose rollup requires every lane to report
        # (lokalekeuze) turns a skipped lane into a red rollup, which is RED here
        # already. ci-failures.sh lists each skipped job by name, which is where the
        # skill reads CI first.
        #
        # WORKFLOW LANES ONLY (`.w != ""`). A check an APP posts through the Checks
        # API carries no workflowName, and an app that renders information rather
        # than judging it has NO verdict to reach: the kendo tracker card is NEUTRAL
        # on every linked PR forever. Counted, it made ATTN permanent, and the only
        # ATTN anyone would ever see was the harmless one. A never-firing gate and an
        # always-firing one fail the same way. (lokalekeuze)
        ci_attn:    ([$checks[] | select((.c == "NEUTRAL" or .c == "STALE") and .w != "") | .n] | sort | join(","))
      }
    | .ci_state = (if .ci_fail != "" then "RED" elif .ci_pending > 0 then "PENDING"
                   elif .ci_attn != "" then "ATTN" elif .ci_pass > 0 then "GREEN" else "NONE" end)' <<<"$raw" 2>/dev/null
}

bus_snapshot() {
  [[ -z "$BUS_TOKEN" || -z "$BUS_ID" ]] && return 1
  local raw
  # -f turns an HTTP error into an unreadable row instead of a JSON body that jq
  # would read as a row with every field defaulted; --max-filesize bounds what a
  # misbehaving service can hand a shell variable.
  raw=$(curl -sSf --max-time 20 --max-filesize 4194304 -K "$BUS_AUTH_CONFIG" \
    "$BUS_URL/api/review-requests/$BUS_ID" \
    -H 'accept: application/json' 2>/dev/null) || return 1
  [[ -z "$raw" ]] && return 1
  jq -c '
    {
      bus_status:   (.status // "?"),
      gate:         (.gate_state // "?"),
      trial:        (.trial_state // "?"),
      conflict:     (.merge_conflict_state // "?"),
      reviewer:     (.last_reviewer // ""),
      bus_reviews:  (.review_count // 0),
      bus_head:     ((.head_oid // "") | .[0:8]),
      findings:     (if (.open_finding_counts // {}) == {} then "not submitted" else ((.open_finding_counts) | "\(.issue // 0) issue/\(.nitpick // 0) nit") end),
      lock:         (.locked_by // "")
    }' <<<"$raw" 2>/dev/null
}

# ------------------------------------------------------------------ change lines

declare -A prev=()
declare -A cur=()
bus_live=0   # 1 when THIS tick read the bus row; a missing read is not a change

load_into_cur() {
  local json="$1" k v n=0
  while IFS=$'\t' read -r k v; do
    v=${v%$'\r'}
    cur["$k"]="$v"
    n=$((n + 1))
  done < <(jq -r 'to_entries[] | [.key, (.value | tostring)] | @tsv' <<<"$json" 2>/dev/null)
  # A jq that produced nothing must not read as "every field cleared" — the
  # ci-failures.sh lesson: a silently empty producer is how a watcher goes blind
  # while still looking alive.
  [[ $n -gt 0 ]]
}

changed() { [[ "${prev[$1]-}" != "${cur[$1]-}" ]]; }
was()     { echo "${prev[$1]-—}"; }
now()     { echo "${cur[$1]-—}"; }

emit_changes() {
  local head_note=""
  # A verdict at a SHA that is no longer the PR head is a result about code that
  # has been replaced. /shepard must not read it as a result about the diff now.
  if [[ -n "${cur[bus_head]-}" && -n "${cur[head]-}" && "${cur[bus_head]}" != "${cur[head]}" ]]; then
    head_note=" (STALE — bus read ${cur[bus_head]}, PR head ${cur[head]})"
  fi

  # An unreadable bus row contributes no keys this tick. Comparing the remembered row
  # against nothing would print every bus field as "-> —" on every outage tick; the
  # [warn] line in the loop is the one announcement an outage gets.
  if [[ $bus_live -eq 1 ]]; then
    if changed bus_reviews && [[ "${cur[bus_reviews]-0}" -gt "${prev[bus_reviews]-0}" ]]; then
      echo "[bus] review $(now bus_reviews) by ${cur[reviewer]:-?} — findings $(now findings) · gate $(now gate)$head_note"
    elif changed findings; then
      echo "[bus] findings $(was findings) -> $(now findings)$head_note"
    fi
    changed gate       && echo "[bus] gate $(was gate) -> $(now gate)$head_note"
    changed trial      && echo "[bus] trial (ci-passed) $(was trial) -> $(now trial)"
    changed bus_status && echo "[bus] request status $(was bus_status) -> $(now bus_status)"
    changed conflict   && [[ "${cur[conflict]-}" != "clean" ]] && echo "[bus] merge conflict: $(now conflict)"
  fi

  # One line per CI state change, not per job: a red set that changes, a red job sent
  # back to the queue, and the whole rollup going green. Jobs finishing one by one inside
  # PENDING say nothing. Bucketing an in-flight check as PENDING empties ci_fail while the
  # job is still red, so an emptied ci_fail alone must never print "cleared".
  if changed ci_fail || changed ci_attn || changed ci_state; then
    case "${cur[ci_state]-}" in
      RED)     echo "[ci]  FAILING: ${cur[ci_fail]}  (pass ${cur[ci_pass]-?} · pending ${cur[ci_pending]-?})" ;;
      PENDING) [[ -n "${prev[ci_fail]-}" ]] && echo "[ci]  red checks re-running, not green yet (pass ${cur[ci_pass]-?} · pending ${cur[ci_pending]-?})" ;;
      # Never green while a lane is neutral or stale — a stale required check does
      # not satisfy branch protection even with every sibling passing, and a neutral
      # lane never reached a verdict at all.
      ATTN)    echo "[ci]  needs attention (neutral/stale): ${cur[ci_attn]}  (pass ${cur[ci_pass]-?})" ;;
      GREEN)   echo "[ci]  all checks green (pass ${cur[ci_pass]-?})" ;;
      NONE)    echo "[ci]  no checks reported yet" ;;
    esac
  fi
  # The PR head is GitHub's alone and always reported: `bus_head` is the head the reviewer
  # READ, and the STALE note above is the comparison of the two.
  changed head     && [[ -n "${prev[head]-}" ]] && echo "[pr]  head moved $(was head) -> $(now head)"

  # GitHub's review lines fire whether or not a bus row is attached. They used to be
  # gated on BUS_ID, and a reviewer that posted on GitHub while its bus row stayed at
  # 0 reviews left the watch blind for an hour (emmie #1297); an unreadable row did the
  # same. One duplicate line per round is the price of never being blind.
  changed decision && echo "[pr]  review decision $(was decision) -> $(now decision)"
  if changed reviews && [[ "${cur[reviews]-0}" -gt "${prev[reviews]-0}" ]]; then
    echo "[pr]  +$(( ${cur[reviews]-0} - ${prev[reviews]-0} )) GitHub review(s)"
  fi
  if changed comments && [[ "${cur[comments]-0}" -gt "${prev[comments]-0}" ]]; then
    echo "[pr]  +$(( ${cur[comments]-0} - ${prev[comments]-0} )) comment(s)"
  fi
}

# ---------------------------------------------------------------------- the loop

fail_streak=0
attach_ticks=0
last_heartbeat=$SECONDS
ended=""

on_exit() {
  rm -f "$GH_ERR"
  [[ -n "$BUS_AUTH_CONFIG" ]] && rm -f "$BUS_AUTH_CONFIG"
  # Silence must never be the only report. Any end — killed, crashed, terminal —
  # says so on stdout, so a dead watch is distinguishable from a quiet PR.
  [[ -n "$ended" ]] && return
  echo "[end] watch on PR #${PR_NUMBER} stopped (signal or timeout) — not a PR outcome"
}
trap on_exit EXIT

# The header's promise ("no line this script emits contains the token") covers stdout,
# not argv: a token passed to curl via `-H` sits in this process's command line for the
# run's whole duration, readable by any other local user through `ps` or
# /proc/<pid>/cmdline. A curl config file read via `-K` keeps it out of argv; mode 600
# and the EXIT trap above keep it off disk past this run. Created under the trap so a
# kill between here and the first tick still removes it, and only when the bus half
# runs at all — BUS_TOKEN is already empty under --source gh. (lokalekeuze #209)
BUS_AUTH_CONFIG=""
if [[ -n "$BUS_TOKEN" ]]; then
  BUS_AUTH_CONFIG=$(mktemp "${TMPDIR:-/tmp}/pr-watch-auth.XXXXXX")
  chmod 600 "$BUS_AUTH_CONFIG"
  printf 'header = "authorization: Bearer %s"\n' "$BUS_TOKEN" > "$BUS_AUTH_CONFIG"
fi

# The bus row is created when the PR is DISPATCHED for review, and dispatch always lands
# after the PR itself opens. A watch armed at PR-open time is therefore early BY DESIGN and
# this first resolve normally misses. Resolving once and giving up would leave the bus
# surface permanently dead on the common path — the loop retries until it attaches.
if [[ "$SOURCE" == "bus" && -z "$BUS_TOKEN" ]]; then
  die "--source bus, but no town-crier token is readable"
fi
if [[ -n "$BUS_TOKEN" ]]; then
  BUS_ID=$(bus_resolve_id) || BUS_ID=""
fi

if [[ -n "$BUS_ID" ]]; then
  surface="bus #$BUS_ID (reviews) + github (ci jobs, reviews)"
elif [[ -z "$BUS_TOKEN" ]]; then
  surface="github only (${BUS_WHY})"
else
  surface="github · bus pending — retrying until the review request lands"
fi
echo "[watch] PR #${PR_NUMBER} — ${PR_TITLE}"
echo "[watch] ${surface} · every ${INTERVAL}s · reporting changes only"

while true; do
  # Attach late. The row appears at dispatch, so on the common path this succeeds a tick or
  # two in. Announcing it matters: without a line, the bus surface coming up looks identical
  # to it never having existed, which is how a watch reads as covered while it is blind.
  if [[ -z "$BUS_ID" && -n "$BUS_TOKEN" ]]; then
    BUS_ID=$(bus_resolve_id) || BUS_ID=""
    if [[ -n "$BUS_ID" ]]; then
      echo "[bus] attached #${BUS_ID} — bus owns the review surface from here"
    else
      attach_ticks=$(( attach_ticks + 1 ))
      if [[ $attach_ticks -eq 20 ]]; then
        # The operator who asked for the bus BY NAME gets a failure, not a silent
        # degradation: 20 ticks (10 min at the default interval) is past any dispatch
        # delay, so a row still missing means this PR is not on the bus.
        if [[ "$SOURCE" == "bus" ]]; then
          echo "[end] --source bus: no open town-crier request for PR #${PR_NUMBER} after ${attach_ticks} ticks — not a PR outcome"
          ended=setup; exit 3
        fi
        echo "[warn] no town-crier row after ${attach_ticks} ticks — this PR may not be dispatched for review; github surface only so far"
      fi
    fi
  fi

  gh_json=$(gh_snapshot) || gh_json=""
  bus_json=""
  [[ -n "$BUS_ID" ]] && { bus_json=$(bus_snapshot) || bus_json=""; }

  if [[ -z "$gh_json" ]]; then
    fail_streak=$((fail_streak + 1))
    gh_why=$(tail -n 1 "$GH_ERR" 2>/dev/null)
    # --once has no later tick to speak on, so it says why here rather than exiting
    # 3 with nothing on stdout.
    if [[ $ONCE -eq 1 ]]; then
      echo "[warn] GitHub unreadable — nothing to report${gh_why:+ (${gh_why})}"
      ended=once; exit 3
    fi
    # 3 in a row is roughly a minute and a half at the default interval — past
    # any single flaky call, and worth a line before the quiet is mistaken for calm.
    if [[ $fail_streak -eq 3 || $((fail_streak % 20)) -eq 0 ]]; then
      echo "[warn] GitHub unreadable for ${fail_streak} ticks — still retrying, treat this watch as blind${gh_why:+ (${gh_why})}"
    fi
    sleep "$INTERVAL"; continue
  fi

  bus_live=0; [[ -n "$bus_json" ]] && bus_live=1
  if [[ -n "$BUS_ID" && -z "$bus_json" ]]; then
    bus_streak=$((${bus_streak:-0} + 1))
    if [[ $bus_streak -eq 3 ]]; then
      echo "[warn] bus row #${BUS_ID} unreadable for 3 ticks — github surface still live"
    fi
  else
    bus_streak=0
  fi

  cur=()
  merged="{$(sed -e 's/^{//' -e 's/}$//' <<<"$gh_json")$([[ -n "$bus_json" ]] && echo ",$(sed -e 's/^{//' -e 's/}$//' <<<"$bus_json")")}"
  if ! load_into_cur "$merged"; then
    fail_streak=$((fail_streak + 1))
    echo "[warn] snapshot could not be parsed — skipping this tick"
    [[ $ONCE -eq 1 ]] && { ended=once; exit 3; }
    sleep "$INTERVAL"; continue
  fi
  fail_streak=0

  if [[ $ONCE -eq 1 ]]; then
    echo "$merged"
    ended=once; exit 0
  fi

  if [[ ${#prev[@]} -gt 0 ]]; then
    emit_changes
  fi

  case "${cur[pr_state]-}" in
    MERGED) echo "[end] PR #${PR_NUMBER} MERGED — watch ends"; ended=terminal; exit 0 ;;
    CLOSED) echo "[end] PR #${PR_NUMBER} CLOSED — watch ends"; ended=terminal; exit 0 ;;
  esac

  if [[ "$HEARTBEAT_MIN" -gt 0 && $((SECONDS - last_heartbeat)) -ge $((HEARTBEAT_MIN * 60)) ]]; then
    echo "[hb]  alive · ci fail:'${cur[ci_fail]-}' pending:${cur[ci_pending]-?} · gate:${cur[gate]-n/a} findings:${cur[findings]-n/a}"
    last_heartbeat=$SECONDS
  fi

  for k in "${!cur[@]}"; do prev[$k]="${cur[$k]}"; done
  sleep "$INTERVAL"
done
