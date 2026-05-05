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

Generate a `WIREFRAMES.md` that answers one question: **"What does the user see and interact with?"**

Two agents consume this file downstream:
- The **wireframe-reviewer** agent checks it immediately after generation — screen coverage,
  token validity, component references, internal consistency, and AC traceability (score >= 7 to proceed).
- The **acceptance-reviewer** agent greps design tokens against component templates during
  implementation review. Keep the token format exact — the reviewer matches tokens literally.

Every line should help someone build or verify the UI. Architecture, data flow, file lists,
and accessibility belong in PLAN.md and TASKS.md, not here.

## Prerequisites

Before generating wireframes, familiarize yourself with the project's design system — read the
CSS/utility framework config (e.g., Tailwind config, UnoCSS config, CSS variables file, theme
file) to understand available tokens and naming conventions.

## Workflow

### Step 1: Locate the plan

Use the canonical algorithm in
[`plan-feature/references/plan-directory.md`](../plan-feature/references/plan-directory.md),
then read `PLAN.md`. Extract the frontend PR file list, acceptance
criteria, and scope.

### Step 2: Research existing layout patterns

Find the closest existing screens in the codebase for each planned page:

1. Glob for page/view components in the project's source directories
2. Read 2-3 reference components — note their tokens, layout composition, and action patterns
3. Check shared/common component directories for reusable components to reference (not reinvent)

Also check during research:
- **Icons**: What icon components/assets exist? If new icons are needed, flag them as
  "needs creation" in the wireframe.
- **Badge/tag patterns**: If the feature needs status badges, check what badge component
  exists and what variants/props it supports. Use existing patterns rather than inventing
  new color combinations.
- **State management patterns**: How do existing pages fetch and manage data? Some areas
  may use stores, others inline API calls. Match the existing pattern for the area you're
  wireframing.

### Step 3: Design interrogation

Before writing the spec, ask the developer design questions using `AskUserQuestion`. The plan
decided *what* to build — you now decide *how it looks and behaves*. This is where visual and
interaction design decisions get made.

#### What to present first

Show the developer what you found in Step 2 — the reference pages, their layout patterns, and
what you'd reuse. Ground every question in the codebase:

> "The closest existing page is the settings detail page — section cards with accent-border
> titles and detail rows. I'd follow that pattern for the new details section.
> Does that match what you have in mind, or should this page feel different?"

#### What to ask about

For each screen, ask about design choices that aren't obvious from the plan:

- **Page structure** — "Should this be one scrollable page with sections, or a tabbed layout?"
- **Information hierarchy** — "This page needs to show plan, usage, and history. What's most
  important? Should key metrics be promoted as stat boxes, or is a detail list enough?"
- **New patterns** — "This feature needs a progress bar — that doesn't exist in the app yet.
  Should it be a thin inline bar or a standalone component with a percentage label?"
- **Action placement** — "Should 'Manage' be a button in the section header or a separate card?"
- **Empty states** — "What does this page show when there's no data yet?"

Use `AskUserQuestion` with concrete options — include ASCII previews when comparing layout
alternatives. Show 2-3 options per question, grounded in what exists in the codebase.

#### Rules for design questions

- **2-3 rounds max.** This is focused design, not a full product discovery session.
- **Always provide options from the codebase.** Show existing patterns and let the developer
  pick — not open-ended "how should we lay it out?"
- **Show, don't describe.** Use ASCII previews to let the developer see the difference.
- **Default to existing patterns.** If the codebase already has an obvious pattern for this
  type of page, present it as the recommended option. Only ask when there's a genuine choice.
- **Skip questions the plan already answered.** If the plan specifies layout decisions, don't
  re-ask them.

#### When to skip interrogation

Skip design questions entirely when:
- The feature only modifies existing screens (adding a column, a section, a button)
- Every screen directly mirrors an existing page pattern with no new components
- The developer explicitly says "just follow existing patterns, don't ask"

### Step 4: Write WIREFRAMES.md

Save to the plan directory. The document has **5 sections** — no more.

---

## Document Structure

```markdown
# Feature: Wireframe Specifications

What the user sees and interacts with. Design tokens throughout.
The acceptance-reviewer checks implementations against these specs.

---

## 1. ASCII Wireframes
## 2. Component Breakdown
## 3. Shared Components
## 4. Screen Specifications
## 5. Interaction Specification
```

### What does NOT belong in WIREFRAMES.md

These are covered by other documents — don't duplicate them here:

| Concern | Where it lives | NOT here |
|---------|---------------|----------|
| Data requirements (stores, API calls) | TASKS.md task context | Wireframe names store methods inline but doesn't spec data flow |
| File references (new/modified files) | PLAN.md PR sections | Wireframe names component files but doesn't list all files |
| Acceptance criteria coverage | PLAN.md AC table | Wireframe implements ACs but doesn't re-list them |
| Accessibility | Implementing agent follows existing page patterns | Not a wireframe concern |
| Responsive behavior | A note per screen ("mobile: stack vertically") | Not a separate section |

---

### Section 1: ASCII Wireframes

Draw ASCII art for each major screen — desktop layout, and mobile only when the layout
changes significantly. This communicates spatial arrangement faster than any other format.

```
┌──────────────────────────────────────────────────────┐
│ SIDEBAR            │  MAIN CONTENT                    │
│                    │                                  │
│  Logo              │  ┌────────────────────────────┐  │
│                    │  │ BANNER                     │  │
│  Nav Item 1        │  └────────────────────────────┘  │
│  Nav Item 2        │                                  │
│  ─────────         │  ┌──────┐ ┌──────┐ ┌──────┐     │
│  Nav Item 3        │  │Stat  │ │Stat  │ │Stat  │     │
│  ▶ New Page ←NEW   │  └──────┘ └──────┘ └──────┘     │
│                    │                                  │
│                    │  ┌────────────────────────────┐  │
│                    │  │ ▎ Section Card             │  │
│                    │  │   Label    Value            │  │
│                    │  └────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

Rules:
- Box-drawing characters (`┌─┐│└─┘`)
- Label every region
- Include navigation context (sidebar, header, tabs)
- Mark new elements with `← NEW`
- Draw modals with backdrop (`░░░`) and centered box
- One ASCII per distinct layout (don't draw variations separately if they share layout)

### Section 2: Component Breakdown

One table mapping every UI region to its component, data source, and what happens on interaction.
This is the implementing agent's primary lookup.

```markdown
| Region | Component | Data Source | Interactivity |
|--------|-----------|-------------|---------------|
| Banner | `UpgradeBanner` | `store.status.plan` | Click → `createSession()` → redirect |
| Details card | inline in `Overview.vue` | `store.status` | "Manage" → `openPortal()` |
```

Rules:
- One row per visual block (not per HTML element)
- Name the exact store property or method
- Interactivity says what happens, not just "clickable"
- For existing shared components, reference by name

### Section 3: Shared Components

New components created for this feature that appear in multiple screens. Each gets:
props, emits, variant table (if applicable), and token structure.

**Component placement rule**: If a component is used by multiple app areas or modules, it
should live in the project's shared/common component directory. Check existing architecture
conventions for placement rules.

```markdown
### StatusBadge

**Component:** `StatusBadge.vue`
**Props:** `status: 'active' | 'inactive' | 'pending'`

| Status | Classes | Label |
|--------|---------|-------|
| active | `bg-success-subtle text-success` | Active |
| pending | `bg-warning-subtle text-warning` | Pending |

Structure: wraps existing badge component with appropriate variant props.
```

### Section 4: Screen Specifications

Per-screen specs with design tokens. This is what the acceptance-reviewer greps against
component templates. Every visual property uses exact tokens from the project's design system.

```markdown
### Screen: Overview — Default State

**Component:** `Overview.vue`
**Route:** `/settings/overview`
**Access:** Admin-only (route guard)
**Store:** `store.fetchStatus()`, `store.createSession()`
**Mobile note:** Stat boxes stack vertically, banner button goes full-width

#### Layout

1. **Banner** — `v-if="status.plan === 'free'"`
2. **Stat row** — `flex gap-4 mb-5`
   - **Box** — `flex-1 bg-surface border border-default rounded-md p-4`
     - Label: `text-xs font-medium text-muted uppercase tracking-wide mb-1`
     - Value: `text-base font-semibold`
```

Token precision — every visual property must use the project's exact design tokens:

| Property | Use | Never use |
|----------|-----|-----------|
| Background | Named token (`bg-surface`, `bg-surface-raised`) | Hex values (`#1c1c22`) |
| Text color | Named token (`text-default`, `text-muted`) | `color: var(--text)` |
| Border | Token syntax (`border border-default`) | Raw CSS (`border: 1px solid #363640`) |
| Radius | Token (`rounded-md`, `rounded-lg`) | Raw CSS (`border-radius: 10px`) |
| Font size | Named token (`text-xs`, `text-sm`, `text-base`) | Raw values (`font-size: 13px`) |
| Font weight | Named token (`font-medium`, `font-semibold`) | Raw CSS (`font-weight: bold`) |

**Always verify tokens against the project's design system config.** The acceptance-reviewer
greps for these exact names in component templates.

Mobile behavior goes inline as a **Mobile note** on the screen, not in a separate section.

### Section 5: Interaction Specification

Every user interaction across all screens. The acceptance-reviewer uses this to verify behavior.

```markdown
| # | Trigger | Action | Result |
|---|---------|--------|--------|
| 1 | Click "Upgrade" | `store.createSession()` | Redirect to payment page |
| 2 | API returns 402 | HTTP interceptor | Upgrade prompt modal opens |
```

Rules:
- One row per distinct interaction
- **Trigger**: what the user does
- **Action**: what code runs (store method, emit, route change)
- **Result**: what the user sees change
- Include error paths (API failures, rate limits)

---

## Anti-patterns

- **Raw CSS values** — always use design tokens from the project's system
- **Inventing new token names** — use tokens that actually exist in the codebase config
- **Inventing badge/tag styles** — use the existing badge component with its supported variants
- **Shared component in wrong directory** — if multiple areas use it, put it in shared
- **Referencing nonexistent icons** — check existing icons before naming them; flag new ones
- **Undefined stores in interactions** — every store/method in the Interaction table must exist
  or be defined in the wireframe
- **Sections beyond the 5** — data flow, file lists, a11y, coverage belong elsewhere
- **Overly long wireframes** — if it's longer than ~250 lines, you're probably duplicating PLAN.md
- **Re-specifying shared components** — reference existing components by name, don't re-describe
- **Inventing new patterns** — copy layout patterns from existing pages
