---
name: wireframe
description: >
  Generate structured UI wireframe specifications (WIREFRAMES.md) for feature plans. Creates
  AI-readable screen specs with ASCII wireframes, design tokens, component breakdowns, and
  interaction specs. Use after /plan-feature produces PLAN.md, whenever the user mentions
  "wireframe", "create wireframes", "design the screens", "screen specs", "UI spec", or wants
  to define what frontend pages/components should look like before implementation. Also trigger
  when the user says "what should the page look like" or "define the UI" for a planned feature.
---

# Wireframe Specification Generator

Generate a `WIREFRAMES.md` that answers one question: **"What does the user
see and interact with?"**

**`wireframe-reviewer`** consumes this file immediately after generation —
screen coverage, token validity, component references, internal consistency,
AC traceability (score ≥ 7 to proceed). **Token format must be exact** — it
matches tokens literally.

Its real audience after that is the implementer. No pre-PR agent greps this
spec against the shipped component templates, so wireframe-vs-implementation
fidelity rests on whoever builds the screen and on the specs they write. Make
the file precise enough for a human to diff by eye.

Every line should help someone build or verify the UI. Architecture, data
flow, file lists, and accessibility belong in PLAN.md and TASKS.md, not
here.

**Reference example:** `references/issue-board.md` for format
inspiration (note: that file includes extra sections like Visual Narrative
and Bold Choices that are useful for design documentation but are NOT part
of the wireframe spec format).

## Prerequisites

Before generating wireframes, load the project's token vocabulary. If the
project provides a design-system skill (e.g. `/<project>-design-system`),
invoke it. Otherwise read the CSS/utility framework config (Tailwind config,
UnoCSS config, CSS variables file, theme file) to learn the available tokens
and naming conventions.

## Workflow

### Step 1: Locate the plan

Use the canonical algorithm in
[`plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md),
then read `PLAN.md`. Extract the frontend PR file list, acceptance
criteria, and scope.

#### 1a: Zero-UI-scope guard (mandatory)

Before designing anything, check whether this plan has UI scope at all.
Look at PLAN.md for:

- Frontend file list under "Approach" (any `.vue`, `frontend/src/**`, components/pages/modals)
- Wireframes section that explicitly says "No frontend changes — wireframes not applicable"
- Acceptance criteria that mention user-visible behaviour (page, button, modal, toast, list)

If **none** of those are present, this plan is backend-only. Output one
line and stop:

> "PLAN.md has no UI scope (no frontend files, AC are backend-only). WIREFRAMES.md isn't needed for this feature. Skipping."

Don't invent screens to fill the gap. If the developer thinks there should
be UI and the plan says otherwise, the right fix is to update PLAN.md, not
to extrapolate here.

#### 1b: Resume vs. restart

Check whether `WIREFRAMES.md` already exists in the plan directory.

- **Doesn't exist** — proceed normally to Step 2.
- **Exists with substantive content** (≥ 1 screen with ASCII wireframe + spec + interactions) — enter **resume mode**: read the existing file, identify which screens are still skeletal or missing, and design only those. Don't overwrite work the developer or a previous run already produced.
- **Exists but empty / placeholder-only** — treat as "doesn't exist" and proceed normally.

In resume mode, present a one-line summary of what you found
("WIREFRAMES.md has 2 screens covered, 1 placeholder, 1 missing — filling
the placeholder and the missing one") before continuing.

### Step 2: Research existing layout patterns

Find the closest existing screens in the codebase for each planned page:

1. Glob for page/view components in the project's source directories
   (overview/list pages, detail/show pages, settings pages, confirm and
   form modals)
2. Read 2-3 reference components — note their tokens, layout composition, and action patterns
3. Check shared/common component directories for reusable components to reference (not reinvent)

Also check during research:

- **Icons** — Glob for the project's icon components. If you'll need icons that don't exist, flag them as "needs creation" in the wireframe with the correct location.
- **Badge/tag patterns** — If the feature needs status badges, read the existing badge component and use its supported variants / colour classes rather than inventing new colour combinations.
- **State management patterns** — How do existing pages fetch and manage data? Some areas may use stores, others inline API calls. Match the existing pattern for the area you're wireframing, and name it the way that area does.

### Step 3: Design interrogation

Before writing the spec, ask the developer design questions using
`AskUserQuestion`. The plan decided *what* to build — you now decide *how
it looks and behaves*. This is where visual and interaction design
decisions get made.

#### What to present first

Show the developer what you found in Step 2 — the reference pages, their
layout patterns, and what you'd reuse. Ground every question in the
codebase:

> "The closest existing page is the settings detail page — section cards with accent-border titles and detail rows. I'd follow that pattern for the new details section. Does that match what you have in mind, or should this page feel different?"

#### What to ask about

For each screen, ask about design choices that aren't obvious from the
plan:

- **Page structure** — "Should this be one scrollable page with sections, or tabs like the users domain (Active / Deleted / 2FA)?"
- **Information hierarchy** — "The billing page needs to show plan, seats, billing date, invoices. What's most important? Should plan + seats be promoted as stat boxes at the top, or is a simple detail list enough?"
- **New patterns** — "This feature needs a progress bar for seat usage — that doesn't exist in the app yet. Should it be a thin inline bar under the stat value, or a standalone component with percentage label?"
- **Upgrade prompts** — "When the user hits a limit, should we show a modal (interrupts flow, forces decision) or an inline banner (visible but doesn't block)?"
- **Action placement** — "Should 'Manage subscription' be a button in the section title bar (like edit buttons on detail pages) or a separate card/section?"
- **Empty states** — "What does the billing page show for a free tenant with no payment history? Just the plan details, or an upgrade-focused layout?"

Use `AskUserQuestion` with concrete options — include ASCII previews when
comparing layout alternatives. Show 2-3 options per question, grounded in
what exists in the codebase.

#### Rules for design questions

- **2-3 rounds max.** This is focused design, not a full product discovery session.
- **Always provide options from the codebase.** "The users page uses tabs. The project detail uses a single scrolling page. Which pattern fits billing?" — not "how should we lay it out?"
- **Show, don't describe.** Use ASCII previews in `AskUserQuestion` options to let the developer see the difference between layouts.
- **Default to existing patterns.** If the codebase already has an obvious pattern for this type of page, present it as the recommended option. Only ask when there's a genuine choice.
- **Skip questions the plan already answered.** If the plan says "dedicated billing page in sidebar" — don't ask "should this be a page or a modal?"

#### When to skip interrogation

Skip design questions entirely when:

- The feature only modifies existing screens (adding a column, a section, a button)
- Every screen directly mirrors an existing page pattern with no new components
- The developer explicitly says "just follow existing patterns, don't ask"

### Step 4: Write WIREFRAMES.md

Save to the plan directory. The document has **exactly 5 sections** —
ASCII Wireframes, Component Breakdown, Shared Components, Screen
Specifications, Interaction Specification. The full template, per-section
rules, token tables, and "what does NOT belong" list live in
[`references/wireframes-template.md`](references/wireframes-template.md).
Load it before writing — `wireframe-reviewer` parses the section names
literally, so the structure has to match exactly.

### Step 5: Self-gate with wireframe-reviewer

Once `WIREFRAMES.md` is saved, spawn the `wireframe-reviewer` agent with
the plan directory path. It scores 1-10 on screen coverage, token
validity, component references, internal consistency, and AC
traceability.

If the score is < 7: address the findings, re-run the reviewer, repeat
until it passes. Do not hand off below the threshold.

When the score is ≥ 7, ask the developer: "Wireframes ready (score X/10).
Proceed to `/task-writer`?" — that's the handoff. `/task-writer` is a
separate skill with its own coverage gate; don't invoke it from inside
this skill.

## Anti-patterns

Lessons-from-pain — wireframes that broke a reviewer and forced a rework
— live in [`references/anti-patterns.md`](references/anti-patterns.md).
Skim it once if you've not built a wireframe in this project before; the
list catches the failure modes that the reviewer's scoring penalises
hardest (raw CSS values, undefined stores in interactions, sections
beyond the 5).
