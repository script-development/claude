---
name: plan-feature
description: |
  Structured feature planning workflow: interrogate the developer with hard, codebase-informed
  questions until requirements are crystal clear, then produce PLAN.md and DECISIONS.md. Use when
  planning a feature, designing a feature, "how should we build this", "let's plan", "I want to
  build X", or any request that needs architectural thinking before implementation. If a feature
  touches multiple layers (frontend + backend + migration), trigger this skill before coding.
---

# Plan Feature

You are entering interrogation mode. Your job is to deeply understand what needs to be built
before any code gets written. You will grill the developer with hard, specific questions informed
by the actual codebase — not generic product-manager questions.

The goal: by the end of this process, you and the developer have a shared, precise understanding
of what's being built, what's NOT being built, and how it should work in edge cases. Then you
produce the plan yourself — you have the deepest context, having read the code and run the
entire conversation.

## Phase 0: Parse arguments

The developer may pass a Kendo issue URL or key as an argument (e.g.,
`https://{{TENANT}}.kendo.dev/projects/{{PROJECT_ID}}/issues/{{ISSUE_KEY_PREFIX}}-0325` or just
`{{ISSUE_KEY_PREFIX}}-0325`).

**IMPORTANT: Issue key ≠ issue ID.** A key like `{{ISSUE_KEY_PREFIX}}-0343` does NOT mean the database
ID is 343. These are different values. Never extract the number from a key and use it as an ID.

If the repo has a `CONTEXT.md` glossary at its root, read it before grilling — it defines the
canonical domain terms and the aliases to avoid.

If an argument is provided:
1. Extract the issue key — for URLs, pull the `{{ISSUE_KEY_PREFIX}}-XXXX` segment from the path
2. Read `kendo://issues/{key}` to get the actual issue (including its real database ID)
3. Use this as your starting context for Phase 1 — skip the blind search and go straight
   to viewing the issue and any related epics

## Phase 1: Research before asking

If the repo has a root `CONTEXT.md` glossary, it is the vocabulary contract for this whole
session. If the developer uses a term that conflicts with the glossary, call it out and resolve
it; if the feature surfaces a new term that isn't defined, add it to `CONTEXT.md` the moment it's
resolved.

Then do the following:

### 1a. Check the Kendo board

Use `/kendo-mcp` to find existing issues, epics, and sprint context for the feature. Check if
there's already an epic with issues defined — the scope may already be broken down.

- Search for related issues using `mcp__kendo__search-issues-tool` with `project_id: {{PROJECT_ID}}`
- Read `kendo://projects/{{PROJECT_ID}}/epics` to check for relevant epics
- If issues exist, read each one via `kendo://issues/{key}` to understand the scope before
  asking questions the board already answers

If no issue exists for this feature, note it — you will create one before producing the plan
(see Phase 4a).

### 1b. Find the closest existing feature

Before designing anything, find the feature in the codebase that most closely resembles what
the developer wants to build. Trace it through the full stack — this becomes the blueprint:

- **Backend:** Route → Controller/Handler → Validation → Service/Action → DTO → Model →
  Resource/Serializer
- **Frontend:** Route → Page → Components → Store/State → Types

Use Glob/Grep to find the candidate. For example, if the developer wants to build "time tracking
on issues", look at how comments or attachments work on issues — they likely follow the same
relation pattern.

Once you find it, read the key files and note:
- How the backend logic is structured (single-action pattern? what validation?)
- How the frontend store is set up
- How the UI components are organized (page → sidebar → form?)
- What tests exist and how they're structured

This existing feature becomes the reference implementation in your plan. Every question you
ask and every decision in the plan should be framed relative to it: "Comments do X — should
this work the same way, or do we need something different here?"

### 1c. Audit existing code for reuse

This step is non-negotiable. The codebase already has components, helpers, services, and
patterns for most common needs. Building something that already exists wastes time and
creates inconsistency.

Check shared/common locations — actually browse them, don't guess from memory:
- Frontend shared modules (`shared/`, `lib/`, `common/`, etc.) — components, services,
  composables, form system, helpers
- Domain-specific helpers in the relevant domain and adjacent ones
- Backend shared modules — actions, services, helpers, base classes

Also find the closest existing page to the one you'd be building and note its layout pattern.
The new feature should look like it belongs in the app, not like a different product.

If the project provides a design-system skill (e.g. `/<project>-design-system`), use it for
any UI/design questions.

Make a concrete list of what you found. This list goes into Phase 2 questioning — present it
to the developer and confirm: "I found these existing pieces we can reuse. Anything I'm
missing, or should any of these be replaced instead of reused?"

### 1d. Sketch module shape (deep vs shallow) — apply the test, don't grade yourself

Before validating layers, decide what new modules this feature introduces and whether each is deep or shallow. Load [`references/module-shape-lens.md`](references/module-shape-lens.md) — read the **shallow-detection test** section in particular. The lens is three specific tests about interface complexity vs implementation per use case, not a vibe check. Implementation line count is not one of them: a Service with 200 lines of HTTP+SSE inside, one method, and 5 primitive params is shallow regardless of body length.

For each in-scope module, output one row to PLAN.md's "Key Design Decisions" table (or a dedicated Module-Shape sub-table) with these columns:

- **Inputs/outputs**
- **Hidden behaviour**
- **Test seam**
- **Shallow-test reckoning** — explicitly answer: "if a plausible second use case lands, do I add a *method* or a *parameter*?" Method ⇒ shallow-and-suspect. Parameter ⇒ likely deep.
- **Verdict** — deep / shallow-but-justified / shallow-and-suspect

The Shallow-test reckoning column is not optional. A row that says "Deep" without showing the reckoning is treated as missing for Phase 1.5 gap-analysis purposes.

Fold or expand any shallow-and-suspect module before continuing. The two fixes (demote into the caller, or promote to protocol primitives) are documented in the lens reference. Plan-time is the last cheap moment to fix this: no pre-PR reviewer grades module depth on its own, and a shallow module only surfaces later as the sibling drift and dead scaffolding `precedent-reviewer` flags — by which point the shape is already built.

### 1e. Validate against architecture rules

**Before proposing where classes live, check the architecture rules that enforce layer boundaries.**
Placing a class in the wrong layer will cause CI failures that force restructuring later. Read the
rule files as the source of truth — don't rely on summaries, they age.

Look for the project's architecture-rule definitions:
- Layer-dependency rules (e.g., Deptrac config, ArchUnit, custom rule files)
- Architecture tests (e.g., a `tests/Arch/` directory with naming/structure assertions)
- Frontend domain-boundary tests (e.g. `tests/arch/domain-structure.spec.ts`)

For every new class in the plan, verify: "Does this class's proposed layer allow it to depend
on everything it needs?" If not, move it to a layer that does — even if it feels semantically
off. The architecture tests are authoritative.

Common patterns to verify against arch tests (adapt to the project's stack):
- Action classes — naming suffix, single-method shape, no facades, transaction wrapping
- Controllers — naming suffix, no inline authorization
- Form Requests — naming suffix, `toDto()` method
- Resources/serializers — eager-load completeness
- Migrations — destructive-op rules

Include findings in the plan: "Proposed class X in layer Y — verified architecture rules allow
Y to depend on [list of needed layers]."

## Phase 1.4: Pre-flight verification (mandatory, fail-closed)

Every path and symbol the plan cites gets resolved mechanically before it lands. Projecting what *should* exist instead of grepping once cost a plan three reviewer rounds — [`references/anti-patterns.md`](references/anti-patterns.md) § Calibration records the four categories it produced.

Collect every path and symbol you're about to cite, one per line, and run them through the resolver:

```bash
printf '%s\n' 'app/Helpers/Slug.php' 'CreateWidgetAction' \
  | .claude/skills/plan-feature/scripts/verify-citations.sh
```

It resolves paths against the repo root plus `backend/` and `frontend/`, greps bare symbols and namespaces across the source trees, and tolerates a trailing line reference (`api.php:233-234`). It reports on every citation before exiting — one pass gives you the whole list, not the first failure. Repos with a different layout set `CITATION_PATH_PREFIXES` / `CITATION_SEARCH_ROOTS` (documented in the script header). **A `MISSING` line is a fabricated citation — fix it or drop the claim. You may not proceed past Phase 1.4 with a non-zero exit.**

Three claim shapes the script can't resolve, which you still owe by hand:

| Check | What | How |
|---|---|---|
| **Framework / library behaviour** | Every claim of the form "the framework does X" / "the ORM does Y" / "the SDK does W" | Cite `vendor/<package>/<file>:<line>` (or the `node_modules/` equivalent) that proves it (then run that path through the script), or weaken the claim to "verify at implementation time." No vibes on framework behaviour. |
| **Symbol-removal blast radius** | Every symbol you plan to delete or rename (Action, Event, route, FE function, type) | `grep -rn <symbol>` across every source tree and **inspect every hit**, not just the ones from the obvious feature path. The third callsite always lives somewhere unexpected (the calibration plan missed a bulk-assign caller of the endpoint it was deleting until round 2). |
| **Added-rule sweep inventory** | Every cross-cutting rule the plan **adds** — a header every response must stamp, a broadcast every status transition must fire, an audit hook every variant must call, a pattern every sibling component must adopt | `grep -rn` the sibling population (the route group, the write paths, the component family) and carry **every hit** into PLAN.md's `## Sweep Inventory`, each marked Applied or `Skipped — <reason>`. The blast-radius row covers what you remove; this row covers what you add. Review keeps finding site N+1 of an N-site sweep: one plan wired every write path but one, another broadcast every done-transition but one. |

Reviewers catch unverified confident claims; they will NOT reliably catch hedged ones. So anything you couldn't verify gets written as "verify at implementation time", not asserted.

## Phase 1.5: Gap analysis (mandatory, fail-closed)

Before any drafting, produce this literal checklist and mark each row **✓ Covered**, **? Partial**, or **✗ Missing**. Every ✓ requires a quoted source. **No ? or ✗ row may survive into drafting** — Phase 2 exists to close them, so an open row sends you there rather than blocking you. Phase 3 is what's unreachable while any row is still ? or ✗.

Load [`references/quality-gates.md`](references/quality-gates.md) for the rationale, sycophancy guards, and proceed/return rules.

| Required for a plan | Marker | Source (must quote / cite) |
|---|---|---|
| **Goal** — one sentence the developer would re-read and agree with | ✓ / ? / ✗ | issue body / first prompt — quote the line |
| **Acceptance criteria** — testable, observable, distinct from the goal (≥ 3) | ✓ / ? / ✗ | issue body — quote each, or mark missing |
| **In-scope** — explicit file list or domain boundary | ✓ / ? / ✗ | issue body / prompt / Phase 1b research |
| **Out-of-scope** — at least one explicit non-goal | ✓ / ? / ✗ | usually missing — interrogate |
| **Edge cases** — empty states, auth, errors, race conditions, scale | ✓ / ? / ✗ | usually missing — interrogate with concrete cases drawn from Phase 1b |
| **Architecture fit** — which existing feature does this resemble; what gets reused | ✓ / ? / ✗ | Phase 1b/1c findings — cite file paths |
| **Module shape** — every new in-scope module has the **shallow-test reckoning** filled in (not just a "Deep" label); any shallow-and-suspect module has been demoted or promoted | ✓ / ? / ✗ | Phase 1d output — a row that says "Deep" without showing the "method or parameter for the next use case?" reckoning counts as ✗, not ✓ |
| **Risk / uncertainty** — what could go wrong, what's unknown | ✓ / ? / ✗ | usually missing — interrogate |

Output the table verbatim to the developer with marks and citations filled in, and carry it into PLAN.md's `## Planning Evidence` section at Phase 4c. A table that exists only in chat is invisible to every downstream reviewer, which defeats the point of citing sources.

**Phase 1.6 comes next either way — it is never skipped.** After it:

- **All ✓** — skip the Phase 2 interrogation and go to Phase 3. The input is genuinely complete.
- **Any ? or ✗** — go to Phase 2, targeting only those rows. Don't sweep.

## Phase 1.6: Security & Cost Surface (mandatory, fail-closed)

Produce a `## Security & Cost Surface` section in PLAN.md with **six prose paragraphs**, each answering the questions for one row — or `N/A — <one-line reason>` when no question on the row applies. **You may not proceed past Phase 1.6 with any unanswered question on a populated row.**

The canonical questions and worked examples live at [`references/surface-questions.md`](references/surface-questions.md) — load it now. It is the single source of truth shared with the `surface-reviewer` agent at Phase 5. The rows are deliberately question-shaped, not field-shaped, so they generalise to feature shapes not seen yet.

Architecture tests do not cover this. They cover *code shape* — not the flow of untrusted bytes, billing dollars, audit fidelity, partial-failure state space, silent UX degradation, or enforcement of conventions the feature introduces. [`references/quality-gates.md`](references/quality-gates.md) carries the rationale and the sycophancy guards (paraphrasing the questions back is THIN, not OK; an LLM-touching feature cannot mark Row 1 N/A).

Output the six paragraphs to the developer for confirmation, then carry them into PLAN.md at Phase 4c. The `surface-reviewer` agent grades them at Phase 5.

## Phase 2: Interrogate

Now ask questions, **targeting only the ? and ✗ rows from Phase 1.5**. No generic sweep.

The mode is **interview with hypotheses**: for every question, propose your recommended answer with one-line rationale, and let the developer confirm or correct. The developer should be reacting to a stance, not authoring answers from cold. A multiple-choice quiz with no opinion attached makes the dev think from zero — that's a worse interview, not a politer one.

### Order of attack

Resolve in dependency order, not gap-table order. A late-discovered data-model change invalidates UI decisions made earlier — that's the most expensive form of mid-interview rework.

1. **Data model & boundaries** — what entities exist, what owns what, where data lives
2. **Behaviour & permissions** — what happens when, who can do what, what's transactional
3. **UI shape** — page vs panel vs modal, layout pattern to mirror
4. **Edge cases & error paths** — empty states, race conditions, scale, failure modes

Don't ask a UI question before the data model is settled. If a row in the gap table is downstream of an unanswered upstream row, defer it.

### Self-serve before asking

Before sending an `AskUserQuestion`: can the codebase answer this? If yes, **answer it from the code and ask for confirmation**, not for the answer. "I see the board uses WebSockets via `useRealtimeChannel.ts:42` — confirming we wire this feature the same way?" is one click. "Should this be real-time?" wastes the dev's attention on something we already know.

If the dev makes a claim about how the code behaves and you suspect it's wrong, **check the code before continuing**. Surfacing a contradiction ("you said X, but `app/Actions/Widgets/CloseWidgetAction.php:88` does Y — which is right?") is more valuable than tactfully agreeing.

### First round: present what you found

Your first question round should always present what you discovered in Phase 1. Before asking
about scope or behavior, show the developer:

1. **The reference feature** you found — "I looked at how [comments/attachments/reports] work.
   It follows [pattern]. I'd like to use that as the blueprint. Sound right?"
2. **Shared code you plan to reuse** — "I found these existing pieces: [list]. Anything missing
   or anything you'd rather rebuild?"
3. **The UI pattern you'd mirror** — "The closest existing page is [settings/project detail/
   issue list]. I'd follow that layout. Does that match what you have in mind?"

This grounds the conversation in the actual codebase and catches "we already have that" early.

### Rules for questioning

- **Every round goes through `AskUserQuestion`** — up to 4 questions per call, each with 2–4 concrete options drawn from the codebase. The developer clicks; they don't parse paragraphs or type prose. Use previews for UX choices (modal vs page, inline vs form).
- **Lead with a stance.** Each question's description carries "I'd pick X because Y" — the dev reacts to a recommendation, not a blank quiz.
- **Push back on vague answers.** "It should be flexible" or "whatever makes sense" is not an answer — ask for the concrete case behind it.
- **Probe relationships with a specific story**, not an abstract category: "User A has record X open with two unsaved child rows; User B archives X while A is still editing — what happens to A's save?" surfaces boundary disagreements that "what about race conditions?" doesn't.
- **Live glossary check.** If the repo has a root `CONTEXT.md`, an answer using a term that conflicts with it stops the round: surface the conflict, propose the canonical term, update `CONTEXT.md` inline. Don't let domain language drift mid-conversation.
- **Restate after every round** in 2-3 lines — "Agreed so far: A → X, B → Y. Open: Z." In-flight alignment means Phase 3 is a final sanity check rather than the only moment the developer can object.
- **Keep text between rounds under 5 lines.** Summaries and context, not essays.

### When to stop asking

Stop when ALL of the following are true — however many rounds that takes:
- You know exactly what the user will see and interact with
- You know what data is involved and where it lives
- You know the scope boundaries (in AND out)
- You know how edge cases are handled
- You've identified which existing patterns to follow
- You can write at least 3 verifiable acceptance criteria that the developer agrees with

## Phase 3: Confirm understanding

Before producing the plan, write a summary and get explicit confirmation:

```
Here's my understanding:

**What we're building:** [one sentence]
**In scope:**
- [explicit list]

**Out of scope:**
- [explicit list]

**Key decisions:**
- [each non-obvious decision from the Q&A]

**Edge cases:**
- [how each is handled]

**Patterns to follow:**
- [specific files/components to mirror]

**Acceptance criteria:**
- [ ] [verifiable pass/fail condition with how to check it]
- [ ] ...

Is this correct? Anything to add or change?
```

Do NOT proceed until the developer confirms. If they correct something, update the summary and
confirm again.

## Phase 4: Produce and save the plan

Once the developer confirms, do the following:

### 4a. Ensure a Kendo issue exists

If no issue was found in Phase 1a:
1. Read the [issue-templates.md](../kendo-mcp/references/issue-templates.md) — the single source of truth for the Feature and Bug formats
2. Create an issue via `mcp__kendo__create-issue-tool` with `project_id: {{PROJECT_ID}}`, writing the description **against** the matching template (Feature: User Story / Context / Acceptance Criteria / Scope / Testing — Bug: Problem / Cause-or-repro / Acceptance Criteria / Scope / Testing). Don't improvise a structure.
3. Note the returned issue key (e.g., `{{ISSUE_KEY_PREFIX}}-0244`)

If an issue already exists, use its key.

### 4b. Write DECISIONS.md

Write decisions to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-slug/DECISIONS.md` **as they are made** during planning, not after — rejected proposals and their reasoning are valuable context.

Use the format and rules in [`references/decisions-template.md`](references/decisions-template.md).

### 4c. Write PLAN.md

Save the plan to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-slug/PLAN.md` using the structure in [`references/plan-template.md`](references/plan-template.md). The template is the contract — downstream agents (`plan-reviewer`, `surface-reviewer`, `/wireframe`, `/task-writer`, `precedent-reviewer`) parse the section names, so don't rename or omit them.

### 4d. Template completeness check (mandatory, fail-closed)

Before spawning the reviewers, verify every section of the saved PLAN.md is substantive. Mark each row **OK** if the bullet rule is met **or** if the section explicitly declares `N/A — <one-line reason>`. Otherwise **THIN** — re-work before continuing.

Load [`references/quality-gates.md`](references/quality-gates.md) for the rationale, the N/A carve-out, and sycophancy guards.

| Section | OK requires |
|---|---|
| Goal | one sentence; describes user-visible outcome, not implementation |
| Key Design Decisions | ≥ 1 row per non-trivial new module; every choice cites a concrete codebase reference |
| Planning Evidence | the Phase 1.5 gap table, all eight rows ✓ with their quoted sources |
| Scope — In | explicit list, not "the feature" |
| Scope — Out | ≥ 1 explicit non-goal |
| Sweep Inventory | every cross-cutting rule the plan adds has its sibling-site table (from the Phase 1.4 grep), zero unmarked rows; **or** explicit `N/A — no cross-cutting rule added` |
| Security & Cost Surface | six rows, each a prose answer to the row's questions or `N/A — <reason>`; carried forward from Phase 1.6 |
| Approach | enumerates files/components in implementation order |
| Acceptance Criteria | ≥ 3 verifiable rows with a Verification column filled in |
| Shared Reuse | ≥ 1 entry **or** an explicit "no reuse — building from scratch because X" line |
| Patterns to Follow | ≥ 1 file path; not "follow project conventions" |
| Testing Strategy | per-PR test table with named test files, behavioural descriptions, and a **red case** per test ("fails when ___" — unstatable red case means the test is decoration); every new gate/ban/allowlist names its committed negative fixture; every new test file names the CI job that runs it |
| Edge Cases | ≥ 3 cases drawn from the Phase 1.5 ✓ Edge Cases evidence |
| Risks | ≥ 1 specific risk; not "the implementation may have bugs" |
| Wireframes / Migration / Site Docs Sync | substance OR explicit `N/A — <reason>`; Site Docs Sync marks each doc surface **and its mirror** (e.g. an LLM-facing text export of the docs, if the repo ships one) Update / N/A per row |
| Hedge parentheticals | Zero `(or whatever)` / `(TBD)` / `(or X)` hedges on load-bearing claims. A hedge papers over a decision you owe — decide it and cite it (Phase 1.4), or escalate via `AskUserQuestion`. |

When every row is OK, proceed to Phase 5.

## Phase 5: Self-gate and hand off

**Before showing the plan to the developer**, spawn **two reviewers in parallel** against the saved PLAN.md:

- `plan-reviewer` — scores 1-10 against codebase conventions (enums, auth, module shape, arch tests). Owns the convention bar.
- `surface-reviewer` — scores 1-10 against the six question-shaped rows of the Security & Cost Surface section, with `mode: "plan"`. Owns the security / cost / audit / lifecycle / enforcement bar.

**Spawn both in a single message with two `Agent()` calls** so they run concurrently. Do not issue them sequentially — if parallel spawning is unavailable in this environment, stop and say so instead. The reviewers are designed to run on a static snapshot of PLAN.md at the same moment; sequencing them lets the second see partial edits from the first and undermines the independent-context property that makes the dual-spawn valuable.

Both must score ≥ 7 to proceed. Below 7 on either, fix the relevant section of the plan and re-run that reviewer until it passes. The two reviewers exist because you'll rationalise your own design choices — context-free agents won't. They probe different surfaces (codebase conventions vs cross-cutting non-functional gaps), so a clean score on one doesn't substitute for the other.

Then present the plan + both reviewer reports to the developer and ask: "Does this look good?". When approved, update PLAN.md `Status: Approved`.

### Handoff

Plan is approved. Stop here — the next step is a separate skill, owned by the developer (or by Claude in continuation):

- **Frontend in scope** — invoke `/wireframe`. It owns generating `WIREFRAMES.md` and self-gates with `wireframe-reviewer`. Then `/task-writer` (or `/implement-plan` for small plans).
- **Backend-only** — go straight to `/task-writer` or `/implement-plan`.

Do not invoke `/wireframe`, `/task-writer`, or their reviewers from inside this skill. Each downstream skill owns its own quality gate; chaining them here would recreate the mega-skill we just trimmed away.

## Anti-patterns to avoid

See [`references/anti-patterns.md`](references/anti-patterns.md) — lessons-from-pain captured outside SKILL.md so they're loaded once on demand, not every invocation.
