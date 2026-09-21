# Decisions — `plugin-skills-rework-kendo-pm`

## D1 — Kendo PM Skills get their own plugin (`kendo-pm`), not folded into `core-skills`;
`kendo-mcp` converts first as the cluster's dependency root

**Chosen.** Starting this branch, `research/plugin-skills-rework-kendo-pm`, cut from the (still
unmerged) `research/plugin-skills-rework` branch rather than off `main`, so this work doesn't
wait on that PR landing first — see that branch's own `docs/plans/plugin-skills-rework/` for the
mechanism and workflow this plan reuses. Asked the user up front whether the six Kendo PM Skills
(`board-sync`, `kendo-cli`, `kendo-mcp`, `lint-issues`, `prepare-issue`, `triage-reports`) bundle
into `core-skills` or a new plugin, since it's a real fork the parent plan hadn't hit yet: every
skill `core-skills` bundles so far is vendor-neutral (reads `.claude/project-context.md` to
*decide* which tracker to call, or needs no tracker at all), where the Kendo PM Skills are the
tracker implementation itself — Kendo-only by definition, useless to a consumer without a Kendo
tenant. User's call: new plugin, `kendo-pm`, keeping `core-skills` vendor-neutral and matching the
README's own table split (Generic vs. Kendo PM Skills).

Converted `kendo-mcp` first, out of the table's alphabetical order, because every other Kendo PM
skill either calls it directly or assumes its tool surface (`board-sync`, `lint-issues`,
`prepare-issue`, `triage-reports` all call `mcp__kendo__*` tools; `kendo-cli` and others link to
its `references/issue-templates.md`) — the same "hard dependency jumps the queue" rule the parent
plan's conversion workflow already established for `worktree`/`build-it`, applied to a whole
cluster's root this time rather than one pairwise dependency.

`kendo-mcp` itself needed **zero `.claude/project-context.md` integration** — a fourth instance
of the "already generic" shape `grill-me`/`memory-hygiene`/`review-mcp-descriptions` each hit in
the parent plan for a different reason: it discovers its project id at runtime
(`kendo://projects`) rather than hardcoding one, so it has no project-specific fact to
externalize. The only edit was swapping the three illustrative `{{ISSUE_KEY_PREFIX}}-00NN`
placeholders in `SKILL.md`'s worked examples for `PROJ-00NN`.

**Correction, caught by the user in review.** The first pass of this edit used `KD-00NN` — the
concrete style `newbranch`/`task-writer`/`pr` established in the parent plan — without checking
whether it actually fit *this* skill. It doesn't: `KD` isn't a generic stand-in in that convention,
it's `core-skills`' own worked examples naming a real project code (this org's own "Kendo
development" project inside its own Kendo tenant — those examples are grounded in a real
consumer's usage, not written as pure placeholders). Reusing it here, inside `kendo-mcp` itself —
the skill whose whole premise is "works with any project hosted on your Kendo tenant" — would
misleadingly suggest `KD` is a reserved or expected value rather than one tenant's arbitrary
project code. Fixed by using `PROJ-00NN` instead: the file's *own* pre-existing generic-issue-key
example, already present a few lines above the first edited spot (the `key` field's example in
Common Operations, `PROJ-0142`) before this conversion touched anything. Matching a skill's own
established placeholder beats importing one from a different skill's worked examples, even when
that skill's convention is otherwise a reasonable default. `references/setup.md` and
`references/issue-templates.md` shipped byte-identical: `setup.md` already used a generic
`<your-tenant>` placeholder rather than a `{{TENANT}}` token, and `issue-templates.md` carried no
placeholder tokens of its own to begin with.

**Rejected — re-pointing the parent plan's already-converted skills at the newly-real
`kendo-mcp/references/issue-templates.md` path.** `newbranch`, `plan-feature`, and `task-writer`
(in `core-skills`) each describe the issue-template shapes generically in their own prose instead
of linking to the file, a call made while `kendo-mcp` was still catalog-only (a reference-doc
hosting problem at the time — see the parent plan's D9/D16). That workaround holds regardless of
`kendo-mcp`'s own conversion status now that it lives in a *different* plugin (`kendo-pm`, not
`core-skills`): a relative link across plugin boundaries doesn't survive independent installs the
way one owned by the same plugin does. Not revisited — out of scope for this plan, which doesn't
touch `core-skills`.

**Confirmed the converse while converting `kendo-cli`.** Its own prose reference to "the kendo-mcp
skill's `references/issue-templates.md`" became a real relative markdown link
(`../kendo-mcp/references/issue-templates.md`) rather than the `core-skills` generic-description
workaround — legitimate specifically because `kendo-cli` and `kendo-mcp` are siblings *inside the
same plugin*, so the link does survive an independent `kendo-pm` install. The plugin-boundary
reasoning above cuts both ways: a real link is right within a plugin, wrong across plugins.

**Rejected — a `kendo-pm`-owned copy of `.claude/project-context.md`'s template.** `core-skills`
already owns the canonical template; a project installing both plugins should still only maintain
one file. See this plan's own PLAN.md, *Rollout approach*, for where a future `kendo-pm` field
would land instead.

**Consequence.** `kendo-pm` exists as a new plugin (registered in the root marketplace and both
READMEs) at version 0.1.0, bundling one skill, `kendo-mcp`. Of the other five Kendo PM Skills,
`kendo-cli`, `prepare-issue`, and `triage-reports` remain catalog-only, next in queue for this
branch (`board-sync` and `lint-issues` are excluded — see D2). Whether any of the remaining three
need a `.claude/project-context.md` field of their own (added to `core-skills`' template per this
plan's ownership call, not a `kendo-pm`-local one) is an open question for whichever converts first
and actually needs one — not decided speculatively here.

## D2 — `board-sync` and `lint-issues` excluded from this conversion pass entirely

**Chosen.** The user relayed the team lead's call: skip `board-sync` and `lint-issues` — both go
unused and are candidates for deprecation. Excluded from the `kendo-pm` conversion queue outright,
the same "not converting this one" treatment the parent plan gave `babysit` (superseded by
`shepard`, no reason to convert it) rather than the D31 treatment (convert into the bundle, then
pull back out on review) — there was never a version of either in `kendo-pm` to remove, since
neither had been picked up yet when the call came in.

Checked both for a hard dependency from a skill that *is* staying in scope, the same reverse-check
D31 ran before its own removal: `kendo-cli`, `prepare-issue`, and `triage-reports` each call
`mcp__kendo__*` tools directly and link to `kendo-mcp`'s `references/issue-templates.md`, but none
of them call, spawn, or otherwise depend on `board-sync` or `lint-issues` themselves. Clear to
exclude both without orphaning anything still in scope.

**Rejected — marking them deprecated in the catalog's own `README.md` now** (the way `babysit`'s
row already reads "Superseded by shepard"). The team lead's framing was "candidates for
deprecation," not a decided, executed deprecation — `babysit`'s annotation states a fact that
already held before this rework touched it; writing a similar note for `board-sync`/`lint-issues`
now would assert a decision that hasn't actually been made yet. Left the catalog `README.md`
untouched; revisit if/when the team lead confirms the deprecation itself.

**Consequence.** The `kendo-pm` conversion queue is now `kendo-cli`, `prepare-issue`,
`triage-reports` — three skills, not five. `board-sync` and `lint-issues` remain exactly as they
are in `skills/`, neither converted nor marked deprecated in the catalog; that's a separate,
not-yet-made call for the team lead.

## D3 — `triage-reports` reuses `issue_tracker_project_id`; `prepare-issue` paused on a real
cross-plugin runtime question

**Chosen.** Picked up `prepare-issue` first (next alphabetically after `kendo-cli`), but paused
it before making any edits: it unconditionally invokes `/newbranch` once Step 5's branch-existence
check comes up empty — a repo-state-gated call, not a developer confirmation, so it counts as a
hard dependency under the parent workflow's Step 5b. `/newbranch` lives in `core-skills`, a
different plugin from `kendo-pm`. Every prior cross-plugin question in this branch (D1's rejected
alternative, the `kendo-cli` confirmation) was about a *reference file* surviving a relative link
across plugin boundaries; this is a different, harder shape — a skill in one plugin needing
another plugin's skill to actually *run* at a specific step, which does bear on whether `kendo-pm`
can be installed alone. Asked the user how to handle it (document as a hard requirement, vs. add a
graceful degrade matching the file's own existing precedent for `/startup`'s absence); they want to
think about it, so `prepare-issue` is parked untouched rather than guessed at. See PLAN.md's
*Paused* section.

Also flagged, not yet acted on: `prepare-issue`'s Step 7 Option C hardcodes its new-worktree path
(`../{worktree_name}`) instead of reading `worktree_dir`. Not an automatic reuse candidate the way
`issue_tracker_project_id` was for `triage-reports` below — `worktree_dir`'s contract substitutes
`{slug}`, while `prepare-issue`'s own convention is `{N}`-based (`<repo-folder>-{N}`, e.g.
`myapp-2`), a different shape. `plan-directory.md` already warns against forcing `plan_dir`'s
`{issue_key}` contract onto a slug it wasn't designed for (the "Catchup variant" note); the same
caution applies here before reusing `worktree_dir`. Left alone pending the `/newbranch` decision,
since resolving both at once may change how much of Step 7 stays hand-written at all.

Converted `triage-reports` instead while `prepare-issue` waits — no dependency between them, and
it's next in the README's Kendo PM Skills table order regardless. It's the first `kendo-pm` skill
to actually need a `.claude/project-context.md` field: its six `{{PROJECT_ID}}` occurrences all
reuse `issue_tracker_project_id` (D14, from the parent plan's template) rather than inventing a
`kendo-pm`-local one, per this plan's own ownership call (D1's rejected-alternative paragraph).
Falls back to `kendo-mcp`'s own `kendo://projects` discovery, then asks the user, when the field is
unset — the same "ask, don't guess" shape `implement-plan` already established in the parent plan
for a missing plan directory, rather than inventing a new degrade behaviour.

**This is not the same shape as the `prepare-issue`/`/newbranch` question above.** Reading
`issue_tracker_project_id` from `.claude/project-context.md` is not a dependency on `core-skills`
being installed: the file is a plain project-owned document defining scalar fields, not a call
into another plugin's skill at runtime. A `kendo-pm`-only consumer can set the field themselves
without ever installing `core-skills` — they'd just be filling in a value `core-skills`' template
happens to also document. Worth stating explicitly since the two could otherwise look like the
same kind of cross-plugin reliance; they aren't.

The three `{{ISSUE_KEY_PREFIX}}-XXXX` occurrences swapped for `PROJ-XXXX`, matching `kendo-mcp`'s
established convention (not `KD-`, per D1's correction). `references/decisions-log-template.md`
shipped byte-identical — no placeholder tokens. The `docs/triage/decisions.md` output path itself
was **not** turned into an override field: the skill's own prose already states it's a fixed
cross-consumer convention, deliberately not project-specific ("kept so the log is found in the
same place everywhere"), unlike `plan_dir`/`worktree_dir`, which exist precisely because their
underlying convention *does* vary by project. Its two existing relative links to
`kendo-mcp/references/issue-templates.md` were already written as real markdown links in the
catalog original (unlike `kendo-cli`'s prose-only version) — needed no fix, and now resolve
correctly as same-plugin siblings.

`kendo-pm`'s own README gained a real `.claude/project-context.md` section, replacing the
speculative "a later skill... should reuse" phrasing from D1 with a description of an actual
reader.

**Correction, caught by the user in review.** `triage-reports`' commit reused
`issue_tracker_project_id` but never added itself to that field's "Used by" comment in
`templates/project-context-template.md` — every within-`core-skills` reuse in the parent plan
updated that comment when adding a new reader (D26 corrected two omissions in
`integration_branch`'s list; D31 corrected `plan_dir`'s). Fixed by adding `triage-reports` to the
comment, explicitly noting it's the field's *first cross-plugin* reader — every other name already
there is a `core-skills` skill, so a bare name addition would have understated what changed. The
canonical `templates/project-context-template.md` edit alone was sufficient: `.githooks/pre-commit`
(D19, from the parent plan) auto-copied it over `plugins/core-skills/references/project-context-template.md`
in the same commit, confirmed byte-identical after.

**Consequence.** `kendo-pm` bundles three skills (`kendo-cli`, `kendo-mcp`, `triage-reports`) at
version 0.3.0. `prepare-issue` is the only skill left in the queue, paused on the `/newbranch`
question above.
