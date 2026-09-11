# Context economy — skills design

**Date:** 2026-08-21
**Status:** Principles settled. Format open — see [Open questions](#open-questions).
**Evidence:** `docs/measured.md`. Every quantitative claim here comes
from that report; nothing below re-derives it.
**Amended 2026-08-24** against `reports/2026-08-24-harness-automation-surface.md` (in mission_control, not carried here), which inventories
the harness's hook, flag and control-protocol surface — the thing this document assumed rather than
enumerated. Claims it refutes are struck or narrowed **in place**, each citing the finding (F1–F8)
that did it, on the same reasoning as O1 and O3 below: _why_ a claim was wrong is the reusable part.
Nothing the first report measured changed.

This document exists because the reasoning that produced it is the part that cannot be recovered.
The measurement is reproducible (`node tools/context-audit.js`) and the tooling is on disk; the
decisions, and the alternatives they beat, existed only in one session's context. That asymmetry is
itself the subject of the design — see [D6](#d6).

---

## The problem in one paragraph

Cost per turn _is_ the resident context size, so total cost is quadratic in session length. Measured
across 8,888 API requests of real prior work: 98.1% of all tokens are cache reads, corpus
amplification is 58.6× (worst context 111×, now a floor — 51.6× and 111× as first reported, whose
denominator double-counted output; `docs/measured.md`, correction 2026-09-02), and 90% of spend
occurs at context depths above 100k.
A session does not end when the terminal closes — resuming appends to the same context, and the
largest session here spans four calendar days. Simulated against each context's own measured growth
rate, resetting at 200k instead of the 1M ceiling would have saved 66%.

---

## Why the quadratic is a replay artifact

_Added 2026-09-02._ The paragraph above is the load-bearing claim of this document, so it is worth
being exact about where the quadratic comes from. The obvious mechanism is the wrong one, and it
licenses a wrong inference.

_Provenance, since the header promises this document re-derives nothing:_ the structural argument
below is reasoning, not measurement. The output-billing figures under
[the rates](#the-rates-this-rests-on) are the exception — measured over the same transcript store
`docs/measured.md` used, by `tools/context-billing.js`, and not figures from that report. That tool
is this section's instrument, and also what found the denominator defect corrected in
`docs/measured.md` on the same date.

Attention is quadratic in sequence length, but that quadratic is **compute per request** — O(N²)
FLOPs to prefill N tokens, asymptotic (at moderate depth the per-token projection work dominates),
and it never reaches an invoice. The quadratic in the bill is a **protocol** artifact: requests are
stateless, so the entire transcript is re-sent every turn. With cache reads at 0.1× base input, a
session of `T` requests reaching depth `N` bills

`total ≈ 0.1 · Σ(depth at request t) ≈ 0.05 · N · T`

The test that separates the two: a model with perfectly linear attention would leave that figure
**completely unchanged**. Nothing about the mechanism is available as a lever — requests × depth is
the whole of it. Finding #1 already says this from the measurement side ("context replay is the
entire cost structure", 58.6× amplification); this is the same claim from the mechanism side, and it
is why every decision here acts on depth ([D1](#d1), [D10](#d10)) or on what enters context at all
(implications #3 and #4), and never on making an individual turn easier to process.

### The inference this closes

Since `c = N / T`, the same expression is `total ≈ 0.05 · N² / c`, where `c` is the average tokens
added per request. Cost falls as `c` **rises**. Adding context in small increments is therefore not
cheaper — it is dearer, because each additional request re-reads the whole prefix at 0.1×, pays
another cache write, and emits its own output.

Compute agrees, which is the part that surprises. Causal attention computes each ordered pair
(i, j), i < j, exactly once, and the set of pairs is a property of the **final sequence**, not of
the schedule by which it arrived. K tokens fed as one chunk cost `K·N + K²/2`; fed as chunks of `k`
they cost `K·N + K²/2 + K·k/2`. Splitting saves no work and adds per-request overhead. And there is
no quadratic-in-K on the invoice at all — K uncached tokens bill as K tokens, once.

**Fewer, larger additions.** Small chunks do have an argument in their favour — retrieval accuracy
over a diluted context — but that is a quality claim, and filing it under token economics is
precisely what inverts the rule.

### The rates this rests on

List prices, not measurements:

| | multiple of base input |
| ---------------------- | ---------------------- |
| cache read             | 0.1×                   |
| cache write, 5-min TTL | 1.25×                  |
| cache write, 1-hour TTL | 2×                    |
| output                 | 5×                     |

An output token is billed in **three** phases, and the cache write is _not_ folded into the output
rate:

1. **generation** — 5×, as output;
2. **the very next request** — 1.25×, as a cache write. The assistant turn is now part of the input
   prefix, and it is written like any other new input material. A separate charge;
3. **every request thereafter** — 0.1×, as a cache read.

Measured, not reasoned — `node tools/context-billing.js`. Token conservation makes the test exact
and needs no character estimate: the tokens sent on a request are `cr + cc + inp`, so between
consecutive requests `Δ(cr + cc + inp) = out(t) + newInput(t+1)`. If `cc(t+1)` equals that whole
delta the prior turn's output was re-billed as a write; if it equals `delta − out(t)` the output rode
in free. Across **1,716** warm consecutive pairs with `out(t) ≥ 300` (store as of 2026-09-02),
`cc(t+1)` matches the **whole** delta in **97.0%** of cases — 2.3% match `delta − out(t)`, 0.6%
neither — and for pairs under a minute apart `cc/Δprefix = 1.01`.

The 2.3% is real, and it is the free-read hypothesis actually winning — _this document asserted
otherwise on first writing and was wrong._ The tempting explanation is that the increment landed in
uncached input because the breakpoint had not advanced; the decomposition refutes it. In those pairs
`inp` averages 2 tokens while `cr` grows by more than the entire previous prefix, by very nearly
exactly `out(t)`: **51,896 of 53,693** shortfall tokens are served as reads, across 43 of 45 pairs.
So the server does sometimes retain the KV it computed while generating and extend the entry for
free — rarely, unpredictably, and for reasons not established here. It does not disturb the 97%
account, and `tools/context-billing.js` now prints that decomposition so the next reader measures it
instead of reasoning about it.

Lifetime cost of an output token surviving `R` further requests is therefore `5 + 1.25 + 0.1·R`
multiples of base input. At the corpus's measured amplification that is ≈11×, of which generation is
~44% and replay ~56% — the two halves are the same order, which is worth knowing before optimising
only one of them. This is also the mechanism under finding #1's otherwise odd pair of numbers
(output is 0.2% of tokens but 8.7% of cost), and under `docs/calibration.md`'s strengthening of
implication #4: bounded output and scoped reads are worth more than a flat per-token ratio makes
them look.

**Phase 2 can also repeat.** A cache write is not a one-time toll — when an entry expires the prefix
is re-written at 1.25×. Same store, all warm growing pairs bucketed by the gap between consecutive
requests.

Both halves of the ratio are per pair of consecutive requests, over the same interval:

- **`Δprefix`, the denominator** — how much bigger the thing you send got. Tokens sent on a request
  are `cr + cc + inp`, so this is that figure on request t+1 minus the same figure on request t. It
  is the genuinely new material: the previous assistant turn, plus tool results, plus your message.
- **`cc`, the numerator** — `cache_creation_input_tokens` on request t+1. The tokens charged the
  1.25× write rate on that request.

So the ratio reads **tokens paid to write ÷ tokens that were actually new.**

| gap | pairs | `cc / Δprefix` |
| ------------- | ----- | -------------- |
| under 1 min   | 2,261 | 1.01           |
| 1–5 min       | 224   | 0.71           |
| 5–60 min      | 68    | 1.85           |
| over 1 hour   | 1     | 152.9          |

**= 1.0** is the ordinary case and needs no story: a turn during active work — agent calls a tool,
result comes back, next request goes out. The previous assistant turn and the tool result are each
written once. Across the 2,471 such pairs the match is near-exact: 4,900,771 tokens written against
4,900,656 new, 115 apart in total. The _first_ request of a session is **not** an instance of it —
there is no predecessor to difference against, and `cr = 0` excludes it as a cold start.

**Every ratio in that table is one identity.** Since `Δprefix = (cr + cc + inp)[t+1] − prevPrefix`,
substituting and cancelling gives, for every pair without exception:

```
cc − Δprefix  ≡  prevPrefix − read − inp
```

That is algebra, not a finding — worth writing down because it collapses the whole table into a
single question. The ratio is not measuring three phenomena; it is measuring **how far request t+1's
cache read reached, relative to everything that was sent on request t.**

| read vs. prior prefix | ratio | what happened |
| --------------------- | ----- | ------------------------------------------------------- |
| `read = prevPrefix`   | 1.0   | the read reached exactly what was sent last time        |
| `read < prevPrefix`   | > 1   | the read stopped short; the gap is written again        |
| `read > prevPrefix`   | < 1   | the read covered *more* than was sent — the generated tokens too |

So the only real question is why the read stopped where it did, and the corpus gives three answers
plus a residue.

**Cause 1 — TTL expiry.** The head entry survives, the body does not:

```
gap  7.1m   prior prefix 103,257   read 32,917   wrote 71,709   ratio 52.3
gap 10.7m   prior prefix 109,579   read 32,917   wrote 77,997   ratio 58.3
```

Read sizes across every large-ratio pair cluster at 27,430 / 29,489 / 30,750 / 32,917 / 32,934 — the
harness preamble, the same ~31k the compaction addendum reads. The conversation body is written
again against a surviving preamble; both of those wrote at the 5-minute TTL with a gap just past
five minutes. The intuitive telling — back from a long lunch, pay for the prefix again — is right
about the cost but names the case the table *excludes*: expire the head too and `read` drops to 0,
which the warm filter discards as a cache miss. A short lunch is what stays in and shows a ratio.

This cause, and only this one, makes **idle time billable**: a session left open across a break pays
to re-establish precisely what it already had, and the charge scales with the prefix rather than with
anything the break accomplished. Causes 2 and 3 below are indifferent to elapsed time. Reducing idle
time is a real lever and this design does not pull it — the [D1](#d1) simulation prices resident
context, not the clock.

**Cause 2 — breakpoint granularity**, and numerically the common one: 7 of the 13, ratios 1.1–2.4,
nothing expired at all. The read did not stop short of the previous request's write — it reached
exactly where that write ended. What it stopped short of is `prevPrefix`, which counts everything
request t *sent*, and a request always sends more than it writes: a write extends only to the
deepest `cache_control` breakpoint, and whatever follows that boundary bills as ordinary input and
is stored nowhere. Call that uncached remainder `tail`, and the identity above becomes

```
cc − Δprefix  ≡  tail(t) − tail(t+1)
```

So the excess is not a fixed tail written twice; it is the amount by which the uncached remainder
*shrank* between the two requests — the breakpoint advancing over material that request t had
already sent bare. Here that is 657–1,839 tokens, about one turn's worth. Those tokens are paid for
twice, at 1.0× as input on t and 1.25× as a write on t+1 — ~2.25×, not the 2.5× that "written
twice" implies. When the remainder holds steady turn over turn the two terms cancel exactly, which
is what the 2,566 pairs sitting at 1.0 are.

Why the boundary lags the end of the request is not decidable from this corpus —
`docs/calibration.md`'s measurement ceiling — but one documented mechanism fits the signature.
Automatic caching places its single breakpoint on the last *cacheable* block, silently stepping back
to the nearest eligible one when the last block is not; a `clear_at: "next_user_message"` system
message, the per-turn-reminder pattern, is explicitly not cache-eligible — `cache_control` on it is
a 400, and the marker goes on the preceding user turn instead. A harness injecting one every turn
holds the write boundary a full turn behind the request, every turn, and the turn it left bare is
written on the next request as ordinary prefix. An explicit marker sitting on the last stable turn
rather than after the newest tool results does the same thing for a different reason, and `usage`
cannot tell the two apart.

Two other documented ways to leave an uncached remainder are *not* candidates, which is worth
stating because both look like ones. A marker deliberately placed before a volatile tail — the
recommended pattern when a request ends in per-request content that will never recur — leaves a
remainder that is never written at all, so it produces no second payment and no pair. And the
minimum cacheable prefix (512 tokens on Opus 5) is measured from position 0, so once a session
clears it no breakpoint is ever below it. Whatever produces the remainder here has to be something
that leaves this turn's material bare and the next turn's request paying for it.

**Cause 3 — the read runs past what was sent**, which is the `< 1.0` case and the interesting one.
The server occasionally serves the previous turn's output as a *read*, charging no write for it: of
53,693 shortfall tokens, **51,896** arrive that way, across 43 of 45 pairs, with `inp` averaging 2
tokens. _This document asserted the opposite on first writing_ — that a sub-1.0 ratio was increment
landing in uncached input because the breakpoint had not advanced. The decomposition refutes it, and
`tools/context-billing.js` now prints that decomposition on every run so the next reader measures it
rather than trusting a sentence. There is no user-facing example, because there is no user-facing
cause: it is unprovokable, about 2% of turns, and oddly concentrated in the 1–5 minute band (16% of
pairs there against 0.8% under a minute) — which is the whole reason that band reads 0.71 while
every other sits at or above 1.0.

Causes 1 and 2 push the ratio above 1.0 and cause 3 pulls it below, and across this corpus they
very nearly cancel — **+599,096** tokens paid for twice against **−551,424** never written at
all, a net of **+47,787** over 2,651 warm pairs, with the aggregate at **1.008**.

_Resist reading that as a mechanism._ An earlier draft of this section called causes 2 and 3 "one
bookkeeping lag seen from both ends", which implies the same tokens paid once and late. They are not
the same tokens: cause 2's are billed as input on one request and as a write on the next, cause 3's
are never written at all, the mechanisms are unrelated, and nothing defers or settles up. The
near-cancellation is a coincidence of this corpus and is not load-bearing for anything. What *is*
safe to say is that the deviation is small in both directions relative to the 2,566 pairs that sit
exactly at 1.0.

Nothing here is misattributed, either — a natural suspicion, since a deviation between "written" and
"new" looks like a charge landing on the wrong request. `cc(t+1)` is a real charge incurred by
request t+1, the transcript records it faithfully, and the identity is exact. What is only a proxy
is `Δprefix` standing in for "new material", which holds while the read boundary lands at
`prevPrefix` and stops holding when it does not. That is a limitation of this metric, not of the
billing or the transcript.

**The residue.** Four pairs resist all three — gaps of 0.1m, 2.3m, 8.2m and 124m, all tagged 1-hour
TTL. Six seconds apart with the whole body re-written is not expiry under any reading, and a TTL or
breakpoint-strategy switch is exactly what `docs/calibration.md`'s measurement ceiling says the
transcript cannot show. Left unattributed rather than explained.

Two further instances of the same phenomenon are absent from the table altogether. Compaction and
rewinding a conversation both do exactly what partial expiry does — a shared head served as reads,
everything from the first divergence written again — and neither appears here, because both make the
prefix *shrink*, which the `Δ > 0` filter drops. The exclusion is structural rather than cautious:
the identity above needs the new prefix to be the old one plus a suffix, and a rewritten history
breaks it, so the denominator stops denoting anything rather than merely going out of range.
Compaction's version of it is measured — `docs/measured.md`'s
[2026-08-31 addendum](measured.md#addendum-2026-08-31--what-a-compaction-costs-in-two-numbers) has
the first post-compaction request reading 31,059 tokens of harness preamble and writing 45,458
fresh, which is the same shape as an expiry row and is why that addendum insists on quoting a
compaction as two numbers. Rewind's version is not measured and cannot be from this corpus: it
re-writes from the nearest live breakpoint at or below the rewind point, and breakpoint positions
are not in the transcript (`docs/calibration.md`'s measurement ceiling), nor does a rewind leave the
detectable prefix-collapse signature that makes compaction findable at all.

### `R` is a property of position, not of the token

`R` above is not a constant — it is the count of requests that follow the one a token arrives on. A
token entering at request 1 of a 100-request context is replayed ~99 times; one entering at request
99 is replayed once. Same bytes, same rate card, two orders of magnitude apart in what they cost.
Lifetime multiples of base input:

| | lifetime cost      |
| --------------- | ------------------ |
| an input token  | `1.25 + 0.1·R`     |
| an output token | `5 + 1.25 + 0.1·R` |

So **position overtakes provenance as depth grows.** At corrected corpus-wide amplification
(`R` = 58.6) an output token costs 1.7× an input token of the same size; at the worst measured
context's 111× (finding #1) it is 1.4×; for a token sitting at position zero of that 486-request
session (finding #6), 1.1×. Deep enough in, it stops mattering much whether a token was expensive
to produce — the replay term swamps its origin.

This is the arithmetic under the implication ranking, and it is worth stating explicitly because the
two levers act on different terms: input hygiene (#4) reduces the **coefficient**, session-lifecycle
discipline (#1) reduces **`R`**. Only one of them acts on the term that grows — which is why #1
outranks #4 even though #4 is the one that feels like thrift, and it agrees with the reason
`docs/measured.md` already gives (#1 caps the damage from every call #4 misses).

It also gives the sharpest available statement of the `CLAUDE.md`-versus-skill rule. `CLAUDE.md` sits
at position zero of every request of every session, so it runs at the maximum `R` on offer,
permanently. A skill body pays `R` only from its trigger onward, and pays nothing at all in the
sessions that never trigger it. The two can hold identical text and differ by two orders of
magnitude in what that text costs.

**What this changes in the design: nothing.** No decision below moves and the ranking of
implications is untouched. What changes is the reasoning offered for them, and one inference —
"add context in small chunks" — that the attention framing was quietly licensing.

---

## What already exists

Establishing this first, because the most expensive mistake available here is rebuilding it.

| piece                      | status                                                                                                                                                                                                                                                                                                                                                                                      |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Reset mechanism**        | **Exists.** Auto-compaction, `trigger:"auto"`, compresses ~1.0M to ~20k — a 98% reduction, _smaller_ than the 25k handoff assumed by the simulation. **~1.0M is the default window, not the mechanism's** — it is settable to any value in 100k–1M (F1).                                                                                                                                    |
| **Threshold trigger**      | ~~Missing, but nearly free~~ — **refuted by F1.** `autoCompactThreshold` / `--autocompact` has always let the existing machinery fire at 200k, which is the whole 66%. What was genuinely missing is a threshold **whose response we control** — compaction's only response is compaction. The statusline half stands: it already receives `context_window` and used it only to draw a bar. |
| **Citation checking**      | **Exists** — `<kendo>/.claude/skills/plan-feature/scripts/verify-citations.sh`, 137 lines, with `verify-citations.test.sh`. Resolves paths and symbols; discards line references. **Now ported** to `tools/verify-citations.sh` + `tools/verify-citations.test.sh` (50 assertions) — see [D4](#d4), [D9](#d9).                                                                              |
| **Externalisation habit**  | **Exists, hand-rolled** — Kendo's `docs/plans/KD-XXXX/PLAN.md` + `DECISIONS.md`. The most re-read files in the entire corpus (one at 40× within a single session tree).                                                                                                                                                                                                                     |
| **Handoff skill + format** | New.                                                                                                                                                                                                                                                                                                                                                                                        |
| **Hygiene hook**           | New, small, optional.                                                                                                                                                                                                                                                                                                                                                                       |

The mechanism is not the problem. **The trigger is.** By 1M the quadratic bill is already paid;
firing the same machinery at 200k is the 66%.

---

## Decisions

Each records the alternative it beat, because that is the part no citation can recover.

### D1 — Attack the threshold, not the mechanism

Auto-compaction already compresses well. A `/handoff` skill that tries to _replace_ it is solving a
solved problem.

_Rejected:_ building a better summariser. Measured post-compaction size is ~20k from ~1M; there is
no headroom worth chasing there, and a hand-written summariser would be worse.

### D2 — A written artifact, in addition to compaction, not instead of it

Compaction produces an in-context summary, selected by a process we cannot audit, ~~that dies with the
session~~. A file survives, is inspectable, is mechanically verifiable, and can be corrected when
wrong.

_Amended 2026-08-24 (F3):_ the summary need **not** die with the session — `PostCompact` hands it over
as `compact_summary`, so it can be persisted for nothing. The rest of D2 stands unchanged, and it is
the load-bearing rest: unauditable selection, not impermanence, is why a written artifact wins. The
correction pays off elsewhere — it makes this document's own falsification test cheap; see
[What would falsify this design](#what-would-falsify-this-design).

_Rejected:_ relying on compaction alone, triggered earlier. Cheaper, and would capture most of the
66% — but it forfeits verifiability, and [D6](#d6) argues the selection process is exactly what we
should not trust.

### D3 — The three-way port test

The README names one axis (codebase specifics → inject via `context/{project}/`). `CLAUDE.md` names
a second (human process artifacts → detect at runtime). Generalising an existing project-specific
script needs a third distinction neither covers:

| kind                                           | treatment                                             |
| ---------------------------------------------- | ----------------------------------------------------- |
| **mechanism** — a bug someone already paid for | port verbatim, comments included                      |
| **layout** — where files happen to live        | detect first; inject only as override                 |
| **process** — how _that team_ works            | do not port; borrow the shape, re-derive the artifact |

_Why it matters:_ `baseline-fix` emitted ticket drafts because it was extracted from a context where
the user was the planner — a _process_ assumption ported as if it were mechanism. This test names
the category that failure falls into.

### D4 — `verify-citations` generalisation stops at three things

**In scope:** (1) port the mechanism verbatim, comments and `verify-citations.test.sh` included;
(2) derive `prefixes` and `search_roots` rather than hardcoding Kendo's layout; (3) keep the line
reference instead of stripping it, and check the cited line's content.

**Out of scope, each for a stated reason:**

- **No rewrite in Node.** The bash is tested, and its comments encode real bugs already paid for —
  the punctuation-before-line-reference ordering, the `sed -E` portability trap, the
  `is_path_shaped` guard. A rewrite discards the test suite and re-earns the bugs.
- **No semantic verification.** "Does line 756 _support_ the claim" needs a model, which forfeits
  deterministic and zero-token — the entire reason it beats a reviewer.
- **No additional citation types** (URLs, commands, test names). Each one that cannot fail
  deterministically dilutes the guarantee. A gate is worth exactly as much as its weakest check.

_Rejected:_ a general-purpose claim verifier. Strictly more capable and strictly less trustworthy.

**Built**, 2026-08-21: `tools/verify-citations.sh`, `tools/verify-citations.test.sh`. All three
in-scope items landed; every out-of-scope item stayed out. Two things the port turned up that this
decision had not anticipated are recorded as O6 and O7 rather than absorbed into the scope.

### D5 — The gate reports MISSING; the agent re-locates

The script's answer is binary. The moment it says _"probably moved to X"_ it has made a claim that
can itself be wrong, and the gate needs a gate.

Keeping the line reference yields three outcomes rather than two:

| result                         | meaning                    | cost to resolve    |
| ------------------------------ | -------------------------- | ------------------ |
| path resolves, content matches | claim intact               | free               |
| path missing                   | **moved** — re-locate      | one grep           |
| path resolves, content differs | **claim may now be false** | re-derive properly |

Path-only checking collapses rows 2 and 3 into "fine", and row 3 is the dangerous one: the file is
still there, so it reads as verified while the thing it was cited for has changed underneath.

This is also `CLAUDE.md`'s _degrade capability, never execution_ — a stale citation narrows what the
run can trust; it does not halt it.

### D6 — Two classes of handoff content; protect the non-citable one by construction

- **Citable** — facts about the code. High volume, low value each, cheap to re-derive even when the
  pointer rots. Citations make this half safe to carry across a reset without keeping the material:
  `AuditTest.php:756 opens with app_path('Audit'), so it cannot see an Action` is ~20 tokens and
  re-checkable in one call; the file is 5k.
- **Non-citable** — the decision and the alternative it beat; the approach already tried that does
  not work; why the obvious thing is wrong here. Nothing to point at, and no way to recover it
  except redoing the work.

**The failure mode this guards against:** summarisation preserves what reads like fact and drops
what reads like conversation — precisely backwards. Both directions are attested in the initiating
session (`reports/sources/2026-08-21-reviewer-token-economy.md`): a confidently wrong `:756` claim
survived, while the four times the trial runs corrected the shared brief were preserved only because
those runs _invented_ a findings section the skill never asked for.

Citations are therefore **not** the valuable payload. They are what makes the cheap half safe. The
format must protect the expensive half deliberately rather than trust a summariser to notice.

### D7 — The handoff lives in the target repo

`<project>/.claude/handoff/<branch>.md`. In the target repo because citations resolve against _that_
git root — the same anchoring `verify-citations.sh` already uses. Disposable, one per task.

_Rejected:_ writing it into mission_control. Would break relative citation resolution and couple a
project's working state to this repo.

### D8 — Borrow one shape from `PLAN.md`/`DECISIONS.md`, port nothing else

Take **a decision recorded with the alternative it beat** — the thing that makes a decision
non-re-derivable and therefore worth its tokens. Not the filenames, not `docs/plans/`, not the
lifecycle, not the assumption that a plan exists or that the user is the planner.

Those files are a _pre-work planning_ convention tied to a directory layout, a ticket key, and a
role split. A handoff is mid-work, machine-authored, disposable. Per [D3](#d3): process, not
mechanism.

### D9 — Derive the layout by exclusion, not by selection

_Resolves O1, which this document called its least-confident decision._

Derive, not configure — but the reason O1 was close is that it weighed the wrong pair. The hazard
O1 named ("a missed source root turns a real symbol into MISSING") is not a property of _deriving_.
It is a property of deriving a **whitelist**. Kendo selected eight known roots by name; anything
outside them was invisible, so a project growing a ninth broke the gate silently.

Deriving by **exclusion** removes the failure rather than trading against it. The default is
everything `git ls-files` reports, minus dependency and prose trees. There is no root left to miss,
and adding a language, service or package to a project cannot silently narrow the search.

That inverts which error survives, which is the whole point:

| derivation           | error left over                                                   | cost                                                        |
| -------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------- |
| whitelist (Kendo)    | a real symbol in an unlisted tree → **MISSING**                   | false positive in a fail-closed gate — the expensive one    |
| denylist (this port) | a phantom symbol vouched for by an unexcluded prose tree → **OK** | missed phantom — the cheap one, by the script's own comment |

So both knobs — search roots and path prefixes — err toward the **larger** set, deliberately and
for that one reason. `--exclude='*.md'` remains the generic prose guard, since markdown is where
prose lives whatever the directory is called; the directory denylist catches the rest.

Two consequences, both handled by _reporting_ rather than by narrowing:

- A larger prefix list can resolve one citation in two places. Kendo's `src/shared/` means
  `frontend/` under its two hardcoded prefixes and matches `extension/` as well under derivation.
  The verdict stays OK — the citation is real — but every alternative is printed, so nobody
  discovers later that a citation resolved through a tree they did not mean.
- A missing _symbol_ is the only verdict the derivation can be wrong about, so it is the only one
  that prints the roots it searched. O1's objection was that deriving fails silently; that line is
  what stops it, and it costs nothing on the runs where it does not matter.

_Rejected:_ a `context/{project}/` entry as the primary mechanism. It puts a config file between a
new project and a working gate, and a stale entry fails in the expensive direction — the same
staleness argument `CLAUDE.md` already makes about planning from a committed artifact. Kept as an
**override** (`VERIFY_CITATIONS_PREFIXES`, `VERIFY_CITATIONS_SEARCH_ROOTS`) for a layout the
derivation gets wrong, which is what [D3](#d3) means by "detect first; inject only as override".

_Evidence:_ run against Kendo's own tree, the derivation reproduces every verdict its hardcoded
list produces for its own test citations, with no configuration.

### D10 — The threshold advisory is passive, two-stage, and costs zero tokens

_Scoped 2026-09-09 by [D18](#d18):_ everything below still stands, and the statusline is now the
**only** consumer of `CTX_URGE_TOKENS`. What D18 removed is the assumption — never stated here, but
inherited by `hooks/handoff-write.sh` when it was built — that the number this advisory *displays* is
also the right number to *arm* an automatic write on. It is not: 200k is a cost judgement a human
acts on, while beating compaction is a continuity constraint relative to a window this decision
never had to know about. The two-stage passive advisory is unchanged.

Built, 2026-08-21. `statusline.sh` compares resident context against 120k / 200k and renders
yellow / bold-red `handoff?` (`reset?` until item 3 landed the skill that word names, 2026-08-24 —
see [D11](#d11)). Below 120k it shows the bare token count with no colour and no
threshold named — the threshold is only worth printing once it is close enough to act on, and
this statusline re-renders ~4× per tool call, so a permanent marker goes blind.

Zero tokens is the load-bearing property, not a nicety. Measured against the alternative: an
advisory injected into context on every prompt is replayed by every subsequent turn, so at the
report's own measured growth rate (2.07k/turn, 200k → 1M ≈ 386 turns) a ~120-token nudge costs
≈ A·N²/2 ≈ **8.9M tokens against a ~232M baseline — ~4%**. A mechanism whose purpose is to shrink
context would spend 4% of the session enlarging it. Latched to fire once, the same nudge costs
≈ A·N ≈ 46k, or 0.02% — a 386× difference. **If an advisory ever reaches the model, it must latch.**
The statusline sidesteps the question entirely by never entering context.

Three findings from probing the live statusline payload rather than assuming its shape, each of
which changed the implementation:

- **`context_window.total_input_tokens` is the resident context size** (it equals the sum of
  `current_usage`'s input components). Both the threshold and the display use it; `used_percentage`
  is not used at all, for the reasons in [D12](#d12).
- **The payload ships `exceeds_200k_tokens`** — a native boolean at exactly this design's chosen
  number. **Deliberately not consumed, not even as a cross-check.** It is a pricing-tier flag owned
  by Claude Code; it can be removed or redefined without notice, taking our threshold with it. A
  cross-check against a field we do not control is still a dependency on it. The coincidence of
  values is a coincidence, not a definition.
- **The statusline is a hot path** — measured at ~4 invocations per tool call, including mid-turn.
  It must stay pure: no logging, no notifications, no state writes. This is why the notification and
  log-only options for O3 are hook work, not statusline work, and it is also why the advisory renders
  nothing below 120k — a marker that is always on goes blind.

_Rejected:_ blocking (`PreToolUse` deny / `Stop` hook). Not for being too aggressive — the objection
is ordering. O2 is unresolved, so blocking would force resets with nothing to hand off to, which is
strictly worse than not resetting. And a block landing inside `baseline-fix` between "PR pushed" and
Phase Omega leaves the worktree undeleted — the exact state that phase exists to prevent. Back on the
table after item 3, when its objection dissolves.

**Now on the table — and the pairing was the error (F4).** Item 3 landed, so the ordering objection is
spent; what is worth recording is that lumping `Stop` in with a `PreToolUse` deny mis-read what `Stop`
is. It is not only a veto: `decision: "block"` returns control to the model with `reason` as its
instruction, which makes it the **write trigger**, not a way to stop work. Three of this paragraph's
own worries are then answered by the event's own timing rather than by design — `stop_hook_active` is
a platform-provided re-entry latch, so the latch [D11](#d11) demands comes free; and `Stop` fires
after the model has finished its turn, so there is no mid-phase landing to prevent. The
undeleted-worktree case is not a counter-example but the clearest illustration: a `PreToolUse` deny
could land between "PR pushed" and Phase Omega, and `Stop` cannot, because by then the model has
stopped. What does _not_ come free: no hook payload carries a token count (F5), so the comparison
reads the last usage record out of `transcript_path` itself. The statusline stays pure.

_Corrected 2026-08-24, same day:_ an earlier version of this paragraph claimed `background_tasks` is
what covers the undeleted-worktree case. It is not, and the mistake is worth keeping because it is
easy to repeat. That field's own description says it distinguishes _"session is done"_ from _"session
is paused waiting for background work to wake it"_ — it answers **will something wake this session on
its own**, not **has the model finished its work**. The latter is invisible in every payload by
construction: the model stopping _is_ its claim to be finished. So `background_tasks` (and
`session_crons`, which carries the same meaning for `ScheduleWakeup` / `/loop` / cron) is not a
mid-task guard; it tells the hook when a block would be pointless because a wake is already coming,
and each wake ends in another `Stop`.

**Measured 2026-08-26, and it closes build item 4's headroom question.** The ceiling this trigger has
to sit below was treated as harness-internal and untraced. It is neither. Traced in `claude.exe`
2.1.246 (`vHe`, `iL`, `cCt`, `uCt`, constants `MYn=13000`, `OYn=3000`, `kHe=0.2`), auto-compaction
fires at a **fixed offset below the window, not a percentage of it**:

```
resolved_window   = min(window_source, model_max_context_window)   # the harness states this itself
effective_window  = resolved_window - reserved_output_tokens       # iL
compact_threshold = effective_window - 13_000                      # vHe, default path
blocked           = effective_window -  3_000                      # uCt
warn              = compact_threshold - 20_000                     # uCt
```

`window_source` resolves `CLAUDE_CODE_AUTO_COMPACT_WINDOW` → the `autoCompactWindow` setting
(`.int().min(1e5).max(1e6)`) → `auto`'s per-model table. The `min` against the model window is not
inferred: `/config`'s own string says _"The actual threshold is the minimum of this setting and your
model's maximum context window."_

**Neither operand of that `min` is a constant, and one is account-scoped** — so the guard reads the
ceiling at runtime, it does not carry a table. `model_max_context_window` is static per binary (a
compiled-in model table: `context:{window:200000,supports_1m_beta:!0,...}`,
`max_output_tokens:{default:32000,...}` — the latter being what `iL` reserves) *except* for the 1M
beta, which `Pp` gates on the beta header plus `context.supports_1m_beta`; that is what the `[1m]`
suffix requests. And the `auto` window is delivered by the server per organisation —
`autoCompactWindowsCache` from the bootstrap response's `auto_compact_windows`, keyed by organization
UUID and populated only when `apiProvider === "firstParty"`. So the effective ceiling can differ
between two accounts on the same binary, and change between two sessions of one account with no
version bump. On subscription tier specifically: the client knows it (`CLAUDE_CODE_SUBSCRIPTION_TYPE`,
`CLAUDE_CODE_RATE_LIMIT_TIER`) but no path was found reading it to compute a window — the dependence is
indirect, via per-org config and beta entitlement, and any plan-to-window mapping is unestablished.

**Probed 2026-08-26 — the window is the one value a hook cannot read, so "read it at runtime" is not
the instruction.** The model-to-window map is compiled into the binary with no CLI to query it, and
`context_window_size` is absent from the transcript. What *is* reachable, verified against a live
transcript and `~/.claude.json`:

| value | source | verified |
| --- | --- | --- |
| resident size | last `usage` in `transcript_path` (`input` + `cache_creation` + `cache_read`) | 229,678 |
| **suffixed** model id | `modelUsage` keys | `claude-opus-5[1m]` |
| explicit window | env — hooks inherit the parent env (spawn is `{...parentEnv}` less a targeted `omit` list, plus `CLAUDE_PROJECT_DIR`) | unset |
| compaction on/off | `autoCompactEnabled`, `DISABLE_AUTO_COMPACT` | on |

So the rule is narrower than "read the ceiling": **detect the `[1m]` suffix in `modelUsage`** — not
`message.model`, which drops it (the same session shows `"model":"claude-opus-5"` on assistant lines
and `claude-opus-5[1m]` in `modelUsage`) — **accept an explicitly declared ceiling** over any
detection, and **decline otherwise, naming the missing signal**. The suffix is what requests the beta,
so its presence is evidence the beta was *granted*: an observation, not a table that goes stale.
Defaulting to 1M stays the unsafe direction — it is exactly what manufactures the negative-slack case
above.

_Not to build on:_ `~/.claude.json`'s `autoCompactWindowsCache`. Readable, but the bootstrap schema
types it `record(string, unknown)` — values unvalidated by the client's own parser — and it is `null`
on a first-party account with no org override, so an implementation tested only locally would never
exercise the populated path.

_A trap for any transcript parser,_ worth recording because it cost a wrong conclusion here: grepping
a transcript for a field name also matches the session **talking about** that field. 22 hits for
`context_window` turned out to be this repo's own `statusline.sh` being read into context. Match on
parsed JSON structure, never on a substring of the raw line.

So the headroom available to `T` is arithmetic, and it is **window-dependent in a way `T` is not**:

| window | compact fires | slack at `T` = 200k           |
| ------ | ------------- | ----------------------------- |
| 1M     | ~987k         | ~787k — one fat turn is noise |
| 200k   | ~187k         | **−13k**                      |

At 200k the harness's threshold sits _below_ `T`. That is not a race and not thin headroom — the
`Stop` hook can never fire, so item 4 becomes dead code and no handoff is ever written. **A trigger
denominated in absolute tokens is only safe on the window it was chosen for**, which is the one cost
[D12](#d12) did not price when it judged loss of auto-compaction visibility "near-zero" — the figure
is dispensable, the _distance_ is not. The constraint now lives beside the number it constrains, in
`tools/context-economy/context-thresholds.sh`.

_Consequence for the build:_ the guard belongs in the hook, which is the only place the real window
is known, and it must **refuse to arm and say so** rather than warn — an armed hook with negative
slack manufactures `compacted: yes` handoffs, which is worse than the status quo. Install-time and
statusline are both wrong homes: the former cannot know the runtime window, the latter is a hot path
that must stay pure.

_Rejected:_ log-only-then-decide. It would re-measure what finding #2 already measured — 90% of spend
above 100k _is_ the crossing data, retrospectively.

### D11 — The two signals are complementary; the shared constant is the coupling

`statusline.sh` (level, continuous, for a human) and the future injected advisory (instruction,
one-shot, for the model) are **not successive versions of the same thing**. B does not supersede A;
they address different recipients and both survive. That matters now rather than later: the
statusline was built to last, not built cheap-and-disposable.

They do share one thing — the decision "are we past the threshold" — and that is the drift hazard
`CLAUDE.md` already names, self-inflicted. So the numbers live in exactly one file,
`tools/context-economy/context-thresholds.sh`, in this repo rather than in claude-dotfiles, because a
number separated from the report that derives it is how a stale threshold survives. Consumers source
it and **never restate the numbers, not even as a fallback default** — a local default is the second
copy. A missing file means _no advisory_, not _guess_: [D5](#d5)'s degrade-capability-never-execution
applied to a threshold instead of a citation.

Two ordering consequences:

- The injected advisory is **blocked on O2, not undecided.** Its payload is an instruction, and an
  instruction needs a referent — "externalise and reset" means nothing until `/handoff` exists. The
  statusline had no such dependency because it emits a number.
- ~~The statusline says `reset?`, not `handoff?`. Naming a command that does not exist yet is the
  cheapest possible way to teach a reader that the advisory is wrong. Item 3 changes the word.~~
  **Done in item 3, 2026-08-24** — the word is now `handoff?`. Left standing above rather than
  deleted, because the constraint is not spent: it still binds, it has just been satisfied. What made
  the word honest is a symlink (`~/.claude/skills/handoff`), not the existence of a file in this repo,
  so it can become dishonest again without anything here changing. That dependency is recorded as a
  comment at the change site in `statusline.sh` rather than only here, on the same reasoning as the
  rest of this section: the reader who needs it is the one editing that line.

### D12 — Show tokens, and drop the percentage entirely

The statusline had shown `ctx:N%` since long before this design. It is now gone, not merely
demoted, and the reason is that it was **actively contrary to the design** rather than redundant.

`used_percentage` is denominated in `context_window_size`. On a 1M window it therefore measures
_distance to auto-compaction_ — the ~1M ceiling that [D1](#d1) and the report's finding #6 identify
as the thing not to rely on, because by then the quadratic bill is already paid. A session sitting
at the 200k reset threshold renders `20%`, which reads as "loads of room" at precisely the depth
where 90% of spend begins. The one number on screen was inviting the wrong conclusion at the wrong
moment, in the same glance the advisory is trying to correct.

Two lesser problems it also had: the field is an integer, so on a 1M window its granularity is 10k
tokens per point — coarser than the distance between the two thresholds is wide; and the same
percentage means a different token count per model (200k here, 40k on a 200k-window session) while
looking like one stable rule.

So: bare `ctx:72k` below NOTICE, and `ctx:152k/200k` once a stage fires, with the denominator
_printed from_ `CTX_URGE_TOKENS` rather than hardcoded — a coloured `152k/200k` explains itself
without the reader knowing the rule, and cannot drift from the comparison beside it. A test asserts
`%` never reappears in the segment, so reintroducing it as a harmless extra fails a test instead of
quietly re-teaching the wrong intuition. Removing it also drops one `jq` spawn from a path that runs
~4× per tool call.

_What this gives up:_ visibility of how close a session is to auto-compaction. Judged near-zero —
compaction remains as a backstop whether or not it is displayed, and anyone who needs the figure can
divide by a window size they already know. Deliberately not shown alongside, because the whole point
is that two denominators on one line is how the wrong one gets read.

_Credited:_ raised by the user mid-build, not caught in the D10 design pass. Worth recording as a
[D6](#d6) instance in miniature — the decision _not_ to show a number is exactly the kind of
non-citable content that would evaporate from a summary, leaving a later reader to "helpfully" add
the percentage back.

### D13 — The handoff's price is turns of work, not tokens

_The number that governs [O2](#open-questions), derived rather than chosen._

With the reset threshold `T` fixed and measured growth `g`, a segment starting from a handoff of size
`H` costs `~(T² − H²)/2g` and buys `(T − H)/g` turns of work. Divide: **mean cost per turn of work is
`(T + H)/2`.** A handoff therefore does not add a one-off cost — it makes every turn of the session it
seeds dearer, and it costs `H/g` turns outright.

At `T` = 200k and `g` = 2.07k/turn (finding #6's measured pre-compaction rate):

| handoff                           | turns of work per segment | cost per turn |
| --------------------------------- | ------------------------- | ------------- |
| 0                                 | 96.6                      | 100k          |
| 4k                                | 94.7                      | 102k          |
| 8k                                | 92.8                      | 104k          |
| 25k (the simulation's assumption) | 84.5                      | 113k          |

So **every ~2.07k of handoff costs one turn of work**, and the test for a paragraph is _"this, or one
more turn?"_ — which is why `tools/verify-handoff.sh` prints turns and not only tokens. Target 4k,
ceiling 8k, both **advisory and unable to fail the gate**: a size gate makes cutting the non-citable
half the cheapest way to pass, exactly inverting [D6](#d6). When over budget the line to cut is a
Pointer, because pointers re-derive from the tree and a decision does not re-derive at all.

**The larger cost is not the file.** `/handoff` runs at maximum depth by construction, so each of its
own tool calls costs ~`T` — about **two turns of work per call** at the numbers above. Ten calls
gathering citations would spend ~2M tokens, ~21% of the segment just ended. Hence the skill's hard
rule: **write from what is already in context; never read or grep to author a handoff.** That is not
only frugality — anything needing a re-read to write down is by definition re-derivable, so it belongs
in Pointers as a pointer, not in the body as content. The cost argument and [D6](#d6) agree.

_Rejected:_ the simulation's 25k. It was a placeholder, and it is ~12 turns of work per reset.

### D14 — Verified on write **and** on read, and a verdict can only ever demote the cheap half

_Resolves O4._ Both — and "both is safest" was the wrong reason. They catch different failures and are
not substitutes:

- **On write** catches _fabrication_, which is attested: a confidently wrong `:756` survived
  summarisation in the initiating session. An unverified citation is worse than none, because it reads
  as verified.
- **On read** catches _rot_, the expected case whenever anything happened in between — a rebase, a
  sibling PR merging, the hours a killed run was absent.

Paying twice costs two zero-token shell calls, so price was never the question.

The consequence worth stating loudly: **a citation verdict can only ever demote the cheap half.** The
non-citable half has no citations to rot; that is what makes it expensive. A reader seeing `3 of 12
CHANGED` must not conclude the handoff is untrustworthy — three claims are untrusted and every
decision still stands.

And on read, **do not re-derive eagerly.** A CHANGED citation whose claim is not needed yet costs
nothing. Re-deriving at resume puts the material in context for the whole session; re-deriving at the
point of use puts it in later, and cost is size × remaining lifetime.

_Extended 2026-08-24 (F2):_ the read leg can be automated — a `SessionStart` hook fires on
`source: "clear"` and may return `additionalContext`, so the handoff can be injected into the fresh
session with no command typed and no model action. **An automated read must carry the gate with it.**
Injecting the document alone deletes this decision's read-side half, and that is the half catching
_rot_ — the expected failure whenever anything happened in between, which is precisely the situation a
fresh session is in. Worse, injected material reads as more authoritative than a file the model chose
to open, so an unverified injection is the first bullet's fabrication failure with the volume turned
up. The hook runs `tools/verify-handoff.sh` — checkout argument included, per [D15](#d15) — and
injects the verdicts alongside the document, or it injects nothing.

### D15 — The handoff lives in the **main** working tree, not the one the work happened in

_Flags and resolves a collision between two settled decisions._ [D7](#d7) fixes the path
(`<project>/.claude/handoff/<branch>.md`) and its reason: citations resolve against that git root.
`CLAUDE.md`'s Phase Omega deletes the throwaway worktree an automated run works in. Taken together and
left unpinned, the natural reading — the handoff goes where the work is — makes **Phase Omega delete
the handoff**, and a handoff that dies with its worktree is not a handoff.

So `<project>` is pinned to the **main** working tree (`git worktree list` first entry), which
[D7](#d7)'s path shape already permits; only the ambiguity is removed. Three consequences:

- Citations still belong to the _branch's_ checkout, so verification takes an explicit checkout
  argument and always prints which tree it used and that tree's HEAD. Resolving against the wrong tree
  yields MISSING and CHANGED verdicts indistinguishable from rot.
- `.claude/` is **tracked** in kendo, emmie and codebook, so an untracked `handoff/` shows up in
  `git status` and can be swept into someone else's commit. It goes in `.git/info/exclude` — local,
  shared across every worktree through the common git dir, and never an edit to the project's committed
  `.gitignore` for our tooling's benefit.
- Branch names contain `/` (observed: kendo-4's `fix/stripe-http-timeout-config-type`), so the filename
  slugs them; detached HEAD falls back to the short SHA.

_Rejected:_ `<common-git-dir>/handoff/`. Never appears in `git status`, needs no exclude entry, survives
everything — but it silently overrides a settled decision's stated path, and hiding a document written
for a human inside `.git/` is worse than one exclude line.

**Superseded in part, 2026-08-27 -- the location half no longer holds.** `f015abd` ("Handoffs: key by
the target tree, declare the checkout") moved the document out of every checkout into a machine-local
store, `~/.claude/context-economy/handoffs/<repo>-<branch>-<hash8>.md`, computed by `handoff_store_path`
(`claude-dotfiles/dotfiles/lib/handoff-store.sh`) and never hand-built. What this decision missed:
pinning `<project>` to the main working tree fixes *which* tree, but a `SessionStart` hook has only
`cwd`, so it can derive exactly one candidate path and would never find a handoff belonging to a
**sibling** checkout -- the normal case when a mission_control session drives one with `git -C`, its own
cwd never moving. Discovery therefore had to become **enumeration** of a central store, not derivation.

The *rejection* above is retracted with it: `.git/` was indeed the wrong destination, but "outside every
checkout" was right for a reason not considered here -- a handoff's Dead ends and Traps are exactly the
candid material about a project's tooling that should not enter a client repo's `git log` permanently.

Surviving unchanged: the branch slug (`skills/handoff/SKILL.md:93`), the detached-HEAD SHA fallback, and
the gate's explicit checkout argument -- which this move promoted from advisable to load-bearing, per
[D16](#d16)'s `checkout:` amendment.

### D16 — The format is a machine-checked contract, not a template a skill remembers

_Answers O2._ Sections, in file order, which is also **authoring order — by irrecoverability**:

```
# Handoff — <task>
branch: / checkout: / compacted: / status:
                                        <- envelope + one-line orientation
## Do not re-derive                     <- the reason the file exists
###  Decisions | Dead ends | Traps      <- exactly D6's three non-citable kinds
## Next                                 <- 1-5 concrete steps
## Pointers                             <- fenced; `path:line | fragment`, gate input verbatim
## Unverifiable                         <- optional; cross-repo, declared unchecked (O6)
```

Four things make this a contract rather than a suggestion, all enforced by `tools/verify-handoff.sh`
(58 assertions) so that no skill has to be trusted to remember them:

- **The three subsections are required and required to be non-empty.** `None.` is a legitimate answer
  and passes; silence does not — per `CLAUDE.md`, an absent section cannot be distinguished from a run
  that never looked. This is [D6](#d6)'s "protect the non-citable half by construction" made
  structural: the only content the format _compels_ is the half a summariser drops.
- **Coverage, in two tiers.** A citation in the prose but absent from Pointers is never seen by the gate,
  and reads as verified because the rest of the document was — [D5](#d5)'s dangerous row 3, one level up.
  But _cited_ is not one thing. **Evidence** carries a numeric line reference — that is what someone
  writes when pointing at a specific fact, and it is the shape [D6](#d6)'s model is about
  (`AuditTest.php:756`); it **fails**. A **mention** is merely path-shaped; it **warns**. `## Next` and
  `## Unverifiable` are excluded from both, because neither makes a claim about the tree as it stands.

  The first version had one tier and called any backticked token containing `/` a citation. The first
  real handoff produced **eight failures, every one wrong**: `/clear`, `/compact`, `/handoff`,
  `~/.claude/lib/`, `(T + H)/2`, `/` alone, and two paths the plan was proposing to _create_. That is
  [D9](#d9)'s expensive error, self-inflicted — and it is the calibration O2 said a real handoff was
  needed for, arriving on the very first one.

- **Three exit codes, mirroring the resolver.** 0 / 1 gate failure / 2 contract violation — and a
  contract violation **suppresses the resolver entirely**, because running it on a document already
  known to be malformed reproduces O8 exactly.
- **Advisory checks can never change the exit code** — size, a mention, an unbackticked citation, a
  Pointer nothing refers to. Which side of that line each check sits on is the only real design question
  in the script. A corollary learned the hard way one fix later: _a wrong warning is worse than a missing
  one_, because it is the whole reason anyone stops reading warnings. "Should this demand a Pointers
  entry" and "does anything refer to this" are opposite questions and need opposite zones — sharing one
  zone warned that a Pointer was unreferenced while `## Next` referred to it twice. Refined once more
  by a third warning that was perfectly _accurate_ and still worthless — `$HOME/.claude/lib/x.sh` is
  indeed unchecked, and cannot be anything else, because a shell expression has no literal path to
  resolve. **The cost of a warning is not whether it is true but whether it is actionable**, which is
  the sharper form of the same rule and the one to apply to the next advisory check.

_Rejected:_ footnote keys (`[C3]`) joining a claim to its citation. The `path:line` string is already a
unique join key, so the keys bought nothing — but the join does have to be mechanical, because
otherwise a CHANGED verdict names a line and no reader can tell which conclusion just became suspect.

_Rejected:_ a summary or narrative section. That is what compaction is good at and [D1](#d1) says not to
rebuild it. The handoff carries what compaction loses; duplicating its strong half is pure cost.

_Extends [D6](#d6):_ the two classes are about _knowledge_, and a handoff also needs an **envelope**
(which branch, which checkout, was this written first-hand) and an **instruction** (`## Next`). Neither
is a third class of knowledge; both are required anyway, and `compacted:` is gated precisely because
ungated it would simply be omitted — the one answer that tells a reader nothing.

**Amended 2026-08-27 -- `checkout:` joined the gated envelope, and it is load-bearing.** Added by
`f015abd` alongside [D15](#d15)'s relocation and gated at `tools/verify-handoff.sh:240`. The block and
the assertion count above are corrected in place rather than appended to, because both merely restate a
machine-checked contract; this note records the decision.

The field exists *because* of the relocation. Once the document lives outside every checkout its own path
no longer implies which tree it describes, and the filename cannot carry an absolute path -- the `hash8`
is a hash *of* the path, not the path itself. The envelope is therefore the only authority, and two
consumers depend on it: the resolver reads `HANDOFF_CHECKOUT` out of the picked candidate's header rather
than trusting its name (`handoff-store.sh:149`), and the read leg falls back to the session's own cwd
without it (`handoff-inject.sh:133`) -- which, for a session driving a sibling checkout, aims the gate at
the wrong repository and returns a page of MISSING indistinguishable from real rot. That is [D15](#d15)'s
third consequence one level up: it is no longer enough for verification to *accept* a checkout argument,
the document has to *declare* one. Hence `_Extends [D6](#d6):_` below, which named "which checkout" as
part of the envelope from the start, is now literally true rather than aspirational.

### D17 — The `compact` read leg reuses the write-trigger's own latch; no new hook, no new marker

Built 2026-09-07 (Route 1, sized in the `T + fat_turn + authoring_turn` build item above). Extends
`hooks/handoff-inject.sh`'s `source` dispatch — `clear|compact) ;;` — and adds one thing to
`hooks/handoff-write.sh` that has nothing to do with arming: once its own per-session latch exists,
it watches for the handoff it demanded actually landing on disk and records the resident size AT
THAT MOMENT into a sidecar (`$HOME/.claude/state/handoff-trigger/$session_id.written`) beside the
latch. That is the whole write side — no `PreCompact`, no `PostCompact`, no compaction corpus
dependency, exactly as [Decisions #1 of the sizing work](#d10) required.

**Why `session_id`, not the /clear marker's (main worktree, branch) key.** `/clear` starts a
genuinely new session, so the reading session's own `session_id` cannot key anything the old one
wrote — hence that marker's key. Compaction does not: `session_id` is **preserved** across it (the
same session continues), so the read leg can look its own sidecar up directly, with no separate
`SessionEnd`-style hook needed to bridge an old session to a new one. Simpler than `/clear`'s path
for exactly the reason the two are different events, not an oversight in one or the other.

**Why the gap is read synchronously, with no async marker at all.** At the exact moment
`SessionStart(source:"compact")` fires, no new API request has run since compaction — compaction is
a client-side operation that crafts a new synthetic prefix for *future* requests, it does not itself
produce a usage record. So the last usage record in the hook's own `transcript_path` is still the
**pre-compaction peak**, read straight off disk with no intermediary. That is what "no async gap,
unlike `clear`" means concretely, and it is why `compact`'s coverage math needs no marker-writing
counterpart to `session-end-marker.sh` at all. Confirmed live, not just reasoned from other
findings: `docs/measured.md` finding #16 — a real `--autocompact` run showed `session_id` identical
across `resume` → `PreCompact` → `SessionStart(compact)` (three separate process launches), and the
transcript's last usage total unchanged across all three (140,670), with a later call confirming
real compaction had by then actually shrunk it to 27,527.

**Why only an EXACT store pick counts, unlike `clear`'s corroborated "recent" pick.** `clear`'s
cross-checkout case exists because an orchestrating session can legitimately drive a sibling
checkout it never `cd`s into, so a "recent" guess corroborated by the /clear marker's timing is
worth surfacing. Compaction happens mid-session, on the branch the session is already standing in —
if that branch has no handoff of its own, the store's newest handoff for some *other* branch is not
evidence of anything about this one. So `compact` only ever trusts `handoff_pick = exact`; a
"recent" pick is discarded outright, no corroboration story needed or wanted.

**Why the coverage check is token-distance, not `COVERAGE_WINDOW_SECONDS`.** Staleness here is
driven by how much work happened between the write and the compaction, not by how much time passed
— an hour idle loses nothing, a fat multi-tool-call turn loses a lot (`docs/measured.md` finding
#15's own tail). `gap = current_tokens - written_at_tokens`, compared against
`CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS` (10,350 — 5 turns at finding #6's measured 2,070/turn growth
rate). That "5 turns" is a **floated judgement call, not a measurement**, and is named as such in
`context-thresholds.sh` precisely so it does not get mistaken for one of the corpus-derived figures
beside it.

**One-shot, not rolling re-arm — the staleness mitigation this session's `## Decisions` chose.** The
sidecar is written once, the first time the handoff's mtime moves past the latch's; there is no
mechanism that re-arms the write trigger for a second handoff later in the same long session. A gap
past the threshold degrades to a stated warning ("likely-undocumented"), never to a second forced
write — matching [D10](#d10)'s own "fire once per session" rule for the identical reason: a
trigger that fires more than once per session risks nagging exactly the autonomous, multi-tool-call
stretches finding #15 found dominate the tail.

_Rejected, for now:_ Route 4 (a nested `claude -p` synthesizing a fresh handoff from the
pre-compaction transcript inside `PreCompact` itself). Real and race-free, but `PreCompact` can fire
with no compaction behind it (`docs/measured.md` finding #13) and blocks the harness synchronously
for as long as it runs, confirmed with no timeout at 65s but no known ceiling either — a worse cost
to pay than Route 1's, and unneeded unless Route 1 proves unacceptably stale in practice.

---

### D18 — The automatic trigger is derived from the compaction ceiling; 200k is advisory only

Decided 2026-09-09. Rewrites the arming block in `lib/context-economy/context-thresholds.sh`,
`hooks/handoff-write.sh`'s trigger, and one branch of `hooks/handoff-inject.sh`'s coverage verdict.
Supersedes the absolute-threshold half of [D10](#d10) for the **automatic** path; D10's passive
statusline advisory is untouched and is now the sole consumer of `CTX_URGE_TOKENS`.

**The trigger and the threshold were the same number, and they should never have been.** `CTX_URGE_TOKENS`
= 200k served two goals at once: *cost* (reset early, because a deep context is expensive to replay)
and *continuity* (get a handoff written before compaction destroys the context it describes). Those
have different right answers, and 200k is a bad answer to the second one on every window:

| window | ceiling | what the absolute 200k trigger did |
|---|---|---|
| 1M | ~887k | Fired at 20% of the window, then let the session run on to 887k regardless. What compaction actually met was a handoff up to ~687k stale. |
| 200k | ~187k | Never fired. The threshold sits *above* the ceiling, so the trigger was unreachable — silently, with no message. |

Neither is thin headroom or a tuning error. Both follow from expressing a compaction-relative
decision as a window-independent constant.

**200k is a judgement call, not a derived number — and it cannot currently be derived.** Worth
stating plainly because the comment in `context-thresholds.sh` cited finding #7 in a way that read
as derivation. Finding #7 samples four points (120k/200k/300k/400k), is monotonic, and says of
itself *"the size of the prize, not a forecast"* — it explicitly prices none of the authoring turn,
the re-reading a fresh session must do, or work lost to a bad handoff. Extending this document's own
budget model (`(T + H)/2`, [D13](#d13)) with the one such term the repo has measured gives
`(T+H)/2 + A·g/(T−H)`, optimal at `T = H + √(2Ag) ≈ 14k` — a reset every five turns, which is absurd
as advice. The absurdity is the useful part: it localises the single missing term as **re-derivation
cost after a reset**, which nothing in the corpus prices. So the manual threshold is *bounded* by
finding #7 and not *derived* from it, and the constant now says so.

**What replaced it.** Three expressions, all in resident tokens, all in the thresholds file:

```
trigger  =  compact_threshold - 2*fat_turn - authoring_turn      fire at or above this
gate     =  resident + fat_turn + authoring_turn  <  compact_threshold
floor    =  trigger  >=  CTX_NOTICE_TOKENS                       else the window cannot be served
```

**Why two fat turns in the trigger and one in the gate.** They are the same inequality in opposite
senses, and conflating them makes the trigger unsatisfiable — the first draft of this decision fired
at `ceiling − fat − auth`, which is *exactly* where the gate starts declining, so every firing would
have failed its own check on arrival. The gate is the real constraint: once fired, the next turn is
the authoring turn and it must finish before compaction. The trigger sits one fat turn beneath it,
which makes `[trigger, gate)` a band one fat turn wide — and since `Stop` only observes at turn
boundaries, a turn no larger than `fat_turn` cannot leap the band unseen. The second term is the
*resolution* of the check, not a second safety margin.

**`CTX_FAT_TURN_TOKENS` moves off the corpus max onto p95 (325,000 → 60,000).** Forced by the above,
and the most consequential constant change here. At the max, `ceiling − 2·fat − auth` evaluates to
174,654 — *below* the 200k advisory point it is supposed to sit far above. The max was the right
statistic while this term was only ever a veto margin (too large cost nothing, with 787k of slack
under the 1M ceiling); once the term sets the trigger's position, too large is not conservative but
self-defeating. This is the specific hazard of a shared constant: the quantity it feeds changed
underneath it. p95 rather than p90 or p99 because what the term now buys is band width — a turn
above it can leap the band — and the failure when that happens is bounded and loud: one decline
message plus a manual `/handoff`, never a handoff authored from a summary. p90 would buy 49k of
coverage at twice the leap risk; p99 costs 197k of coverage for four points.

**The floor, and an honest scope limit.** The margin (`2·fat + auth` = 185,000) is fixed while the
ceiling is not, so below a ceiling of ~305k the trigger lands under `CTX_NOTICE_TOKENS` and a
handoff would be demanded from a context with nothing in it. **Prediction cannot serve those windows
at all** — not a gap to close later, a property of needing to reserve a worst-case authoring turn
plus a wide turn inside a window barely larger than their sum. A 200k-window session therefore gets
the statusline advisory and the manual path, plus one message naming the arithmetic. That is a
deliberate narrowing of who the automation serves, and it is strictly better than the pre-D18
behaviour on the same windows, which was silence.

**A read-side incoherence this exposed, and fixed.** An automatically written handoff lands
`2·fat_turn` below the ceiling **by construction**, so its gap at compaction is ~120,000 — twelve
times `CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS` (10,350). Judged against that constant every auto-written
handoff would be flagged `likely-undocumented` for doing exactly what it was designed to do: not a
staleness finding but a category error, and one no test caught because the coherence checks only
covered `NOTICE < URGE` and the old `URGE + fat + auth < declared`. Even at the *median* turn (6,707)
the reserved gap exceeds the constant. So `handoff-write.sh` now records `expected_gap_tokens` into
the sidecar when the handoff lands, and `handoff-inject.sh` judges against **whichever bound is
larger**. Larger, not "the writer's if present": a writer that reserved less must not be able to
tighten a verdict that is the constant's judgement to make. A sidecar without the field is pre-D18
and falls back to the constant, which errs toward flagging — the safe direction for a verdict a
reader acts on. `CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS` is now explicitly the **manual** path's number,
where the gap really is a free variable worth judging.

**Rejected along the way.** `min(absolute, relative)` as a single trigger — correct in shape, and
where this decision started, but a no-op in every configuration that ships: the declared ceiling is
887k for everyone who has not overridden it, so `min(200k, 887k − margin)` is always 200k. Its only
effect appears once a user has correctly declared a *small* ceiling, i.e. after doing the
configuration the ideal was supposed to remove. Also rejected: two triggers with two latches (cost
*and* continuity, each firing once) — it preserves finding #7's saving inside the automation, but it
partly reverses [D17](#d17)'s one-shot rule and bundles a staleness fix into a windowing fix. The
staleness question ("should a stale handoff be refreshed before compaction?") is orthogonal, D17 has
a reasoned position on it already, and it deserves its own argument rather than arriving as a side
effect of this one.

**Deferred, and named so it is not mistaken for settled:** measuring re-derivation cost after a
reset is the one thing that would let the manual threshold be derived rather than bounded. Nothing
above depends on it.

---

### D19 — Step 4 branches on *why* the write happened, not on who is watching

Decided 2026-09-11. Rewrites `skills/handoff/SKILL.md`'s write-mode Step 4. Closes [O3](#o3) in
full; O3's own 2026-08-24 amendment had already closed the attended half.

**The existing text asked the wrong question.** It branched on attended vs. unattended, and inside
each branch treated every write the same way regardless of why it happened — but [D18](#d18) already
answered, for the automatic path, what an attended session should do with one: an auto-written
handoff lands `2·fat_turn` below the ceiling *by construction*, with a ~120,000-token gap at
compaction that D18 calls "doing exactly what it was designed to do." A gap that size is only
defensible if the session is expected to keep running toward the real ceiling after the write, not
stop for a human to `/clear`. So the variable that actually governs Step 4 was never attendance — it
is whether *anyone asked for a pause*, and the Stop hook, by design, never does.

**Trigger, not attendance, is the outer branch.**

- **Fired by the Stop hook.** Nobody asked for a reset, only for insurance against one — per D18,
  this path is supposed to stay as invisible as real auto-compaction. Report the write in one line
  and keep going; no `/clear` instruction, on any turn, regardless of who — if anyone — is attending.
- **Invoked directly.** A human typed `/handoff`, or an orchestrator watching this session's growth
  from outside (`monitor-agent-runs`, a driver script, anything holding this session's task id) sent
  the instruction. Either way the ask itself *is* the request for a controlled pause — bypassing the
  automatic path has no other reason — so this branch always stops. Attendance only changes what the
  stop message says, because it changes who has to act on it next: a human present is told what to
  run (`Run /clear, then /handoff --read` — unchanged from the prior text); nobody present gets a bare
  confirmation ("ready for reset") instead, since there is nothing to instruct and no self-reset tool
  to fall back on either. The actor performing the reset is external either way — O3's own resolution
  below: a human, or `monitor-agent-runs` killing and relaunching the run against the handoff it just
  wrote — and the confirmation is what tells that actor it is safe to do so.

**Closes O3 in full.** The unattended half was left open pending "the one-shot injected advisory"
landing; it has, and what was actually missing was never the advisory but this same conflation of
attendance with intent-to-pause. Once trigger is the branch, unattended stops needing a separate rule
of its own — it is the wording variant of whichever branch the trigger already put it in, not a third
case.

_Rejected: a full trigger × attendance 2×2._ Correct in shape, wrong in size — hook-triggered
attended and hook-triggered unattended behave identically (keep going), and the two manual cells
differ only in message wording, never in whether they stop. Three leaf behaviors, one real branch
plus a wording fork inside it, not four.

---

## Open questions

Genuinely unresolved. Recorded so that "was more design interrogation worthwhile" is answered by
this list rather than by recollection.

- **O1 — Derive `search_roots`, or configure it?** ~~Deriving (git-tracked directories minus
  vendor/prose trees) drops the config surface to near zero and keeps the script project-agnostic
  without requiring a `context/{project}/` entry. But it is more code than a config file and it can
  be wrong _silently_ — a missed source root turns a real symbol into MISSING, and per the script's
  own comment, _"a false positive in a fail-closed gate is worse than a missed one: it teaches the
  planner the script is wrong and can be ignored."_ Least-confident decision in this document.~~
  **Resolved by [D9](#d9)** — derive by exclusion. Left standing above rather than deleted, because
  _why_ it was close is the reusable part: the hazard belonged to whitelisting, not to deriving, and
  the question as posed could not see that.
- **O2 — The handoff template.** ~~[D6](#d6) fixes the two classes; the actual sections, ordering and
  length budget are unwritten. Needs at least one real handoff to calibrate against.~~
  **Resolved by [D16](#d16)** (sections, ordering, and the four rules that make it a contract) and
  **[D13](#d13)** (the budget). Left standing because the _needs a real handoff to calibrate against_
  clause was wrong in an instructive way: the length budget did not need calibrating, it needed
  deriving. `(T + H)/2` falls straight out of figures the report already had, and it gives a sharper
  answer than any single example would — a _unit_ (one turn of work per ~2.07k) rather than a number
  someone would later have to defend. What a real handoff is still needed for is whether the three
  required subsections are the right three; that is a claim [D6](#d6) makes and this format only
  enforces.
- **O3 — What the threshold _does_ when it fires.** ~~Passive advisory in the statusline, a prompt,
  or something that blocks? A nag that is ignored is worse than nothing, because it converts a real
  signal into noise.~~ **Answered for attended sessions by [D10](#d10)** — passive advisory, built.
  **Still open for unattended ones:** a `claude --bg` run, or anything `monitor-agent-runs` is
  watching, has no one at the statusline, and that is exactly where a session runs to 1M
  unchallenged. The remaining half is the one-shot injected advisory ([D11](#d11)), which is blocked
  on [O2](#o2) rather than undecided. O3 should not be closed until that lands.

  **Amended by build-order item 3, and the amendment changes what the advisory can say.** A model
  cannot reset its own context — there is no tool for it, `/clear` and `/compact` are user commands,
  and finding #6's own evidence agrees from the other direction: all three compactions in the corpus
  carry `trigger:"auto"` and _not one was invoked manually_, by a human either. So half of
  [D11](#d11)'s stated payload — _"externalise and reset"_ — is unactionable by its own recipient.
  The instruction an unattended run can actually obey is **"write a handoff now"**; the reset needs an
  actor that can perform one, which is a human or `monitor-agent-runs` killing and relaunching the run
  against the handoff it just wrote. Worth noting that this makes the handoff valuable with **no reset
  at all** — a file on disk survives the summariser, so it is also insurance against compaction
  dropping the non-citable half, which strengthens [D2](#d2) independently of the threshold.

  **Amended again 2026-08-24, and this closes O3 for the attended case.** The amendment above is
  right that a model cannot reset its own context, and then generalises too far — it concludes the
  automation is blocked on an actor, having never asked which of the three legs (write / reset / read)
  need one. Two of them do not. The **write** leg is a `Stop` hook returning `decision: "block"` with
  the instruction as `reason` (F4, and see [D10](#d10)); the **read** leg is a `SessionStart` hook
  firing on `source: "clear"` and returning `additionalContext` (F2, and see [D14](#d14) for the
  condition that injection must carry the gate). Only the reset itself needs an actor, so the human
  gesture shrinks to the single word `/clear` — and under a driver it disappears, because there the
  reset is a process boundary (F8: the control protocol exposes `get_context_usage` but no
  clear/compact command, so a long-lived headless session cannot be told to clear itself, and does not
  need to be — one segment is one process).

  Two things not to conclude from that. Injected context does **not** start a turn (F6), so the
  attended case cannot reach zero keystrokes by this route however much is automated. And the harness
  already ships the full write → clear → read cycle behind one keystroke for _plans_ —
  `ExitPlanMode`'s "clear conversation and start with only the plan" (F7) — which is a precedent worth
  copying the shape of, and the wrong artifact to reuse: a plan carries `## Next` well and Decisions /
  Dead ends / Traps not at all, i.e. exactly the half [D6](#d6) exists to protect.

  **Closed in full by [D19](#d19), 2026-09-11.** The unattended half was left open on the theory that
  it still needed its own rule; it needed the outer branch changed instead, from attended/unattended
  to trigger/no-trigger, at which point unattended stopped being a separate case and became a wording
  variant of whichever branch the trigger already selected.

- **O4 — When is a handoff verified?** ~~On write (the producing session proves its own citations), on
  read (the consuming session checks before trusting), or both. Both is safest and pays twice.~~
  **Resolved by [D14](#d14)** — both, because they catch different failures (fabrication vs. rot) and
  are not substitutes; "pays twice" priced two zero-token shell calls, so cost was never the real
  question. The load-bearing part is not the answer but its corollary: a citation verdict can only
  ever demote the _cheap_ half, and a reader must not read `3 of 12 CHANGED` as "this handoff is
  unreliable".
- **O5 — Hygiene hook scope.** Measured: 68.2% of Reads are unscoped, 55.8% of large shell calls
  uncapped, 16.1% of Reads are repeats. A `PreToolUse` hook is the right _form_ — it must fire on
  every call, not be remembered by a skill — but warn-only versus block is unresolved, and the same
  nag-fatigue risk as O3 applies.

- **O6 — A cross-repo citation and a fabricated one are the same verdict.** Found by running the
  gate on this document. Citations resolve against one git root ([D7](#d7)), so
  `<kendo>/.claude/skills/plan-feature/scripts/verify-citations.sh` and
  `claude-dotfiles/dotfiles/statusline/statusline.sh` — both real files in sibling checkouts —
  report MISSING, indistinguishable from a phantom. The design work this repo does is _inherently_
  cross-repo, so this is not an edge case here even though it is one in Kendo. Options: resolve a
  `<name>/` prefix against a sibling-checkout map; accept it and require cross-repo citations be
  marked so the gate can skip them (honest, and keeps the guarantee undiluted); or leave it. Not
  decided. Note that a _template_ path (`<project>/.claude/handoff/<branch>.md`, `context/{project}/`)
  is the same shape but a different problem: those are not citations at all, and keeping them out is
  is the job of whatever assembles the citation list, not of the gate.

  **Answered for the handoff by [D16](#d16), still open for the gate.** The format takes O6's second
  option — mark and skip: cross-repo pointers go in a `## Unverifiable` section that is excluded from
  both the coverage check and the resolver, and labelled unchecked. Two reasons beyond cheapness.
  First, the first option is worse than it looks: **a sibling-checkout map reproduces exactly the
  whitelist failure [D9](#d9) removed** — a project added beside the others is invisible, and the
  error left over is a MISSING on a real file, the expensive direction. Deriving by exclusion is not
  available across repositories, because no git index spans them. Second, template paths turned out
  to need the same exclusion for a different reason, so this note's own closing sentence is now
  implemented: `verify-handoff.sh` drops any candidate containing `<` or `>`.

- **O7 — `path:symbol` is a false MISSING on a real file.** `tools/context-audit.js:simulate`
  appears in `docs/measured.md` and reports MISSING: the trailing-
  reference rule matches digits, so a non-numeric anchor stays glued to the path. This is the
  v2/v3 failure class — a false positive in a fail-closed gate, the error the mechanism comments
  call worse than a missed phantom — and it is _inherited_, not introduced: Kendo's copy behaves
  identically. Deliberately left unfixed, because [D4](#d4) fixed the scope at three changes and
  this is a fourth. The fix that preserves the guarantee is not "strip it" (which would hand a real
  file a free OK with an unverified anchor) but "treat the identifier as the content fragment", which
  reuses [D5](#d5)'s machinery and can only turn a MISSING into OK or CHANGED, never the reverse.

  **Routed around rather than fixed, and the route is better than the fix.** `verify-handoff.sh`
  _refuses_ a `path:symbol` anchor at exit 2 — a contract violation, not a gate failure, because the
  citation may well be true and the document merely asked the wrong question. Refusing costs the
  format nothing: `Foo.php:24 | someMethod` verifies that line 24 still holds the symbol, where
  `Foo.php:someMethod` could at best confirm the file exists. So the weaker form has no use case to
  protect, and [D4](#d4)'s scope stays shut. Still open as an inherited defect for _other_ callers of
  the resolver, Kendo's included.

- **O8 — Misusing the gate manufactured 219 false positives, and it read as rot.** ~~Found by piping
  this document straight into `verify-citations.sh` instead of a citation list: every prose sentence
  became a candidate and 219 of 227 "failed". The output was shape-identical to catastrophic citation
  rot — the error [D9](#d9) calls the expensive one — produced not by the resolver but by a caller
  mistake the script did nothing to distinguish from the real thing.~~ **Resolved, 2026-08-21** —
  input contract guard, exit 2, 8 new assertions (58 total). Left standing rather than deleted,
  because the generalisable part is _why it was invisible_: [D4](#d4) fixed the scope at what the
  gate **checks**, and nobody asked what happens when the gate is **fed the wrong thing**. A
  fail-closed gate has a second trust surface — its input contract — and violating it is
  indistinguishable from the failure it reports. Reporting a misuse as MISSING also collapses two
  outcomes needing different work into one verdict, which is [D5](#d5)'s own bug one level up; hence
  a distinct exit 2 rather than joining the existing binary. Kendo's copy has the same gap; flowed
  back via `upstream-feedback/kendo.md`.

  _Conservative in one direction, deliberately:_ the guard refuses only at ≥5 candidate lines **and**
  a strict majority of them non-citation-shaped, because a guard that refused a real citation list
  would be the same class of error it exists to prevent. The discriminator — whitespace in the
  pre-`|` half — measures ~0% on a real list against ~95% on prose, so the majority test has room to
  spare. The `|` fragment half is excluded from the test, since it is prose by design.

- **O9 — Does `--exclude-dynamic-system-prompt-sections` change anything about the handoff's design?**
  Considered and closed without pursuing further, not left open. The flag (`docs/measured.md`
  finding #11) only relocates cwd/env/memory-*paths*/git-status between the system prompt and the
  first user message, and affects cross-context prompt-cache reuse — a different layer from what the
  handoff protects. It doesn't change what survives compaction, what `## Do not re-derive` needs to
  capture, or the wave-append mechanism `docs/measured.md` finding #10 documents for `nested_memory`/
  `skill_listing` — those are content-injection attachments, not the *paths* this flag moves. No
  design change follows from it either way.

---

## Build order

1. ~~`verify-citations` generalisation~~ — **done**, 2026-08-21. `tools/verify-citations.sh` +
   `tools/verify-citations.test.sh`, 50 assertions passing. Scope per [D4](#d4), layout per
   [D9](#d9), three outcomes per [D5](#d5). Flowed back via `upstream-feedback/kendo.md`, which also
   carries the two findings the port made against Kendo's own copy.
2. ~~Threshold advisory in `statusline.sh`~~ — **done**, 2026-08-21. Context now shown in
   tokens, not percent ([D12](#d12)); two-stage passive advisory (yellow `152k/200k` at 120k,
   bold red `+ reset?` at 200k — the word became `handoff?` in item 3). Thresholds owned by
   `tools/context-economy/context-thresholds.sh`, symlinked into `~/.claude/lib/` by
   claude-dotfiles' `install.sh`. `dotfiles/statusline/statusline.test.sh`, 15 assertions
   passing. Partially resolves O3 — see [D10](#d10) for what it does and does not settle.
3. ~~`/handoff` skill and format~~ — **done**; format and gate 2026-08-21, skill and wiring
   2026-08-24. The format and its gate: `tools/verify-handoff.sh` + `tools/verify-handoff.test.sh`,
   54 assertions passing, plus the handoff budget added to
   `tools/context-economy/context-thresholds.sh`. Sections and the four contract rules per
   [D16](#d16), budget per [D13](#d13), verification per [D14](#d14), location per [D15](#d15).
   Resolves O2 and O4; answers the handoff's half of O6 and O7; amends O3. Then
   `skills/handoff/SKILL.md` (write and `--read` modes, four steps and three tool calls each,
   markers per `CLAUDE.md`), four symlinks under `~/.claude/`, the README entries, and the
   `reset?` → `handoff?` word change in `statusline.sh` plus its two assertions ([D11](#d11);
   15 passing).

   Two things the build found that the plan had not:

   - **The gate needed three `lib/` symlinks, not one.** Bash does not resolve symlinks in
     `BASH_SOURCE`, so `$(dirname "$0")` through the link is `~/.claude/lib/` — which is where
     `verify-handoff.sh` then looks for both `verify-citations.sh` (exit 2 without it) and
     `context-economy/context-thresholds.sh` (no size line without it, though the tool says so
     rather than dropping it silently, and still checks every citation). Fixed with links rather
     than by teaching the script `readlink -f`, which is absent on BSD/older macOS and so is
     exactly the portability trap this repo's porting rule exists to avoid.
   - **`ln -s` outperforms the documented command.** PowerShell's `New-Item -ItemType
SymbolicLink` fails with `Administrator privilege required`, where git-bash's `ln -s`
     succeeds unelevated for the same target. `README.md` claimed the opposite; corrected there,
     with `MSYS=winsymlinks:nativestrict` so a failure is loud rather than a silent file copy.

4. ~~**The automated write/read cycle**~~ — **done**, 2026-08-26, per
   `reports/2026-08-24-harness-automation-surface.md`. Four hooks in `claude-dotfiles`, all
   registered in **user** settings, all with suites alongside as with items 1–3:

   - `hooks/handoff-write.sh` (`Stop`) — the write leg. Measures resident context out of
     `transcript_path` (F5), compares against `CTX_URGE_TOKENS`, and blocks once with the
     instruction to run `/handoff` (F4). 30 assertions. _Amended 2026-09-09 by [D18](#d18):_ the
     comparison is no longer against `CTX_URGE_TOKENS` but against a trigger derived from the
     compaction ceiling, with `CTX_NOTICE_TOKENS` as a floor. Assertion counts in this item are
     left as the 2026-08-26 record rather than maintained; the suites are the live count.
   - `hooks/handoff-inject.sh` (`SessionStart`, `source: "clear"`) — the read leg. Runs
     `tools/verify-handoff.sh` and injects document-with-verdicts (F2, [D14](#d14)), and surfaces
     the `/clear` marker below. 54 assertions.
   - `hooks/compaction-capture.sh` (`PostCompact`) — the corpus (F3). 30 assertions.
   - `hooks/session-end-marker.sh` (`SessionEnd`, matcher `clear`) — records the loss (F9).
     29 assertions.

   The human keystroke in the middle stays: `additionalContext` does not start a turn (F6), so this
   is zero-**typing**, not zero-touch.

   Four things the build found that the plan had not:

   - **The `[1m]` detection channel is far thinner than assumed.** `modelUsage` appears only on
     `cost-state` lines — a 2.1.246 addition, and sporadic even there (measured: 1 of 4 transcripts
     on that version, 0 of 26 on 2.1.235/2.1.228). So *declining to arm* is the common outcome of
     the headroom check, not its edge case, and a machine that wants the trigger armed should
     declare `CTX_COMPACT_THRESHOLD_TOKENS`. Recorded in full beside the instruction it qualifies,
     in `tools/context-economy/context-thresholds.sh`.
   - **The `/clear` marker had to be surfaced by the read leg, not by a hook of its own.** The only
     question worth answering — does the handoff on disk describe the session just discarded, or an
     older one? — needs the marker and the handoff in one place. Two hooks would emit two blobs and
     leave the reader to join them at the most expensive moment in a session. So the read leg reads
     both, compares the handoff's mtime against the clear, and says which.
   - **A recorded path and a path used for local reads are different values.** Both the marker and
     the corpus record `transcript_path`, and that value is followed *by the model*, which hands it
     to a file-reading tool wanting a native path. Passing it through `cygpath -u` first yields
     `/c/Users/...` — readable to bash and to nothing else — so the most valuable field in the
     marker would have named a file its only consumer could not open. The converted form is now
     kept separately, for the hooks' own reads.
   - **jq writes stdout in text mode on Windows**, so text round-tripped through `jq -r` into a
     shell variable returns with CRLF. Cosmetic in most hooks; in the corpus it rewrote the
     evidence. See the falsification section above for the measurement and the fix.

   Two things settled before writing it, and one deliberately not:

   - **Do not set `autoCompactThreshold` to the reset threshold**, tempting as F1 makes it. With
     compaction and the `Stop` trigger at the same depth the two race, and when compaction wins the
     handoff is authored from a summary — the degradation `compacted:` is gated to record
     ([D16](#d16)). Leave auto-compaction at its default so it stays the backstop [D1](#d1) wants:
     one mechanism owns the threshold.
   - **Capture `compact_summary` from `PostCompact` at the same time** (F3). It is nearly free and it
     is the experiment this document's own falsification section names.
   - **There is no last-chance trigger at `/clear`** (F9). `Stop` does not fire there — traced: the
     clear handler's first statement runs `SessionEnd` hooks with `reason: "clear"`, and the binary's
     own hook table is wrong on this point. `SessionEnd` is awaited and sees full depth, but it cannot
     inject and cannot make the model write, so a clear typed ahead of the threshold `Stop` loses the
     session outright. Mitigate in the pair rather than the single hook: `SessionEnd` records that a
     clear happened over the threshold with no fresh handoff, and the `SessionStart` hook surfaces
     that in the next session's injected context.
   - **No longer open, and it was the wrong question (F10).** Skipping when `background_tasks` or
     `session_crons` is non-empty was meant to protect in-flight work from the block. Nothing needs
     protecting: a block yields a turn, the task registry runs independently of turns, and `/clear`
     kills running **foreground** tasks while **preserving** backgrounded ones — so `background_tasks`,
     whose predicate excludes `isBackgrounded === false`, lists a clear's survivors and never its
     casualties. The block may fire whatever those fields say. What replaces the question is a
     **format** requirement, and the useful framing is that the harness **already transfers background
     work across a reset** — preserved in the registry, ids carried over, still able to wake the
     session — while transferring none of the _intent_. So the handoff supplies the intent, and it
     supplies a **disposition** rather than a bare identity: a surviving task's result arrives in the
     fresh context, which is the most expensive moment there is (cost is size × remaining lifetime), so
     the disposition has **three** states and the section encodes it: a task that **blocks** a `## Next`
     step says so on that step _and carries a fallback_ (`TaskOutput <id>`, or how to re-derive) —
     read-mode's default is to start item 1 immediately, and a bare wait is unbounded, which unattended
     is a hang; a task that **feeds** a step without blocking says to fold its result in there; a task
     that feeds nothing gets one `### Traps` line so an unprompted report reads as expected. So
     [D16](#d16)'s contract absorbs this with no new section and no gate change — a task id carries no
     `path:line`. One line of `skills/handoff/SKILL.md` read-mode Step 3 changes with it: _start the
     first unblocked item_, not item 1.

     _On the token cost, now traced:_ a completion delivers `status`, a `summary` string and an
     `output_file` **path** — never the body. The result enters context only if the receiving session
     reads it, so the unbidden tax is one line and the rest is deferrable, which is [D14](#d14)'s
     resolve-at-point-of-use rule arriving from a second direction. That also retires the earlier
     reason for killing unwanted work before a clear: the reason is wasted compute and side effects,
     not context.

   - **The latch must be on disk, not `stop_hook_active`** (F10, REASONED). That flag marks the current
     continuation as stop-hook-induced, so it only breaks the tight loop; a background task waking the
     session later starts a turn with it false, threshold still crossed and the handoff already
     written. Fire-once state is keyed by `session_id`.
   - ~~**Still open:** how much headroom `T` needs. The check's resolution is one turn — ~2.07k at
     `CTX_GROWTH_TOKENS_PER_TURN`, but unbounded at the tail, since one turn that reads widely can add
     50k+ — so `T` must sit far enough below any hard ceiling to absorb a single fat turn.~~
     **Resolved 2026-08-26 by tracing the ceiling** ([D10](#d10)): auto-compaction fires at
     `effective_window - 13_000`, a fixed offset, so the slack is computable rather than open. At the
     1M default it is ~787k and a fat turn is noise; at a 200k window it is **negative** and the hook
     can never fire. Two terms the original bullet undercounted: the **authoring turn** is itself wide
     (writing a handoff means reading files to cite them, and F4b prices block → write → re-fire at one
     extra turn), and `reserved_output_tokens` comes off the window before any of this. So the
     invariant is `T + fat_turn + authoring_turn < effective_window - 13_000`, and the hook must
     evaluate it at fire time and decline to arm when it fails.
   - **`authoring_turn` measured 2026-09-07, from the existing corpus rather than a fresh probe**
     (`docs/measured.md` finding #14): 20 clean initial handoff-authoring turns, mined from past
     sessions across this repo, `kendo`, `kendo-2` and `mission-control` — **13,698–64,618 tokens,
     median 25,025, mean 30,024** (one contaminated outlier at 53,166 excluded from that range).
   - **`fat_turn` measured 2026-09-07, same method** (`docs/measured.md` finding #15): F4b's own
     "50k+" was qualitative and, it turns out, not conservative. 724 mid-session turns mined across
     48 sessions (this repo, `kendo`, `kendo-2`, `mission-control`) give **median 6,707, p90 34,897,
     p95 59,367, p99 158,290, max 323,673** — a second, excluded population of 12 whole-session
     "zero-baseline" turns (cold start to first boundary, median 208,403, max 952,946) is a
     different thing entirely and must not be pooled with the mid-session figures above. "50k+"
     sits between p90 and p95; p99 and max run 3–6x higher, and every one of the top 10 is a long
     autonomous `Bash`/`Edit`/`Write` stretch (22–259 tool calls), not the single wide `Read`/grep
     F4b's illustration described.
   - **Recomputed against the real check, not the abstract invariant — no percentile trade-off
     turned out to be needed.** `hooks/handoff-write.sh` never evaluates the invariant against
     `effective_window` directly; it evaluates `resident + fat_turn + authoring_turn < ceiling`,
     where `ceiling` is either `CTX_COMPACT_THRESHOLD_TOKENS` if a machine declared one, or the
     hard-coded `CTX_1M_COMPACT_THRESHOLD_TOKENS = 887,000` if the `[1m]` suffix was detected, or
     the hook declines outright — there is no code path today that resolves to an intermediate
     ceiling like the ~455k a 500k window would need. That collapses the design space to two cases
     the earlier framing (this paragraph, as it read before this measurement) conflated:
     - **200k-class window: already dead, independent of `fat_turn`'s value.** `CTX_URGE_TOKENS`
       (`T` = 200,000) already exceeds the true `compact_threshold` there (~187,000, this section's
       own table above) before either turn-cost term is added. This was established at 2026-08-26,
       not by this measurement — `fat_turn`'s real distribution changes nothing about it.
     - **1M-declared/detected window: the only one that ever arms, and the corpus MAX fits with
       room to spare.** `resident ≈ T = 200,000` at the moment the hook fires. Plugging in the
       corpus **max** for both terms — not a percentile, the literal worst value seen — gives
       `need = 200,000 + 323,673 + 64,618 = 588,291`, against `ceiling = 887,000`: **~299,000
       tokens of margin remain.** Because the declared ceiling is itself a deliberately
       conservative lower bound (887,000 vs. the true ~987,000), and because that margin is this
       wide, there is no cost to skipping the percentile question entirely and sizing both
       `CTX_FAT_TURN_TOKENS` and `CTX_AUTHORING_TURN_TOKENS` at their corpus maxima (325,000 and
       65,000, rounded up) rather than gambling on p95 or p99 and hoping the tail doesn't extend
       further. **Both constants were updated in `lib/context-economy/context-thresholds.sh`
       2026-09-07** on this basis (fat: 50,000 → 325,000; authoring: 30,000 → 65,000 — the latter
       taken at finding #14's n=20 max rather than its trimmed-mean figure, since a fail-closed
       bound must cover a turn that really happened, not just a clean one; the excluded turn was
       smaller than the max regardless, so this changes nothing about which value is the ceiling).
       Tests
       (`context-thresholds.test.sh`, `handoff-write.test.sh`) pass unchanged — the coherence check
       `urge + fat + authoring < declared` still holds (590,000 < 887,000), and `handoff-write.test.sh`
       fixtures its own thresholds, so retuning the real file cannot break it.
     - **What would make the percentile question live:** a future ceiling declared for an
       intermediate window (the exact gap `CTX_1M_COMPACT_THRESHOLD_TOKENS`'s own comment already
       flagged, e.g. 500k → `compact_threshold ≈ 455,000`). There, max-sizing's 588,291 would
       exceed the budget while a p95-sized 324,367 (`59,367 + 65,000` on top of `T`) would still
       clear it with room. Nothing in the current build declares such a ceiling, so this is a note
       for if one ever gets added, not an open decision blocking anything today.
     - **So a single static `T` (200,000) remains viable, as configured, for exactly the window
       class this hook currently serves** — the earlier framing in this paragraph (before this
       recomputation) read the ~205k of required slack against the true ~787k 1M slack figure and
       called it "a large fraction... leaves nothing at a 200k-class window"; the second half was
       already true for an unrelated reason (200k dead on arrival regardless of `fat_turn`), and
       the first half undersold the margin because the real check gates on the declared 887,000
       ceiling, where even the corpus max leaves ~34% of it unspent.
   - **Also open, and not the same question:** a session parked above the threshold that is simply
     left alone produces no further `Stop` at all, yet its context survives — resuming appends to the
     same transcript (measured report, "What was measured"). That case belongs to
     `SessionStart(source: "resume")`, not to `Stop`.

5. Hygiene hook — last, and optional.

---

## What would falsify this design

- A handoff that costs more to author and re-read than the reset saves. The simulation assumes a 25k
  brief and does **not** price authoring, re-reading, or work lost to a bad handoff.
- Auto-compaction turning out to preserve the non-citable half well. [D2](#d2) and [D6](#d6) both
  assume it does not; that assumption is _reasoned, not measured_. Comparing a real compaction
  summary against a hand-written handoff for the same session would settle it, and is the cheapest
  experiment available. **Cheaper than this said (F3):** `PostCompact` is handed the summary as
  `compact_summary`, so a three-line hook accumulates the corpus automatically from ordinary work.
  There is no longer a reason for the load-bearing assumption under [D2](#d2) and [D6](#d6) to stay
  unmeasured — hence its place in build-order item 4, wired alongside the hook that needs it.

  _Wired 2026-08-26._ `claude-dotfiles/dotfiles/hooks/compaction-capture.sh`, registered on
  `PostCompact`. Records accumulate at `~/.claude/context-economy/compactions/` — outside every
  checkout, because they hold verbatim conversation content and mission_control gets pushed.
  **The corpus is not merely a pile of summaries:** each record snapshots the branch's handoff
  *body* alongside the summary, because a handoff is overwritten by the next `/handoff` run on
  that branch and a record holding only a path would decay into an unpaired summary pointing at
  a later handoff about later work, with nothing saying so. `trigger` is kept because `auto` and
  `manual` are different events and pooling them answers a different question than the one asked.
  Nothing analyses this yet — it only accrues; the comparison is still someone's to run.

  One thing the wiring taught, which the "three-line hook" estimate did not anticipate: on Windows
  `jq` writes stdout in text mode, so pulling the summary through `jq -r` into a shell variable
  returns it with CRLF endings. The first version stored `line1\nline2` as `line1\r\r\nline2\r\n`
  while every single-line field tested clean. For most hooks that is cosmetic; for this one it
  rewrites the evidence. The record is now built in a single `jq` invocation reading the original
  payload, so the summary reaches the file without a shell variable touching it.
- Threshold resets fragmenting work badly enough to cause rework that exceeds the token saving.
