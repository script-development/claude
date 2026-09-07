# DECISIONS.md template

Write decisions to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-slug/DECISIONS.md` **as they are made** during planning,
not after the plan is finalized. Rejected proposals and their reasoning are valuable context.

`/implement-plan` and `/next` read this file whole, in a session that usually holds nothing
else. Every line costs the implementer context, so an entry carries the trade-off and nothing
around it.

```markdown
# {{ISSUE_KEY_PREFIX}}-XXXX: Decisions

## D1: [Short decision title]
**Status:** Accepted | Rejected | Superseded by D3

**Context:** [One or two sentences — the problem or question that forced a choice]

**Decision:** [What was chosen, and the one reason that carried it — cite the file or precedent]

**Rejected:**
- [Option B] — [why it lost, one line]
- [Option C] — [why it lost, one line]

**Consequences:** [What this means for implementation — one line; omit when the Decision line already says it]
```

Rules:
- Write each decision **the moment it's made** during planning, not after
- **5–10 non-blank lines per entry**, heading included. Phase 4d checks this. An entry that
  needs more is two decisions, or carries prose the plan body already holds — a pro/con list per
  option is the shape that balloons; one line per rejected option naming why it lost is the
  whole record
- Rejected proposals get their own entry with `Status: Rejected` — they explain why NOT
- PLAN.md references decisions by number (e.g., "see D3") instead of repeating reasoning
