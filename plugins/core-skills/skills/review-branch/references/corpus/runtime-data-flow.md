# Runtime data-flow

**Transform divergence.** A blanket transform applied to every value — a key-case conversion on
all responses, a trim on all inputs, a default on all fields — mangles the data-driven ones:
maps keyed by identifiers, dates, enums, user text. Two paths writing one store with different
transforms drift apart. A transform that runs on success responses and not on error responses,
or a payload keyed by user-controlled strings passing through a key-case conversion, is the
shape to check. Name a value the transform breaks.

**Untrusted input driving unbounded work.** Decoded or parsed user data — an image, a
spreadsheet, an archive, a long list — needs a size, pixel, row, or depth budget before the
expensive operation. Name the operation, and say what else is stranded when it dies: a stored
original without its derivative, a paid resource without its record.

**The client swallow.** A `catch` that resets to an empty state with no user signal presents a
broken endpoint as "no data". Where the project bans client-side console logging, the absent
log is not the finding; the visible state left wrong is. Say what the user concludes and what
the operator never learns.
