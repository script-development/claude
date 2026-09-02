# Wireframe anti-patterns

Lessons-from-pain captured outside SKILL.md so they're loaded once on
demand, not every invocation. Each one represents a wireframe that
shipped, broke `wireframe-reviewer`, and forced a rework.

- **Raw CSS values** — always design tokens from the project's system. `wireframe-reviewer` validates token names; raw `color:` and `border:` declarations don't match anything and read as "no spec given here."
- **Raw computed sizes** (`text-size-0.82rem`, `font-size: 13px`) — use the project's named tokens (`text-xs`, `text-sm`, `text-base`, ...). The reviewer matches names, not computed sizes.
- **Inventing badge colour classes** — use the existing badge component with its supported variant / tint classes, not custom `bg-success-subtle text-success border-success/30` combos. New colour combinations will fail token validation.
- **Cross-area component in wrong directory** — if two app areas both use it, it goes in the shared directory. The repo's app-boundary architecture test (if it has one) will fail the build otherwise; flagging this in the wireframe saves a CI round-trip.
- **Referencing nonexistent icons** — check existing icons before naming them in specs; flag new ones as "needs creation" with the correct location. The reviewer grep-verifies icon names exist.
- **Undefined stores in interactions** — every store / method in the Interaction table must be defined in the wireframe or confirmed to exist. Areas that use inline API calls instead of stores get named as inline calls, not as a fictional store.
- **Sections beyond the 5** — data flow, file lists, a11y, coverage belong elsewhere. The reviewer counts sections; an extra one causes a structural fail even if the content is fine.
- **470-line wireframes** — if it's longer than ~250 lines, you're probably duplicating PLAN.md. The wireframe is a visual contract, not a re-articulation of the plan.
- **Re-specifying shared components** — reference the existing table or button component by name, don't describe how tables work. Implementing a `<TableRoot>` "again" inside the wireframe creates two sources of truth.
- **Inventing new patterns** — copy layout patterns from existing pages. New patterns are the developer's call, made during the Step 3 interrogation, not invented quietly while writing Section 4.
