# Module-shape lens (deep vs shallow)

A **deep module** hides a lot of behaviour behind a small interface and rarely changes — easy to test in isolation, hard to break. A **shallow module** is a thin wrapper whose interface is almost as complex as its implementation — usually a sign that the abstraction isn't carrying its weight.

## In scope

Apply the lens to: Actions, services, helpers, composables, stores, **domain Models** (especially new ones introduced for this feature), and any class introduced specifically for this feature whose shape isn't dictated by a framework convention.

## Exempt — framework-shaped artefacts

Skip the lens for these; their shallowness is intrinsic to the role, not a design smell. The exact list depends on the project's stack — common examples in a Laravel + Vue codebase:

- Mailables (`envelope()` + `content()` only)
- Exception classes (carry a message, no behaviour)
- Icon components (single `<svg>`)
- Migration classes
- ResourceData / DTO classes
- FormRequest classes
- Controllers (HTTP-layer dispatch)
- MCP Tool classes
- **Eloquent scopes** (single `scopeFoo()` query-builder methods on existing Models — *not* whole new Model classes)

The Eloquent distinction matters: a `scopeVisibleTo()` method added to an existing Model is exempt; a brand-new Model whose entire interface is `belongsTo` relations is **not** exempt — it's the canonical shallow module the gate catches. If a new Model class has zero domain behaviour beyond its relations, it earns nothing over a plain pivot relationship and should be folded out.

Adopters on a different stack should adjust this list to their framework's natural shallow-by-design artefacts.

## What to answer per in-scope module

- **Inputs/outputs** — the smallest interface that does the job
- **Hidden behaviour** — what this module knows that callers don't have to
- **Test seam** — what you'd test through the public interface, in plain English ("can register, then verify, then revoke")
- **Verdict** — deep, shallow-but-justified (e.g. one-shot adapter or a precedent-cited pattern with explicit rationale), or shallow-and-suspect

## Resolution

If a module comes back **shallow-and-suspect**, either fold it into the caller or expand its responsibility. Don't ship a five-shallow-modules-glued-together design. This is the single most common failure mode caught later by `simplicity-reviewer` — surface it now, while the design is cheap to change.

## Output

Goes into PLAN.md's "Key Design Decisions" table as one row per non-trivial module, with the test seam captured separately under "Testing Strategy".
