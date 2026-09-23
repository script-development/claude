# Test disciplines

This section rides only when the diff changes a test file (`*.spec.*`, `*.test.*`, `*Test.*`,
`test_*.py`, anything under a `tests/` or `test/` directory). When it does not, say so in
`checked` and stop. Apply it to every test the diff touches and to every claim you support
with one.

- **An assertion this diff edited is the change, not its proof.** Never cite an expected
  value this diff wrote as evidence the new behaviour is intended. When expected values
  change in the same diff as the behaviour they pin, say so plainly — "the pinning test
  was edited to agree" — and grade code and test as one change against the recorded
  rulings and the pre-existing contract, never against each other.
- **A test this diff weakened pins less than it did.** A matcher loosened, an assertion
  deleted, a case dropped, a `skip` added, an arch-test allowlist grown — each retires a
  defect the suite could catch, and the diff that retires one owes its reason. Name the
  regression that now passes: the value the old assertion rejected and the new one accepts.
- **A test's name is a claim.** Read the assertions and say what they actually pin. A test
  named for a rule that asserts only a weaker property certifies nothing about the rule —
  a sum matching the total does not pin how a remainder was distributed. The gap between
  the name and the assertions is a finding under the covering-test rule.
- **A test that can fail only on its own setup is ceremony.** Where the repo's `CLAUDE.md`
  files or test docs state testing rules, hunt each in every test the diff touches; name the
  rule a test breaks. Three shapes regardless: a rule proven at two layers, such as an
  integration test re-asserting a unit test, or a component spec reading a prop back off a
  stub; an assertion on what the test's own Arrange put there, such as a flag the stub set or
  a mock's return handed back; a fixture sized to a limit, 501 rows to see one dropped, where a
  parameter or an oracle would prove the rule. Name the defect the test cannot fail on.
- **Coverage attests execution, not correctness.** A suite can run every changed line and
  still be unable to fail on the defect class the change risks. Name what the suite is
  blind to, never what percentage it runs.
