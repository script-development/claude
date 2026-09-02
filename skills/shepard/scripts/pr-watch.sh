#!/usr/bin/env bash
# pr-watch.sh — live watch on ONE pull request. Built for /shepard's Monitor tool:
# every stdout line becomes one chat notification, so the script prints ONLY
# changes, never a running status.
#
# Two surfaces, one tick, with the bus first among them:
#   GitHub  — PR state, head SHA, per-job check rollup (always). Its review/comment/
#             decision lines fire ONLY while no bus row is attached: the bus row is the
#             reviewer's own record and reporting both duplicates every round.
#   The bus — town-crier's ledger row: gate, trial, findings, reviewer (when the
#             PR is announced there and a token is readable). The row is created at
#             DISPATCH, which always lands after the PR opens, so the watch attaches on
#             a later tick and says so with "[bus] attached #<id>".
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
#   3  setup failure: no PR, missing dependency, unreadable repo
#
# The token is read from $TOWN_CRIER_TOKEN, else from $TOWN_CRIER_ENV_FILE
# (default ~/Code/crit/.env). It is never printed, and no line this script emits
# contains it. No token means no bus surface — not an error.
set -uo pipefail

command -v gh   >/dev/null || { echo "error: gh CLI required" >&2; exit 3; }
command -v jq   >/dev/null || { echo "error: jq required" >&2; exit 3; }
command -v curl >/dev/null || { echo "error: curl required" >&2; exit 3; }

INTERVAL=30
HEARTBEAT_MIN=30
SOURCE=auto
ONCE=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)  INTERVAL="${2:?--interval needs seconds}"; shift ;;
    --heartbeat) HEARTBEAT_MIN="${2:?--heartbeat needs minutes}"; shift ;;
    --source)    SOURCE="${2:?--source needs gh|bus|auto}"; shift ;;
    --once)      ONCE=1 ;;
    -*)          echo "error: unknown flag '$1'" >&2; exit 3 ;;
    *)           TARGET="$1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- resolve the PR

if [[ -z "$TARGET" ]]; then
  TARGET=$(git branch --show-current 2>/dev/null) || true
  [[ -z "$TARGET" ]] && { echo "error: no PR/branch argument and not on a branch" >&2; exit 3; }
fi

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  pr_json=$(gh pr view "$TARGET" --json number,url,title 2>/dev/null)
else
  pr_json=$(gh pr list --head "$TARGET" --json number,url,title --jq '.[0]' 2>/dev/null)
fi
[[ -z "${pr_json:-}" || "$pr_json" == "null" ]] && { echo "error: no PR found for '$TARGET'" >&2; exit 3; }

PR_NUMBER=$(jq -r .number <<<"$pr_json")
PR_URL=$(jq -r .url <<<"$pr_json")
PR_TITLE=$(jq -r .title <<<"$pr_json")

# ------------------------------------------------------------------- bus access

read_env_key() {
  [[ -f "$1" ]] || return 1
  sed -n -E "s/^[[:space:]]*$2=[\"']?([^\"'#[:space:]]+).*/\1/p" "$1" | tail -1
}

BUS_ENV_FILE="${TOWN_CRIER_ENV_FILE:-$HOME/Code/crit/.env}"
BUS_TOKEN="${TOWN_CRIER_TOKEN:-$(read_env_key "$BUS_ENV_FILE" TOWN_CRIER_TOKEN 2>/dev/null)}"
BUS_URL="${TOWN_CRIER_URL:-$(read_env_key "$BUS_ENV_FILE" TOWN_CRIER_URL 2>/dev/null)}"
BUS_URL="${BUS_URL:-https://town-crier-mcp.fly.dev}"
BUS_URL="${BUS_URL%/}"

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
  for status in open in_review done; do
    body=$(curl -sS --max-time 20 "$BUS_URL/api/review-requests?status=$status&limit=200" \
      -H "authorization: Bearer $BUS_TOKEN" -H 'accept: application/json' 2>/dev/null) || continue
    id=$(jq -r --arg url "$PR_URL" '.requests[]? | select(.pr_url == $url) | .id' <<<"$body" 2>/dev/null | head -1)
    [[ -n "$id" ]] && { echo "$id"; return 0; }
  done
  return 1
}

# --------------------------------------------------------------------- snapshots

# One compact JSON object per surface. Keys are stable; a missing surface
# contributes nothing, so a bus outage cannot look like a bus change.
gh_snapshot() {
  local raw
  raw=$(gh pr view "$PR_NUMBER" --json state,headRefOid,statusCheckRollup,reviews,comments,reviewDecision 2>/dev/null) || return 1
  [[ -z "$raw" ]] && return 1
  jq -c '
    ([.statusCheckRollup[]? | {n: (.name // .context // "?"), c: (.conclusion // .state // "PENDING")}]) as $checks
    | {
        pr_state:   (.state // "?"),
        head:       ((.headRefOid // "") | .[0:8]),
        decision:   (if ((.reviewDecision // "") == "") then "NONE" else .reviewDecision end),
        reviews:    ((.reviews // []) | length),
        comments:   ((.comments // []) | length),
        ci_fail:    ([$checks[] | select(.c == "FAILURE" or .c == "TIMED_OUT" or .c == "CANCELLED" or .c == "ERROR") | .n] | sort | join(",")),
        ci_pending: ([$checks[] | select(.c == "PENDING" or .c == "IN_PROGRESS" or .c == "QUEUED" or .c == "EXPECTED")] | length),
        ci_pass:    ([$checks[] | select(.c == "SUCCESS")] | length)
      }' <<<"$raw" 2>/dev/null
}

bus_snapshot() {
  [[ -z "$BUS_TOKEN" || -z "$BUS_ID" ]] && return 1
  local raw
  raw=$(curl -sS --max-time 20 "$BUS_URL/api/review-requests/$BUS_ID" \
    -H "authorization: Bearer $BUS_TOKEN" -H 'accept: application/json' 2>/dev/null) || return 1
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
      findings:     ((.open_finding_counts // {}) | "\(.blocker // 0)/\(.major // 0)/\(.minor // 0)/\(.nit // 0)"),
      lock:         (.locked_by // "")
    }' <<<"$raw" 2>/dev/null
}

# ------------------------------------------------------------------ change lines

declare -A prev=()
declare -A cur=()

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

  if changed bus_reviews && [[ "${cur[bus_reviews]-0}" -gt "${prev[bus_reviews]-0}" ]]; then
    echo "[bus] review $(now bus_reviews) by ${cur[reviewer]:-?} — findings $(now findings) (b/m/n/nit) · gate $(now gate)$head_note"
  elif changed findings; then
    echo "[bus] findings $(was findings) -> $(now findings) (b/m/n/nit)$head_note"
  fi
  changed gate       && echo "[bus] gate $(was gate) -> $(now gate)$head_note"
  changed trial      && echo "[bus] trial (ci-passed) $(was trial) -> $(now trial)"
  changed bus_status && echo "[bus] request status $(was bus_status) -> $(now bus_status)"
  changed conflict   && [[ "${cur[conflict]-}" != "clean" ]] && echo "[bus] merge conflict: $(now conflict)"

  changed ci_fail && {
    if [[ -n "${cur[ci_fail]-}" ]]; then
      echo "[ci]  FAILING: ${cur[ci_fail]}  (pass ${cur[ci_pass]-?} · pending ${cur[ci_pending]-?})"
    else
      echo "[ci]  all red checks cleared (pass ${cur[ci_pass]-?} · pending ${cur[ci_pending]-?})"
    fi
  }
  # The PR head is GitHub's alone and always reported: `bus_head` is the head the reviewer
  # READ, and the STALE note above is the comparison of the two.
  changed head     && [[ -n "${prev[head]-}" ]] && echo "[pr]  head moved $(was head) -> $(now head)"

  # The bus owns the review surface once attached. Its row is the reviewer's own record —
  # gate, findings and verdict in one read — while GitHub only counts reviews and comments.
  # Reporting both duplicates every round as [bus] review N and [pr] +1 GitHub review(s),
  # so these three degrade to the bus and fire only where there is no bus row to own them.
  if [[ -z "$BUS_ID" ]]; then
    changed decision && echo "[pr]  review decision $(was decision) -> $(now decision)"
    if changed reviews && [[ "${cur[reviews]-0}" -gt "${prev[reviews]-0}" ]]; then
      echo "[pr]  +$(( ${cur[reviews]-0} - ${prev[reviews]-0} )) GitHub review(s)"
    fi
    if changed comments && [[ "${cur[comments]-0}" -gt "${prev[comments]-0}" ]]; then
      echo "[pr]  +$(( ${cur[comments]-0} - ${prev[comments]-0} )) comment(s)"
    fi
  fi
}

# ---------------------------------------------------------------------- the loop

fail_streak=0
attach_ticks=0
last_heartbeat=$SECONDS
ended=""

on_exit() {
  # Silence must never be the only report. Any end — killed, crashed, terminal —
  # says so on stdout, so a dead watch is distinguishable from a quiet PR.
  [[ -n "$ended" ]] && return
  echo "[end] watch on PR #${PR_NUMBER} stopped (signal or timeout) — not a PR outcome"
}
trap on_exit EXIT

# The bus row is created when the PR is DISPATCHED for review, and dispatch always lands
# after the PR itself opens. A watch armed at PR-open time is therefore early BY DESIGN and
# this first resolve normally misses. Resolving once and giving up would leave the bus
# surface permanently dead on the common path — the loop retries until it attaches.
if [[ "$SOURCE" != "gh" && -n "$BUS_TOKEN" ]]; then
  BUS_ID=$(bus_resolve_id) || BUS_ID=""
fi
if [[ "$SOURCE" == "bus" && -z "$BUS_TOKEN" ]]; then
  echo "error: --source bus, but no town-crier token is readable" >&2
  ended=setup; exit 3
fi

if [[ -n "$BUS_ID" ]]; then
  surface="bus #$BUS_ID (reviews) + github (ci jobs)"
elif [[ "$SOURCE" == "gh" ]]; then
  surface="github only (--source gh)"
elif [[ -z "$BUS_TOKEN" ]]; then
  surface="github only (no town-crier token)"
else
  surface="github · bus pending — retrying until the review request lands"
fi
echo "[watch] PR #${PR_NUMBER} — ${PR_TITLE}"
echo "[watch] ${surface} · every ${INTERVAL}s · reporting changes only"

while true; do
  # Attach late. The row appears at dispatch, so on the common path this succeeds a tick or
  # two in. Announcing it matters: without a line, the bus surface coming up looks identical
  # to it never having existed, which is how a watch reads as covered while it is blind.
  if [[ -z "$BUS_ID" && "$SOURCE" != "gh" && -n "$BUS_TOKEN" ]]; then
    BUS_ID=$(bus_resolve_id) || BUS_ID=""
    if [[ -n "$BUS_ID" ]]; then
      echo "[bus] attached #${BUS_ID} — bus owns the review surface from here"
    else
      attach_ticks=$(( attach_ticks + 1 ))
      if [[ $attach_ticks -eq 20 ]]; then
        echo "[warn] no town-crier row after ${attach_ticks} ticks — this PR may not be dispatched for review; github surface only so far"
      fi
    fi
  fi

  gh_json=$(gh_snapshot) || gh_json=""
  bus_json=""
  [[ -n "$BUS_ID" ]] && { bus_json=$(bus_snapshot) || bus_json=""; }

  if [[ -z "$gh_json" ]]; then
    fail_streak=$((fail_streak + 1))
    # 3 in a row is roughly a minute and a half at the default interval — past
    # any single flaky call, and worth a line before the quiet is mistaken for calm.
    if [[ $fail_streak -eq 3 || $((fail_streak % 20)) -eq 0 ]]; then
      echo "[warn] GitHub unreadable for ${fail_streak} ticks — still retrying, treat this watch as blind"
    fi
    [[ $ONCE -eq 1 ]] && { ended=once; exit 3; }
    sleep "$INTERVAL"; continue
  fi

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
