# Recorded rulings

The repository's front door records rulings: decisions already made, under headings like
"Critical gotchas", "Conventions", "DECIDED", or an ADR number. The front door is authoritative
over docblocks, code comments, and the diff's own account of itself. The front door is:

- every `CLAUDE.md` in the repo — root and per-area
- a domain glossary (`CONTEXT.md` or similar) and an `ARCHITECTURE.md`, where they exist
- the repo's ADR set, where it has one — a `docs/adr/` directory, an ADR section inside a
  `CLAUDE.md`, or a projection of an external ADR site

The front door's rulings are the authoritative list of standing rules; do not work from memory
of which rules exist. Where a front-door file projects an external ADR site, escalate to the
canonical page only when a projection is ambiguous against a site you are auditing or cites a
sub-rule not reproduced inline — one fetch per review at most, and cite the URL in `evidence`.

A front door may name another file as the home of its rules. Open that file too when it is in
this worktree, one hop, and read its rulings as the front door's own. A file the front door
merely links — a skill, a README — is not that home. In `checked`, name each file you followed
this way, or say the front door names none.

Open every front-door file. List each ruling that names a behaviour this diff changes, then
check the diff against it. Cite the ruling by its ADR number or heading. Three shapes:

- **The diff changes code against a ruling it does not touch.** The recorded rule stands
  and the change now contradicts it. File it — `introduced`, and `confirmed` when the
  contradiction is on the page. The ruling is the repository's decision; a test edited in
  the same diff to expect the new behaviour is part of the change, never a license for it.
  Say plainly which ruling the change reverses.
- **The diff rewrites a ruling while the code keeps the old behaviour.** The front door
  now misstates the code it governs, and every later reader inherits the error. File it —
  `introduced`.
- **The diff rewrites a ruling and the code together, consistently.** A rule change is
  allowed — and never silent. File the reversal with `confidence: unconfirmed` and a
  `proof_gap` naming what would authorize it (a `<plan-root>/<slug>/DECISIONS.md` entry naming
  the reversal). State the old rule, the new rule, and that ruling text, code, and tests
  moved together.

A disagreement this diff touched on neither side is ordinary `pre_existing` territory, not
this census.

**The branch's own prose.** When the plan directory's `PLAN.md` exists, every factual claim it
makes about what the code does — especially in `## Security & Cost Surface` — is a ruling of
the same kind: check it against the diff. A contradicted safety or cost claim files
`introduced`, `confirmed`. A D-numbered entry in `DECISIONS.md` is a recorded choice: you may
file a finding against its factual basis, and you file the finding the choice would waive
anyway, quoting the D-line in `evidence` — the parent session weighs it. You never
apply the waiver yourself.
