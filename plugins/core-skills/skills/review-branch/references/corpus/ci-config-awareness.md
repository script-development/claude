# CI-config awareness

What you can read of CI is point-in-time; the run this merge triggers has not happened, and
before the PR exists there is no check state to read. Two censuses, both answered from the
CI workflow files in the tree (`.github/workflows/`, or the repo's equivalent), never from a doc
or a test header that says CI enforces something. A repo with no CI config in the tree: say so
in `checked` and stop.

A workflow that delegates carries no steps to read. A job whose body is `uses:
<owner>/<repo>/.github/workflows/<file>@<ref>` runs its steps from another repository that is
not in this worktree. Name the job and its `uses:` target in `checked`, say the steps are
unreadable from this tree, and file no absence: "CI never runs X" about a delegated job is a
claim about a file you do not have. A composite action (`uses:` on a step) hides its steps the
same way.

**The gate a diff arms.** A diff touching CI, a test matrix, or coverage config changes which
jobs run and what they measure. A workspace newly wired into a coverage floor exposes its
pre-existing untested files; a matrix leg added or removed changes what a green check means.
A ruleset edit that narrows what a gate inspects is a change to the gate. Name the gate and
what it will do on the next run.

**The gate a diff never arms.** Two censuses, each with its own line in `checked`.

*The filter census, per path.* Enumerate the top-level directories the diff touches. For each
workflow with a `paths:` or `paths-ignore:` filter on `pull_request`, say whether every touched
directory falls inside it. A directory that falls outside every filtered workflow that would
otherwise test it is the finding: the surface can change without the job running. Name the
workflow file, the filter, and the path that falls outside it. A guard test that runs when the
test changes and not when the guarded surface changes is a test that cannot fail; a doc or
header that certifies enforcement the workflow does not perform is a false audit trail.

*The matrix census.* A test suite, project, or package the tree defines that no CI leg runs —
a test-runner project no workflow invokes, a test suite no CI script names, a package no
workflow tests, a workflow the diff adds that no event triggers. Name the suite and say which
leg should have carried it. Where the repo already has a test that diffs its test projects
against the CI legs, do not repeat that census; cover only what it does not.
