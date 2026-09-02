# Context economy, measured

**Date:** 2026-08-21
**Question:** Where do tokens actually go, and which interventions would have saved real money?
**Prompted by:** `reports/sources/2026-08-21-reviewer-token-economy.md` (in mission_control,
not carried here) — a session-transcript
excerpt that reasoned about reviewer cost from completion-notification figures and explicitly
disclaimed having instrumentation ("I can't give you exact per-turn numbers — I have no
instrumentation on my own context growth"). That disclaimer turned out to be false: the
instrumentation exists on disk.

It is cited for provenance only — every claim below is reproducible from `tools/context-audit.js`
against the transcript store, independently of it.

## What was measured

**The corpus** is every Claude Code transcript on this machine: `~/.claude/projects/**/*.jsonl`,
204 files, 126 MB, spanning 2026-07-03 to 2026-08-21 across 11 project directories (`kendo`,
`kendo-2`, `kendo-3`, `emmie`, `emmie-2`, `mission_control`, `claude-dotfiles`, and worktrees).
Claude Code writes one line per transcript event; assistant events carry a complete `usage` object
(`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`).

After deduplication: **8,888 API requests across 191 contexts.** This is real prior work — the
Kendo and Emmie epics, the baseline skill trial runs — not a synthetic benchmark.

**Method.** `tools/context-audit.js` in this repo, run with no arguments. It is the reproduction
of every figure below; the numbers here are a snapshot and will drift as new sessions land.

```
node tools/context-audit.js                 # whole corpus
node tools/context-audit.js --session <id>  # one context, with composition breakdown
node tools/context-audit.js --json          # machine-readable
```

**What counts as one unit.** One transcript file = one `sessionId` = one context. A session begins
at a fresh `claude` invocation or immediately after `/clear` (observed: new session files opening
20–204s after a prior one's last event). It does **not** end when the terminal closes — resuming
appends to the same file, and the largest session here spans 2026-08-06 to 2026-08-10 across gaps
of up to 65 hours. It does **not** end at compaction either: `compact_boundary` is a row inside the
file and the session continues under the same id.

**Three measurement traps**, each of which produces a confidently wrong number, and each of which
was hit and corrected while writing the tool:

1. **One API response is written as several transcript lines** — one per content block (text,
   thinking, each `tool_use`) — and every line repeats the same `usage` object. Summing lines
   inflates by 2.1× (18,500 lines for 8,888 requests). Dedupe on `requestId`.
2. **Subagent transcripts live in a separate directory**, `<project>/<parent-session>/subagents/`.
   The `isSidechain` flag alone does not find them.
3. **`sessionId` is not a context boundary.** A subagent transcript carries its *parent's*
   `sessionId`. Grouping on it merges a parent context with all of its children into one imaginary
   session — which then reports a file read once per agent as a "repeat read", when having separate
   contexts is the entire point of a subagent. The unit of context is the **transcript file**.

**Accuracy.** Token counts come from `usage` and are exact. Composition and tool-volume figures are
character counts and are approximations, labelled as such wherever they appear. The conventional
4-chars-per-token rule is **too generous for this material**: calibrating character counts against
measured context size gives a median of **2.68 chars/token**, unsurprising for code, JSON and diffs.
Character-derived figures below therefore understate by roughly 1.5×.
Dollar figures use public list rates ($15/$75 per Mtok, cache write ×1.25, cache read ×0.1) and are
a *split of where cost sits*, not a bill.

> **Correction, same day.** The first version of this report stated that tool traffic was "0.27% of
> spend" and concluded per-call frugality was a rounding error. That compared a **stock** (7.09M
> tokens entering context once) against a **flow** (2.67B including every replay) — the wrong
> comparison, since material that enters context is then replayed with everything else. Attributing
> spend by what actually occupies the replayed context puts tool traffic at **~50%**. Finding #4 and
> the "What this overturns" table are rewritten accordingly. The top-line conclusion — that
> reset-at-threshold is the largest single lever — is unaffected.

## Findings

### 1. 98.1% of all tokens are cache reads. Context replay is the entire cost structure.

| | tokens | share |
|---|---|---|
| uncached input | 0.61M | 0.0% |
| cache creation (new material) | 44.06M | 1.7% |
| **cache read (context replay)** | **2,617.12M** | **98.1%** |
| output | 6.06M | 0.2% |
| total | 2,667.86M | |

At list rates that is ~$5,215, of which cache read is 75.3% and output 8.7%.

**Amplification is 51.6×** corpus-wide: every token of new material is re-sent about 52 times
before its session ends. The worst single context reached **111×** — 4.1 MB of unique material,
459M tokens spent.

> **Both figures are too low.** The denominator double-counted output; corrected, corpus-wide
> amplification is **58.6×**. See [correction 2026-09-02](#correction-2026-09-02--the-amplification-denominator-double-counted-output).

### 2. 90% of spend happens at context depths above 100k. 61% above 400k.

| context depth | spend | cumulative |
|---|---|---|
| 0–100k | 136M | 5% |
| 100–200k | 308M | 17% |
| 200–300k | 304M | 28% |
| 300–400k | 276M | 39% |
| 400–500k | 283M | 49% |
| 500–600k | 339M | 62% |
| 600–700k | 336M | 75% |
| 700–800k | 256M | 84% |
| 800–900k | 161M | 90% |
| 900k–1M | 261M | 100% |

This is the load-bearing table. Cost per turn *is* the context size, so total cost is quadratic in
session length. Nothing about *what* a turn does matters nearly as much as *how deep* the context
was when it did it.

### 3. Spend is extremely concentrated: 11 of 191 contexts (6%) account for 80% of all tokens.

All eleven are main-loop sessions, not subagents. Subagents are 5.4% of total spend.

### 4. Tool traffic is ~50% of spend — because it is replayed, not because it is bulky.

Everything ever read, written, grepped or run enters context exactly once, and that is a small
number: ~7.09M characters-derived tokens corpus-wide, 1,452 `Read` calls totalling ~3.0M. It is
tempting to divide that by 2.67B and declare it irrelevant. **That division is invalid** — it
compares a stock against a flow. Material that enters context is thereafter replayed alongside
everything else, so its true cost is its size times its remaining lifetime in that context.

Attributing each context's spend by what actually occupied it — preamble measured directly from
turn-1 residency, the remainder split by measured character proportions:

| occupies the replayed context | spend | share |
|---|---|---|
| tool traffic (calls + results) | 1,324M | **49.5%** |
| conversation + injected context | 1,083M | 40.5% |
| harness preamble (system prompt, tool defs, `CLAUDE.md`, skill listings) | 265M | 9.9% |

Halving tool traffic would cut roughly **25%** of total spend. A 20k `Read` at turn 50 of a
500-turn context does not cost 20k; it costs 20k × ~450 replays.

Two sub-findings:

- **`tool_use` inputs are a third of tool traffic** — 1.67M against 5.4M of results. `Write`
  averages 1,329 tokens per call, `Edit` 356. A file you write enters context in full as your own
  tool call, and again if you later read it back.
- **The harness preamble is smaller than expected but never leaves.** Median 55k for a main-loop
  context (range 0–67k), 23k for a subagent. Because it is resident from turn 1 it is replayed on
  every turn: 49% of spend in contexts that stayed under 100k, but only 6% in those that passed
  600k. It is the dominant cost of *short* sessions and a rounding error in long ones — the exact
  inverse of the usual intuition, and the reason "just start a fresh session" is not free.

### 5. Composition of a real 999k-peak context (mission_control, 2026-08-06)

Excluding transcript bookkeeping that is never sent to the model (`file-history-*`, `mode`,
`last-prompt` — a third of the file, and counting it overstates context badly):

| | ~tokens | share |
|---|---|---|
| tool call inputs | 240k | 29% |
| tool results | 228k | 27% |
| assistant text | 109k | 13% |
| user messages | 67k | 8% |
| injected: skill_listing | 48k | 6% |
| injected: edited_text_file | 35k | 4% |
| injected: diagnostics | 33k | 4% |
| system notices | 29k | 3% |
| everything else | ~50k | 6% |

The model's own tool calls are the single largest line, ahead of everything it read.

> **Corrected 2026-08-24.** The `injected:*` and `system notices` rows in this table are
> overstated — `context-audit.js` was measuring whole transcript records, metadata included. See
> *Correction, 2026-08-24* at the end of this report for the revised figures. No other table in this
> report is affected.

### 6. The reset mechanism already exists, works extremely well, and fires far too late.

Every compaction in the corpus — all three of them — carries `"trigger":"auto"`. **Not one was
invoked manually.** Their metadata:

| pre | post | dropped |
|---|---|---|
| 1,000,355 | 22,978 | 977,377 |
| 999,757 | 17,920 | 981,837 |
| 1,001,516 | 20,056 | 981,460 |

Auto-compaction fires at the ~1M window ceiling and compresses to **~20k, a 98% reduction** —
*smaller* than the 25k handoff brief assumed by the simulation in finding #7. The mechanism is not
the problem.

The problem is the trigger. By 1M the quadratic bill is already paid: per finding #2, 90% of spend
happens above 100k, so a reset that fires at the ceiling salvages almost nothing. In the largest
session, context drops 881k → 70k at request ~486; average per-request cost falls from 547k to
407k, a 26% improvement, and context then regrows at a comparable rate (2.07k/turn before,
1.38k/turn after) to 723k by the end. **One reset at the ceiling changes the intercept, not the
slope.**

This is the single most actionable finding in the report: the lever is the **threshold**, not the
mechanism. Firing the same machinery at 200k instead of 1M is finding #7's 66%.

What auto-compaction does *not* give is durability or inspectability — it produces an in-context
summary, chosen by a process we cannot audit, that vanishes with the session. That is the argument
for a written handoff artifact rather than reliance on compaction alone: a file survives the
session, can be verified mechanically, and can be corrected when wrong.

### 7. Counterfactual: a reset-*threshold* discipline would have saved 45–77%.

Simulated against the real per-turn growth rates each context exhibited, assuming a reset lands at
a 25k handoff brief and regrows at that same measured rate:

| reset at | simulated | actual | saved |
|---|---|---|---|
| 120k | 604M | 2,661M | **77%** |
| 200k | 896M | 2,661M | **66%** |
| 300k | 1,187M | 2,661M | **55%** |
| 400k | 1,465M | 2,661M | **45%** |

The model is deliberately simple and its assumptions are visible in
`tools/context-audit.js:simulate`. It does **not** price the handoff brief's authoring cost, the
re-reading a fresh session must do, or work lost to a bad handoff. Treat the percentages as the
size of the prize, not a forecast.

### 8. Hygiene findings — real, and small

- **16.1%** of `Read` calls (234/1,451) re-read a file already read in the same context. Worst:
  `skills/baseline-fix/SKILL.md`, 12× in one context.
- **68.2%** of `Read` calls pulled a whole file with no `offset`/`limit`.
- **55.8%** of large shell calls (`git log`/`diff`/`find`/`grep -r`) ran with no `head`/`tail` cap.

Each is genuinely wasteful, and per finding #4 they are not trivial — they are the addressable
portion of a ~50% line. But they are bounded by how much of a read is genuinely avoidable, and none
of them helps once the material is already resident. They reduce what enters context; only #7
reduces how long it stays.

## What this overturns

The initiating report proposed five interventions. Measurement re-ranks them, and contradicts three:

| proposal | verdict |
|---|---|
| Bound every unbounded command | **Confirmed, and larger than it looks.** 55.8% of large shell calls run uncapped. Tool traffic is ~50% of spend, so the prize is a real slice of that, multiplied by how early in the context the call happens. |
| Batch independent tool calls into one message | **Confirmed, small.** Saves one context replay per merged call. Real; a few percent. |
| Split reviewers by model tier (Haiku for mechanical checks) | **Still contradicted as a cost lever**, but for a different reason than first stated. Reading is not cheap — but a cheaper model reading the same files builds the *same* context and replays it the same number of times. Tiering changes the price of the 8.7% output slice, not the 90% that is replay. Do it for latency or accuracy, not economy. |
| "Resuming an agent is not cheaper than a fresh one" | **Confirmed, and it generalises.** This is finding #1 restated. It is the single most valuable line in the report. |
| "`/clear` beats compaction; externalize evidence first" | **Confirmed, and understated.** Findings #6 and #7: compaction moves the intercept, threshold-resetting moves the slope. |

The unifying correction: **there is no such thing as a cheap tool call, only an early one.** Cost is
size × remaining lifetime. That is why the two levers compound rather than compete — putting less
into context, and keeping context shorter-lived, multiply.

The report's closing exchange arrives at the right principle by reasoning rather than measurement:
*preserve cheap re-derivability, not evidence.* A claim carrying `file:line` is ~20 tokens and
re-checkable in one cheap call; the file it came from is 5k and must be re-read. That principle is
what makes finding #7 actionable — a reset is only safe if what mattered was written down in a form
that fails loudly when wrong.

## Design implications

Ranked by measured leverage, not by how satisfying they are to build:

1. **Session-lifecycle discipline** (45–77%). A structured handoff at a context threshold, not a
   compaction. Requires an externalization format good enough to reset onto.
2. **Falsifiable handoff artifacts** (enabler, ~0%). Worth nothing directly; without it, #1 is
   unsafe. A handoff brief that keeps conclusions and loses pointers decays exactly like the
   `CLAUDE.md` arch-test inventory that misled the initiating session twice.
3. **Subagents as context firewalls** (structural). Not because subagents are cheap — because
   reading done inside one never enters the parent's replayed context. The rule this implies is
   *delegate reading, keep judgement* — close to the opposite of "downgrade the reviewer model".
4. **Input hygiene** (up to ~25% if tool traffic were halved; realistically less). Bounded output,
   scoped reads, no repeat reads, batched calls. Mechanically enforceable via a `PreToolUse` hook,
   which is the right form — it needs to fire on every call, not be remembered by a skill. Ranked
   below #1 not because it is small but because #1 also caps the damage from every call #4 misses.

## Reproduction

```
node tools/context-audit.js --top 12
```

Figures above were produced from the corpus as of 2026-08-21 at commit `6c5b9ba`, working tree
containing untracked `tools/context-audit.js`. Re-running later will not reproduce them exactly —
the corpus grows. That is the point of shipping the tool rather than only the table.

---

## Correction, 2026-08-24 — payload-measure fix in `context-audit.js`

Appended, not merged into the findings above: the original figures stand as what the tool reported
on 2026-08-21, and this section says exactly how they move. Source:
`docs/calibration.md`, correction 1.

**The defect.** The tool measured `textLen(r)` — the whole transcript record — for `attachment` and
`system` lines, so every one carried ~459 characters of `parentUuid`/`uuid`/`timestamp`/`cwd`/
`sessionId`/`version`/`gitBranch` that was never sent to the model. Worse for `system`: **84% of
those records have no `content` field at all**, only `durationMs`/`messageCount`/`subtype`
bookkeeping, so the old measure scored ~474 characters for a 2-character payload. Corpus-wide this
was **3.55M phantom characters, 7.4% of the old total**. Now fixed to measure `r.attachment` /
`r.content`.

**What does not change.** Every token figure in this report. Findings #1, #2, #3, #6, #7 and #8 read
from `usage` or from `Read`/shell call counts, none of which the fix touches — verified by running
the pre-fix and post-fix tools over an identical window and diffing: the token tables are
byte-identical. Finding #4's *shares* are also unaffected in the direction that matters, because a
proportional split is invariant to the level of the ratio (see the calibration report for the
distinction that does bite: the ratio *varying between* categories).

**What changes: finding #5's composition table.** Absolute figures for the four content rows are
unchanged; their shares rise because the denominator shrank by ~65k (~8%).

| row | as published | corrected |
|---|---|---|
| tool call inputs | 240k / 29% | 240k / **31%** |
| tool results | 228k / 27% | 228k / **29%** |
| assistant text | 109k / 13% | 109k / **14%** |
| user messages | 67k / 8% | 67k / **9%** |
| injected: skill_listing | 48k / 6% | **38k** / 5% |
| injected: edited_text_file | 35k / 4% | **33k** / 4% |
| injected: diagnostics | 33k / 4% | **31k** / 4% |
| system notices | 29k / 3% | **2k / 0.3%** — effectively not context at all |
| injected: task_reminder | 17k / 2% | **2k / 0.2%** |
| injected: queued_command | 12k / 1% | **5k / 0.7%** |

The `system notices` row should be read as deleted rather than shrunk. Its remaining 2k is the
minority of records that do carry `content`.

**Reproducing the old run.** `--until <date>` was added at the same time, and the date window now
applies to **every** section. Before this, `--since` filtered only the usage table, so a windowed
run reported a windowed token table beside a whole-corpus composition table — the two halves
silently described different corpora. Exact reconstruction of the 2026-08-21 request set is not
possible from a date alone (that run happened mid-day, and sessions landed after it), so the
closest clean boundary is everything strictly before that day:

```
node tools/context-audit.js --until 2026-08-21          # 8,773 requests / 185 contexts
```

against the 8,888 requests / 191 contexts this report measured.

**A deeper limitation this correction does not fix**, documented here because it bounds how far any
composition table in this report can be trusted: `thinking.display` defaults to `"omitted"` on
Opus 5, so **all 5,660 thinking blocks in the corpus carry zero characters** while still being
billed and still sitting in context. Every character-derived figure here therefore under-counts the
assistant side by roughly half of its output. `CHARS_PER_TOKEN = 4` was deliberately left in place
so these figures stay comparable with the original run; `tools/context-calibrate.js` is the tool
that measures both properly.

---

## Addendum, 2026-08-31 — what a compaction costs, in two numbers

Appended rather than merged: finding #6 already reports the three boundaries' `pre`/`post`/`dropped`
and its conclusion is unchanged. What is new here is the **cache side** of the same three events,
which #6 did not look at, and one property that follows from it.

**Report the cost of a compaction as two numbers, never one.** They answer different questions and a
blended figure answers neither — one is a recurring saving and the other a one-off charge, so their
sum has no referent:

1. **Context dropped** — ~980k tokens of resident material, per #6. This is a *recurring saving*:
   every subsequent request stops replaying it.
2. **Cache-write price paid once** — 36–45k tokens written fresh by the first post-compaction
   request, billed at the write multiplier (1.25× at the 5-minute TTL, 2× at the hour).

### The three boundaries, cache side

Same three events as #6's table, same order; `pre`/`post` repeated only as the join key. `read` is
`cache_read_input_tokens`, `create` is `cache_creation_input_tokens`, for the last request before
the boundary and the first one after it.

```
kendo-2/7359db87   preTokens=1,000,355  postTokens=22,978  durationMs=172,956
     BEFORE  read=997,853  create=1,067   input=2
     AFTER   read= 31,059  create=45,458  input=2
kendo-2/7efc5ac2   preTokens=  999,757  postTokens=17,920  durationMs= 96,221
     BEFORE  read=998,251  create=  411   input=1
     AFTER   read= 29,600  create=36,473  input=2
mission-control/29e903e9  preTokens=1,001,516  postTokens=20,056  durationMs= 87,028
     BEFORE  read=999,050  create=   46   input=2
     AFTER   read= 30,092  create=39,488  input=2
```

Two things to read off this directly. **`read` ≈ `preTokens` before every boundary** (997.9k against
1,000.4k) — the pre-compaction steady state is a near-total cache hit, which is finding #1 seen from
the cache's side rather than the ledger's. And **`create` before a boundary is 46–1,067 tokens**: in
normal operation a turn writes almost nothing, so the 36–45k written after a compaction is not
routine growth. It is the boundary's own bill.

### An early-prefix entry survives the compaction

The post-compaction `read` is **~30k in all three cases**, against a `postTokens` of 18–23k. The
conversation tail was destroyed, yet ~30k was still served from cache at 0.1×.

`cache_read_input_tokens = N` means literally *the first N tokens of the rendered prompt* — reads
are necessarily prefix-shaped. That is what licenses identifying this ~30k as the tools-plus-system
preamble rather than "30k of material from somewhere", and it is the assumption to check first if a
later analysis makes this number mean something else.

Priced with this report's rates (write 1.25×, read 0.1×), surviving is worth ~35k effective tokens
per boundary at the 5-minute TTL and ~57k at the hour — the difference between reading that prefix
and re-writing it.

**Consequence: compaction repays its write inside the first request.** Pre-compaction steady state
is 997.9k read at 0.1× ≈ 99.8k effective tokens per request. The first post-compaction request costs
45,458 at 1.25× plus 31,059 at 0.1× ≈ 59.9k effective — already cheaper, and still cheaper (≈94k) if
the write is billed at 2×. This is a derivation from the numbers above, not a fourth measurement.

### Caveat: this demonstrates validity, not warmth

`durationMs` on the three boundaries is 87–173 s, so the gap between the last pre-compaction request
and the first post-compaction one never stressed any TTL. Every competing hypothesis about cache
lifetime predicts a hit at that gap. What is shown is that the surviving prefix stayed **valid**
across a mid-conversation invalidation — not that it would stay **warm** across an idle. Nothing
here measures TTL behaviour, and the ceiling on what this corpus can say about breakpoints is
recorded in `docs/calibration.md`.

### Two notes, one inferred and one confirming

- **`preCompactDiscoveredTools` looks load-bearing for this, and that is inferred, not measured.**
  Tools render *before* system in the prefix, so a changed tool set invalidates from position 0,
  system prompt included. The metadata field exists so the deferred-tool set is re-declared
  identically across the boundary — which would be the reason the read is ~30k and not 0. The
  corollary this suggested has since been tested and **refuted** — see finding #9 below, which also
  says what that does and does not do to this inference.
- **All three fired at ~1.0M `preTokens`**, confirming these sessions run the `[1m]` beta and that
  the ceiling is not ~150k or ~200k. This confirms the `[1m]`-suffix detection path at
  `hooks/handoff-urge.sh:144`; it is not a new constraint.

### Reproduction

Not covered by `tools/context-audit.js`. Filter the transcript store for records with
`subtype == "compact_boundary"`, then take the nearest `message.usage` before and after by index —
and parse the JSON structure rather than grepping for field names, per the trap already recorded at
`hooks/handoff-urge.sh:105`.

---

## Finding #9, 2026-08-31 — loading a deferred tool mid-session does *not* rewrite the cache prefix

Numbered as a finding rather than appended to the addendum above because it settles a question the
addendum could only pose, and the answer is the opposite of what was predicted.

**The hypothesis, from the addendum's own trap.** Claude Code defers most tool schemas: they are
named but undefined until `ToolSearch` loads one. Tools render *before* the system prompt, so a tool
set that changes mid-session should invalidate the cache from position 0 — system prompt included —
making every mid-session tool load cost a full prefix rewrite.

**It is answerable because it is a question about the read's *size*, not its structure.** Reads are
prefix-shaped, so a prefix invalidation shows up as `cache_read_input_tokens` collapsing. This is
exactly the distinction drawn in `docs/calibration.md`'s measurement-ceiling section: the breakpoint
question needs structure the transcript never records, this one does not.

**The corpus contains its own control group.** A `ToolSearch` whose `select:` names a tool that does
not exist returns `"No matching deferred tools found"` and zero `tool_reference` entries — the call
happens, the tool set does not change. So there are matched pairs at the same context depth,
differing only in whether the tool set grew. Classes: **NEW** (≥1 returned tool not loaded earlier
in that context), **REPEAT** (all already loaded), **MISS** (nothing returned), and **CONTROL**
(adjacent request pairs with no `ToolSearch` at all).

Survival below is the next request's `cache_read` over the prompt total of the request that made the
call. Pairs are excluded if they span a `compact_boundary`, if the first request read nothing
(cold start), or if the gap exceeds 240 s — that last one so TTL expiry cannot pose as invalidation.

| class | pairs | median survival | read = 0 | median write on the next request |
|---|---|---|---|---|
| NEW | 132 | 100.0% | 2 (1.5%) | 2,128 |
| REPEAT | 3 | 100.0% | 0 | 967 |
| MISS | 11 | 100.0% | 0 | 229 |
| CONTROL | 6,597 | 100.0% | 6 (0.1%) | 1,040 |

**Verdict: refuted.** The prefix survives a new deferred-tool load. Outside one workflow discussed
below, 101 of 104 NEW pairs survived at *exactly* 100%.

**The two collapses are not caused by the tool load, and the corpus proves it.** Both are subagent
contexts inside a single ~100-way parallel workflow (`wf_baccf070-3e3`). Within that workflow, 29
sibling agents made the *identical* load — `WebFetch` — at near-identical prompt sizes (~23.2k) and
gaps (~4 s). **27 kept their prefix and 2 read zero.** A deterministic invalidation would have hit
all 29. Cache eviction under heavy parallel load is the obvious candidate and the transcript cannot
confirm it, so the honest statement is that the mechanism for those two is undetermined — not that
the tool load did it.

**Read the 74.4% cluster as breakpoint granularity, not partial invalidation.** Those same 27 agents
all report `cache_read` of exactly 17,281 against a ~23.2k prompt. A constant read across 27
independent contexts is a breakpoint, not decay: the prefix up to the last breakpoint was reused and
the ~6k of tail below it was rewritten, which is what an ordinary turn does. This is why survival
alone is a poor test and `read = 0` is the column that carries the verdict — a partial read is
routine, a zero read is different in kind.

**The actionable number is the marginal write: ~1.1k tokens.** The request following a new-tool load
writes a median 2,128 tokens against a control turn's 1,040. So the cost of pulling in a deferred
tool mid-session is on the order of a thousand tokens of cache write — not the ~30k prefix rewrite
the hypothesis predicted, and small enough that avoiding `ToolSearch` for economy is not a lever.
Consistent with the result, and **inferred rather than measured**: the schema arrives as ordinary
conversation content (the result record is a `{type: "tool_reference", tool_name}` entry in the
message stream) rather than being re-rendered into the tools block ahead of the system prompt.

**What this does to the `preCompactDiscoveredTools` inference above: weakens its premise, does not
refute the inference.** The premise was "a changed tool set invalidates from position 0". What is
now measured is narrower — *`ToolSearch` does not change the rendered tools block at all*, so it
never tests what a genuinely changed tools block would do. Whether that field is what keeps the
~30k prefix valid across a compaction is still untested, and still inferred.

### Reproduction

`tools/toolsearch-cache-probe.js` is **not shipped in this bundle** — it answers this one question
and a consumer of the plugin has no use for it. It lives in mission_control at
`tools/toolsearch-cache-probe.js`:

```
node tools/toolsearch-cache-probe.js            # summary table and verdict
node tools/toolsearch-cache-probe.js --verbose  # every pair, so an outlier can be chased
```

Figures above are from a 286-transcript corpus as of 2026-08-31, of which 100 carried the string
`ToolSearch` and were parsed structurally — the string match is a speed pre-filter only, per the
trap at `hooks/handoff-urge.sh:105`.

---

## Correction, 2026-09-02 — the amplification denominator double-counted output

Appended on the same terms as the 2026-08-24 correction: the original figures stand as what the
tool reported on 2026-08-21, and this section says exactly how they move. Unlike that one, this
correction moves a **headline number**, and it moves it in the direction that strengthens the
report.

**The defect.** `tools/context-audit.js` computed `newMaterial = inp + cc + out`, corpus-wide and
per context. The reasoning was that output enters context and is not cache creation, so it must be
a third source of new material. It is not — it is the *same* material counted twice. An assistant
turn is re-sent as ordinary **input** on the very next request, where it is billed inside
`cache_creation_input_tokens`. So output already sits in `cc`, and adding it again inflates the
denominator and understates how many times material is actually replayed.

**Why this is a measurement and not an argument.** The alternative was genuinely plausible: the
server computed the KV for those tokens while generating them, so it *could* retain them and serve
the next prefix as a pure read. Token conservation decides it exactly, with no `CHARS_PER_TOKEN`
anywhere. The tokens sent on a request are `cr + cc + inp`, so between consecutive requests in one
context `Δ(cr + cc + inp) = out(t) + newInput(t+1)`. Then `cc(t+1) ≈ Δ` means the whole increment
was written, output included; `cc(t+1) ≈ Δ − out(t)` means the output rode in free. Measured by
`tools/context-billing.js` (landed 2026-09-02, this correction's instrument): across **1,716** warm
consecutive pairs with `out(t) ≥ 300`, `cc(t+1)` matches the whole `Δ` in **97.0%** of cases — 2.3%
match `Δ − out(t)`, 0.6% neither. For pairs under a minute apart, `cc/Δ = 1.01`.

**The 2.3% minority is real, and getting it wrong is instructive.** Both this correction's first
write-up and `docs/design.md` explained those pairs as increment that landed in uncached input
because the cache breakpoint had not advanced. The decomposition refutes it: `inp` averages 2
tokens in those pairs while `cr` grows by more than the whole previous prefix, by very nearly
exactly `out(t)` — 51,896 of 53,693 shortfall tokens served as reads, across 43 of 45 pairs. The
server does sometimes retain the KV it computed while generating and extend the entry at no write
charge; rarely, and for reasons this corpus cannot reach.

The instructive part is that the wrong explanation was already ruled out in writing. It is exactly
the class of claim `docs/calibration.md`'s measurement-ceiling section forbids — breakpoint
placement is not in the transcript, so *no* transcript-derived finding can attribute anything to
it. A rule stated in one document did not stop the same repository asserting its negation in
another, five days later, in a section whose whole subject was being exact. The tool now prints the
`inp`-versus-`cr` decomposition on every run, which is the form of the fix that survives being
forgotten: the reader is handed the discriminating numbers instead of a sentence to trust.

**What changes: finding #1's amplification, 51.6× → 58.6×.** "Re-sent about 52 times" becomes
about **59**. This needs no re-run — it is arithmetic on finding #1's own published totals:

```
old:  2617.12 / (0.61 + 44.06 + 6.06)  =  51.6x
new:  2617.12 / (0.61 + 44.06)         =  58.6x
```

**What does not change.** Every token figure in every table. The four rows of finding #1's totals,
the depth chart (#2), concentration (#3), the spend attribution and shares of #4, the compaction
figures (#6), the counterfactual (#7) and the hygiene counts (#8) all read from `usage` or from
`cr + cc` depths, none of which the denominator touches — `simulate()` never sees `newMaterial`.
The estimated spend is also unaffected: cost is computed per token class directly.

**What cannot be recovered.** The per-context figure — the worst context's **111×** — understates
for the same reason, but by how much is no longer measurable: the 2026-08-21 corpus is largely gone
from disk. Re-running the published window today yields 1,630 requests where the report had 8,888,
so per-context denominators cannot be recomputed. Read 111× as a floor. This is itself the
argument for [D6](design.md#d6): the measurement was reproducible right up until the transcripts
rotated, and then it was not.

**The fix.** `newMaterial = inp + cc` and `s.newTok = s.cc + s.inp`, documented as burn #5 in the
tool's header so it is not helpfully re-added. The tool now also prints its own denominator under
the amplification line. One knock-on inside the tool, not quoted in this report: finding #4's
"all tool traffic = N% of new material" line shares the denominator, so that percentage rises
(~14% → ~15.9% on the published totals).

```
node tools/context-billing.js              # the phase test, the TTL table, the lifetime table
node tools/context-billing.js --json       # machine-readable
```

Two further things the instrument found, which are properties of the cost model rather than
corrections to this report:

- **A cache write is once per *entry*, not once per token.** Bucketed by the gap between
  consecutive requests, `cc/Δ` is 1.01 under a minute, **1.87 at 5–60 minutes**, and 152.9 for the
  single pair over an hour: above the 5-minute TTL the prefix is written again at 1.25×. Idle time
  is billable, and nothing in this report or its counterfactual prices it.
- **`R` is a property of position, not of the token.** Amplification is the token-weighted mean of
  `R`, but `R` for any individual token is the number of requests that follow the one it arrived
  on. Lifetime cost is `1.25 + 0.1R` for an input token and `5 + 1.25 + 0.1R` for an output token,
  so the output premium falls from 1.7× at `R` = 58.6 to 1.1× at `R` = 485. Deep in a context,
  position dominates provenance. Finding #4 already reasons this way ("its true cost is its size
  times its remaining lifetime in that context"); this is that sentence with the arithmetic
  attached, and it is written up in `docs/design.md`.
