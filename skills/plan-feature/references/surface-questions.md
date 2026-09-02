# Security & Cost Surface — canonical questions

This is the **single source of truth** for the six row questions that:

- the planner answers in PLAN.md's `## Security & Cost Surface` section during Phase 1.6 of `/plan-feature`
- the `surface-reviewer` agent grades the answers against at plan-time (prose-vs-Approach) and `precedent-reviewer` runs drift detection against at PR-time (prose-vs-code)

The rows are deliberately **question-shaped, not field-shaped**. Filling in a form trains for the past; answering a question generalises to the next feature. Worked examples below each row show what a strong answer reads like — they are illustrative, not templates. They name the kind of file or rule to cite; substitute the repo's own.

For the rationale and sycophancy guards, see [`quality-gates.md`](quality-gates.md) § Phase 1.6.

---

## Row 1 — Untrusted input → LLM prompt

Questions:

- Which user-controlled fields reach an LLM context (prompt-building calls, MCP tool arguments, vision endpoints)?
- For each, which framework tags wrap it in the prompt template — *including* outer wrappers an attacker-controlled body could close-and-replace, not just the immediate inner wrapper?
- Does the sanitizer at the callsite escape **every** framework tag wrapping the field, on every call?

*Strong answer:* "`record.description` reaches the Researcher prompt inside `<record><description>...</description></record>`. Both `description` and `record` are listed in the prompt-injection guard's framework-tag constant (`app/Agent/PromptInjectionGuard.php`), and `sanitize()` escapes all framework tags on every call — not a per-call tag argument. Every agent prompt shares the const, so adding a new framework tag auto-protects every callsite."

*N/A acceptable when:* feature reaches no LLM / agent / vision endpoint.

---

## Row 2 — External mutation

Questions:

- For each external mutation (HTTP, queue, file write, billing call), is there a timeout threaded into construction or per-call? Cite the arch test (e.g. the repo's external-HTTP timeout test) that pins it.
- Walk all three partial-failure shapes and name the compensating action *or* idempotency mechanism for each:
  - (a) **local-then-external throws** — local row committed, external never created
  - (b) **external-then-local rolls back** — external created, local rolled back
  - (c) **concurrent collision wins-loses** — second caller's local insert hits a unique violation *after* the external resource was created
- For multi-instance external state (multiple billing subscriptions per customer, multiple webhook subscriptions per app, multipart upload parts), is the cleanup an explicit loop or a single-instance shorthand?

*Strong answer:* "The billing provider's `cancelNow()` runs outside the DB transaction; idempotent via the provider's `status === 'canceled'` short-circuit on retry. Multi-subscription cleanup: `$tenant->subscriptions()->whereNotNull('provider_id')->where('status', '!=', 'canceled')->each(fn($sub) => $sub->cancelNow())`. Timeout: the billing client is on the allowlist of `tests/Arch/ExternalHttpTimeoutTest.php`. Partial-failure (a) is impossible — the provider is the first call. (b) is idempotent on retry. (c) doesn't apply — tenant id is the key."

*N/A acceptable when:* no new external mutation; reusing an already-compliant client without adding new methods or new mutation sites.

---

## Row 3 — Endpoint surface

Questions:

The row covers every surface a client can hit: REST routes **and** broadcast channels. A WebSocket subscription is an endpoint with a long-lived response.

- For each new route, is the authorization gate the **doing-the-work** permission (not `viewAny` for writes, not `update` for deletes, not a coarser permission than the operation justifies)?
- For each broadcast channel this feature adds or **widens**: who can subscribe (the channel-authorization gate, e.g. `routes/channels.php`), and does that audience match the REST permission for the same data? A client-side filter is rendering, not authorization — a member without read permission on the data must not receive its payloads over the wire. A past channel merge was closed over exactly this, after all the code was written.
- What is the fan-out cost — egress scales as subscribers × payload. Name the multiplier the change introduces and any server-side interest filter that bounds it.
- When a channel is renamed, merged, or removed: what is the transition window for already-open tabs? Removing every old registration in one deploy leaves open clients silently stale.
- Is the rate limit a **named** limiter registration (e.g. `RateLimiter::for()`) with a per-user or per-tenant cap, not the framework default (`throttle:120,1` or equivalent)?
- For endpoints that consume paid external resources, what's the per-user/per-tenant spend cap?
- For endpoints that accept redirect-bound `state` parameters (OAuth callbacks, install flows), is the state an **opaque random token** with payload stored server-side? `tenantId|userId|salt`-shaped states leak identifiers through referrer logs, browser history, and proxy logs.
- For endpoints that find-or-overwrite a row keyed by an externally-controllable identifier (installation_id, customer_id, subdomain, webhook payload id), where's the `if ($existing->tenant_id !== null && $existing->tenant_id !== $current) throw` guard? Unconditional overwrite is a cross-tenant takeover vector.

*Strong answer:* "`POST /api/records/{record}/summarise` — auth: `update` on `Record` (`viewAny` would let anyone with read access pay for a summary). Rate limit: named `summarise-record` limiter at 5/min/user. Spend cap: 20 sessions/tenant/day via the Action's precondition. No redirect-bound state — flow is intra-app. Cross-tenant guard N/A — record is scope-bound by route, not externally-supplied."

*N/A acceptable when:* feature exposes no new routes, all routes are intra-tenant reads, no OAuth/install/webhook callback is added, and no broadcast channel is added, widened, renamed, or removed.

---

## Row 4 — Audit-log fidelity

Questions:

- **When** is the audit row written — at press-time, outcome-time, or both? (A press where the downstream call throws and leaves no outcome row also leaves no audit trail unless the press itself is logged.)
- **What** does it snapshot — which fields, captured from where? Snapshots must be taken at action-time, not by re-querying referenced rows at log-time (the user may have been deleted, the field may have changed).
- **Which outcomes** does it record — does the logger enumerate failure / expiry / terminate / timeout, or hard-code `status: 'success'` regardless of caller?
- **Variant parity** — if a singular Action exists for this operation, does every variant (bulk, scheduled, cascade-induced) share the same audit hook, or carry a documented exception? `DeleteRecordAction` calls the logger; `BulkDeleteRecordsAction` must too.

*Strong answer:* "Press audit: `SummariseRecordAction::execute` writes an audit row immediately on press, snapshotting `user.first_name + last_name + email + role + permission_set_id` into `actor_snapshot` from `$actor`, not re-queried. Outcome audit: `HandleSessionWebhookAction::handleOutcome` writes a second row with `status ∈ {success, failed, max_iterations, terminated, expired}` — the logger signature accepts the outcome enum, no hard-coded success. Variant parity: N/A — summarise is per-record, no bulk variant."

*N/A acceptable when:* feature writes no audit-relevant rows (no deletes, no role changes, no AI/PII writes, no tenant mutations).

---

## Row 5 — State-machine walkthrough

Questions:

- Which state machines does this feature introduce (partial unique index with status column, queue retry policy with finite max, multi-stage external mutation, server-side payload-drop guard, broadcast-too-large guard)?
- For each, walk both the happy path and every failure mode (terminal-state-reached, retry-exhausted, partial-rollback, concurrent-race, payload-too-large, rate-limited-by-server). Where does each failure mode resolve?
- List every side effect the feature emits outside the primary DB write — broadcasts, cache bumps / hash stamps, un-awaited promises, fire-and-forget dispatches. For each: does it fire **inside** or **after** the transaction? An inside-transaction broadcast publishes state a rollback revokes; `ShouldDispatchAfterCommit` defers and **discards on rollback** — name which behaviour you rely on. A snapshot captured before the transaction goes stale inside it (one past plan's pre-transaction status snapshot suppressed the dependent broadcast under a concurrent move).
- What happens when the enclosing action **retries**? A retried transaction must not turn a delete into a silent no-op or double-fire a side effect (one past plan added a retry budget and made `$model->delete()` a silent no-op on attempt 2+).
- When the side effect itself fails, who observes that — the user, an operator log, or nobody? "Nobody" is acceptable only as a written best-effort decision in DECISIONS.md (a documented best-effort visit-write decision once deflected a blocking review finding); an un-awaited promise whose rejection vanishes is not a decision.
- Does any failure mode produce **silent UX degradation** — a user seeing stale / dropped / capped state with no signal? An operator-only log breadcrumb does not count. If yes, what client-facing surface communicates degradation?

*Strong answer:* "Sessions: `unique(['record_id', 'in_flight'])` where `in_flight` is nullable, set to `true` on insert and `NULL` on completion — a second run after completion succeeds because the completed row's `in_flight` is NULL. Webhook retries: max 3 with 30s/60s/120s backoff, dead-letter logged to `webhook_failures` + an operator-log warning. Broadcast drops: the payload-size guard over 10KB → drops + emits a `refresh-required` sentinel on a small fallback channel; the page's subscription composable listens and re-fetches. No silent staleness path."

*N/A acceptable when:* feature adds no state machines (no partial unique indexes, no finite retries, no multi-stage external mutations, no server-side drop guards) **and** emits no side effects outside the primary DB write (no broadcasts, cache bumps, or un-awaited dispatches).

---

## Row 6 — Convention enforcement level

Questions:

- For each new structural rule this plan introduces ("every new X must do Y", "all classes in Z must inherit from W", "no method on this client may skip the timeout convention", "callers must remember to call `validateRelationsLoaded`"), what enforces it at CI time?
- Name the level on the Enforcement Escalation Ladder:
  - **L1** — architecture test (`tests/Arch/*.php` or the repo's equivalent)
  - **L2** — static-analysis rule (a repo-local rule, or the shared rule package the repo's standing rule for convention enforcement names for cross-repo rules)
  - **L3** — runtime assertion at construction or first use
  - **L4** — code review only (acceptable only when explicitly chosen with a stated trade-off)
- For each new method on an existing convention-bearing class (an external API client, a managed-agents client, an Action base), which conventions of the host class must it inherit, and where does the inheritance get enforced?

*Strong answer:* "New convention introduced: 'every method on `<Vendor>ApiClient` calls `->timeout()` per request.' Enforcement: L1, `tests/Arch/ExternalHttpTimeoutTest.php` extends its allowlist to include the new class. New methods on `<Vendor>AppService`: inherit `final readonly` + `#[Config]` credentials + per-call timeout; inheritance pinned by the existing `ServicesTest.php` arch coverage (already L1). No L4 reliance — the repo's standing rule for convention escalation names the shared static-analysis rule package as the lever if this drifts later."

*N/A acceptable when:* feature introduces no new structural rules and no new methods on existing convention-bearing classes.

---

## How the planner uses this file (Phase 1.6)

Read each row, write a prose paragraph in PLAN.md's `## Security & Cost Surface` section answering the row's questions for *your* feature. Mark `N/A — <one-line reason>` if no question on the row applies — but check the N/A clause first; agentic / paid / cross-boundary features rarely qualify.

Paraphrasing the questions back instead of answering them is THIN, not OK (Phase 4d rule). The `surface-reviewer` agent flags THIN prose at Phase 5.

## How `surface-reviewer` uses this file

Loads this file once at Step 1. For each row, compares the planner's prose against what the Approach section says the implementation will do.

At PR-time, `precedent-reviewer` reads the `### Surface Review (plan-time)` notes and holds the shipped code against them. A row that PASSed at plan-time and fails against the diff is **drift** — flagged BLOCKER regardless of underlying severity.
