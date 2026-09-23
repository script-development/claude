# Module-shape lens (deep vs shallow)

A **deep module** hides a lot of behaviour behind a small interface and rarely changes — easy to test in isolation, hard to break. A **shallow module** is a thin wrapper whose interface is almost as complex as its implementation — usually a sign that the abstraction isn't carrying its weight.

> **The most common author failure mode**: rationalising "Deep" because the implementation has lots of code inside. **Implementation line count is NOT the test.** Authors get a Service with 200 lines of HTTP+SSE inside, see "lots of behaviour," and stamp "Deep." Wrong test. The right test is interface-vs-implementation *ratio* per use case — see the shallow-detection test below.

## The shallow-detection test (the load-bearing part)

A module is **shallow-and-suspect** if any of these three checks fires:

1. **The interface mirrors the use case.** One public method whose name *is* the use case (`runResearchSession`, `processInvoice`, `sendWelcomeEmail`), whose parameters describe its whole job in primitives. The method name + signature could be lifted into a docstring on the caller and nothing important would be lost.
2. **The interface is roughly proportional to the implementation per use case.** 5 primitive params + 1 method ⇒ interface complexity ≈ implementation complexity, even when the method body is 150+ lines. The body's size is irrelevant — what matters is whether the *interface* shrinks the caller's burden.
3. **A second consumer would require adding a method, not a parameter.** Concrete forcing question: "what about <plausible next use case> tomorrow?" If the honest answer is "add `runOtherThingSession`," the module is per-use-case scaffolding, not per-protocol abstraction. Each new use case will duplicate the lifecycle code.

If a module fails any of these, it's shallow-and-suspect. Two ways to fix:

- **Demote it.** Push the use-case method down into the calling Action; the Service disappears. The Action gets deeper (now owns orchestration). Whatever protocol/lifecycle was hiding inside the Service gets exposed as its own deep low-level client. This is what fixes the "one-method-per-use-case service" anti-shape.
- **Promote it.** Replace the per-use-case method with protocol primitives the caller composes. Now the module is reusable across use cases and the interface no longer mirrors any single one.

## Calibration: a vendor-app service split (2026-04)

An `app/Services/<Vendor>AppService.php` once held `getInstallationToken`, `createCheckRun`, `createPrComment`, `dispatchWorkflow`, `downloadReleaseAsset` — five per-use-case methods. The split landed:

- `app/Services/<Vendor>/<Vendor>ApiClient.php` — **deep** (low-level read-side protocol; multiple consumers compose its primitives).
- `app/Services/<Vendor>/<Vendor>OAuthClient.php` — **deep** (OAuth flow primitives).
- `app/Services/<Vendor>AppService.php` — kept the methods that genuinely shared the app-level JWT-auth lifecycle (`getInstallationToken` + a few app-as-bot operations), now justified because their public interface (auth) is much smaller than the lifecycle they hide.

The pattern that triggered the split: each method's interface mirrored a specific use case (test #1), and adding another use case meant adding another method (test #3). The fix demoted shared protocol concerns into a deep low-level client and kept only the legitimately shared auth lifecycle in the high-level service.

Plans for new vendor-namespaced services (e.g. `app/Services/<LlmVendor>/`, `app/Services/<PaymentVendor>/`) should mirror this shape from day 1, not relive the split.

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

The Eloquent distinction matters: a `scopeVisibleTo()` method added to an existing Model is exempt; a brand-new Model whose entire interface is two `belongsTo` relations is **not** exempt — it's the canonical shallow module the lens catches. If a new Model class has zero domain behaviour beyond its relations, it earns nothing over a plain `belongsToMany` and should be folded out.

Adopters on a different stack should adjust this list to their framework's natural shallow-by-design artefacts.

## What to answer per in-scope module

For each row in PLAN.md's Key Design Decisions / module-shape table:

- **Inputs/outputs** — the smallest interface that does the job
- **Hidden behaviour** — what this module knows that callers don't have to
- **Test seam** — what you'd test through the public interface, in plain English ("can register, then verify, then revoke")
- **Shallow-test reckoning** — explicitly answer: "if a second use case lands, do I add a method or a parameter?" Method ⇒ shallow. Parameter ⇒ likely deep. This is the bit that catches author rationalisation.
- **Verdict** — deep, shallow-but-justified (e.g. one-shot adapter or a precedent-cited pattern with explicit rationale), or shallow-and-suspect

A verdict of "Deep" without the shallow-test reckoning is **not** an acceptable lens output. Authors must show the test, not just label the result.

## Resolution

If a module comes back **shallow-and-suspect**, demote or promote it before continuing. Don't ship a five-shallow-modules-glued-together design. Plan-time is the last cheap moment: no pre-PR reviewer grades module depth directly, so a shallow design surfaces later only as the sibling drift and dead scaffolding `precedent-reviewer` flags — after it's built.

## Calibration evidence

Original drafts of rewritten plans show this gate is load-bearing when applied at draft time:

- A watcher join-model — deleted in R1 (zero domain behaviour beyond two relations; failed test #1 + #2).
- A `scope_type` enum in a predecessor plan — scrapped (shallow indirection over a primitive).
- A first-draft `ManagedAgentsService::runResearchSession(string $agentId, string $envId, string $userMessage, string $repoUrl, string $token)` — caught by the developer mid-review (failed all three tests; one method whose params described its whole job, interface ≈ implementation per use case, would have grown a sibling method per future use case). Restructured into `<LlmVendor>\ManagedAgentsClient` (deep — protocol primitives) + `ResearchAction` doing composition. The lens *exists* to catch this shape; the original "Deep — ~150 lines of HTTP+SSE inside" justification was the textbook author rationalisation that this section now explicitly forbids.

## Output

Goes into PLAN.md's "Key Design Decisions" table (or a dedicated module-shape sub-table) as one row per non-trivial module, with the test seam captured separately under "Testing Strategy". Every row must include the **Shallow-test reckoning** column, not just a verdict label.
