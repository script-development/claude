# Contract & boundary integrity

Data is only as good as the check at the crossing. Three censuses over the boundaries this
diff adds or moves.

**Boundary validation.** List every site where data from outside the process enters typed
code: an HTTP response cast into store state, a queue payload, a webhook body, a parsed file, a
database row cast to a richer type. For each site, cite the line that checks the shape before
the first field read. A cast with no check between the read and the use — `as Foo` on a fetch
body, an unchecked `JSON.parse`, a row spread into a typed object — is the finding. Say what
happens on a mismatch: fail closed, or garbage propagating downstream wearing the type, and
name the first consumer that acts on the wrong value. Inbound request validation through the
framework's request-validation layer is correct by design and not this census; the response
half is.

**Schema↔runtime drift.** List every pair where one artifact declares a shape and another
produces or consumes it: a server-side resource or serializer beside the client type that reads
it, a validator schema beside the type it claims to prove, a broadcast payload beside its
listener, a serializer beside its parser. Diff each pair field by field. A field one side has
and the other lacks, an optionality or nullability the two sides disagree on, a narrowing one
side never applies — name which side is wrong and what the disagreement silently accepts or
drops.

**Transaction-scope integrity.** For every transaction this diff opens or edits, check what
runs inside against when its inputs were computed: an identifier resolved before the
transaction that a step inside renames or deletes out from under a later step; a nested begin
whose semantics on this stack are savepoint, no-op, or error — name which, from the stack in
the worktree, never from memory of the ORM; a read outside the transaction feeding a write
inside it; anything fallible, slow, or external inside the closure, holding a database
connection for its duration. State what a concurrent writer or a mid-transaction failure
leaves behind.
