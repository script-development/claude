# Decisions — rework catalog skills into project-agnostic plugin skills

Each entry: what was chosen, why, and the rejected alternative.

## D1 — A dedicated `.claude/project-context.md`, not `CLAUDE.md`

**Chosen.** Project-specific facts that plugin skills read live in their own file, separate
from the project's `CLAUDE.md`.

**Why.** `CLAUDE.md` is free-form human/Claude prose, already used loosely across the catalog
(grep turns up a dozen "check the project's CLAUDE.md" ad hoc references). Bolting a required,
machine-parsed schema onto it makes the schema fragile to unrelated edits and means every
plugin skill has to reliably find its section inside whatever else a given project's CLAUDE.md
contains.

**Rejected.** Adding a structured section inside `CLAUDE.md`.

## D2 — Fixed filename `project-context.md`, not named after the project

**Chosen.** Every plugin skill probes the same path, `.claude/project-context.md`, in whatever
project it's running in.

**Why.** A project only ever has one of these; there's no need to embed the project's own name
in the filename to disambiguate it from other projects, since a skill only ever sees the one
it's running inside. A fixed name means a skill can read one deterministic path with no
knowledge of the project's name in advance — a glob-and-disambiguate step would add complexity
for nothing.

**Rejected.** `.claude/<project-name>.md`.

## D3 — YAML frontmatter + prose, mirroring `SKILL.md`'s own shape

**Chosen.** `.claude/project-context.md` (and its template) has a YAML frontmatter block of
`key: value` fields, followed by prose sections that elaborate each field.

**Why.** Frontmatter is already the catalog's convention for machine-parsed metadata
(`SKILL.md` itself). A plugin skill can read one field with a grep/parse pass; the prose below
stays there for a human editing the file to understand what each field does and when to set it.

**Rejected.** Plain markdown bullets with no frontmatter (fine, but gives up the parse-ability
frontmatter already gets elsewhere in the catalog for no real gain). A separate JSON/YAML file
outside markdown (breaks from the catalog's markdown-everywhere convention, worse for a human to
hand-edit).

## D4 — Runtime file reads replace `{{PLACEHOLDER}}` substitution, for converted skills only

**Chosen.** A plugin-ized skill reads project facts from `.claude/project-context.md` at run
time. It does not use `{{ISSUE_KEY_PREFIX}}`-style tokens that a consumer fills in by hand at
adoption time.

**Why.** The placeholder mechanism (documented in `../kendo-realign/DECISIONS.md` D2 — used 81
times for `{{ISSUE_KEY_PREFIX}}` alone) means each consumer's copy is only identical to the
catalog's *before* substitution; after adoption, every copy differs by the filled-in values,
and every catalog update has to be manually re-propagated into each already-filled-in copy. A
plugin's body can stay byte-identical for every installer precisely because the differing part
lives outside it, in a file the plugin never ships.

**Rejected.** Keeping placeholder substitution for plugin skills too, and only adding the
reference file for facts placeholders don't already cover. Two mechanisms doing the same job
(supplying a project-specific value) is exactly the kind of drift the placeholder mechanism
itself already causes.

**Scope.** This only applies to skills that get converted into plugins. Catalog-only skills
keep using `{{PLACEHOLDER}}` exactly as before — this pass doesn't touch that mechanism.

## D5 — Missing file or field degrades capability, never blocks execution

**Chosen.** If `.claude/project-context.md` doesn't exist, or a field a skill wants isn't set,
the skill falls back to its own generic default (or skips that part of its output) rather than
erroring or asking before proceeding.

**Why.** Matches the existing catalog convention (`catchup/SKILL.md` already does this for
missing `DECISIONS.md`/plan dirs) and `context-economy`'s explicit design principle for the same
situation ("Degrade capability, never execution" — `plugins/context-economy/skills/handoff/SKILL.md:242`).
A project that hasn't set up `project-context.md` yet should still get a working skill, just a
less-tailored one.

**Rejected.** Treating a missing file/field as an error that stops the skill and asks the user
to create it first.

## D6 — This pass converts `catchup` only; marketplace registration and the old catalog copy are deferred

**Chosen.** Ship `plugins/catchup/` and `templates/project-context-template.md` in this pass.
Leave `skills/catchup/SKILL.md`, `.claude-plugin/marketplace.json`, and `README.md`'s Plugins
table untouched for now.

**Why.** `catchup` is explicitly the instructive first example — the point is to validate the
`.claude/project-context.md` mechanism on one skill before deciding two things that affect every
future conversion: whether plugin adoption is meant to retire the catalog copy outright (breaking
consumers still on copy-adoption) or coexist with it, and how plugins get grouped once there's
more than one converted skill. Registering it in the marketplace and README before those are
settled would ship a plugin under conventions likely to change on the next conversion.

**Rejected.** Doing the full cutover (register in marketplace, update README, remove or deprecate
`skills/catchup/`) in the same pass — premature given only one skill has gone through the
mechanism so far.

## D7 — One new bundle plugin, `core-skills`, not one plugin per skill

**Chosen.** `catchup` moved from its own `plugins/catchup/` into `plugins/core-skills/skills/catchup/`.
Future project-agnostic conversions land in the same `core-skills` plugin unless a reason to
split emerges. `context-economy` is untouched — this is a second, separate plugin, not a
merge into the first.

**Why.** Team lead's call, made explicit before more than one skill went through the mechanism:
default to bundling, because splitting a skill back out of a bundle later is a cheap, mechanical
move (new plugin dir, move the skill's folder, update marketplace.json), while the reverse —
un-bundling several already-interdependent plugins after consumers have installed them
individually — is not. Cheap to change now is the reason to decide it now rather than defer.

**Rejected.** One plugin per skill (this pass's original shape, before this decision). Waiting
until a second skill is converted to decide — rejected because the whole point is that the
choice is easy to reverse *now*, while nothing yet depends on the boundary.

**Left open.** No threshold is set for when `core-skills` should split (by skill count, by
unrelated themes, or otherwise) — deferred to whoever hits the case that argues for it.

## D8 — `issue_tracker_skill` defaults to `kendo-mcp` when unset

**Chosen.** `catchup` (and any future plugin skill reading `issue_tracker_skill`) defaults to
`kendo-mcp` when the field is absent from `.claude/project-context.md`, provided that skill is
actually installed in the project. `issue_tracker_skill: none` opts out explicitly; any other
value overrides the default with a different tracker skill.

**Why.** D5 established "missing field degrades, never fails" for the general case, on the
premise that there's no universal issue-tracker to default to. That's true across
organisations, but this catalog (`script-development`) is a single org whose skills already
assume Kendo elsewhere (`kendo-mcp`, `kendo-cli` exist as catalog skills; `{{ISSUE_KEY_PREFIX}}`
substitutions across the catalog are Kendo-shaped). Defaulting to the org's own in-house tool is
a real default, not a guess, and it means most projects in this org never have to set the field
at all — only the exceptions (a different tracker, or none) need `project-context.md` to say so.

**Rejected.** Leaving the field default-less (original D5-only behaviour) and requiring every
project to set `issue_tracker_skill: kendo-mcp` explicitly even though nearly all of them mean
it. Hardcoding `kendo-mcp` unconditionally (no override, no `none`) — rejected because a
consumer of this catalog outside the org, or a project deliberately not using Kendo, needs a way
to say so.

**Consequence.** `templates/project-context-template.md` and `plugins/core-skills/skills/catchup/SKILL.md`
both state the default and the two ways to override it (name a different skill, or `none`).

## D9 — Ship a copy of the template inside the plugin itself

**Chosen.** `plugins/core-skills/references/project-context-template.md` is a bundled copy of
the root `templates/project-context-template.md`, kept in sync by hand. `catchup` (and every
skill after it) points to the shipped copy for bootstrapping, not the catalog root.

**Why.** A project that installs `core-skills` via the marketplace never clones the `claude-2`
catalog repo — it only ever receives what the plugin ships. `templates/project-context-template.md`
living only at the catalog root left every plugin consumer with no way to discover the schema
or start their own `.claude/project-context.md`. This was already true for the shipped `catchup`
before this pass caught it.

**Rejected.** Leaving the template catalog-only and describing its fields entirely inline in
each skill's prose instead — rejected because that duplicates the same content once per skill
rather than once per plugin, which is a worse drift risk than one shipped copy of one file.

**Cost accepted.** Two copies of the template now need to move together (root, and each plugin
that reads `project-context.md`) — the same manual-propagation duty `CLAUDE.md` already assigns
to every shared skill mirrored across consumers, extended to this one template file.

## D10 — `worktree` and `build-it` are already project-agnostic; only their customization
storage needed to move

**Chosen.** `worktree` (and, transitively, `build-it`, which only ever acts on what `worktree`
hands back) needed no change to its detection logic — it never hardcoded a project assumption.
The one thing that had to move is *where* its per-repo customization lives: from
`references/<repo-name>.md` inside the skill's own directory to `.claude/project-context.md` in
the project being worked on.

**Why.** Verified (not assumed) that a `.claude-plugin` marketplace install puts each plugin
version in its own independent cache directory
(`~/.claude/plugins/cache/<marketplace>/<plugin-name>/<version>/`), so a file hand-added inside
an installed plugin's own tree does not survive an update to a new version. `worktree`'s
existing mechanism assumed a copy-adopted, personally-owned skill directory that a user edits
directly and controls — true for the catalog copy, false once it ships as a plugin. Also
considered `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/{plugin-id}/`), which does survive
updates, and rejected it: it's per-user and machine-local with no built-in per-repo scoping,
the wrong shape for house rules and gates a whole team should see and share — that content
belongs committed alongside the code it describes, the same argument that already put
`CLAUDE.md` in the repo rather than a user's home directory.

**Rejected.** Leaving `worktree`'s reference-file mechanism untouched inside the plugin (silently
loses customizations on every version bump — a correctness bug, not a style choice). Moving the
content to `${CLAUDE_PLUGIN_DATA}` (wrong scope — private and per-user, not project-owned and
team-shared).

## D11 — `project-context.md` gains prose `##` sections, not just frontmatter scalars

**Chosen.** `worktree`'s richer content — setup commands with do-nots, a gates table, house
rules — lives in a `## Worktrees` body section in `project-context.md`, in the same shape
`worktree`'s own (now-retired) `references/<repo-name>.md` template already used. Frontmatter
stays reserved for simple one-line overrides (`integration_branch`, `worktree_dir`).

**Why.** A flat YAML scalar can't hold an ordered command list, a table, or a do-not with its
reasoning without becoming unreadable. This mirrors `SKILL.md`'s own shape — thin frontmatter,
substantive body — and reuses content structure the catalog had already proven out in
`worktree`'s reference-file template rather than inventing a new one.

**Rejected.** Forcing gates/setup/house-rules into nested YAML frontmatter — technically
possible, but fights the template's readability and departs from how this catalog already
writes this kind of content.

## D12 — Dependency ordering: convert a hard dependency before its dependent, even out of
README order

**Chosen.** `worktree` was converted before `build-it`, despite sorting after it alphabetically
in the README's Generic Skills table, because `build-it` unconditionally invokes `/worktree`.

**Why.** Committing `build-it` first would have left a commit where `core-skills` referenced a
skill not yet in the bundle — a broken intermediate state. Recorded here, and in the
conversion-workflow memory, as the general rule for the rest of this rework: a hard functional
dependency (one skill invoking another, not just documenting it) jumps the queue ahead of
README order.

## D13 — `commit` reuses `integration_branch`; no new field

**Chosen.** `commit`'s branch-safety check (Step 1) and upstream-push check (Step 5) now treat
a project's `integration_branch` (from `.claude/project-context.md`, added for `worktree`) as
protected, in addition to the existing hardcoded list (`main`, `master`, `develop`,
`development`).

**Why.** The hardcoded list is a fixed set of common names; a project whose integration branch
is named something else (`trunk`, `staging`, ...) would get no warning before a direct commit
to it. `integration_branch` already exists for exactly this concept (the branch new work
integrates back into) — reusing it is a strict superset of the old check: a project that never
sets the field gets byte-identical behaviour, one that does gets the gap closed. No new field
needed, matching the established reuse-before-add workflow.

**Also fixed, same skill, same commit.** The original skill's Step 2 gathered `git log
--oneline -5` "for recent commit message style" but Step 4b then imposed a fixed
conventional-commit type list regardless of what that showed — an internal inconsistency, not
a project-specific fact requiring a field. Fixed by making Step 4b actually follow the
convention Step 2 detects, falling back to conventional commits only when there's no clear
existing pattern. Verified against this repo's own history (free-form subjects, no type
prefix) that conventional commits is not a safe universal default the way `kendo-mcp` is for
issue tracking (D8) — it's a per-project convention the skill should detect, not assume.

## D14 — `newbranch` gets a new field, `issue_tracker_project_id`, and fully delegates tracker
mechanics instead of keeping Kendo's tool names hardcoded

**Chosen.** Added `issue_tracker_project_id` under the existing "Issue tracking" section
(alongside `issue_tracker_skill`) — the tracker-scoped project id the original skill hardcoded
as `{{PROJECT_ID}}`. Also rewrote the workflow to describe *what* Step 2 (find/create issue) and
Step 4 (start work) need to accomplish, delegating *how* to whichever skill
`issue_tracker_skill` resolves to, the same abstraction `catchup` already uses — rather than
assuming every project's tracker exposes Kendo's exact tool names
(`prepare-project-context-tool`, `start-work-on-issue-tool`, ...). The default path
(`kendo-mcp`) still documents those concrete calls inline, since it's the only tracker this
catalog actually implements and `kendo-mcp`'s own `SKILL.md` already owns that documentation —
this isn't new information, just not duplicated as the *only* path.

**Why.** `issue_tracker_project_id` is a genuine new fact distinct from `issue_tracker_skill`
(which tracker) — Kendo (and the catalog's other Kendo-shaped skills: `board-sync`,
`prepare-issue`, `kendo-cli`, `triage-reports`, `plan-feature`, `task-writer`, `lint-issues`,
`pr`, `review-mcp-descriptions`) all separately hardcode `{{PROJECT_ID}}` today, confirming
it's a real per-project constant, not something to rederive at runtime each session.
Full delegation matches D8's own premise: `issue_tracker_skill` already models "the tracker is
pluggable, kendo-mcp is just this org's default" — a converted skill that then hardcodes one
tracker's tool names contradicts that pluggability the moment a project sets a different value,
or `none`.

**Rejected.** Keeping the original skill's unconditional `mcp__kendo__*` tool calls and adding
only the new field — rejected because `issue_tracker_skill: none` or a different tracker name
would then have no defined behavior; the field would exist but do nothing. Making the generic
path fully abstract with no concrete example at all — rejected because `kendo-mcp` is the only
tracker this catalog implements, so leaving the default path undocumented would make the skill
useless out of the box for the common case.

**Scope note.** `issue_tracker_project_id` is added to the shared template, not scoped only to
`newbranch` — a future conversion of a Kendo-shaped skill (`board-sync`, `prepare-issue`, etc.,
currently out of `core-skills`' scope, listed under README's Kendo PM Skills) can reuse it
without inventing its own field, per the reuse-before-add workflow.

## D15 — One shared "Notation" paragraph in the plugin README, not a repeated explanation per
skill

**Chosen.** `plugins/core-skills/README.md` gains one paragraph stating, once, what it means
for a skill to name a `.claude/project-context.md` field in backticks (read this field; the
skill states its own fallback) and what a hyphenated code-block placeholder (e.g.
`<integration-branch>`) stands for. `catchup`, `worktree`, and `newbranch` — the three skills
whose intro paragraph had independently re-explained the same "missing file/field degrades,
never blocks" mechanism in slightly different words — now each state only *which* fields they
read and link back to the README for how the mechanism works. `newbranch`'s one stray
underscore-named code placeholder (`<issue_tracker_project_id>`, inconsistent with every other
skill's hyphenated-English-word placeholders like `<branch>`, `<base>`) was fixed to
`<project-id>` to match.

**Why.** User noticed, while reviewing the `newbranch` conversion, that the same degrade-not-
fail explanation was being hand-written into every converted skill's intro — a real
duplication, not just verbosity, since drift between the copies was only a matter of time
(D5/D8's wording already differs slightly between `catchup` and `newbranch` as written). The
mechanism itself (D5, D8) doesn't change — this only moves *where its explanation lives* from
N places to one, and gives future conversions (`next`, `task-writer`, `wireframe`, ...) a fixed
notation to follow instead of each inventing its own phrasing.

**Rejected.** A real templating/include mechanism that would let a skill "transclude" the
README paragraph at read time — no such mechanism exists for plugin skills (`SKILL.md` is a
static file read as-is, not preprocessed — see the chat transcript that prompted this decision
for the fuller "why not `{{PLACEHOLDER}}` for plugins" answer, D4/D10). A shared prose
convention, restated once and linked to, is the closest available substitute.

**Consequence.** Every future `core-skills` conversion states which fields it reads and what it
falls back to, and links to the README's Notation paragraph instead of re-deriving the
degrade-semantics sentence from scratch.

## D16 — A reference doc hosted by an unconverted catalog skill is a hosting problem, not a
hard dependency; ship a trimmed copy (extends D9)

**Chosen.** `next`'s Step 1 needs the canonical plan-directory slug-derivation algorithm,
previously linked at `../plan-feature/references/plan-directory.md`. `plan-feature` is itself
unconverted (in the deferred agent/reviewer cluster). Rather than either (a) treating this as a
hard dependency that jumps `plan-feature` — and by extension its whole deferred cluster — ahead
in the queue, or (b) reinventing a looser algorithm inline the way `catchup` deliberately does,
shipped a trimmed copy at `plugins/core-skills/references/plan-directory.md`: the same
canonical algorithm, `{{ISSUE_KEY_PREFIX}}` replaced with the generic `[A-Z]+-\d+` description
(matching `catchup`'s own phrasing), and the catalog's other still-unconverted consumers
(`implement-plan`, `review-branch`, `pr`, `fix-bug`'s bug-side parallel) trimmed out since they
don't apply inside this plugin yet.

**Why.** Step 5/6 of the conversion workflow (see the `feedback-plugin-skill-conversion-
workflow` memory) defines a hard dependency as one skill *calling or spawning* another
unconditionally — `next` never invokes `/plan-feature`; it reads a doc `/plan-feature` merely
hosts because it owns the directory-naming convention (`/plan-feature` itself doesn't use the
algorithm — it creates the directory and already knows the slug). That's the same shape D9
already solved for `project-context-template.md`: canonical content that lives inside a
catalog-only tree a plugin consumer never clones. The catchup-variant escape hatch (reinventing
a simpler algorithm) was rejected here for the reason plan-directory.md's own "Catchup variant"
note already gives: `next` needs the *precise* algorithm, because it executes tasks out of
whatever directory it finds — a wrong directory is a wrong task list, not just a thinner
summary the way a missed catchup detail would be.

**Rejected.** Pulling `plan-feature` (and transitively its own deferred-cluster reasons — see
D12/the "Deferred" PLAN.md section) into the queue just to unblock `next`'s Step 1 — that cluster
is deferred as a unit for reasons unrelated to this one reference doc. Reimplementing `catchup`'s
looser issue-key-only algorithm for `next` — rejected per plan-directory.md's own explicit
warning not to unify the two.

**Consequence.** Two copies of `plan-directory.md` now need to move together by hand, same
maintenance duty D9 already established for the project-context template — extended here to a
second shared file. When `implement-plan`/`review-branch`/`pr`/`fix-bug` eventually convert (the
deferred cluster's own future pass), re-sync from the catalog original rather than re-deriving
independently — noted inline in the shipped copy's own "Catalog origin" section.
