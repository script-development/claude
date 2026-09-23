# Sibling precedent

Before accepting any novel shape, find the code that already solves it — another action or
service in the domain, another consumer of the same event, another page in the relation,
another store, another architecture test.

List every new or moved unit the diff introduces (an action, a composable or hook, a
component, a store, a migration shape, a middleware) and, for each, name the sibling you
compared it against or state that you grepped and found none. Finding the sibling is the
expensive part of this review and the thing that makes findings actionable — budget for it. A
claim that nothing like this exists is a `confirmed` claim of absence and needs the grep behind
it in `checked`.

Three shapes:

- **A second implementation of something a shared module or a sibling already provides.** The
  same snapshot / bulk-update / re-read / audit-log block appearing at yet another site instead
  of a helper is the recurring case.
- **A convention the sibling applies that this diff drops.** Check the pre-diff version of a
  moved unit: a *removed* convention is a regression and weighs more than one that was never
  there.
- **A cross-stack contract the sibling establishes that this diff diverges from** — a resource
  field named differently from every other resource, an event payload shaped unlike its peers.

Name the sibling `file:line` on every finding. A finding with no named sibling is preference,
and preference is not this section — "could be shorter", "extract a helper" are not findings
unless a sibling establishes the shape. Precedent is the standard, not taste.
