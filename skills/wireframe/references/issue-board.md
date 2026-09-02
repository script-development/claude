> **Worked example.** A real board page, written up in full for format inspiration. Issue keys
> appear as `XX-####` — read them as `{{ISSUE_KEY_PREFIX}}-####`. Tokens (`--brand`, `--surface-*`,
> `bg-*`, `text-*`) are the example product's; substitute the repo's own design system. Sections
> beyond the five in `wireframes-template.md` (Creative Provocation, Data Requirements, Responsive
> Behavior, Visual Narrative, Accessibility Notes, Surface Depth Map, Bold Choices Ledger, File
> References) are design-documentation extras, not part of the WIREFRAMES.md spec format.

# Issue Board — Wireframe Specification

**Page:** Issue Board (Kanban)
**Route:** `projects.board.overview`
**Purpose:** Active sprint visualization. Issues organized into status-based swim lanes with drag-and-drop reordering. The primary daily workspace for developers tracking their sprint.
**Auth:** Authenticated tenant session. Board is read-only without issue permissions; lane visibility tied to project membership. "Add Issue" gated by `ISSUES.CREATE` permission. "Plan Feature" gated by feature flag + AI key access.
**Primary Action:** Drag an issue card from one lane to another to update its status.

---

## Creative Provocation

### Personality Test

If this page walked into a standup meeting, it would be the lead who already has the board open on their laptop, says nothing until someone asks about a blocker, and then gives a three-word answer that resolves it. The board does not explain itself. It shows the state of the sprint and expects you to act on what you see.

### Opposite Test

The opposite of this page is a Trello board — rounded corners on everything, pastel lane backgrounds, card covers with stock photos, sticker reactions, and a background image of a sunset. That page wants you to feel good about your work. This page wants you to finish it.

### Memory Test

What you remember after closing the tab: horizontal columns of dark cards on a slightly-less-dark background, a red "Add Issue" button in the top-right corner, and the colored dots of issue type icons in the bottom-left of each card. The board reads left-to-right like a pipeline — raw material on the left, finished product on the right.

---

## ASCII Wireframe — Desktop (>768px)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ SIDEBAR (230px, fixed)  │  MAIN CONTENT AREA                                           │
│                         │                                                               │
│ ┌─────────────────────┐ │  ┌─────────────────────────────────────────────────────────┐   │
│ │ logo.                │ │  │ Board  Backlog  Issues  Epics  Reports  Settings       │   │
│ │      ▲ red dot       │ │  │ ═══╗                                                   │   │
│ └─────────────────────┘ │  │    ╚══ red underline on active tab                      │   │
│ ┌─────────────────────┐ │  └─────────────────────────────────────────────────────────┘   │
│ │ 📥 Inbox        [3] │ │                                                               │
│ │ 👤 My Issues    [7] │ │  ┌─────────────────────────────────────────────────────────┐   │
│ │ 📁 All Projects     │ │  │ FILTER BAR                                              │   │
│ ├─────────────────────┤ │  │ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐ ┌────┐ │   │
│ │ MY TEAM              │ │  │ │🔍 Search │ │Assignees │ │Priorities│ │Types │ │... │ │   │
│ │  ● Project Alpha     │ │  │ └──────────┘ └──────────┘ └──────────┘ └──────┘ └────┘ │   │
│ │  ● Project Beta      │ │  │                                   [Plan Feature] [+Add]│   │
│ │  ● Project Gamma     │ │  └─────────────────────────────────────────────────────────┘   │
│ ├─────────────────────┤ │                                                               │
│ │ WORKSPACE            │ │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐ │
│ │  Teams               │ │  │ Todo    [4] │ │In Prog [3] │ │ Review [2] │ │ Done   [8] │ │
│ │  Roles               │ │  │            │ │            │ │            │ │            │ │
│ │  Time Tracking       │ │  │ ┌────────┐ │ │ ┌────────┐ │ │ ┌────────┐ │ │ ┌────────┐ │ │
│ │  Settings            │ │  │ │ Title  │ │ │ │ Title  │ │ │ │ Title  │ │ │ │ Title  │ │ │
│ ├─────────────────────┤ │  │ │        │ │ │ │        │ │ │ │        │ │ │ │        │ │ │
│ │ ◀ Collapse           │ │  │ │●XX-42 ◐│ │ │ │●XX-15 ◐│ │ │ │●XX-88 ◐│ │ │ │●XX-03 ◐│ │
│ └─────────────────────┘ │  │ │[Epic]  │ │ │ │        │ │ │ │[Epic]  │ │ │ │        │ │ │
│                         │  │ └────────┘ │ │ └────────┘ │ │ └────────┘ │ │ └────────┘ │ │
│ ┌─────────────────────┐ │  │ ┌────────┐ │ │ ┌────────┐ │ │            │ │ ┌────────┐ │ │
│ │ 🌓 Jane Example     │ │  │ │ Title  │ │ │ │ Title  │ │ │            │ │ │ Title  │ │ │
│ └─────────────────────┘ │  │ │●XX-17 ◐│ │ │ │●XX-29 ◐│ │ │            │ │ │●XX-44 ◐│ │
│                         │  │ └────────┘ │ │ └────────┘ │ │            │ │ └────────┘ │ │
│                         │  └────────────┘ └────────────┘ └────────────┘ └────────────┘ │
│                         │                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────┘

CARD ANATOMY (zoomed):
┌───────────────────────────────┐
│ Fix login redirect loop       │  ← Title (text-base, --text, fw-500)
│                               │
│ 🔴 XX-142         🔀 ▲▲ (●) │  ← Meta row: type icon + key (left), branch + priority + avatar (right)
│ ┌───────────────┐             │
│ │ Authentication │             │  ← Epic badge (conditional, tint color)
│ └───────────────┘             │
└───────────────────────────────┘
```

### Legend

| Symbol | Meaning |
|--------|---------|
| `●` | Issue type icon (colored SVG: red=bug, blue=task, green=feature) |
| `◐` | Profile picture avatar (22px, rounded-full) or unassigned circle |
| `▲▲` | Priority chevrons icon |
| `🔀` | Branch status icon (conditional — only when branch linked) |
| `[3]` | Count badge |
| `═══╗╚══` | Active tab underline (2px `--brand`) |

---

## ASCII Wireframe — Mobile (<768px)

```
┌──────────────────────────────────┐
│ ┌──────────────────────────────┐ │
│ │ FILTER BAR (collapsed)       │ │
│ │ [▼ Filters]    [+Add Issue]  │ │
│ └──────────────────────────────┘ │
│                                  │
│ ← swipe →                       │
│ ┌──────────────────────────────┐ │
│ │ Todo                     [4] │ │
│ │                              │ │  85vw per lane
│ │ ┌──────────────────────────┐ │ │  snap-x scrolling
│ │ │ Card title               │ │ │  no drag-drop
│ │ │ ● XX-42          ▲▲ (●) │ │ │
│ │ └──────────────────────────┘ │ │
│ │ ┌──────────────────────────┐ │ │
│ │ │ Card title               │ │ │
│ │ │ ● XX-17          ▲▲ (●) │ │ │
│ │ └──────────────────────────┘ │ │
│ └──────────────────────────────┘ │
│                                  │
│ ┌──────────────────────────────┐ │
│ │ Board │ Backlog │ Issues ... │ │  ← fixed bottom tab bar
│ └──────────────────────────────┘ │
└──────────────────────────────────┘

MOBILE FILTER EXPANDED:
┌──────────────────────────────────┐
│ ┌──────────────────────────────┐ │
│ │ [▲ Filters ●]   [+Add Issue]│ │  ● = red dot when filters active
│ ├──────────────────────────────┤ │
│ │ 🔍 Search issues...         │ │
│ │ Assignees ▼                 │ │  stacked vertically,
│ │ Priorities ▼                │ │  full width
│ │ Types ▼                     │ │
│ │ Epics ▼                     │ │
│ │ Creators ▼                  │ │
│ └──────────────────────────────┘ │
```

---

## Component Breakdown

| Region | Component | Source File | Data Source | Interactivity |
|--------|-----------|------------|-------------|---------------|
| Sidebar | `SidebarLayout` > `Navbar` | `shared/.../SidebarLayout.vue`, `tenant/.../Navbar.vue` | `projectStore`, `teamStore`, `notificationStore`, `userIssueStore` | Click to navigate; collapse/expand toggle; keyboard shortcut |
| Brand header | `AppLogo` | `tenant/.../AppLogo.vue` | Static | Links to `projects.overview` |
| User footer | `SidebarUserFooter` | `shared/.../SidebarUserFooter.vue` | `authService.getLoggedInUser()` | Profile link, theme toggle, logout |
| Tab bar | `MenuTabs` | `shared/.../MenuTabs.vue` | `useProjectTabs()` — 6 tabs, permission/feature-gated | Click to navigate between project views |
| Filter bar | `FilterBar` | `tenant/.../filters/FilterBar.vue` | N/A (slot container) | Mobile: toggle expand/collapse; "Clear all" button when filters active |
| Search filter | `SearchFilter` | `tenant/.../filters/SearchFilter.vue` | `searchTerm` (shared reactive ref) | Type to filter; clear X button |
| Multi-select filters | `MultiSelectFilter` x5 | `tenant/.../filters/MultiSelectFilter.vue` | `selectedAssignees`, `selectedPriorities`, `selectedTypes`, `selectedEpics`, `selectedCreators` | Dropdown with searchable multi-select; count badge overlaps top-right |
| Plan Feature button | `Button` (variant: white) | `shared/.../buttons/Button.vue` | Feature flag `featurePlanner` + `hasAiKeyAccess` | Navigate to feature planner |
| Add Issue button | `Button` (variant: primary) | `shared/.../buttons/Button.vue` | Permission: `ISSUES.CREATE` | Navigate to issue create form |
| Board lanes | `Lane` | `tenant/.../Lane.vue` | `laneStore.getAll` — project-configured status lanes | Container for draggable cards |
| Issue cards | `DragElement` | `tenant/.../issues/DragElement.vue` | `kanbanStore` — filtered + lane-sorted issues | Click title to navigate to issue; drag to change lane/order |
| Drag system | `VueDraggable` | `vue-draggable-plus` | `kanbanStore.data` | Drag ghost: 40% opacity, dashed red border; fires `endDragging` to persist |
| Issue type icon | `IssueTypeIcon` | `tenant/.../IssueTypeIcon.vue` | `issue.type` enum | Visual indicator only |
| Priority icon | `PriorityIcon` | `tenant/.../PriorityIcon.vue` | `issue.priority` enum | Visual indicator only |
| Branch status | `BranchStatusIcons` | `tenant/.../BranchStatusIcons.vue` | `issue.branchLinkStatuses` | Visual indicator with title tooltip |
| Assignee avatar | `ProfilePicture` (size: sm) | `shared/.../ProfilePicture.vue` | `userStore.getById(issue.assigneeId)` | Title tooltip with full name |
| Unassigned icon | Inline `<div>` + `UserIcon` | — | When `assigneeId` is null | Title: "Unassigned" |
| Epic badge | `EpicBadge` > `SimpleBadge` | `tenant/.../epics/EpicBadge.vue` | `epicStore.getById(issue.epicId)` | Visual indicator with tint color |

---

## Interaction Specification

| # | Trigger | Action | Result | Loading State |
|---|---------|--------|--------|---------------|
| 1 | **Drag card** to new lane | `VueDraggable` `@end` fires `endDragging()` → `kanbanStore.update()` → `updateBoardForProject()` API call | Card stays in new position; lane counts update reactively | Optimistic — card moves immediately, API call is fire-and-forget unless error |
| 2 | **Drag card** within same lane | Reorder detected by index comparison; same `endDragging` flow | Card order persisted | Same optimistic approach |
| 3 | **Click issue title** | `RouterLink` navigates to `projects.issues.show` with `issue.key` | Issue detail page loads | Route-level suspense fallback ("Loading...") |
| 4 | **Type in search** | `v-model` updates `searchTerm` reactive ref | Board re-filters: `matchesSearch` applied to all issues; lane contents and counts update instantly | None — client-side filtering, no API call |
| 5 | **Select multi-filter option** | Dropdown option toggled in `selected` array | Count badge appears/updates on filter trigger; board re-filters via corresponding `matches*` function | None — client-side filtering |
| 6 | **Click "Clear all"** | `clearAllFilters()` resets all filter refs | All badges disappear; full unfiltered board restores; "Clear all" button hides | None |
| 7 | **Click "Add Issue"** | `navigateToCreateIssue()` → route push to `projects.issues.create` | Issue creation form loads | Route-level suspense |
| 8 | **Click "Plan Feature"** | `navigateToFeaturePlanner()` → route push to `projects.feature-planner.overview` | Feature planner page loads | Route-level suspense |
| 9 | **Mobile: tap "Filters"** | `isExpanded` toggles | Filter panel slides open below bar with vertical stacked filters | None — CSS transition |
| 10 | **Mobile: swipe lanes** | CSS `snap-x snap-mandatory` on lane container | Lanes snap into view one at a time (85vw each) | None — native scroll behavior |
| 11 | **Sidebar collapse** | Toggle button or keyboard shortcut | Sidebar shrinks from 230px to 64px; project items show code abbreviation; 0.2s width transition | CSS transition |

---

## Data Requirements

### Page Load (parallel `Promise.all`)

| Store | Method | Returns | Used By |
|-------|--------|---------|---------|
| `laneStore` | `retrieveAll()` | `Lane[]` — id, title, order | Lane headers, lane width calculation |
| `sprintStore` | `retrieveAll()` | `Sprint[]` — id, status | Active sprint detection (filter by `ACTIVE` status) |
| `issueStore` | `retrieveAll()` | `Issue[]` — id, title, key, type, priority, assigneeId, epicId, sprintId, laneId, branchLinkStatuses | Card rendering, filtering, lane assignment |
| `epicStore` | `retrieveAll()` | `Epic[]` — id, title, color | Epic badge on cards |

### Pre-loaded by Parent (`ProjectLayout.vue`)

| Store | Returns |
|-------|---------|
| `projectStore` | All projects (needed for sidebar, tab permissions) |
| `userStore` | All users (needed for assignee avatars, filter options) |
| `teamStore` | All teams (needed for sidebar team groups, assignee options) |

### Computed Filter Options

| Option Set | Built From | Sorting |
|-----------|-----------|---------|
| `assigneeOptions` | Project members + team members + all users | Alphabetical |
| `priorityOptions` | `PriorityEnum` collection | Enum order |
| `typeOptions` | `TypeEnum` collection | Enum order |
| `epicOptions` | `epicStore.getAll` | Alphabetical |
| `creatorOptions` | Users who created issues in active sprint | Alphabetical |

### Card Fields

| Field | Type | Display |
|-------|------|---------|
| `title` | `string` | Card body text — RouterLink |
| `key` | `string` | Bottom-left, uppercase, monospace-weight (`XX-142`) |
| `type` | `TypeEnum` | Colored SVG icon left of key |
| `priority` | `PriorityEnum` | Chevron icon, bottom-right |
| `assigneeId` | `number \| null` | 22px avatar or unassigned circle, bottom-right |
| `epicId` | `number \| null` | Tinted SimpleBadge below meta row (conditional) |
| `branchLinkStatuses` | `BranchLinkStatusEnum[]` | Git status icon, bottom-right (conditional) |

---

## Responsive Behavior

| Breakpoint | Element | Behavior |
|-----------|---------|----------|
| `>768px` (desktop) | Sidebar | Fixed left, 230px expanded / 64px collapsed, `--surface-1` background |
| `>768px` | Filter bar | Inline horizontal layout — search + 5 multi-selects + action buttons |
| `>768px` | Board lanes | Flex row, `gap-4`, percentage widths (`100 / laneCount`) |
| `>768px` | Drag-drop | Enabled — `VueDraggable` group `drag-board` |
| `>768px` | Tab bar | Top of content area, bottom border, text links |
| `>768px` | "Plan Feature" text | Visible (`lt-md:hidden` removes only on mobile) |
| `<768px` (mobile) | Sidebar | Hidden by default; hamburger opens as overlay (z-50) with backdrop |
| `<768px` | Filter bar | Collapsed to toggle button with filter icon + chevron; expands as panel below |
| `<768px` | Filter active indicator | Red dot (2px, `bg-primary`) on toggle button when filters active and collapsed |
| `<768px` | Board lanes | 85vw per lane, `flex-shrink-0`, `snap-x snap-mandatory` horizontal scroll |
| `<768px` | Drag-drop | Disabled (`isMobile` check) |
| `<768px` | Tab bar | Fixed bottom bar (z-30), `--surface` background, top border instead of bottom, equal-width tabs |
| `<768px` | "Plan Feature" text | Hidden — only sparkle icon visible |
| `<768px` | "Add Issue" text | Shows "Issue" only (no "Add" prefix) |
| `<768px` | Content padding-bottom | Extra 7rem to clear fixed bottom tab bar |

---

## Visual Narrative

### What This Page Looks Like

The board is a dark, still surface. The page canvas (`#09090e`) is nearly black — not the blue-black of a night sky but the flat black of a matte desk in a room with one lamp. On top of this darkness sit four (or however many lanes the project defines) vertical columns, each a slightly lighter shade (`#111116`) with softly rounded corners. Inside each column, issue cards float on yet another surface level (`#1c1c22`), bordered by a barely-visible line (`#262630`) and the faintest shadow you have ever seen on a card — a 1px blur at 4% opacity. The overall effect is geological: layers of dark stone, each one fractionally lighter than the one beneath it, with cards sitting like specimens in labeled drawers.

### Filter Bar

A single horizontal strip at the top, the same surface tone as the lane backgrounds (`#111116`). The search input is compact (220px) with a dim magnifying glass icon on the left. The multi-select triggers sit in a row, each with its placeholder text in muted gray. When a filter is active, a small red pill (`--brand`, `#c8553a`) floats at the top-right corner of the trigger — offset by -6px so it overlaps the button edge like a notification badge on an app icon. The "Add Issue" button at the far right is the only element on the page with a solid red background. The "Plan Feature" button beside it is more restrained — white variant with a sparkle icon. When active filters exist, a "Clear all" button with a danger-red border appears in the actions area.

### Board Lanes

Each lane is a rounded column with a small header area: the lane title in dim text (`#a0a0aa`, semibold) on the left, and a count badge on the right. The count badge sits on `--surface-3` (`#30303b`) — one depth level above the lane itself — with muted text. This badge is compact: 24px tall, minimum 24px wide, centered content. Below the header, cards stack vertically with 6px gaps between them. The lanes divide the available width equally — four lanes each get 25%, three lanes get 33.3%. There is a 16px gap between lanes. The columns do not have visible borders — their rounded-corner `--surface-1` background is enough to separate them from the `--bg` canvas.

### Issue Cards

Each card is a compact rectangle — roughly 10px horizontal padding, 14px vertical. The title sits at the top in primary text color (`#e8e8ec`), medium weight, snug leading. Below the title, a meta row splits into two sides. The left side shows the issue type icon (a small colored SVG — red for bugs, blue for tasks, green for features) followed by the issue key in uppercase, wide-tracked, muted text at 11px. The right side clusters three elements tightly: an optional branch status icon (when the issue has a linked git branch), the priority chevron icon, and a 22px circular avatar. When the issue has no assignee, the avatar slot shows a muted circle with a user silhouette icon on a `--surface-1` background. If the issue belongs to an epic, a tinted badge appears on a third row below the meta — a small pill with the epic name in its assigned color. The overall card impression is dense but readable — a business card, not a Post-it note.

### Drag Ghost

When you grab a card and begin dragging, the original position shows a ghost: the card at 40% opacity with a dashed red border (`--brand`). The dragged card follows the cursor at full opacity. The animation duration is 150ms — fast enough to feel direct, slow enough to not feel instant. On mobile, dragging is disabled entirely. You swipe between lanes instead.

---

## Accessibility Notes

### Focus Order

1. Skip-to-content link (hidden, visible on focus — defined in `theme.css`)
2. Sidebar navigation links (top to bottom: Inbox, My Issues, All Projects, project items, workspace links)
3. Sidebar collapse toggle
4. Tab bar links (Board, Backlog, Issues, Epics, Reports, Settings)
5. Filter bar: Search input, then multi-select triggers left to right, then "Clear all" (if visible), then "Plan Feature" (if visible), then "Add Issue"
6. Board cards: Lane 1 top to bottom, then Lane 2 top to bottom, etc. Each card's RouterLink is the focusable element (stretched-link covers the full card)

### Keyboard Navigation

| Key | Context | Action |
|-----|---------|--------|
| `Tab` | Anywhere | Move to next focusable element in focus order |
| `Shift+Tab` | Anywhere | Move to previous focusable element |
| `Enter` / `Space` | Tab link | Navigate to that project view |
| `Enter` / `Space` | Card (RouterLink) | Navigate to issue detail |
| `Enter` / `Space` | Filter toggle (mobile) | Expand/collapse filter panel |
| `Enter` / `Space` | Multi-select trigger | Open dropdown |
| `Escape` | Open dropdown | Close dropdown |

### ARIA Patterns

| Element | Attributes | Notes |
|---------|-----------|-------|
| Sidebar | `aria-label="Sidebar"` on `<aside>` | Landmark for screen readers |
| Main navigation | `aria-label="Main navigation"` on `<nav>` | Navigation landmark |
| Filter toggle (mobile) | `:aria-expanded="isExpanded"` on `<button>` | Communicates panel state |
| Search clear button | `aria-label="Clear search"` | Non-text button needs label |
| Multi-select dropdown | Inherits from `MultiSelect` shared component | `role="listbox"` / `role="option"` pattern |
| Menu tabs | Focus-visible ring via `.menu-tab:focus-visible` CSS | 2px `--brand` outline |
| Sidebar links | `focus-visible:ring-2 focus-visible:ring-brand` | Consistent focus indicator |

### Screen Reader Experience

The board reads as: sidebar landmark with navigation, then a tab list for the project views, then a group of filters (search input + buttons), then the lane contents in DOM order. Each lane is a heading (`h4`) followed by card links. Cards read as: title text, then the issue key (visually small but present in DOM). The epic badge and icons are decorative or have title attributes — they provide supplementary context on hover/focus but the card link text is the title alone.

### Known Gaps

- Board cards are `<div>` containers with a stretched `RouterLink` — the entire card is clickable via CSS `stretched-link`, but the drag handle and the click target are the same surface. Screen reader users cannot drag cards.
- Priority icons and type icons lack `aria-label` — they are visual-only indicators. The information they convey (priority level, issue type) is not available to screen readers on the board view (it is available on the issue detail page).
- Lane count badges use `data-test` but no `aria-label` — the count is visible text content, so screen readers will read the number, but the relationship to the lane title is implicit (visual proximity, not programmatic).

---

## Surface Depth Map

```
DEPTH 0 ──── Page canvas (#09090e, --bg)
│             The void. Everything sits on top of this.
│
├── DEPTH 1 ──── Sidebar (#111116, --surface-1 via --surface-raised)
│   │             Lane backgrounds (#111116, --surface-1)
│   │             Filter bar (#111116, --surface-1)
│   │
│   ├── DEPTH 2 ──── Issue cards (#1c1c22, --surface)
│   │   │             Tab bar (on mobile: #1c1c22, --surface)
│   │   │             Search input background (#1c1c22, --surface)
│   │   │             Sidebar brand header (same surface, separated by border)
│   │   │
│   │   │             Cards are the ONLY depth-2 element with a shadow:
│   │   │             0 1px 3px rgba(0,0,0,0.04) — barely perceptible,
│   │   │             just enough to lift them off the lane surface.
│   │   │
│   │   ├── DEPTH 2.5 ── Card borders (#262630, --surface-2)
│   │   │                  Hover states, table row alternation
│   │   │                  Unassigned avatar circle background (#111116, --surface-1)
│   │   │                  — deliberately one level DOWN to recede
│   │   │
│   │   └── DEPTH 3 ──── Lane count badge (#30303b, --surface-3)
│   │                      Filter dropdowns (when open)
│   │                      Multi-select popovers
│   │
│   └── SPECIAL ──── Active sidebar item
│                     Background: rgba(200,85,58,0.1) (--brand-subtle)
│                     Left bar: 3px solid --brand
│                     Text promoted to --text (from --text-muted)
│
└── FLOATING ──── Modal overlay (--shadow-lg)
                   Dropdown menus (--shadow-md, --surface-3)
                   Toast notifications (--shadow-sm)
                   — These exist above the depth stack, not within it
```

### Depth Rules on This Page

1. **Lane sits at depth 1, card sits at depth 2.** The 1-step difference is enough for visual separation in dark mode. Cards do not need heavy shadows — the surface color difference does the work.
2. **The card shadow is an exception.** No other element on this page has a shadow. The card's `0 1px 3px rgba(0,0,0,0.04)` is barely visible — it exists as a subtle lift cue, not as a depth indicator. Remove it and the cards still read as elevated; keep it and they feel slightly more tangible.
3. **The unassigned avatar circle drops DOWN one level** to `--surface-1` — the same surface as the lane. This makes it visually recede, communicating "nothing here" more effectively than a same-level empty state would.
4. **Filter dropdowns jump to depth 3** when open, matching the popovers and dropdown convention across the app. The `--shadow-md` on dropdowns is the primary floating-element depth cue.

---

## Bold Choices Ledger

Existing bold choices in the board's design — what makes this board this product's, not a generic kanban.

| # | Choice | What It Does | Why It Works |
|---|--------|-------------|-------------|
| 1 | **No lane borders** | Lanes are differentiated purely by their `--surface-1` background against the `--bg` canvas. No visible border lines. | Reduces visual noise. The dark mode surface layering is strong enough to communicate "this is a container" without drawing a line around it. This is a confidence move — it trusts the depth system. |
| 2 | **Card shadow at 4% opacity** | The thinnest possible shadow that still registers on a dark background. Most dark-mode UIs either skip card shadows entirely or over-apply them. | It adds physicality without contradicting the "depth through surface, not shadow" philosophy. The shadow says "I can be picked up" — which matters for a drag-and-drop interface. |
| 3 | **Issue key as uppercase monospace-weight** | `XX-142` rendered in 11px, `fw-600`, `tracking-wide`, `uppercase` — a stamp, not a label. | Gives the key a mechanical, stamped-on quality that contrasts with the natural-language title above it. It reads like a serial number on hardware. |
| 4 | **Type icon as the only color on the card** | The small issue type SVG (red/blue/green) is the only chromatic element on an otherwise grayscale card (unless an epic badge is present). | The color dot draws the eye to the card's metadata corner, creating a consistent scan pattern: title first, then bottom-left for type, bottom-right for assignment. |
| 5 | **Percentage-based lane widths** | Lanes divide the available space equally (`100 / laneCount`%). No fixed widths, no min-widths on desktop. | The board breathes with the content. Three lanes feel spacious; six lanes feel compressed — which is appropriate pressure to simplify your workflow. |
| 6 | **Drag ghost uses brand red** | The dashed border on the ghost placeholder is `--brand`, not a generic gray dashed line. | The red dashed outline makes the drop source immediately identifiable. It is the only moment on the board where `--brand` appears as a border, making it unmistakably intentional. |
| 7 | **Filter count badge as overlapping pill** | The red badge sits at `top: -6px, right: -6px` — physically overlapping the filter trigger button edge. | Borrows the mobile notification badge convention (unread count on app icon) for a desktop filter interface. The overlap creates urgency — "this filter is active and affecting what you see." |
| 8 | **No empty state illustration** | When no lanes exist: plain text "No lanes in project, go to Settings to add them." When no active sprint: plain text. No SVGs, no illustrations, no friendly characters. | Consistent with the product's personality — it tells you the problem and where to fix it. A cartoon illustration of an empty board would violate the application's character. |

---

## File References

| Purpose | Path |
|---------|------|
| Board page | `frontend/src/apps/tenant/domains/projects/relations/issues/pages/Board.vue` |
| Issue card | `frontend/src/apps/tenant/domains/projects/relations/issues/components/DragElement.vue` |
| Board lane | `frontend/src/apps/tenant/domains/projects/components/Lane.vue` |
| Filter bar | `frontend/src/apps/tenant/domains/projects/components/filters/FilterBar.vue` |
| Search filter | `frontend/src/apps/tenant/domains/projects/components/filters/SearchFilter.vue` |
| Multi-select filter | `frontend/src/apps/tenant/domains/projects/components/filters/MultiSelectFilter.vue` |
| Project layout | `frontend/src/apps/tenant/domains/projects/pages/ProjectLayout.vue` |
| Menu tabs | `frontend/src/shared/components/navigation/MenuTabs.vue` |
| Sidebar layout | `frontend/src/shared/components/navigation/SidebarLayout.vue` |
| Sidebar navigation | `frontend/src/apps/tenant/components/navigation/Navbar.vue` |
| Project sidebar item | `frontend/src/apps/tenant/components/navigation/SidebarProjectItem.vue` |
| App logo | `frontend/src/apps/tenant/components/ui/AppLogo.vue` |
| Epic badge | `frontend/src/apps/tenant/domains/projects/relations/epics/components/EpicBadge.vue` |
| Branch status icons | `frontend/src/apps/tenant/domains/projects/relations/issues/components/BranchStatusIcons.vue` |
| Project tabs config | `frontend/src/apps/tenant/domains/projects/projectTabs.ts` |
| Kanban store | `frontend/src/apps/tenant/services/draggable/kanban.ts` |
| Filter logic | `frontend/src/apps/tenant/domains/projects/relations/issues/filters.ts` |
| Design system spec | `docs/design-system.md` |
| Design system tokens | `frontend/src/shared/styles/theme.css` |
| UnoCSS config | `frontend/uno.config.mts` |
