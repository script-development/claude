---
name: triage-reports
description: |
  Triage incoming reports (bug reports, feedback, feature requests) from the Kendo report queue.
  Decides the *right response* to each piece of user signal — most of which is not a new issue.
  Fetches pending reports via MCP, loads the project's product context (personas, positioning,
  decision principles) as a product-fit oracle, cross-references existing issues, then walks the
  user through each report one-by-one with AskUserQuestion for a verdict: Promote, Combine/Epic,
  Park, or Dismiss (always with a recorded reason). Promoted reports become correctly-typed issues
  (Feature / Bug / Task) written against the canonical issue templates. Use whenever the user
  mentions "triage", "triage reports", "check reports", "process feedback", "review reports",
  "incoming reports", "report queue", "what reports do we have", or any variant of wanting to
  process the Kendo report queue. Also trigger when the user asks about unprocessed feedback or
  pending bug reports.
---

# Report Triage

Walk through pending Kendo reports one-by-one and decide the right response to each. Promotion is
**one** of four outcomes — not the default gravity. The user makes every call; the model gathers
the evidence and recommends.

## Prerequisites

- Load the `kendo-mcp` skill for MCP resource URIs, tool references, and — critically — the
  **canonical issue templates** at
  [`../kendo-mcp/references/issue-templates.md`](../kendo-mcp/references/issue-templates.md). That
  file is the single source of truth for Feature (user story), Bug (cause-known / repro-first), and
  **Task** formats. This skill does **not** carry its own copies — always write promoted issues
  against the canonical templates so they match every other issue in the backlog.
- A **product-context source** is the fit oracle for the "do we want this?" decision — see
  Step 0. If the repo ships a product-context skill (company docs, positioning, personas) or a
  product docs folder, that is the oracle. If it ships neither, the user is the oracle.
- If your project ships a domain glossary (e.g. `CONTEXT.md`), read it before triaging —
  especially any **Report → Issue** promotion semantics. The semantics are universal across
  consumers: a promoted report becomes a *new* issue with a fresh `{{ISSUE_KEY_PREFIX}}-XXXX` key,
  not a relabel. Use the canonical terms in any issue you promote, and flag a term back to the user
  if their phrasing conflicts.
- Read `docs/triage/decisions.md` — the **dismissal log**. The path is a repo convention shared
  by every consumer of this skill; keep it so the log is found in the same place everywhere. Every
  Dismiss records a reason there, and its **Declined patterns** section lists reusable "we don't
  do this" rules to match new reports against (Step 1). If the file does not exist yet, create it
  from [`references/decisions-log-template.md`](references/decisions-log-template.md) on the first
  Dismiss.

## Why This Exists

Reports are raw user signal — bug reports, feature requests, confusion, praise. **Most signal is
not a new issue.** Some describes a real defect (→ issue). Some is a good idea aligned with where
the product is going (→ issue). But plenty is a valid request that is off-strategy, premature, a
support question, a duplicate, or noise.

The job of this skill is to decide the *right response* to each one — and to make that decision
defensible against the product's direction, not just convert everything into board clutter. The
old flow was a conversion funnel (Promote / Dismiss / Combine) that biased toward turning every
report into an issue. This flow is a judgment process.

## Verdicts (the four outcomes)

| Verdict | Meaning | Backend action |
|---------|---------|----------------|
| **Promote** | Real signal, we want it, now | `promote-reports` (correctly typed, canonical template) |
| **Combine / Epic** | Duplicate → one issue; thematic cluster (≥3) → epic | `promote-reports` batch, or `create-epic` + promote into it (`epic_id`) |
| **Park** | Not deciding now — leave it alone | **No backend call, no record.** Report stays Pending and resurfaces next run. The deliberate "decide later" bucket (a better mechanism is a future call). |
| **Dismiss (+ reason)** | Not becoming work: off-strategy / noise / duplicate / already-shipped / not-a-product-change | `dismiss-report` — **always record the reason** in the dismissal log |

> **There is no separate "Decline".** A valid-but-unwanted request (off-strategy) is just a
> **Dismiss** whose *reason* is "off-strategy" — the verdict is the same archive action, the
> nuance lives in the recorded reason. "Off-strategy", "noise", "already-shipped", and
> "not-a-product-change" are reason values, not distinct verdicts.
>
> **Every Dismiss records a reason.** The Kendo report queue stores no dismissal reason today, so
> `docs/triage/decisions.md` is the interim home. If the product grows a `triage_reason` field on
> the report itself, the ledger is retired in favour of it. A Dismiss is never a silent black hole.

## Step 0: Load product context (the fit oracle)

The oracle for the "do we want this?" decision. Load the repo's product-context source and pull:

- **Target personas / end-user roles** — who the product is for.
- **Positioning** — what the product deliberately is and is not, especially versus the
  alternatives it competes with. Surface area we deliberately don't chase.
- **Product decision principles** — the tie-breakers for product calls.

Where to find it, in order of preference:

1. A **product-context skill** in the repo (e.g. a company-docs or product-docs skill). Invoke it
   and pull only the docs you need.
2. A **product docs folder** (`docs/product/`, a positioning or personas doc). Read the relevant
   file(s).
3. **Neither exists** — ask the user for product fit at the point of decision (Step 4.5). Say
   plainly that the repo has no product-context source, so the fit judgement is theirs, and
   suggest recording the answer as a Declined pattern or a product doc so the next run has an
   oracle.

**Fetch lazily and narrowly.** Only pull the oracle when the queue actually contains a
fit-ambiguous feature, and fetch only the doc(s) you need (e.g. just the auth decision doc for a
security ask) rather than all of positioning + personas + principles every time. A bug-only or
task-only queue needs none of this. When you do fetch, summarise the relevant points in-context
and cite them *by name* in the fit-check.

> Bugs and Tasks largely **bypass** the fit gate: a bug is a defect in something already chosen
> (the question is fix-vs-accept, not fit); a Task is internal (refactor / infra). The fit gate
> fires mainly on **features** and on **"is this something the product does at all?"** asks.

## Step 1: Gather data (parallel)

Fire in one tool-call block:

1. **Pending reports**: `mcp__kendo__list-reports-tool` with `project_id: {{PROJECT_ID}}, status: 0`
   (0=Pending — filtered server-side, so the response is pending-only).
2. **Project context**: `mcp__kendo__prepare-project-context-tool` with `project_id: {{PROJECT_ID}}`
   — returns `project`, `lanes` (lane IDs), `sprints` (all Planned/Active), `active_sprint`
   shortcut, `labels` (id + name + color — use `label.id` for `label_ids` filter in search and for
   `sync-issue-labels-tool` after promoting), `members` (assignee lookup), `current_user`.

Also read `docs/triage/decisions.md` and load its **Declined patterns** — the reusable "we don't
do this" rules. You match new pending reports against these in Step 4.

## Step 2: Confirm pending count

Tell the user the count:

> "Found N pending reports. Let me cross-reference with existing issues."

If zero pending reports, say the queue is clean and stop.

> Note: previously-**Parked** reports reappear here with no flag (Park leaves no record by
> design — the resurfacing mechanism is a future call). Dismissed reports are gone from this list.

## Step 3: Cross-reference existing work (one fetch)

Fetch the existing-issue set **once** to match reports against — do not re-query per report. In
parallel:

1. **Active sprint issues**: `mcp__kendo__search-issues-tool` filtered by active sprint (status=1).
2. **Backlog issues**: `mcp__kendo__search-issues-tool` filtered by the To Do lane (`lane_id` from
   Step 1).
3. **Recently-resolved work**: for bug reports especially, also check the **Done lane** (`lane_id`
   from Step 1, most-recently-updated) and recent merges — "we already fixed that" is one of the
   most common and highest-value dismiss reasons, and it only surfaces if you look at closed work.

Extract key fields with `jq`: key, title, lane, sprint, type, priority, label_ids. In Step 4 you
match each report against this in-context set (no second round-trip per report). You can narrow
either search with `label_ids` (resolved from Step 1's `labels` array) when the user wants to
focus on a specific label.

> **Search caveat:** `search-issues` AND-matches multi-word queries, so `"comment submit shortcut"`
> can return zero even when a match exists. Prefer **single-word or OR-style** queries, or rely on
> the lane fetches above and match in-context.

Done issues are context only — they tell you a report was already addressed ("shipped in
`{{ISSUE_KEY_PREFIX}}-XXXX`") so you can Dismiss it with that reason. **Never reopen, update, or
append to a Done issue.**

## Step 4: Per-report triage

Go through each pending report one at a time with `AskUserQuestion`. This is the core — the user
makes every decision. The goal of each pass is to fill a small **decision card** — *value, fit,
effort* — and nothing more. Those three inputs point your **recommendation** almost mechanically.
You never decide a verdict yourself — every report is presented in Step 4.8 and the user ratifies
or overrides it. The recommendation logic:

- wanted + cheap → recommend **Promote** now (easy win)
- wanted + expensive → recommend **Park**, or an **epic** / `/plan-feature` pass
- not wanted, or already-shipped / noise / not-a-product-change → recommend **Dismiss** (with the
  reason); no need to size work you'd advise against
- genuinely unsure / "decide later" → recommend **Park** (leave it Pending)

For each report, in order:

1. **Read it.** What is the user actually *experiencing*? (Not yet: what did they ask for.)

2. **Matches a declined pattern?** If the report matches a rule in the dismissal log's **Declined
   patterns** (e.g. "mobile login without 2FA"), recommend **Dismiss** with that reason and a
   pointer to the pattern — no need to re-run the fit gate.

3. **Classify** — this is the Bug / Feature / Task differentiation, made explicit. Reports carry
   no type (`source` is only Manual vs Api — provenance, not category), so type is *your*
   judgment:
   - **Not a product change?** Support question, user error, docs gap, "how do I…" → it is not an
     issue. Answer / redirect the user, then **Dismiss** with reason `not-a-product-change`.
   - **Bug** (`type: 1`) — existing behaviour is wrong or broken.
   - **Feature** (`type: 0`) — new user-facing capability.
   - **Task** (`type: 2`) — work with no direct user-facing surface: refactor, infra, perf,
     chore, dependency bump.

4. **Overlap.** Match against the existing-issue set from Step 3 (open *and* recently-resolved)
   and against *other pending reports* (cluster detection — three reports about one theme may be
   an epic, not three issues). An already-shipped match → **Dismiss** with reason `already-shipped`.

5. **Value + fit** (features + ambiguous asks; skip for clear bugs/tasks). Two halves of the
   "do we want this?" question:
   - **Value** — which persona does it serve, and how often do they hit the pain? Reinforce with
     signal count ("3 similar reports this month" is stronger than one).
   - **Fit** — check it against positioning and a decision principle from Step 0. If the repo has
     no product-context source, put the fit question to the user here, in one sentence.
   Form a *recommendation* — promote / park / dismiss — **in product terms**, not "low priority".
   This step is cheap, so form it **before** sizing: if your recommendation is **Dismiss** on fit
   alone (off-strategy), skip the sizing pass (Step 4.6) — there's no point estimating work you're
   advising against. You still present it (Step 4.8) and the user makes the call; if they push back
   ("no, I want this"), *then* size it and re-present. Skipping sizing skips Grep calls, never the
   user.

6. **Size the work (effort).** This is what the lightweight investigation is *for* — not to
   understand the feature in the abstract, but to answer "how much work is this, and does the
   codebase already make it cheap?" Run only for promote/park candidates and (lightly) for bugs.
   A few Grep/Glob calls to the relevant area, then pick a band and **state the evidence behind
   it** — a grounded claim the user can check, never a bare number:
   - **Trivial** — extends something that already exists; ~1 file / a few lines
     (e.g. "add a field to the report resource — the column's already there").
   - **Small** — one component or handler + its test; under half a day.
   - **Medium** — a few files across layers (UI + backend + maybe a migration); ~1–2 days.
   - **Large** — new subsystem, multi-layer, or a migration with backfill. Doesn't fit one
     issue → recommend an **epic** or a `/plan-feature` pass, not a flat promote.

   *"Small — board already has multi-select via the selection store; add one bulk-action +
   endpoint"* beats *"~4h"*. For **bugs**, sizing is lighter (one-line fix or a rabbit hole?) and
   feeds *priority*, not the keep/drop call.

7. **Need, not solution** (features). Separate the *job-to-be-done* from the reporter's proposed
   fix. People report solutions they imagined ("add a checkbox in settings"); your value-add is
   the underlying need ("I keep losing my filter when I navigate away"). The promoted user
   story's acceptance criteria describe the **outcome the user needs**; the reporter's suggested
   mechanism goes in **Context**, never in AC. (This is the canonical templates' "AC at the
   outcome layer, not mechanism" rule.)

8. **Present via `AskUserQuestion`** — lead with the **decision card** so the user weighs value
   and cost side by side, then the tailored verdicts:

   > **#42 — "Bulk-archive old issues"** · Feature
   > **Value:** team leads with 200+ issues; 3 similar reports this month
   > **Fit:** serves the team-lead persona; aligns with the "fast, keyboard-first" principle ✓
   > **Effort:** **Small** — board already has multi-select (the selection store); add one
   > bulk-action + endpoint (~2 files + test)
   > **Overlap:** none open or shipped
   > → Recommended: **Promote**, Medium

   - Recommendation **first**, marked "Recommended".
   - **2–4 verdicts tailored to this report** (AskUserQuestion caps at 4 options + auto-"Other").
     Don't show verdicts that don't apply — e.g. *Combine* only when there is an overlap
     candidate; *Park* when it's genuinely a "decide later"; *Dismiss* (always state the reason)
     for off-strategy / noise / duplicate / already-shipped / not-a-product-change.
   - When the user picks **Promote**, the effort band can seed `estimated_minutes` if they want it.
   - If sizing was skipped (a Dismiss-on-fit recommendation), the **Effort** line reads
     *"not sized — recommending Dismiss (off-strategy)"*. If the user overrides toward
     Promote/Park, size it then and re-present the card.
   - Every **Dismiss** option must carry a one-line reason — that reason is what gets recorded.

### Handling user input

The user may:
- Pick a verdict directly — proceed.
- Pick with notes — fold their context into the next step (issue body, or dismiss reason).
- Reject all options — re-ask with adjusted verdicts based on their feedback.
- Give design direction (e.g. "opt-in checkbox, localStorage") — capture it in the promoted
  issue's **Context**, keeping AC at the outcome layer.
- Correct your understanding ("you got this wrong") — investigate further (use an Explore agent
  for the relevant codebase area) before re-presenting.
- Ask to assign someone — use `members` from Step 1 to resolve the user ID.

### Investigation depth

The sizing pass (Step 4.6) is an **estimate, not a spec**. A few Grep/Glob calls to confirm
whether the hook already exists and gauge how many layers it touches — then pick a band and move
on. The point is a verdict, not a plan; precision is what `/plan-feature` is for *after* the
report is promoted. Go deeper (an Explore agent) only when the user asks, or when the estimate
straddles a band boundary that changes the verdict (e.g. "Small → just promote" vs "Large → epic").

## Step 5: Execute verdicts

Collect every verdict during Step 4, then execute in batch at the end (parallel where possible).

### Promote / Combine

Use `mcp__kendo__promote-reports-tool`. Write the issue against the **canonical templates** in
[`../kendo-mcp/references/issue-templates.md`](../kendo-mcp/references/issue-templates.md) —
Feature (user story), Bug (cause-known or repro-first), or **Task** (direct description). Do not
inline or improvise a template.

Triage-specific deltas to apply on top of the templates:

- **Type** — set `type` to the class you decided in Step 4.3 (`0` Feature / `1` Bug / `2` Task).
- **Priority** — full 0–4 scale, not a 3-bucket guess:
  - `0` Highest — security, data loss, outage, broken core flow with no workaround
  - `1` High — blocks a core flow (has a workaround)
  - `2` Medium (default) — functional bug or meaningful UX gain
  - `3` Low — minor UX, small polish
  - `4` Lowest — cosmetic, icebox
- **Use the fuller field set** the tool supports (the old flow ignored these):
  - `epic_id` — promote a clustered theme *into* an epic instead of a flat issue.
  - `estimated_minutes` — when the user gives a rough size.
  - `blocked_by_ids` / `blocks_ids` — when the report depends on or unblocks known issues.
- **Labels**: `promote-reports-tool` does not accept `label_ids`. To attach labels, call
  `mcp__kendo__sync-issue-labels-tool` immediately after promotion using the new issue's `id`
  and the label IDs resolved from `labels` in the Step 1 project-context response. Only do
  this when the user explicitly requests a label.
- **Combine**: pass multiple `report_ids` in one call — the extra reports are dismissed
  automatically as part of the batch. For a thematic cluster, prefer `create-epic` then promote
  each into it via `epic_id`.
- **Standard params**: `project_id: {{PROJECT_ID}}`, `lane_id`: the To Do lane id from Step 1;
  `assignee_id` only if the user said who; `sprint_id` only if the user said to add it. If the
  user names a sprint (e.g. "put it in Sprint 12"), the `sprints` array in the Step 1
  `prepare-project-context` response already covers Planned/Active sprints; call
  `mcp__kendo__get-sprints-tool` with `project_id: {{PROJECT_ID}}` only when the named sprint is
  not in that list.

Fold any design decision the user made during triage into the issue **Context** (not AC).

### Dismiss (always with a reason)

Run `mcp__kendo__dismiss-report-tool` with the `report_id`, **then record the reason** in
`docs/triage/decisions.md` — never a silent dismiss. Append a row to the dismissal-log table
(newest on top): report id, title, reason category (`off-strategy` / `noise` / `duplicate` /
`already-shipped` / `not-a-product-change`), a one-line note, and `YYYY-MM-DD · <decider>`.

If the report is an instance of a recurring ask (especially from external users), also add or
update a rule in the **Declined patterns** section so future matches can be dismissed on sight.

No confirmation needed — the user already confirmed the verdict via AskUserQuestion.

### Park

**No MCP call, no record.** The report stays Pending and will resurface next run. Park is the
deliberate "decide later" bucket — don't write a ledger row for it (a real resurfacing mechanism
is a future call).

## Step 6: Summary

After all reports are processed, show:

```markdown
### Promoted (N)
| Issue | Report | Type | Priority | Assignee |
|-------|--------|------|----------|----------|
| {{ISSUE_KEY_PREFIX}}-XXXX | #XX | Feature/Bug/Task | Highest…Lowest | name or — |

### Parked (N) — left Pending, no record
| Report | Why deferred |
|--------|--------------|
| #XX | … |

### Dismissed (N) — reason recorded in the dismissal log
| Report | Reason | Note |
|--------|--------|------|
| #XX | off-strategy / already-shipped / … | … |
```

If any reports were dismissed, remind the user the dismissal log was updated (and any new
Declined pattern added).

## Edge cases

- **Large queue (>30 pending)**: ask whether to process all, or focus on a date range / reporter.
- **Reports with attachments**: mention the count — the user may want to view them
  (`mcp__kendo__fetch-attachment-tool`) before deciding.
- **Vague / terse reports**: present as-is; don't auto-dismiss for lack of detail — the user often
  knows what a terse report means.
- **Recurring dismiss pattern**: if several reports request the same off-strategy thing, capture it
  once as a **Declined pattern** in the dismissal log so the next instance is a one-glance Dismiss.
- **Thematic cluster**: ≥3 reports on one theme → offer an epic (`create-epic` + `epic_id`) rather
  than N separate issues or a lossy Combine.
- **User provides context not in the report**: fold their knowledge into the promoted issue.
- **Multi-project consumers**: default to `{{PROJECT_ID}}` but respect any project the user names.
