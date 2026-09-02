# WIREFRAMES.md template

Save the spec to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-slug/WIREFRAMES.md`. The document
has **exactly 5 sections** — `wireframe-reviewer` parses these names and
counts them. Renaming, adding, or omitting sections breaks the reviewer
silently.

## Document structure

```markdown
# {{ISSUE_KEY_PREFIX}}-XXXX: Wireframe Specifications

What the user sees and interacts with. Design tokens throughout.
Implementations are built against these specs.

---

## 1. ASCII Wireframes
## 2. Component Breakdown
## 3. Shared Components
## 4. Screen Specifications
## 5. Interaction Specification
```

## What does NOT belong in WIREFRAMES.md

These are covered by other documents — don't duplicate them here:

| Concern | Where it lives | NOT here |
|---|---|---|
| Data requirements (stores, page load) | TASKS.md task context | Wireframe names store methods inline but doesn't spec data flow |
| File references (new/modified files) | PLAN.md PR sections | Wireframe names component files but doesn't list all files |
| Acceptance criteria coverage | PLAN.md AC table | Wireframe implements ACs but doesn't re-list them |
| Accessibility | Implementing agent follows existing page patterns | Not a wireframe concern |
| Responsive behavior | A note per screen ("mobile: stack vertically") | Not a separate section |

---

## Section 1: ASCII Wireframes

Draw ASCII art for each major screen — desktop layout, and mobile only
when the layout changes significantly. This communicates spatial
arrangement faster than any other format.

```
┌──────────────────────────────────────────────────────┐
│ SIDEBAR (230px)  │  MAIN CONTENT                     │
│                  │                                   │
│  logo.           │  ┌────────────────────────────┐   │
│                  │  │ UPGRADE BANNER             │   │
│  Projects        │  └────────────────────────────┘   │
│  Teams           │                                   │
│  ─────────       │  ┌──────┐ ┌──────┐ ┌──────┐      │
│  Users           │  │Plan  │ │Seats │ │Proj  │      │
│  ▶ Billing ←NEW  │  └──────┘ └──────┘ └──────┘      │
│                  │                                   │
│                  │  ┌────────────────────────────┐   │
│                  │  │ ▎ Section Card             │   │
│                  │  │   Label    Value            │   │
│                  │  └────────────────────────────┘   │
└──────────────────────────────────────────────────────┘
```

**Rules:**

- Box-drawing characters (`┌─┐│└─┘`)
- Label every region
- Include sidebar for navigation context
- Mark new elements with `← NEW`
- Draw modals with backdrop (`░░░`) and centered box
- One ASCII per distinct layout (don't draw Free / Pro / PastDue separately if they share layout)

## Section 2: Component Breakdown

One table mapping every UI region to its component, data source, and what
happens on interaction. This is the implementing agent's primary lookup.

```markdown
| Region | Component | Data Source | Interactivity |
|--------|-----------|-------------|---------------|
| Upgrade banner | `UpgradeBanner` | `billingStore.status.plan` | Click → `createCheckoutSession()` → payment-provider redirect |
| Plan details card | inline in `BillingOverview.vue` | `billingStore.status` | "Manage subscription" → `createPortalSession()` |
```

**Rules:**

- One row per visual block (not per HTML element)
- Name the exact store property or method
- Interactivity says what happens, not just "clickable"
- For existing shared components, reference by name (`TableRoot`, `SimpleButton`)

## Section 3: Shared Components

New components created for this feature that appear in multiple screens.
Each gets: props, emits, variant table (if applicable), and token
structure.

**Component placement rule:** if a component is used by more than one app
area, it **must** live in the project's shared component directory.
Placing it in either area's directory will fail the repo's app-boundary
architecture test, if it has one. Always check which areas use a
component before deciding its location.

```markdown
### PlanStatusBadge

**Component:** `PlanStatusBadge.vue`
**Props:** `status: 'free' | 'pro' | 'past-due' | 'cancelled'`

| Status | Classes | Label |
|--------|---------|-------|
| free | `bg-surface-2 text-dim` | Free |
| pro | `bg-success-subtle text-success` | Pro |

Structure: wraps `SimpleBadge` with `colorClass="tint-green"` — `rounded-md px-2 py-0.5 text-xs font-normal`
```

## Section 4: Screen Specifications

Per-screen specs with design tokens. **This is what the implementer builds
from, and what `wireframe-reviewer` validates.** Every visual property uses
exact tokens from the project's design system — the reviewer matches them
literally.

```markdown
### Screen: Billing Overview — Free Plan

**Component:** `BillingOverview.vue`
**Route:** `/billing`
**Access:** Admin-only (`user.isAdmin` route guard)
**Store:** `billingStore.fetchBillingStatus()`, `billingStore.createCheckoutSession()`
**Mobile note:** Stat boxes stack vertically (`flex-col`), banner button goes full-width

#### Layout

1. **UpgradeBanner** — `v-if="status.plan === 'free'"`
2. **Stat row** — `flex gap-4 mb-5`
   - **Box** — `flex-1 bg-surface border border-default rounded-md p-4`
     - Label: `text-xs font-medium text-muted uppercase tracking-wide mb-1`
     - Value: `text-base font-semibold`
```

### Token precision

Every visual property must be an exact token from the project's design
system. The "Use" column shows the shape; substitute the project's own
names:

| Property | Use | Never use |
|---|---|---|
| Background | Named token (`bg-surface`, `bg-surface-raised`) | `#1c1c22`, `var(--surface)` |
| Text color | Named token (`text-default`, `text-dim`, `text-muted`) | `color: var(--text)` |
| Border | Token syntax (`border border-default`, or the utility framework's attributify form) | `border: 1px solid #363640` |
| Accent bar | Token syntax (`border-l-3 border-brand`) | `border-left: 3px` |
| Radius | Named token (`rounded-md`, `rounded-lg`) | `border-radius: 10px` |
| Font size | Named token (`text-xs`, `text-sm`, `text-base`) | `text-size-0.82rem`, `font-size: 13px` |
| Font weight | Named token (`font-normal`, `font-medium`, `font-semibold`) | `font-weight: bold` |
| Font family | `font-mono` | `font-family: monospace` |
| Semantic | `text-success`, `bg-warning-subtle` | `color: green` |
| Transition | `transition-all`, `transition-colors`, `transition-opacity` | `transition-width` |

### Named font size tokens

Grep-verify the project's named font-size tokens from its utility config
before writing a single one, and list them here the way this example does:

| Token | Size | Use for |
|---|---|---|
| `text-xs` | 0.6875rem | Helper text, small badges, captions |
| `text-sm` | 0.75rem | Labels, filter pills, secondary text |
| `text-base` | 0.82rem | Body text, item titles, input values |
| `text-md` | 0.875rem | Page titles, modal headers |

**Never use raw computed sizes** (`text-size-X.XXrem`, `font-size: 13px`) —
always the named tokens. `wireframe-reviewer` validates these exact names,
and they're what the implementer types into the template.

Mobile behavior goes inline as a **Mobile note** on the screen, not in a
separate section.

## Section 5: Interaction Specification

Every user interaction across all screens. This is the behavioural contract
the implementer builds and writes specs against.

```markdown
| # | Trigger | Action | Result |
|---|---------|--------|--------|
| 1 | Click "Upgrade to Pro" | `billingStore.createCheckoutSession()` | Redirect to payment-provider checkout |
| 2 | API returns 402 `plan_limit_exceeded` | HTTP interceptor | UpgradePromptModal opens |
```

**Rules:**

- One row per distinct interaction
- **Trigger:** what the user does
- **Action:** what code runs (store method, emit, route push)
- **Result:** what the user sees change
- Include error paths (API failures, rate limits)
