---
name: kendo-mcp
description: |
  MCP integration for kendo project management. Use when creating, updating, moving, or
  searching issues via MCP tools. Also use when writing user stories, logging time,
  managing epics (Goal, Done when wishes and their ticks, What done looks like),
  commenting on issues or epics, setting labels, linking branches to issues, recording token
  usage, reading error groups, or triaging reports (bug reports, feedback). Provides access to
  projects, issues, lanes, sprints, epics, labels, reports, and teams through MCP resources and tools.
---

# Kendo MCP

Manage issues using the Kendo MCP server. Works with any project hosted on your Kendo tenant.

## Setup

Before using these tools, ensure the Kendo MCP server is configured. See
[references/setup.md](references/setup.md) for installation instructions.

## Discovering Your Project

Before using project-scoped resources, find your project ID:

```
Read kendo://projects → find your project's ID and code
```

Use this ID for all `project_id` parameters and resource URIs below.

## MCP Resources (Read-Only)

| URI | Description |
|-----|-------------|
| `kendo://projects` | List the accessible active projects (archived ones are left out) |
| `kendo://projects/archived` | List the archived projects; every other resource still reads them |
| `kendo://projects/{id}` | One project, with its linked GitHub repositories |
| `kendo://projects/{id}/issues` | List issues in a project |
| `kendo://projects/{id}/lanes` | List board lanes |
| `kendo://projects/{id}/sprints` | List sprints (status: 0=Planned, 1=Active, 2=Completed) |
| `kendo://projects/{id}/epics` | List epics for a project: `get-epics-tool`'s list form plus `issues_count`, without issue rows |
| `kendo://projects/{id}/members` | List project members (for assignee_id) |
| `kendo://projects/{id}/github-repos` | List linked GitHub repositories |
| `kendo://issues/{id}` | Get a single issue with details; also takes a key (`kendo://issues/{{ISSUE_KEY_PREFIX}}-0042`) |
| `kendo://reports/{id}` | Get a single report with its attachments and triage status |
| `kendo://teams` | List teams and members |

## MCP Tools

### Issues

| Tool | Purpose |
|------|---------|
| `mcp__kendo__create-issue-tool` | Create new issue (`label_ids`, `blocked_by_ids`, `blocks_ids`: at most 500 each) |
| `mcp__kendo__bulk-create-issues-tool` | Create 1–25 issues in one call, all in the backlog and one lane. Rows take `title`, `description`, `priority`, `type` only; one malformed row rejects the whole call. Returns `keys` and per-row `failed` |
| `mcp__kendo__update-issue-tool` | Update issue fields (including lane changes via `lane_id`). Blocking lists replace the stored ones: omit to keep, `[]` to clear |
| `mcp__kendo__delete-issue-tool` | Delete issue (destructive) |
| `mcp__kendo__link-branch-tool` | Link a git branch to an issue (multi-repo: retry with a `repo_id` from the candidate-listing error) |
| `mcp__kendo__unlink-branch-tool` | Remove a git branch link from an issue (multi-repo: pass `repo_full_name` to disambiguate) |
| `mcp__kendo__prepare-project-context-tool` | Read-only bundle: returns `project + lanes + sprints (Planned/Active) + active_sprint shortcut + labels + members + members_count + current_user` in one call. Use as the gather step for any project-scoped flow (triage, board sync, branch creation, picking up an issue); replaces separate reads of `kendo://projects/{id}`, `kendo://projects/{id}/lanes`, `kendo://projects/{id}/sprints`, `kendo://projects/{id}/members`, plus the legacy `git config user.email` heuristic |
| `mcp__kendo__prepare-issue-context-tool` | Read-only bundle: returns `issue + epic` (full issue payload with comments, branches, attachments; the epic with its `goal`, description, derived status, `checks` and `wishes`). For project meta, fire `prepare-project-context-tool` in parallel — see the parallel-gather pattern below |
| `mcp__kendo__search-issues-tool` | Search, filter or count issues in one project — see [Search Issues](#search-issues) |
| `mcp__kendo__get-my-issues-tool` | Your assigned issues across all projects, done lane excluded (filter by `project_id`, `priority`, `type`, `query`). Capped at 500: check `truncated` |
| `mcp__kendo__kendo-today-tool` | Your Today snapshot in one read: active sprints, open issues per project, today's logged minutes. Prefer it over `get-my-issues` for "what's on my plate" |
| `mcp__kendo__start-work-on-issue-tool` | Idempotent one-call write: assigns user, moves to lane, optionally updates sprint, and links a git branch. The act step that pairs with the gather tools. The repo resolves when the project has exactly one; with several, retry with a `repo_id` from the candidate-listing error |

### Labels

| Tool | Purpose |
|------|---------|
| `mcp__kendo__get-labels-tool` | A project's labels (`id`, `name`, `color` 0–9, `order`). `prepare-project-context-tool` carries them too |
| `mcp__kendo__create-label-tool` | Create a label (`name` unique in the project, `color` 0–9) |
| `mcp__kendo__update-label-tool` | Rename or recolor a label |
| `mcp__kendo__delete-label-tool` | Delete a label; issues keep everything but the label (destructive) |
| `mcp__kendo__sync-issue-labels-tool` | Set an issue's labels: `label_ids` replaces the set exactly, `[]` clears it |

### Comments

Each comment tool names its subject with exactly one of `issue_id`, `issue_key` or `epic_id`; none,
or more than one, is refused.

| Tool | Purpose |
|------|---------|
| `mcp__kendo__add-comment-tool` | Comment on an issue or an epic (max 10,000 chars). `parent_id` replies to a top-level comment on the same subject; a reply to a reply is refused |
| `mcp__kendo__update-comment-tool` | Edit a comment. Find its ID in `kendo://issues/{id}`, or in `get-epics-tool` with `epic_id` |
| `mcp__kendo__delete-comment-tool` | Delete a comment and its attachments (destructive) |

Comments read back with `parent_id`, `is_pinned` and `liker_ids`. A comment on an issue notifies the
issue's watchers; epics have no watchers, so a comment on an epic notifies only the members it
mentions, and a reply its parent's author.

### Time and Token Usage

| Tool | Purpose |
|------|---------|
| `mcp__kendo__get-time-entries-tool` | Query time entries between `date_from` and `date_to` (filter by project, user, team, issue; group by user/project/team/issue/day, or `none` for raw entries, at most 100 with `has_more`). An entry counts on the day its work started |
| `mcp__kendo__create-time-entry-tool` | Log time on an issue: `minutes_spent` (at least 1), optional `started_at` and `note` |
| `mcp__kendo__update-time-entry-tool` | Correct your own entry: minutes, note, start, or move it to another issue in the project |
| `mcp__kendo__delete-time-entry-tool` | Delete your own entry (destructive) |
| `mcp__kendo__record-token-usage-tool` | Record one session's token usage for one model on an issue (`model`, `tokens_in`, `tokens_out`, optional cache counts). Pass `external_event_id` (`<session id>:<model>`) so a resend replaces instead of adding |

### Epics

| Tool | Purpose |
|------|---------|
| `mcp__kendo__get-epics-tool` | Get epics with their issues and progress (filter by derived `status`: 0=Open, 1=Closed). With `epic_id`, also the description, `checks`, `wishes` and comments — see [Epics in Detail](#epics-in-detail) |
| `mcp__kendo__create-epic-tool` | Create an epic: title, color, `goal`, `assignee_id`, dates, `issue_ids`, `checks`, `wishes` |
| `mcp__kendo__update-epic-tool` | Update an epic's fields, issues, `checks` or `wishes`. Status is derived, not set |
| `mcp__kendo__delete-epic-tool` | Delete an epic and its comments (destructive). Issues are kept. |
| `mcp__kendo__tick-epic-wish-tool` | Tick one Done when wish (`epic_id`, `wish_id`); records who and when |
| `mcp__kendo__untick-epic-wish-tool` | Untick one Done when wish; clears who and when |

### Sprints

| Tool | Purpose |
|------|---------|
| `mcp__kendo__create-sprint-tool` | Create a new sprint (title, start/end dates). Created as Planned. |
| `mcp__kendo__update-sprint-tool` | Update sprint title, dates, or status (partial updates supported) |
| `mcp__kendo__complete-sprint-tool` | Complete the active sprint, move incomplete issues to target sprint |
| `mcp__kendo__delete-sprint-tool` | Delete a Planned sprint; its issues leave the sprint (destructive) |
| `mcp__kendo__assign-issues-to-sprint-tool` | Bulk-assign up to 100 issues to a sprint (or `null` to clear). Prefer over looping `update-issue` when the only change is sprint membership |
| `mcp__kendo__get-sprints-tool` | List sprints for a project (all statuses, or filter by `status` 0/1/2). Use to resolve a sprint id by name before write operations, or to list Completed sprints (excluded from `prepare-project-context`). Optional `sprint_id` for a single sprint. |

### Reports

| Tool | Purpose |
|------|---------|
| `mcp__kendo__list-reports-tool` | List reports (bug reports, feedback) for a project with triage status: the last `limit` (default 20, max 500) of the triage queue. Pass `status: 0` for pending; check `truncated` |
| `mcp__kendo__get-report-tool` | One report by `report_id`, in the list's shape |
| `mcp__kendo__create-report-tool` | Create a new report (bug report, feature request, feedback) |
| `mcp__kendo__promote-reports-tool` | Promote/convert one or more reports into a single issue (core triage action) |
| `mcp__kendo__dismiss-report-tool` | Dismiss a report as not actionable (soft-archive). Requires a reason `category` (`not-planned` / `invalid` / `duplicate` / `already-shipped`), optional `note`; both are stored on the report. A second dismiss is refused |
| `mcp__kendo__delete-report-tool` | Delete a report permanently (destructive) |
| `mcp__kendo__send-feedback-tool` | Send feedback about Kendo itself to the Kendo team (`title`, `description`), from any tenant. Not for a project's own queue: that is `create-report-tool` |

### Error Groups

| Tool | Purpose |
|------|---------|
| `mcp__kendo__get-error-groups-tool` | Recurring exceptions captured from the apps, newest failure first, across accessible projects or one `project_id`. Filter by `environment`, `since_days`; `limit` default 20 (max 500). Stack traces only with `include_stack_trace: true` — pair it with a small `limit` |

### Attachments

| Tool | Purpose |
|------|---------|
| `mcp__kendo__fetch-attachment-tool` | Fetch attachment bytes by ID — returns image block for `image/*`, text block for `text/*` + `application/json`. Capped at 5 MB images / 500 KB text; binary types (PDF, zip, video) return an error with `download_url` fallback hint. |

## Common Operations

### Create Issue

```
project_id: <your-project-id>
title: "Clear descriptive title"
description: "Markdown content"
lane_id: <lane-id> (optional, defaults to first lane)
priority: 0-4 (0=Highest, 2=Medium default, 4=Lowest)
type: 0-2 (0=Feature, 1=Bug, 2=Task)
assignee_id: <user_id> (optional)
sprint_id: <sprint_id> (optional)
```

**Important:** The response includes both `id` (database ID, e.g. `206`) and `key` (display
reference, e.g. `PROJ-0142`). These are different values — always use `key` for branch names and
user-facing references, and `id` for API calls to other tools.

### Mentions in description / comment body

When writing `description` (create-issue-tool, update-issue-tool) or `content` (add-comment-tool, on an issue or an epic), a plain
`@Full Name` or unique `@FirstName` of a project member is resolved server-side into a
mention that notifies the named person. Ambiguous or unknown names stay as literal text —
no error is raised.

Applies to: `create-issue-tool`, `update-issue-tool`, `add-comment-tool`.

#### @Mention pre-processing

Before passing content to `create-issue-tool`, `update-issue-tool`, or `add-comment-tool`, scan the `description` / `content` argument for bare `@Name` patterns and pre-process them. This catches ambiguous names that the server would silently leave as literal text and lets the agent resolve them interactively.

**Prerequisite:** `members[]` must be in context from a prior `prepare-project-context-tool` call. If it is not, skip pre-processing entirely and write the content as-is — the server-side resolver is the fallback.

**What to scan:** every `@Name` token in prose — not inside fenced (` ``` `) or inline (`` ` ``) code spans, and not already in `[@ id="N"]` wire-format (those are already resolved).

**Matching policy** (mirrors the server-side resolver):
1. For each `@Name` token, compare case-insensitively against member full names first, then first names; evaluate longest candidate first.
2. A name qualifies only when it maps to **exactly one** member — any ambiguity disqualifies it from the unambiguous path.

**Unambiguous match** (one member maps to `@Name`): write `@Name` as-is. The server will resolve it; the agent may note in its reasoning that the mention is confirmed.

**Ambiguous match** (multiple members share the name): use `AskUserQuestion` with one question per ambiguous token. List all matching members as options plus a "none of these" option:
- User picks a member → rewrite that token to `[@ id="N"]` (server will render the chip; the person is notified)
- User picks "none of these" → leave the token as literal text

**Multiple ambiguous tokens:** handle one per `AskUserQuestion` call. If more than 4 ambiguous tokens appear in a single piece of content, ask in rounds of up to 4.

**`update-comment-tool` is excluded** — the server neither resolves nor notifies mentions on a comment update; pre-processing comment updates is a no-op.

### Move Issue (via update-issue)

```
issue_id: <issue-id>
lane_id: <target-lane-id>
```

### Link Branch

```
issue_id: <issue-id>          # or issue_key: "{{ISSUE_KEY_PREFIX}}-0042"
branch_name: "feature/my-branch"
# The repo resolves when the project has exactly one. With several, the call fails with a
# candidate list: retry with one of its repo_id values, or ask the user.
```

**Guard:** when the branch name already carries the issue key (e.g.
`feat/{{ISSUE_KEY_PREFIX}}-0003-target-context`), Kendo auto-links it — do not call `link-branch`
for that branch. Reserve the tool for branches whose name does not contain the key.

### Epics in Detail

An epic has a title, a color (`0`–`9`: Grey, Green, Blue, Red, Purple, Yellow, Orange, Teal, Pink,
Indigo; reads send `color_name` beside it), a **Goal** (`goal`, at most 500 characters, what the
epic delivers), a description (at most 65,535), `start` and `end` (sent together), an assignee
(`assignee_id`, a project member; a new assignee is notified unless they set it themselves),
`issue_ids`, and two ordered lists of at most 100 items of at most 500 characters:

- **Done when** (`wishes`): the customer's wishes. Each is ticked by hand, with
  `tick-epic-wish-tool`, and can link up to 100 issues of the same epic (`issue_ids`).
- **What done looks like** (`checks`): plain-text lines to verify the work against, labelled by
  habit `Proof: …` / `Browser look: …`. Never ticked, no links.

**Status is derived** (`status` 0=Open / 1=Closed, with `status_name`); no tool sets it. An epic
with wishes is Closed once every wish is ticked, even with issues still open. Without wishes, it
is Closed when it has issues and every one is in the project's last lane. `progress` counts issues
either way.

**Read one epic for the full picture.** The list form (`get-epics-tool` without `epic_id`, and
`kendo://projects/{id}/epics`) sends the goal, the status and the counts (`checks_count`,
`wishes_count`, `checked_wishes_count`), but no description, lists or comments. Pass `epic_id`
for those; each wish then carries its linked issues as `{id, key}`, `checked_at` and
`checked_by_id`.

**A list is saved whole.** `create-epic-tool` and `update-epic-tool` take `checks` and `wishes` as
the complete list, in order:

- An item sent with its `id` keeps its row, and a wish keeps its tick.
- An item without an `id` is created. A stored item left out is deleted, a wish with its tick.
- Omitting the key, or sending `null`, keeps the list; `[]` clears it. `issue_ids` works the same.
- Every issue a wish links must be in the epic once the call's own `issue_ids` apply. One wrong
  link, or an `id` from another list, rejects the whole call and nothing is stored.

So before sending a list on `update-epic-tool`, read the epic with `epic_id` and send every kept
item with its `id`. To change only the goal, dates, assignee or issues, leave both lists out. An
issue that leaves the epic loses its wish links; the wish keeps its text and its tick.

**Ticking.** `tick-epic-wish-tool` and `untick-epic-wish-tool` take `epic_id` and a `wish_id` from
the `epic_id` read. Both are idempotent: a second tick keeps the first ticker and time. Both answer
the wish and the epic's `status` and wish counts after the change, so ticking the last open wish
answers Closed. Saving an epic never ticks or unticks a wish.

```
# A new epic whose wishes link the issues the same call attaches
create-epic-tool  project_id: <your-project-id>, title: "Checkout", color: 2,
                  goal: "Customers pay for an order in one step.",
                  issue_ids: [<issue-a>, <issue-b>],
                  wishes: [{text: "The customer can pay by card", issue_ids: [<issue-a>]}],
                  checks: [{text: "Browser look: checkout on desktop and phone"}]
```

### Log Time

```
issue_id: <issue-id>          # or issue_key: "{{ISSUE_KEY_PREFIX}}-0042"
minutes_spent: 60             # At least 1
started_at: "2026-01-15"      # Optional: when the work started (ISO 8601)
note: "What was done"         # Optional
```

### Query Time Logs

```
date_from: "2026-01-01"
date_to: "2026-01-31"
group_by: "user"  # user, project, team, issue, day, or none
project_id: <your-project-id> (optional)
```

### Workflow

1. Read `kendo://projects` to find your project ID
2. Call `mcp__kendo__prepare-project-context-tool` to bundle lanes, active sprint, members, and the calling user
3. Use tools to create/update issues

### Parallel-gather pattern

When a flow needs **both** project meta and issue payload (e.g. "pick up issue {{ISSUE_KEY_PREFIX}}-0042"), fire
both gather tools in the same tool-call block — same wall-clock as one round-trip:

```
parallel:
  mcp__kendo__prepare-project-context-tool(project_id: <your-project-id>)
  mcp__kendo__prepare-issue-context-tool(issue_key: "{{ISSUE_KEY_PREFIX}}-0042")
```

Use only the project tool when no specific issue is in play (triage queue scan, board alignment
sweep). Use only the issue tool when project meta is already in context (commenting on an
existing issue you just looked up). The two tools are sized to be cheap to call independently.

### Get Issue by ID

Use `ReadMcpResourceTool` with `server: "kendo"` and `uri: "kendo://issues/{id}"` to fetch a single
issue directly; the URI takes a key too (`kendo://issues/{{ISSUE_KEY_PREFIX}}-0042`). This returns full details
including comments, branch links, blocking relations, and time spent. **Always prefer this over
searching when you have the issue ID or key.** Prefer
`prepare-issue-context-tool` when you have the key and want the gather bundle.

### Search Issues

Use `mcp__kendo__search-issues-tool` to find, filter or count issues in one project. `query` searches
title, description and issue key; it does not match on numeric database IDs.

- **Lists match any value.** `lane_ids`, `assignee_ids`, `sprint_ids`, `epic_ids`, `label_ids`,
  `priorities`, `types`. The scalar forms (`lane_id`, `priority`, …) still work and merge into the list.
- **`exclude_*` leaves issues out** (`exclude_lane_ids`, `exclude_types`, …). An exclusion wins over an
  inclusion of the same value.
- **`0` means none** in assignee, sprint and epic lists: unassigned, backlog, no epic. An exclusion keeps
  issues without a value unless `0` is in it, so `exclude_epic_ids: [0]` returns only issues with an epic.
- **`group_by` counts instead of listing** (`lane`, `assignee`, `sprint`, `epic`, `priority`, `type`,
  `label`). It returns `total` plus `groups` of `{key, label, count}`, uncapped; the "none" group has
  key `0`. Grouped by label the counts can sum above `total`.
- **`include_description: false`** drops each description. Use it for any list you only scan.
- **`limit`** is 1–100, default 25. Check `truncated` before treating a list as complete.

Each row names its lane, assignee, sprint and epic next to their IDs, carries `labels` as `{id, name}`,
and gives `priority_name` / `type_name` beside the numeric `priority` / `type`. Answer the user from the
names and feed the IDs to the next call — no `get-labels` round-trip is needed to name a label.

One call answers questions that used to take several:

```
# Open issues per lane, without Tasks. Nothing is excluded by default, so leave out the
# done lane yourself: it is the highest-order lane in prepare-project-context's lanes.
search-issues-tool  project_id: <your-project-id>, group_by: "lane", exclude_lane_ids: [<done lane>], exclude_types: [2]

# Unassigned bugs in the active sprint, light rows
search-issues-tool  project_id: <your-project-id>, sprint_ids: [<active>], assignee_ids: [0], types: [1], include_description: false
```

`mcp__kendo__get-my-issues-tool` rows name the lane, project, sprint and epic the same way and carry
`labels` as `{id, name}`, with `priority` / `type` as numbers and `priority_name` / `type_name`
beside them, as search does.

## References

| File | Content |
|------|---------|
| [setup.md](references/setup.md) | MCP server setup instructions |
| [issue-templates.md](references/issue-templates.md) | Issue templates (feature user story + bug report + task) — single source of truth, referenced by `/newbranch`, `/triage-reports`, `/plan-feature`, `/task-writer`, `/kendo-cli` |
