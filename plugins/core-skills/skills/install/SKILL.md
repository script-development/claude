---
name: install
description: |
  Create or top up this project's `.claude/project-context.md` — the one file every installed
  plugin skill (core-skills, kendo-pm, ...) reads for project-specific facts — from the shipped
  template, keeping only the fields the skills actually installed here read. Detects values from
  the repo first and asks (AskUserQuestion) only for what it can't detect or wants confirmed.
  Additive and safe to re-run: never overwrites a value already set. Use whenever the user says
  "install", "set up project context", "configure the plugin", "create project-context.md",
  "init core-skills", just installed a plugin from this marketplace, or added another one (e.g.
  kendo-pm after core-skills) and wants its fields added. Also offer it when another skill
  reports that `.claude/project-context.md` or a field it reads is missing.
---

# Install — set up `.claude/project-context.md`

One file per project serves every plugin from this marketplace (see this plugin's README for why
it's one file and not one per plugin). This skill writes that file for the plugins installed
*here and now*, and tops it up when a plugin is added later. It is the only skill that writes the
file wholesale; every other skill only reads it.

Every field in the file is optional — a reading skill falls back to its own default when a field
or the whole file is absent. So the goal is not to fill in every field: it's to record the facts
where this project **differs** from those defaults. Pinning a value that equals the default is
worse than leaving it unset, because the pinned copy stops following the repo when it changes.

## Step 1: Locate the template and the existing file

The canonical template ships with this plugin at `references/project-context-template.md` (this
plugin's root, two levels above this skill's own directory). If this skill's base directory isn't
known, resolve it:

```bash
tpl=""
for d in "$HOME"/.claude/plugins/cache/*/core-skills/*/references/project-context-template.md; do
  [ -f "$d" ] && tpl=$d   # last match wins: newest cached version
done
echo "tpl=$tpl"
```

No template found — stop: *"install can't find core-skills' project-context template; reinstall
the plugin."*

Then check whether `.claude/project-context.md` exists at the repo root
(`git rev-parse --show-toplevel`). Exists → **update mode** (Step 5). Absent → **create mode**.

## Step 2: Work out which fields apply

Each template section and field carries a `used by:` / `Used by:` list of skill names in its
comment. A field applies when **at least one** skill it names is available in this session — the
session's own skill list (plugin skills appear namespaced, e.g. `core-skills:newbranch`,
`kendo-pm:triage-reports`) is the source of truth, since a disabled plugin's skills don't run
anyway. `~/.claude/plugins/installed_plugins.json` is a cross-check, not the primary signal.

A **checked-in copy** of a reader counts too: a skill at `.claude/skills/<name>/` or
`~/.claude/skills/<name>/`, or an agent at `.claude/agents/<name>.md`, with the same name as a
`used by:` entry. That's the project moving from its own copies to these plugins — `core-skills`
is installed (this skill is running), but a sibling plugin like `kendo-pm` may not be yet, while
the project still runs its own `prepare-issue` or `triage-reports`. The copy itself has its values
baked in and reads nothing, but the plugin version replacing it will. Say in the summary which
fields were kept on a checked-in copy's account, so the user knows they take effect only once
that plugin is installed.

Drop every field, and every `##` body section, none of whose readers is available.

**The project's file holds data, not documentation.** Every skill reads the whole file each time
it needs one field, and the template's comments and explanatory sections are already restated by
the skills that read them. So none of that text is copied: the template stays the one place that
documents each field, and the project's file links to it (Step 5).

## Step 3: Detect values (in parallel)

For each applicable field, find what the reading skill would get *by default* and whether this
repo has a reason to differ. Only a difference is a candidate value.

Work through **every** applicable field in the table below, in order, and settle each on exactly
one outcome, with its evidence:

- **candidate** — a value that differs from the default (asked in Step 4);
- **default fits** — you checked, and the default already matches this repo;
- **no default, nothing found** — asked in Step 4;
- **undetectable** — the check itself couldn't run (no MCP, no `gh`); stays unset.

"Default fits" is a claim like any other: state what you checked (*"all 29 plan folders are
named after their branch"*), not what the default is. No field is skipped silently. Every
applicable field appears in the Step 6 summary under its outcome, so two runs on the same repo
can be compared line by line.

| Field | Detect | Candidate when |
|---|---|---|
| `issue_tracker_skill` | Is `kendo-mcp` (or `kendo-pm:kendo-mcp`) available? Any other tracker skill (`*jira*`, `*linear*`, `*github-issues*`)? | `kendo-mcp` absent and another tracker skill present → that skill; no tracker skill at all → ask (`none` vs leave unset) |
| `issue_tracker_project_id` | If Kendo MCP tools are reachable: list projects (`kendo://projects` resource), match on repo name / issue-key prefix from recent branch names (`git branch -a`) | Always a candidate when a match or shortlist exists — there's no default to fall back on |
| `integration_branch` | Run the `worktree` chain: `origin/development`, `origin/develop`, then `git symbolic-ref refs/remotes/origin/HEAD` | Chain result disagrees with where recent PRs actually merge (`gh pr list --state merged -L 20 --json baseRefName`) |
| `plan_root` | Where do existing `PLAN.md` / `TASKS.md` / `DECISIONS.md` files live (`git ls-files '*/PLAN.md' '*/DECISIONS.md'`)? | They sit one folder deep under a root other than `docs/plans/`, or `docs/plans/` already holds something that isn't per-branch plan folders |
| `bug_root` | Same for `BUG.md` | Same, against `docs/bugs/` |
| `worktree_dir` | A Docker build context at the repo root (`docker build .`, compose `context: .`), test-runner or IDE globs over the whole tree | The default `.claude/worktrees/` sits inside that context and the project's `.dockerignore` doesn't exclude it. Check the ignore file, not the Dockerfile's `COPY` lines: the whole context is sent to the daemon before any `COPY` runs, and root-anchored patterns like `backend/vendor` don't match a nested worktree's `.claude/worktrees/x/backend/vendor`. A sibling folder named like the project's existing worktrees (`git worktree list`) is the usual candidate. A `.gitignore` entry already covering the default is not a reason to override — it goes under House rules |
| `doc_paths` | `docs/`, `README.md`, `*/README.md`, `CHANGELOG.md`, `**/*.md` outside source dirs | Any user-facing text found — this field has **no** default, so unset silently disables docs review. A candidate prefix that contains the plan or bug root (e.g. `docs/` around `docs/plans/`) gets a `:(exclude)` for each root — otherwise every branch with a plan folder triggers the docs reviewer on branch scratch it then ignores |

**Plan and bug folder names aren't a field.** Only the roots are configurable; the folder
inside is the slug the plugin's own skills mint and find (branch name first, then the issue-key
prefix — see `references/plan-directory.md`). Existing folders named `<issue-key>-<description>`
or after the branch need nothing set — including a folder named after a branch with no issue key
(`issue-detail-load-path/` for branch `issue-detail-load-path`), which the exact-name step finds. Folders named some other way aren't fixable here — say so in
the summary rather than inventing a value.

**Migrating from checked-in skills.** A project moving from its own `.claude/skills/` and
`.claude/agents/` copies to these plugins already has the answers baked into them — the values
the catalog's `{{PLACEHOLDER}}` tokens were substituted with at adoption (`project_id: 1`, a
reviewer's hardcoded `git diff -- site/ .claude/` trigger). Grep those copies for the field's
concept, and when the reading skill or agent is gone, check git history
(`git log --all -- .claude/agents/<name>.md`, then `git show <sha>:<path>`). A deletion is
evidence too: record in the option's description *that* the project retired the reader and why
(from the commit message), since that may mean "leave unset" is the project's own decision.

A detection that fails (no network, no MCP, no `gh`) isn't an error — the field simply has no
candidate and stays unset unless the user supplies one in Step 4.

## Step 4: Confirm with the user

Ask only about fields that have a candidate, or that have no default and no detectable answer.
Everything else stays unset without a question — say so in the summary instead.

Use AskUserQuestion, up to four fields per call, one question per field:

- **Detected value** → options: `Use <value> (Recommended)`, `Leave unset — <what the default
  is>`. The built-in "Other" covers a custom value.
- **Shortlist** (e.g. several Kendo projects) → one option per candidate (max 3) plus `Leave
  unset`.
- **Nothing detectable, no default** → `Leave unset — <consequence>` plus the most plausible
  guess, if any.

Put the evidence in each option's description (*"PRs #41–#60 all merged into `develop`"*), so the
user is confirming a fact, not guessing. If AskUserQuestion is unavailable (a headless run), take
every `(Recommended)` option and list the choices in the summary for review.

**Prose sections** (`## Worktrees` → Setup, Gates, House rules): these hold only knowledge
verified in this project, with its *why*. Don't invent it. Write each applicable subsection's
heading only if it gets confirmed content; an empty subsection is left out, not stubbed. Offer —
once, as a single question — to draft Gates from the project's own scripts (`package.json`
scripts, `composer.json` scripts, `Makefile` targets). If the user accepts, check that each
script exists, then ask a second question whose option carries the **exact text** to be written
as an AskUserQuestion `preview` (the table plus any notes, such as a watch-mode script that never
exits). Write that confirmed text verbatim; a line the user never saw doesn't go in. A guess
recorded here is followed by every skill as if it were verified.

## Step 5: Write

**Create mode** — write `.claude/project-context.md` in this shape, and nothing else:

```markdown
---
# Written by /core-skills:install. Every field is documented in the template:
# <repository>/references/project-context-template.md
# Left at their defaults: plan_root, bug_root, integration_branch
issue_tracker_project_id: 1
worktree_dir: ../kendo-{slug}
---

## Worktrees

### Gates

<the confirmed text, verbatim>
```

- **Header**: `<repository>` is the `repository` URL in this plugin's `.claude-plugin/plugin.json`.
  It's a link the whole team can open. Never write a local cache path: the file is committed, and
  that path is personal and changes with every plugin version.
- **Left at their defaults**: every applicable field that ended unset, in template order. It
  tells a reader which fields exist, and tells a later re-run which fields were already reviewed.
  Omit the line when every applicable field has a value.
- **Fields**: only those with a value, in template order, with no comments. The reason for each
  value is in the Step 6 summary.
- **Body**: only `## Worktrees` and those of its `###` subsections (Setup, Gates, House rules)
  that got confirmed content. No guidance text and no explanatory sections. No confirmed prose →
  no body at all.

**Update mode** — read the existing file first and change it only additively:

- The header lines are install's own. Refresh them: the template link, and the "Left at their
  defaults" list (a field that now has a value leaves the list; a newly applicable one that ends
  unset joins it). A file without that header gets one.
- An applicable field neither in the frontmatter nor in the defaults list → run Steps 3–4 for it.
  A value is inserted in template order, with no comment; an unset one joins the defaults list.
- A field already present, or listed as left at its default, is the user's decision: leave its
  value alone. Run Step 3 for it only if it's unset, and only offer a value, never replace one.
- A file written in the older, commented shape (every field present, most empty, with per-field
  comments and explanatory sections) → leave its comments and sections alone. Treat an empty field
  as listed at its default. Mention in the summary that re-creating the file (delete it, re-run)
  gives the smaller, data-only shape.
- A confirmed `### Worktrees` subsection missing from the body → append it in template order. An
  existing section is never rewritten.
- A field or section in the file that the template doesn't know (renamed, removed, or
  project-invented) → keep it and mention it in the summary. Don't delete.
- In particular `plan_dir` (an older `{issue_key}`-substitution field): no skill reads it any
  more. Keep it, and say in the summary that `plan_root` replaced it — offer `plan_root` only if
  the old value pointed outside `docs/plans/`.

Nothing to add → change nothing and say the file is already up to date for the installed
plugins. Don't commit — the file belongs to the project; leave it for the user or `/commit`.

## Step 6: Summarize

```
## .claude/project-context.md — <created | updated | already up to date>

**For:** <installed plugins whose skills read it>
**Set:**   <field>: <value> — <evidence>
**Unset (using defaults):** <field> — <default in a few words> — <what was checked>
**Unset (undetectable):** <field> — <which check couldn't run>
**Skipped (no reader installed):** <section or field>
**Kept for a checked-in copy:** <field> — read once <plugin> replaces `.claude/skills/<name>/`
**Left alone:** <existing fields/sections, including unknown ones>
**Replaced by plugin:** `.claude/skills/<name>/`, `.claude/agents/<name>.md` — now also shipped as `<plugin>:<name>`

Re-run /core-skills:install after installing another plugin from this marketplace.
```

**Replaced by plugin** lists every checked-in skill or agent (the same locations Step 2 scans)
whose name matches a skill or agent an installed plugin now ships. Both copies stay available
side by side, so a project midway through migrating can end up running either one. List them and
say they can be deleted once the plugin version is trusted; don't delete them yourself. A
checked-in copy with no plugin counterpart isn't listed — it's the project's own skill. Omit the
line when nothing matches.

## What this skill never does

- Never overwrites or deletes a value, field, or section already in the file.
- Never writes a prose rule (Setup, Gates, House rules) the user hasn't confirmed.
- Never pins a field to a value that equals its own default.
- Never deletes a checked-in skill or agent, even one a plugin now replaces.
- Never commits.
