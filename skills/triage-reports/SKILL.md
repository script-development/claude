---
name: triage-reports
description: |
  Triage incoming reports (bug reports, feedback, feature requests) from the Kendo report queue.
  Fetches pending reports via MCP, cross-references with existing open issues to find overlaps,
  then walks the user through each report one-by-one using AskUserQuestion for a verdict: promote
  to issue, dismiss, or combine with another report. Promoted reports get proper user stories
  or bug reports following project conventions. Use this skill whenever the user mentions "triage",
  "triage reports", "check reports", "process feedback", "review reports", "incoming reports",
  "report queue", "what reports do we have", or any variant of wanting to process the Kendo
  report queue. Also trigger when the user asks about unprocessed feedback or pending bug reports.
---

# Report Triage

Walk through pending Kendo reports one-by-one, cross-reference with existing issues, and let the user decide what to do with each one.

## Prerequisites

Load the `kendo-mcp` skill for MCP resource URIs and tool references. Issue templates (feature user story + bug report) live in [`../kendo-mcp/references/issue-templates.md`](../kendo-mcp/references/issue-templates.md) — promoted reports must follow them.

If your project ships a domain glossary (e.g. `CONTEXT.md`), read it before triaging — promoted issues should use canonical terms, and a report's wording may need to be flagged back to the user when it conflicts with the glossary. The promotion semantics are universal across consumers: a promoted report becomes a *new* issue record with a fresh `{{ISSUE_KEY_PREFIX}}-XXXX` key, not a relabel.

## Why This Exists

Reports flow in from users via the feedback widget and API. They pile up as unstructured feedback and need human judgment to become actionable issues. This skill turns that into an efficient per-report decision flow instead of a wall of text.

## Step 1: Gather Data (parallel)

Fetch all of these simultaneously:

1. **Pending reports**: `mcp__kendo__list-reports-tool` with `project_id: {{PROJECT_ID}}, status: 0` (0=Pending — the tool filters server-side so the response contains only pending reports)
2. **Lanes**: `kendo://projects/{{PROJECT_ID}}/lanes` (to identify lane IDs)
3. **Sprints**: `kendo://projects/{{PROJECT_ID}}/sprints` (to identify active sprint)
4. **Members**: `kendo://projects/{{PROJECT_ID}}/members` (for assignee lookup)

## Step 2: Confirm Pending Count

Show the user the count of pending reports returned by the tool:

> "Found N pending reports. Let me cross-reference with existing issues."

If zero pending reports, tell the user the queue is clean and stop.

## Step 3: Fetch Existing Open Issues

Search for existing issues to cross-reference against. Fetch in parallel:

1. **Active sprint issues**: `mcp__kendo__search-issues-tool` filtered by active sprint (status=1)
2. **Backlog issues**: `mcp__kendo__search-issues-tool` filtered by To Do lane (lane_id from Step 1)

Use `jq` to extract key fields: issue key, title, lane, sprint, type, priority.

These are used as context for overlap detection — nothing more. **Never suggest reopening, updating, or appending to Done issues.** Done issues are closed chapters. They can inform whether a report was already addressed, but are never targets for modification.

## Step 4: Per-Report Interrogation

Go through each pending report one at a time using `AskUserQuestion`. This is the core of the skill — the user makes every decision, not the model.

### For each report:

1. **Read the report** — understand what the user is actually describing
2. **Quick investigation** — two things in parallel:
   - **Issue overlap**: search existing open issues by keywords from the report. Done issues can be mentioned as context ("this was addressed by `{{ISSUE_KEY_PREFIX}}-XXXX` which shipped") but never as targets.
   - **Codebase context**: do a lightweight search of the relevant area of the codebase (the component, page, or feature the report mentions) so you understand what the current behavior actually is. This prevents bad recommendations — a report saying "X doesn't work" means nothing until you know how X currently works. Keep it to a few Grep/Glob calls, not a deep dive. The goal is to understand the current state, not to plan a fix.
3. **Present via AskUserQuestion** — one question per report with:
   - The report summary: who reported it, what they said, any attachments
   - What you found: relevant open issues, whether this seems like a duplicate
   - Your recommendation as the first option (marked "Recommended")
   - 2-3 clear options: Promote / Dismiss / Combine with #XX

### Investigation depth

Keep it lightweight — enough to judge, not enough to fix. The goal is to make a triage decision, not to analyze the codebase. Only dig deeper if the user explicitly asks ("research this further", "I think you got this wrong").

When the user asks for deeper investigation, use an Explore agent to research the specific area of the codebase and come back with findings before re-presenting the question.

### Handling user input

The user may:

- Pick an option directly — proceed
- Pick an option with notes — incorporate their context into the next step
- Reject all options — re-ask with adjusted options based on their feedback
- Provide design direction (e.g., "add a checkbox with localStorage") — capture this in the issue description when promoting
- Correct your understanding ("I think you got this wrong") — investigate further before re-presenting
- Ask to assign to someone — use project members from Step 1 to find the user ID

### Combining reports

When two reports describe the same thing, present them together in one AskUserQuestion. If the user confirms they should be combined, promote them together using a single `mcp__kendo__promote-reports-tool` call with multiple `report_ids`. The second report gets dismissed automatically when promoted as part of the batch.

If reports seem similar but the user says they're actually different issues (different aspect of the same area), promote them separately.

## Step 5: Execute Verdicts

Collect all verdicts during the interrogation phase, then execute them in batch at the end. This is faster and allows parallel execution of promotes and dismissals. Track decisions in a local list as you go through Step 4, then fire all MCP calls together.

### Promoting a report

Use `mcp__kendo__promote-reports-tool` with a properly written issue body that follows [`../kendo-mcp/references/issue-templates.md`](../kendo-mcp/references/issue-templates.md):

- **Features (`type: 0`)** — feature user story template (User Story + Context + Acceptance Criteria + Scope + Testing).
- **Bugs (`type: 1`)** — bug-report template (Problem + Steps to reproduce + Expected/Actual + Testing).

Include any design decisions the user made during triage in the description (e.g., "opt-in checkbox with localStorage persistence").

**Priority mapping:**

- Blocks core functionality for users → High (1)
- Functional bug or significant UX improvement → Medium (2)
- Minor styling, low-impact UX, nice-to-have → Low (3)

**Parameters:**

- `project_id`: `{{PROJECT_ID}}`
- `lane_id`: the To Do lane id from Step 1
- `assignee_id`: only if the user explicitly says who to assign it to
- `sprint_id`: omit unless user explicitly says to add to a sprint

### Dismissing a report

Use `mcp__kendo__dismiss-report-tool` with the `report_id`.

No confirmation needed — the user already confirmed via AskUserQuestion.

## Step 6: Summary

After all reports are processed, show a summary table:

```markdown
### Dismissed (N)
| Report | Reason |
|--------|--------|
| #XX | [brief reason] |

### Promoted (N)
| Issue | Report | Type | Priority | Assignee |
|-------|--------|------|----------|----------|
| {{ISSUE_KEY_PREFIX}}-XXXX | #XX | Bug/Feature | High/Medium/Low | [name or —] |
```

## Edge Cases

- **Very large report list (>30 pending)**: Ask the user if they want to process all of them or focus on a specific date range or reporter.
- **Report with attachments**: Mention the attachment count — the user may want to view them before deciding (use `mcp__kendo__fetch-attachment-tool` to inspect images / text bytes inline).
- **Vague/terse reports**: Present as-is and let the user decide. Don't dismiss reports just because they lack detail — the user may know context you don't.
- **User provides context not in the report**: Incorporate their knowledge into the promoted issue description. The user often knows exactly what a terse report means.
- **Multi-project consumers**: The user may specify a different `project_id`. Default to `{{PROJECT_ID}}` and respect any project specification.
