# Security & cost surface

The two censuses below catch the worst findings this review produces. Run both wherever the
diff adds or moves an entry point, or reaches a language model.

**Untrusted input reaching a language-model prompt.** List every user-controlled field that
can reach a prompt-assembly site. For each field, trace the path from its entry point to the
prompt. Two things must hold on every path: outer wrapping tags around the untrusted text, and
a sanitizer that handles nested and repeated tags. A path that skips either is the finding —
name the path, and name what an injected payload then controls. Where nothing in the diff
assembles a model prompt, this census has no items: name that absence in one clause and stop.
It never becomes a per-field trace of fields that reach no model.

**Entry-point census.** First list every entry point the diff adds or moves: HTTP routes,
console commands with side effects, queued-job entry points, webhooks, scheduled tasks, MCP
tools. Then check five guards on each one, and cite the line that applies each guard:

1. **Authorization at the right granularity** — the policy or ability that matches the action,
   not merely "authenticated". Where the repo routes authorization through a middleware or
   policy layer, an inline role check beside it is the finding.
2. **A named rate limiter** — not the default one, not an inline count that shares a counter
   with every other unnamed route.
3. **A spend cap**, where the route does paid work.
4. **Opaque-token state**, where a token names a resource — an enumerable or guessable token is
   the finding.
5. **A cross-tenant or cross-user overwrite guard**, where the input names another party's
   resource. In a multi-tenant app, a query that reaches a row by id without the tenant scope
   is this finding.

Group inheritance counts only when you cite the group's middleware stack. Where a sibling entry
point exists (tenant and central, admin and user, singular and bulk, REST and MCP), list both
guard sets side by side — a guard the sibling has and this one lacks is a finding. On a stack
where a guard has no analogue, say so; do not manufacture a failure.

**Guard-set delta.** Then compare head against base — the diff is that comparison — and report
security posture that got weaker, even where the new code works as intended. Work per entry
point and per guarded operation the diff touches: list its guard set at base, list it at head,
and report every guard that fell out of the set. A removed guard is the finding even though the
removal is a deletion — tag `provenance` by where the guard lived, and say what the head now
permits that the base refused. The shapes:

- guards weakened or removed: validation, escaping, rate limits, permission checks
- secrets: credentials in code, tokens in logs, sensitive values in error messages
- crypto downgrades: weaker algorithms, shorter keys, verification turned off
- cookies and headers losing protections they had at base
- new capability wider than the change needs: file paths, subprocess use, network reach
- external mutations losing their safety net: a timeout removed or absent on a call that
  mutates outside state; a compensating cleanup no longer run when a later step fails —
  name what orphans and who pays for it
- the audit trail getting thinner: a record of a mutation moved out of the transaction
  that performs it, snapshots read back later instead of taken at action time, an
  outcome or bulk variant no longer recorded — the record of what happened goes absent
  or wrong

State what the failure costs: missing authorization on a mutating route or a cross-tenant
overwrite is a takeover; a default limiter on a paid endpoint or authorization that is too
coarse is spend and over-reach.
