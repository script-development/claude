# DECISIONS.md template

Write decisions to `docs/plans/{{ISSUE_KEY_PREFIX}}-XXXX-slug/DECISIONS.md` **as they are made** during planning,
not after the plan is finalized. Rejected proposals and their reasoning are valuable context.

```markdown
# {{ISSUE_KEY_PREFIX}}-XXXX: Decisions

## D1: [Short decision title]
**Status:** Accepted | Rejected | Superseded by D3

**Context:** [What triggered this decision — the problem or question]

**Options considered:**
1. **[Option A]** — [brief description]
   - Pro: [...]
   - Con: [...]
2. **[Option B]** — [brief description]
   - Pro: [...]
   - Con: [...]

**Decision:** [Which option and why]

**Consequences:** [What this means for implementation]
```

Rules:
- Write each decision **the moment it's made** during planning, not after
- Rejected proposals get their own entry with `Status: Rejected` — they explain why NOT
- Keep entries concise — 5-10 lines per decision, not essays
- PLAN.md references decisions by number (e.g., "see D3") instead of repeating reasoning
