# Runtime-state simulation

A clean static diff is not proof of behaviour. Execute the changed code — in your head, or by a
read-only probe — along the paths the happy-path test never takes. For each path below that the
diff can reach, say what happens; for each it cannot, say why not.

- **The second and Nth loop iteration** — state read after the first write; a per-iteration
  query, relation load, audit row, broadcast serialization or SDK call (also an N+1).
- **The cancelled or partial path** — a new guard that locks the user out for good; a
  half-written row; a step that ran and cannot be undone.
- **The row, tenant, or install that already exists** — an edited schema, a new default, a
  backfill that no-ops on rows already in place.
- **The non-default toggle** — a positional selector, a magic offset, or an index assumption
  that does not survive a column toggled off or a non-default filter.
- **The absent, empty, or zero value** — an unset field that becomes a valid one: integer
  coercion turns absent into `0`, and an enum lookup on `0` matches the first case, so "not
  set" silently reads as the first state. Enumerate the adjacent unhandled case.
- **The concurrent second actor** — the same request or job twice at once. Trace lock order and
  snapshot timing under the isolation level before claiming either safety or a race; a
  scheduler with no overlap guard is this case. Name what produces the second actor — a
  retry, a redelivery on an at-least-once queue, a cron overlap, a worker pool, a
  double-click, the clock, or a shared serialization point every write touches — or say
  that nothing in this tree does.
- **The multi-step flow's failure branch** — does a non-validation error surface anything?
  does unmount cleanup destroy state a committed step needs? does a retry re-run a step that
  is not idempotent? An ORM delete inside a retried transaction is this case: where rollback
  does not restore the model's in-memory "exists" state, attempt two returns without deleting.
- **The batch item that throws** — first establish what the batch owes its caller when one
  item fails: abort the run, skip the item and report it, or roll every item back. Read the
  transaction boundary, the queue's retry, and what the caller does with the count. Then
  simulate one throwing item against that contract: under abort, the earlier items left
  applied with nothing said; under skip, a skipped item nobody hears of; under roll back, a
  partial run that reports success. A missing per-item guard is a finding only where the
  contract is per-item.

On a **presentational diff** — templates, styles, transitions, composables or hooks — simulate
the UI runtime; CSS and lifecycle are behaviour:

- the departing element that stays interactive — a leave transition with no
  `pointer-events: none` keeps the node clickable
- the real containing block — `position: absolute` resolves against the nearest positioned
  ancestor; an element with none jumps; stacking-context assumptions are the same family
- the timer or listener outliving the state that armed it — a cleared flag and a still-armed
  timer fires into the next occupancy; walk each to its cancel site. Anything subscribed,
  watched, or registered in a path that runs more than once (route resolvers, navigation
  guards, re-renders) needs a matching teardown.
- the refetch racing a live event — a wholesale `state = await fetch()` resolving after a live
  event overwrites newer state, which becomes the next baseline; a search or filter re-issued
  before the previous answer lands is the same shape. Where the repo has a latest-request seam
  for this, name it.
- the capped snapshot as the universe — a fact derived from absence in a truncated list
  fabricates state outside the window

A break on any of these is a real finding on a clean diff with green CI.
