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
placeholders in `SKILL.md`'s worked examples for the concrete `KD-00NN` style
`newbranch`/`task-writer`/`pr` already established, per the parent workflow's own placeholder-style
convention — no functional change. `references/setup.md` and `references/issue-templates.md`
shipped byte-identical: `setup.md` already used a generic `<your-tenant>` placeholder rather than
a `{{TENANT}}` token, and `issue-templates.md` carried no placeholder tokens of its own to begin
with.

**Rejected — re-pointing the parent plan's already-converted skills at the newly-real
`kendo-mcp/references/issue-templates.md` path.** `newbranch`, `plan-feature`, and `task-writer`
(in `core-skills`) each describe the issue-template shapes generically in their own prose instead
of linking to the file, a call made while `kendo-mcp` was still catalog-only (a reference-doc
hosting problem at the time — see the parent plan's D9/D16). That workaround holds regardless of
`kendo-mcp`'s own conversion status now that it lives in a *different* plugin (`kendo-pm`, not
`core-skills`): a relative link across plugin boundaries doesn't survive independent installs the
way one owned by the same plugin does. Not revisited — out of scope for this plan, which doesn't
touch `core-skills`.

**Rejected — a `kendo-pm`-owned copy of `.claude/project-context.md`'s template.** `core-skills`
already owns the canonical template; a project installing both plugins should still only maintain
one file. See this plan's own PLAN.md, *Rollout approach*, for where a future `kendo-pm` field
would land instead.

**Consequence.** `kendo-pm` exists as a new plugin (registered in the root marketplace and both
READMEs) at version 0.1.0, bundling one skill, `kendo-mcp`. The other five Kendo PM Skills
(`board-sync`, `kendo-cli`, `lint-issues`, `prepare-issue`, `triage-reports`) remain catalog-only,
next in queue for this branch. Whether any of them need a `.claude/project-context.md` field of
their own (added to `core-skills`' template per this plan's ownership call, not a `kendo-pm`-local
one) is an open question for whichever of them converts first and actually needs one — not decided
speculatively here.
