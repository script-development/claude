#!/usr/bin/env bash
# ci-failures.sh — one-shot CI snapshot for a PR: per-job status plus trimmed
# logs of every failed step. Runs are resolved by the PR's head SHA, so a
# just-pushed commit never reads the previous run's logs.
#
# Usage:
#   ci-failures.sh              PR for the current branch
#   ci-failures.sh 1478         explicit PR number
#   ci-failures.sh some-branch  explicit head branch
#   ci-failures.sh --run <id>   inspect one specific workflow run (any SHA)
#   ci-failures.sh --full       print failed-step logs untrimmed
#
# Exit codes:
#   0  all runs completed green
#   1  at least one failed job (run may still be in progress)
#   2  in progress, nothing failed yet
#   3  no PR / no runs / missing dependency
set -uo pipefail

command -v gh >/dev/null || { echo "error: gh CLI required" >&2; exit 3; }
command -v jq >/dev/null || { echo "error: jq required" >&2; exit 3; }

FULL=0
TARGET=""
RUN_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) FULL=1 ;;
    --run)  RUN_ID="${2:?--run needs a run id}"; shift ;;
    *)      TARGET="$1" ;;
  esac
  shift
done

# Failed-step logs are trimmed to first+last lines: the head identifies the
# command that ran, and every checker CI runs (test runners, type checkers,
# linters, formatters) prints its failure summary at the end.
HEAD_LINES=10
TAIL_LINES=140

if [[ -n "$RUN_ID" ]]; then
  runs=$(gh run view "$RUN_ID" --json databaseId,workflowName,status,conclusion --jq '[.]' 2>/dev/null)
  [[ -z "${runs:-}" ]] && { echo "error: run '$RUN_ID' not found" >&2; exit 3; }
  echo "Inspecting single run ${RUN_ID}"
else
  if [[ -z "$TARGET" ]]; then
    TARGET=$(git branch --show-current 2>/dev/null) || true
    [[ -z "$TARGET" ]] && { echo "error: no PR/branch argument and not on a branch" >&2; exit 3; }
  fi

  if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    pr_json=$(gh pr view "$TARGET" --json number,title,headRefOid,headRefName,url 2>/dev/null)
  else
    pr_json=$(gh pr list --head "$TARGET" --json number,title,headRefOid,headRefName,url --jq '.[0]' 2>/dev/null)
  fi
  [[ -z "${pr_json:-}" || "$pr_json" == "null" ]] && { echo "error: no PR found for '$TARGET'" >&2; exit 3; }

  pr_number=$(jq -r .number <<<"$pr_json")
  pr_title=$(jq -r .title <<<"$pr_json")
  sha=$(jq -r .headRefOid <<<"$pr_json")
  branch=$(jq -r .headRefName <<<"$pr_json")

  echo "PR #${pr_number} — ${pr_title}"
  echo "Branch: ${branch} @ ${sha:0:9}"

  local_head=$(git rev-parse HEAD 2>/dev/null) || true
  if [[ -n "${local_head:-}" && "$local_head" != "$sha" ]]; then
    echo "WARNING: local HEAD (${local_head:0:9}) differs from PR head — fixes would be diagnosed against code you don't have checked out."
  fi

  runs=$(gh run list --commit "$sha" --json databaseId,workflowName,status,conclusion --limit 20)
  if [[ $(jq length <<<"$runs") -eq 0 ]]; then
    echo "error: no workflow runs found for ${sha:0:9} (CI may not have started yet)" >&2
    exit 3
  fi
fi

any_failed=0
any_running=0
failed_jobs=()   # "jobId<TAB>jobName" of every failed job across all runs

# Both read loops strip a trailing \r off the last field: jq on Windows opens
# stdout in text mode and emits CRLF, and `read` splits on \n only, so the CR
# would ride along. That silently broke every `case "$conclusion"` — `failure`
# never matched, so failed_jobs stayed empty and the failure logs (this script's
# whole point) were never fetched, while the run-level check below flipped green
# runs to FAILING. Command substitution is unaffected; MSYS bash trims CRLF
# there, which is why $sha and friends were always clean. trim_logs already
# strips \r for the same reason.
#
# Stripped in bash rather than piped through `tr`: a process substitution's exit
# status is never seen by the consuming `while read`, so an unavailable `tr`
# would feed both loops zero records and land on Status: GREEN, exit 0 — the
# exact false-green this script exists to prevent (PR #1977 review).
while IFS=$'\t' read -r run_id workflow status conclusion; do
  conclusion=${conclusion%$'\r'}
  echo
  echo "Run: ${workflow} (${run_id}) — ${status}${conclusion:+: ${conclusion}}"
  [[ "$status" != "completed" ]] && any_running=1

  jobs=$(gh run view "$run_id" --json jobs --jq '.jobs')
  while IFS=$'\t' read -r job_id job_name job_status job_conclusion; do
    job_conclusion=${job_conclusion%$'\r'}
    case "$job_conclusion" in
      success)        echo "  ok    ${job_name}" ;;
      failure)        echo "  FAIL  ${job_name}"
                      any_failed=1
                      failed_jobs+=("${job_id}	${job_name}") ;;
      cancelled)      echo "  CANC  ${job_name}"; any_failed=1 ;;
      skipped)        echo "  skip  ${job_name}" ;;
      "")             echo "  ...   ${job_name} (${job_status})" ;;
      *)              echo "  ${job_conclusion}  ${job_name}" ;;
    esac
  done < <(jq -r '.[] | [.databaseId, .name, .status, .conclusion] | @tsv' <<<"$jobs")

  # A run can fail with zero failed jobs (startup_failure, cancelled at run level)
  if [[ "$conclusion" != "" && "$conclusion" != "success" && ${#failed_jobs[@]} -eq 0 ]]; then
    any_failed=1
  fi
done < <(jq -r '.[] | [.databaseId, .workflowName, .status, .conclusion] | @tsv' <<<"$runs")

# Strip gh's job/step prefixes, timestamps, and ANSI codes; group lines per
# failed step; bound each group to HEAD_LINES + TAIL_LINES unless --full.
trim_logs() {
  sed -E -e $'s/\x1b\\[[0-9;?]*[A-Za-z]//g' -e $'s/\r$//' \
  | awk -F'\t' -v head_n="$HEAD_LINES" -v tail_n="$TAIL_LINES" -v full="$FULL" '
    {
      if (NF >= 3) {
        key = $1 " > " $2
        line = $3
        for (i = 4; i <= NF; i++) line = line "\t" $i
        sub(/^\357\273\277/, "", line)  # GitHub log files start with a UTF-8 BOM
        sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:.]*Z ?/, "", line)
      } else {
        key = "(raw)"
        line = $0
      }
      if (!(key in count)) order[++nkeys] = key
      count[key]++
      buf[key, count[key]] = line
    }
    END {
      max = head_n + tail_n
      for (k = 1; k <= nkeys; k++) {
        key = order[k]; n = count[key]
        if (!full && n > max)
          printf "\n--- %s  (%d lines, showing first %d + last %d) ---\n", key, n, head_n, tail_n
        else
          printf "\n--- %s  (%d lines) ---\n", key, n
        if (full || n <= max) {
          for (i = 1; i <= n; i++) print buf[key, i]
        } else {
          for (i = 1; i <= head_n; i++) print buf[key, i]
          printf "... %d lines omitted (--full for everything) ...\n", n - max
          for (i = n - tail_n + 1; i <= n; i++) print buf[key, i]
        }
      }
    }'
}

if [[ ${#failed_jobs[@]} -gt 0 ]]; then
  echo
  echo "================ FAILURE LOGS ================"
  for entry in "${failed_jobs[@]}"; do
    job_id="${entry%%	*}"
    job_log=$(gh run view --job "$job_id" --log-failed 2>/dev/null)
    if [[ -z "$job_log" ]]; then
      echo
      echo "--- ${entry#*	} ---"
      echo "(logs not yet available — job may still be uploading; retry shortly)"
    else
      trim_logs <<<"$job_log"
    fi
  done
fi

echo
if [[ $any_failed -eq 1 ]]; then
  [[ $any_running -eq 1 ]] && echo "Status: FAILING (run still in progress — more results may come)" \
                           || echo "Status: FAILING"
  if [[ ${#failed_jobs[@]} -gt 0 ]]; then
    echo "Full logs:"
    for entry in "${failed_jobs[@]}"; do
      printf '  gh run view --job %s --log-failed   # %s\n' "${entry%%$'\t'*}" "${entry#*$'\t'}"
    done
  else
    # Run-level failure (startup_failure, cancelled) — no job ids to name.
    echo "Full logs: gh run view --job <job-id> --log-failed"
  fi
  exit 1
elif [[ $any_running -eq 1 ]]; then
  echo "Status: RUNNING — no failures yet"
  exit 2
else
  echo "Status: GREEN"
  exit 0
fi
