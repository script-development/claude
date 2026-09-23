# Sins of omission

Hunt what the change obligates but does not contain — an absence is a finding. Flag
obligations this diff creates, not a recital of the list.

- **The symmetric operation** — create obligates delete or cleanup; write obligates read; attach
  obligates detach; a cache write obligates the invalidation; a subscribe obligates the
  teardown; a broadcast event obligates a listener, a resource field obligates a reader.
  Dead-code tools catch unused exports inside one language; they cannot see a backend event
  with no frontend listener. Name the missing half and what accumulates without it.
- **Exhaustiveness over the new case** — a new enum case, state, or event obligates every
  switch, renderer, listener, and consumer over that set. Grep them all; say what an unhandled
  one does.
- **The covering test** — new observable behaviour obligates a test that observes it; a bug fix
  obligates a regression test that reproduces the symptom. Two ways a test that cannot fail
  still passes: a faked boundary sits between the assertion and the defect, so the defective
  path never executes; or a matcher is loose enough to accept the wrong value. Name what the
  suite is blind to. Faked boundaries worth naming: a transaction mock that invokes the closure
  once; a cache-prefix test on an in-memory driver; a typed parameter the test feeds a number
  while the transport delivers a string; an optional field the test always sets, so the
  explicit null it now writes never reaches a column that refuses one. Verify a
  behaviour-preserving change against the layer that broke, never against the new code's own
  mock. The coverage gate attests execution, not this.
- **The promised behaviour** — user-facing copy that names a system action (an email arrives, a
  file downloads, data is deleted, history is tamper-proof) obligates the implementing path.
  This covers in-app template strings, site guides, API docs, legal pages, generated LLM
  corpora (an `llms.txt` or `llms-full.txt`) and skill docs alike — in the diff, and sentences
  elsewhere that this diff's code change made false. Grep for it; an unkept promise is a
  finding. A claim on a legal page or about data handling, retention, or security posture needs
  a human's sign-off rather than a rewrite — say which. On the failure path, name what data
  persists.
- **The data already in place** — a schema, default, or config change obligates the backfill for
  rows, tenants, and installs that already exist.
- **The operational trail** — a new failure mode obligates a signal someone can act on; a new
  entry point or job obligates its guards; a new knob obligates its `.env.example` (or
  equivalent) entry and the docs that provision it. Run the census yourself: a key the diff
  reads from config or the environment with no line in the example env file, or set in
  deployment config and absent from the example, silently reverts to the default on every
  environment provisioned from the example. A key the code assigns at runtime is not a missing
  knob.

State the consequence of the absence.
