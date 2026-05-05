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

If an argument is provided:
1. Extract the issue key — for URLs, pull the `{{ISSUE_KEY_PREFIX}}-XXXX` segment from the path
2. Read `kendo://issues/{key}` to get the actual issue (including its real database ID)
3. Use this as your starting context for Phase 1 — skip the blind search and go straight
   to viewing the issue and any related epics

## Phase 1: Research before asking

Before asking a single question, do these things:

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

### 1d. Sketch module shape (deep vs shallow)

Before validating layers, decide what new modules this feature introduces and whether each is deep or shallow.

A **deep module** hides a lot of behaviour behind a small interface and rarely changes — easy to test in isolation, hard to break. A **shallow module** is a thin wrapper whose interface is almost as complex as its implementation — usually a sign that the abstraction isn't carrying its weight.

**In scope** — apply the deep/shallow lens to: actions, services, helpers, composables, stores, **domain models** (especially new ones introduced for this feature), and any class introduced specifically for this feature whose shape isn't dictated by a framework convention.

**Exempt — framework-shaped artefacts.** Skip the lens for these; their shallowness is intrinsic to the role, not a design smell:

- Email/notification envelope classes (e.g. Laravel Mailables, with only `envelope()` + `content()`)
- Exception classes (carry a message, no behaviour)
- Icon components (single `<svg>`)
- Migration classes
- DTO / ResourceData classes
- Form-request / validation-only classes
- Controllers (HTTP-layer dispatch)
- MCP tool classes
- **Single-purpose query scopes** (e.g. one `scopeFoo()` query-builder method added to an existing model — *not* whole new model classes)

The model distinction matters: a `scopeVisibleTo()` method added to an existing `User` is exempt; a brand-new `IssueWatcher` model whose entire interface is `belongsTo user()` + `belongsTo issue()` is **not** exempt — it's the canonical shallow module a simplicity reviewer catches. If a new model class has zero domain behaviour beyond its relations, it earns nothing over a plain pivot relation and should be folded out.

For each in-scope module, answer:

- **Inputs/outputs** — the smallest interface that does the job
- **Hidden behaviour** — what this module knows that callers don't have to
- **Test seam** — what you'd test through the public interface, in plain English ("can register, then verify, then revoke")
- **Verdict** — deep, shallow-but-justified (e.g. one-shot adapter or a precedent-cited pattern with explicit rationale), or shallow-and-suspect

If a module comes back **shallow-and-suspect**, either fold it into the caller or expand its responsibility. Don't ship a five-shallow-modules-glued-together design. This is the single most common failure mode caught later by `simplicity-reviewer` — surface it now, while the design is cheap to change.

The output goes into PLAN.md's "Key Design Decisions" table as one row per non-trivial module, with the test seam captured separately under "Testing Strategy".

### 1e. Validate against architecture rules

**Before proposing where classes live, check the architecture rules that enforce layer boundaries.**
Placing a class in the wrong layer will cause CI failures that force restructuring later.

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

## Phase 1.5: Gap analysis (mandatory, fail-closed)

Before any drafting and before deciding how deep to interrogate, produce a literal checklist of what a complete plan needs and mark each row as **✓ Covered**, **? Partial**, or **✗ Missing**. This gate exists because the path of least resistance — "this looks crisp, let me draft and we can iterate" — is the most expensive failure mode in planning. A draft built on partial information costs a full restart later. The checklist makes "is the input complete?" a binary question instead of a feel.

**The rule:** every ✓ requires a quoted source. Every ? or ✗ is a topic for Phase 2 interrogation. **You may not proceed past Phase 1.5 with any ? or ✗ row.** Fail-closed.

| Required for a plan | Marker | Source (must quote / cite) |
|---|---|---|
| **Goal** — one sentence the developer would re-read and agree with | ✓ / ? / ✗ | issue body / first prompt — quote the line |
| **Acceptance criteria** — testable, observable, distinct from the goal (≥ 3) | ✓ / ? / ✗ | issue body — quote each, or mark missing |
| **In-scope** — explicit file list or domain boundary | ✓ / ? / ✗ | issue body / prompt / Phase 1b research |
| **Out-of-scope** — at least one explicit non-goal | ✓ / ? / ✗ | usually missing — interrogate |
| **Edge cases** — empty states, auth, errors, race conditions, scale | ✓ / ? / ✗ | usually missing — interrogate with concrete cases drawn from Phase 1b |
| **Architecture fit** — which existing feature does this resemble; what gets reused | ✓ / ? / ✗ | Phase 1b/1c findings — cite file paths |
| **Module shape** — deep modules identified; shallow-and-suspect modules resolved | ✓ / ? / ✗ | Phase 1d output |
| **Risk / uncertainty** — what could go wrong, what's unknown | ✓ / ? / ✗ | usually missing — interrogate |

**Output the table verbatim to the developer** with marks and citations filled in. Then either:

- **All ✓** — say "All eight checks pass with cited evidence. Proceeding to Phase 3 confirmation." Skip Phase 2 interrogation; the input is genuinely complete.
- **Any ? or ✗** — list the missing rows and proceed to Phase 2 to fill them. Phase 2 questions target only ? and ✗ rows. Don't sweep.

**Sycophancy guards:**

- A ✓ without a quoted source is invalid. If you can't cite it, mark ?.
- An issue body of "Add settings page for X" cannot mark Acceptance Criteria ✓ — there's nothing testable in there.
- A long developer prompt is not evidence of completeness. Length doesn't make a row ✓; only specifics do.
- "Edge cases will be handled during implementation" is ✗, not ✓.

This gate also gives `plan-reviewer` something concrete to verify post-hoc — every ✓ in the checklist must have produced a corresponding section of PLAN.md grounded in that evidence.

## Phase 2: Interrogate

Now ask questions, **targeting only the ? and ✗ rows from Phase 1.5**. No generic sweep. Your questions should demonstrate that you've read the codebase — reference specific files, patterns, and existing behavior.

### Use AskUserQuestion, not text walls

**CRITICAL:** All questions MUST go through the `AskUserQuestion` tool — not as plain text in
your response. The developer should not have to read paragraphs and mentally parse questions.
Each question becomes a selectable option they can answer quickly.

- Group 3-4 related questions into one `AskUserQuestion` call
- Provide concrete options (not open-ended) — the developer picks from choices informed by the codebase
- Use previews for UX choices (e.g., modal vs page, inline vs form)
- Short text summaries are fine between question rounds, but keep them under 5 lines

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

### What to ask about

- **Scope boundaries** — "You said X. Does that include Y? Where does this feature stop?"
- **User behavior** — "What happens when a user does Z? What if they do it twice? What if they do it while someone else is doing W?"
- **Edge cases** — "What about empty states? What about 500 items? What about permissions — who can and can't do this?"
- **Existing patterns** — "I see `[specific file]` handles something similar by doing A. Should we follow that pattern or is there a reason to diverge?"
- **Priority trade-offs** — "This could be done as a quick version without B, or a full version with B. Which matters more right now?"
- **What's NOT being built** — "Just to be clear: this does NOT include C, correct?"
- **Data model** — "Where does this data live? New table? New column on existing table? Derived from existing data?"
- **UI expectations** — "Is this a new page, a panel, a modal, or part of an existing view?"

### Rules for questioning

- **Use `AskUserQuestion` for every round.** Never dump questions as plain text. The developer answers by clicking options, not by reading paragraphs.
- **3-4 questions per `AskUserQuestion` call.** The tool supports 1-4 questions — use that constraint.
- **Provide concrete options.** Each question should have 2-4 selectable choices informed by the codebase. The developer picks, not types.
- **Push back on vague answers.** If the developer says "it should be flexible" or "whatever makes sense", don't accept it. Follow up: "Flexible how? Give me a concrete example of what a user would do."
- **Minimum 2 rounds of questions.** Even if the first round covers a lot, there are always follow-ups. Complex features need 3+ rounds.
- **Reference the codebase** in your questions. "I see the board view uses WebSockets for real-time updates. Should this feature also update in real-time, or is polling fine?" is much better than "Should this be real-time?"
- **Short text between rounds is fine** — but keep it under 5 lines. Summaries and context, not essays.

### When to stop asking

Stop when ALL of the following are true:
- You know exactly what the user will see and interact with
- You know what data is involved and where it lives
- You know the scope boundaries (in AND out)
- You know how edge cases are handled
- You've identified which existing patterns to follow
- You can write at least 5 verifiable acceptance criteria that the developer agrees with

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
1. Read the [issue-templates.md](../kendo-mcp/references/issue-templates.md) for the feature + bug templates
2. Create an issue via `mcp__kendo__create-issue-tool` with `project_id: {{PROJECT_ID}}` and a clear title and description
3. Note the returned issue key (e.g., `{{ISSUE_KEY_PREFIX}}-0244`)

If an issue already exists, use its key.

### 4b. Write DECISIONS.md

Write decisions to `docs/plans/<KEY>-<slug>/DECISIONS.md` as they are made. Don't wait until
the plan is finalized — rejected proposals and their reasoning are valuable context.

```markdown
# <KEY>: Decisions

## D1: [Short decision title]
**Status:** Accepted | Rejected | Superseded by D3

**Context:** [What triggered this decision — the problem or question]

**Options considered:**
1. **[Option A]** — [brief description]
   - Pro: [...]
   - Con: [...]
2. **[Option B]** — [brief description]
   - Pro: [...]
   - Con: [...]

**Decision:** [Which option and why]

**Consequences:** [What this means for implementation]
```

Rules:
- Write each decision **the moment it's made** during planning, not after
- Rejected proposals get their own entry with `Status: Rejected` — they explain why NOT
- Keep entries concise — 5-10 lines per decision, not essays
- PLAN.md references decisions by number (e.g., "see D3") instead of repeating reasoning

### 4c. Write PLAN.md

Save the plan to `docs/plans/<KEY>-<slug>/PLAN.md`:

```markdown
# <KEY>: <name>

**Date:** <YYYY-MM-DD>
**Status:** Draft
**Issue:** [<KEY>](link to issue)
**Decisions:** [DECISIONS.md](DECISIONS.md)

## Goal
<one sentence — what this enables for the user>

## Key Design Decisions

Short table of every structural choice the developer should review. This section exists so the
developer can catch convention violations in 30 seconds without parsing the full plan.

| Decision | Choice | Convention Reference |
|----------|--------|---------------------|
| <what needed deciding> | <what you chose> | <file:line or pattern that proves this matches the codebase> |

Examples of what belongs here:
- Enum type: "int-backed enum + matching frontend type" → reference existing enum file
- Where auth logic lives: "Interaction class in `Policies/Interactions/`" → reference existing interaction
- Data storage: "new pivot table" → reference existing pivot table
- Frontend state: "adapter-store pattern" → reference existing store file

**Every choice must cite a concrete codebase reference.** If you can't point to an existing
file that proves this matches the conventions, flag it as a deliberate deviation and explain why.

**Architecture-rule compliance:** For each decision that creates a new structural component
(controller, action, model, DTO, migration, etc.), note the architecture rules it must satisfy.
Example: "New DeleteReportAction — must be final readonly, single execute(), inject
ConnectionInterface, wrap mutations in transaction (per ActionsTest), call audit logger
(per AuditTest)."

**Layer-dependency compliance:** For each new class, note which layer it lives in and confirm
the layer's dependency rules allow it to depend on everything it needs (per the project's
layer-dependency config).

## Wireframes

<if feature includes frontend work>
Structured screen specifications: [WIREFRAMES.md](WIREFRAMES.md) — design tokens, component names,
props, emits, and layout hierarchies. Generated by `/wireframe` after plan approval.
The acceptance-reviewer verifies implementations against this spec.
<else>
No frontend changes — wireframes not applicable.

## Scope
- **In scope:** <explicit list>
- **Out of scope:** <explicit list — things confirmed we're NOT building>

## Approach
<which files to create/modify, in what order>

## Acceptance Criteria

Verifiable conditions that must ALL be true for this feature to be complete.
QA will check each criterion against the implementation.

| # | Criterion | Verification |
|---|-----------|-------------|
| 1 | <user-visible outcome — binary pass/fail> | <how to verify: route to visit, action to take, assertion to check> |
| 2 | ... | ... |

## Shared Reuse
<list shared components, services, and patterns being reused — with file paths>

## Patterns to Follow
<reference existing code that does something similar, with file paths>

## Migration / Schema Changes
<if applicable — table changes, new columns, indexes>

## Testing Strategy

### Mandatory Rules
1. **TDD is non-negotiable:** Write failing tests first → implement to make them green → refactor
2. **The project's testing skill MUST be loaded before writing any test** (where the project
   provides one)
3. **Coverage thresholds** as defined by the project (often 100% on new business-logic classes)
4. **Use the project's narrowed/pipeline test commands**, not full-suite watch mode

### Testing Philosophy
Test behavior, not implementation. Every test answers "what can the user do?" not "what
does the code call internally?"

### Per-PR Test Tables
<for each PR, include a table with test file names and behavioral test descriptions>
<test names MUST start with "should" and describe user-visible outcomes>
<3-6 tests per component — more means you're testing implementation>

## Documentation Sync

If the feature changes any user-facing capability or API surface, list which docs need updating
(e.g. `docs/api/`, `docs/guides/`, README sections, MCP tool docs, CLI man pages).

## Edge Cases
<cases from the Q&A — how each is handled>

## Risks
<what could go wrong, what to watch for during implementation>
```

### 4d. Template completeness check (mandatory, fail-closed)

Before spawning `plan-reviewer`, verify every section of the saved PLAN.md has substantive content. This is the **output gate** — the symmetric pair to Phase 1.5's input gate. The two gates catch different failure modes: the input gate catches "drafted on partial information," and this gate catches "drafted with thin filler text in the gaps."

For each section below, mark **OK** if the bullet rule is met **OR** if the section explicitly declares `N/A — <one-line reason>` (e.g. "Wireframes — N/A, backend-only feature"). Otherwise **THIN** and re-work the section before continuing.

The N/A carve-out exists because pure-content plans (translation work, refactor-only changes, backend-only features) legitimately have empty Wireframes / Migration / Documentation Sync sections, and treating those as THIN would block them. An explicit N/A with a reason is substance — silent emptiness or "TBD" is not.

| Section | OK requires |
|---|---|
| Goal | one sentence; describes user-visible outcome, not implementation |
| Key Design Decisions | ≥ 1 row per non-trivial new module; every choice cites a concrete codebase reference |
| Scope — In | explicit list, not "the feature" |
| Scope — Out | ≥ 1 explicit non-goal |
| Approach | enumerates files/components in implementation order |
| Acceptance Criteria | ≥ 3 verifiable rows with a Verification column filled in |
| Shared Reuse | ≥ 1 entry **or** an explicit "no reuse — building from scratch because X" line |
| Patterns to Follow | ≥ 1 file path; not "follow project conventions" |
| Testing Strategy | per-PR test table with named test files and behavioural descriptions, not "add tests" |
| Edge Cases | ≥ 3 cases drawn from the Phase 1.5 ✓ Edge Cases evidence |
| Risks | ≥ 1 specific risk; not "the implementation may have bugs" |
| Wireframes / Migration / Documentation Sync | substance OR explicit `N/A — <reason>` |

**Sycophancy guards specific to the output:**

- "TBD" in any row is THIN, not OK. If you don't know yet, you shouldn't be at Phase 4.
- A section consisting of one bullet is THIN unless the bullet rule explicitly allows it.
- Acceptance Criteria written as goals ("the feature should work well") are THIN. Each row is a binary observable.
- Restating the Goal in different sections doesn't count toward those sections' bulk.

If any row is THIN, fix the section using evidence from Phase 1.5 / Phase 2 transcripts. Do not invent new content here — that's a sign the input gate let something slip and you should re-open Phase 2 for that topic.

When every row is OK, proceed to Phase 5.

## Phase 5: Plan convention review

**Before showing the plan to the developer**, spawn the **plan-reviewer** agent to check the
plan against codebase conventions. This is a separate agent with no shared context from the
planning conversation — it has no investment in your design decisions.

Spawn the plan-reviewer with the plan file path. It reads the project's conventions and checks
every design decision against the actual codebase.

The plan-reviewer scores the plan from 1-10 on convention compliance. Plans scoring below 7
do NOT go to the developer.

If the score is below 7:
1. Fix the plan to match conventions
2. Re-run the plan-reviewer until the score is 7 or above
3. Only then proceed to developer review

This step exists because the planner (you) is cognitively primed to defend its own design
choices. A separate agent with no context of why you chose strings over ints will simply check
whether the plan matches the codebase. It has no reason to rationalize.

### 5a. Present and confirm

Present the plan to the developer along with the plan-reviewer's report, and ask: "Does this
look good? Ready to generate wireframes and tasks?"

When approved, update the plan status to `Approved`.

### 5b. Generate wireframe specifications

If the feature includes **any frontend work** (new pages, components, modals, or modifications
to existing UI), invoke `/wireframe` to generate `WIREFRAMES.md` in the plan directory.

This step happens while you still have full context from the planning conversation — the feature
scope, the codebase research, the reference pages you found, and the design decisions. The
wireframe skill uses this context plus the project's design system tokens to produce structured
screen specifications.

Skip this step only if the feature is purely backend (no UI changes at all).

### 5c. Wireframe review

After wireframes are generated, spawn the **wireframe-reviewer** agent to check WIREFRAMES.md
for completeness, token validity, component references, and consistency. This is a separate
agent with no shared context — it verifies the spec independently.

Spawn the wireframe-reviewer with the plan directory path. It checks:
- All screens from PLAN.md's frontend scope are covered
- Design tokens are valid (exist in the codebase)
- Referenced shared components exist or are well-defined
- Internal consistency across the spec sections
- UI-related acceptance criteria are traceable to wireframe specs

The wireframe-reviewer scores the wireframes from 1-10. Wireframes scoring below 7 do NOT
proceed to task breakdown.

If the score is below 7:
1. Fix the wireframes to address the reviewer's findings
2. Re-run the wireframe-reviewer until the score is 7 or above
3. Only then proceed to the developer

After wireframes pass review, ask: "Wireframes ready. Want to proceed to `/task-writer`?"

## Anti-patterns to avoid

- **Dumping questions as plain text** instead of using `AskUserQuestion` — the developer should click answers, not parse paragraphs
- **Writing long summaries** expecting the developer to read them — keep text between rounds under 5 lines
- **Skipping the issue-tracker check** — issues and epics may already define the scope
- **Skipping the shared code audit** — don't plan to build what already exists in shared modules
- **Writing "add tests" without behavioral detail** — every test in the plan must describe a user-visible outcome, not an implementation check. Read the project's testing skills (where they exist) to understand the testing philosophy before writing test requirements
- **Generic questions** that could apply to any product — ground every question in the codebase
- **Asking about low-level implementation details** — "Should we use a computed property or a watcher?" — that's the developer's call during implementation
- **Skipping the codebase read** and asking questions that the code already answers
- **Accepting vague answers** without probing deeper — "it should be flexible" is not an answer
- **Self-reviewing your own conventions usage** — you will rationalize your choices. The plan-reviewer agent exists specifically to catch what you won't. Never skip Phase 5.
- **Leading questions** that assume the answer: "Should we use the same pattern as X?" — instead ask "I see X uses pattern A. What are your thoughts on following that here vs. doing something different?"
- **Designing from first principles instead of from the codebase** — if the codebase uses int-backed enums, your plan uses int-backed enums. If the codebase puts auth logic in Interactions, your plan puts auth logic in Interactions. You don't get to invent a "better" approach unless the developer explicitly asks for a deviation.
- **Burying design decisions in the plan body** — the developer should not have to read 400 lines to find that you chose `category (string)` over `resource (tinyInteger)`. Key Design Decisions go in the table at the top. If a structural choice isn't in that table, it's invisible to review.
