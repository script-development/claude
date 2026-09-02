---
name: lint-issues
description: |
  Orchestrates an issue-quality audit across the To Do and In Progress lanes. Fans out to the
  issue-linter agent in parallel (one agent per issue), then posts a summary comment to the
  designated audit issue. Use when the user invokes /lint-issues <audit_issue_key_or_id>.
  Requires an existing audit issue to receive the summary comment — the caller creates it first.
  Never touches In Review or Done issues.
---

# Lint Issues

Orchestrate a parallel issue-quality audit across To Do and In Progress: fan out to `issue-linter`
agents for every issue in those lanes, collect verdicts, and post a summary to the audit issue.

The lane titles below (`To Do`, `In Progress`, `In Review`, `Done`) are the Kendo defaults. If the
board uses different titles, substitute them — the rule is "lint the lanes where work has not yet
been reviewed, never the lanes past review".

## Guard: argument required

If no `audit_issue_key_or_id` argument was provided, stop immediately and tell the user:

> "An audit issue is required. Create a Kendo issue to collect the lint results, then re-run:
> `/lint-issues <key-or-id>`"

Do not proceed past this point without a valid argument.

## Step 1 — Resolve IDs (sequential)

**1a.** Call `mcp__kendo__prepare-issue-context-tool` with the provided key or ID.
Extract `issue.id` (`audit_issue_id`), `issue.key` (`audit_key`), and `issue.project_id`. If the
issue cannot be found, tell the user and stop.

**1b.** Call `mcp__kendo__prepare-project-context-tool` with `project_id` from 1a.
From the returned `lanes[]`, find the lane whose `title` is `"To Do"` and the lane whose `title`
is `"In Progress"`. Record both lane IDs. If either lane is not found, tell the user which lane is missing and stop.

## Step 2 — Fetch Target Lane Issues (parallel)

Fetch both lanes simultaneously — they are independent reads. `limit: 100` is the tool maximum;
the default is 25, which would miss most of the To Do backlog.

1. `mcp__kendo__search-issues-tool` — `project_id`, `lane_id: <To Do id>`, `limit: 100`
2. `mcp__kendo__search-issues-tool` — `project_id`, `lane_id: <In Progress id>`, `limit: 100`

**In Review and Done lanes are never fetched. Do not touch them under any circumstances.**

If either lane returns exactly 100 issues, warn the user before continuing, naming the specific
lane that hit the ceiling:
> "[To Do / In Progress] lane returned exactly 100 results — the lane may exceed the ceiling and
> some issues may have been missed. Proceed anyway or abort?"

If both lanes hit 100, mention both in one warning.

If a result is saved to a file because it exceeds the inline token limit, do NOT spawn a
subagent — read the file directly with the `Read` tool. The file is JSON with schema
`{issues: [{id, key, title, description, type, ...}]}`. Parse it and use the `issues` array
as if it had been returned inline.

If `Read` returns truncated content (default cap is 2000 lines), call `Read` again with `offset`
to continue from where the previous call ended, repeating until the JSON closes. Concatenate
the chunks before parsing.

Merge both result sets into a single flat list. Deduplicate by `id` if the same issue appears
in more than one response (should not happen, but guard against it). Then remove any issue whose `id` matches `audit_issue_id` — the audit issue is never a lint target.

## Step 3 — Fan Out to issue-linter Agents (parallel)

For each issue in the merged list, spawn one `issue-linter` agent.

**All agents must be spawned in a single parallel batch** — send every Agent tool call in one
message. Do not serialize, do not wait for one agent before launching the next.

Pass this prompt to each agent (substitute values per issue):

```
Grade and report suggested rewrites if necessary:

issue.id: <id>
issue.key: <key>
issue.title: <title>
issue.type: <type>
issue.description:
<description>

audit_issue_id: <audit_issue_id>
```

Each agent returns exactly one of:
- `**[key]** — PASS` (optionally suffixed ` — [n] non-blocking nits` when the issue is sound but has style nits)
- `**[key]** — FAIL — Flagged: [Section], [Section]`
- `**[key]** — RUBRIC NOT FOUND — cannot grade`

A FAIL now means at least one **hard** failure (missing required section, wrong type, untestable
AC, unfilled placeholder) — not a style nit. Issues that are structurally sound but carry only
advisory nits return PASS. This is deliberate: a FAIL should always be worth acting on.

Collect all return values. A FAIL agent will have already posted its own per-issue comment with
suggested rewrites to the audit issue — the orchestrator does not need to post individual failure
details, and no target issue is ever modified by the linter.

## Step 4 — Post Summary Comment to Audit Issue

Call `mcp__kendo__add-comment-tool` with `issue_id: <audit_issue_id>` and body:

```
Lint run complete — [total] issues checked

✓ Pass: [n]  (of which [k] carry non-blocking nits)
✗ Fail: [n]
⚠ Error (rubric not found): [n]

Passed issues: {{ISSUE_KEY_PREFIX}}-XXXX, {{ISSUE_KEY_PREFIX}}-XXXX, ...
Failed issues: {{ISSUE_KEY_PREFIX}}-XXXX, {{ISSUE_KEY_PREFIX}}-XXXX, ...
Error issues: {{ISSUE_KEY_PREFIX}}-XXXX, {{ISSUE_KEY_PREFIX}}-XXXX, ...

Top failure categories:
- [Section]: [n]
- [Section]: [n]

All [n] issues meet the writing standard.
```

- Omit `Passed issues:` if pass count is zero.
- Omit `Failed issues:` if fail count is zero.
- Omit `Error issues:` if error count is zero.
- Omit `Top failure categories:` if fail count is zero. Tally section names from the `Flagged:` suffix of each FAIL return value. List the top 5 at most, highest count first.
- The final line `All [n] issues meet the writing standard.` only appears when both fail and error counts are zero.

## Step 5 — Report to the User

Report the same totals and point the user to the audit issue for per-failure details:

```
Lint run complete — [total] issues checked

✓ Pass: [n]  ✗ Fail: [n]  ⚠ Error: [n]

Per-failure suggestions posted on [audit_key] — review and apply manually.
```

## Constraints

- **Parallel spawning is required.** All issue-linter agents fire in one batch. Never serialize.
- **In Review and Done lanes are never touched.** Never fetch them, never pass their issues to any agent.
- **Linter agents never mutate the target issue.** They only post suggestion comments to the audit issue.
- **Do not create the audit issue.** Receive it as input only.
- **Do not modify the audit issue itself.** Only post a summary comment to it — the linter agent
  handles per-issue suggestion comments.
