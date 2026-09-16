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
3. **`sessionId` is not a context boundary.** A subagent transcript carries its _parent's_
   `sessionId`. Grouping on it merges a parent context with all of its children into one imaginary
   session — which then reports a file read once per agent as a "repeat read", when having separate
   contexts is the entire point of a subagent. The unit of context is the **transcript file**.

**Accuracy.** Token counts come from `usage` and are exact. Composition and tool-volume figures are
character counts and are approximations, labelled as such wherever they appear. The conventional
4-chars-per-token rule is **too generous for this material**: calibrating character counts against
measured context size gives a median of **2.68 chars/token**, unsurprising for code, JSON and diffs.
Character-derived figures below therefore understate by roughly 1.5×.
Dollar figures use public list rates ($15/$75 per Mtok, cache write ×1.25, cache read ×0.1) and are
a _split of where cost sits_, not a bill.

> **Correction, same day.** The first version of this report stated that tool traffic was "0.27% of
> spend" and concluded per-call frugality was a rounding error. That compared a **stock** (7.09M
> tokens entering context once) against a **flow** (2.67B including every replay) — the wrong
> comparison, since material that enters context is then replayed with everything else. Attributing
> spend by what actually occupies the replayed context puts tool traffic at **~50%**. Finding #4 and
> the "What this overturns" table are rewritten accordingly. The top-line conclusion — that
> reset-at-threshold is the largest single lever — is unaffected.

## Findings

### 1. 98.1% of all tokens are cache reads. Context replay is the entire cost structure.

|                                 | tokens        | share     |
| ------------------------------- | ------------- | --------- |
| uncached input                  | 0.61M         | 0.0%      |
| cache creation (new material)   | 44.06M        | 1.7%      |
| **cache read (context replay)** | **2,617.12M** | **98.1%** |
| output                          | 6.06M         | 0.2%      |
| total                           | 2,667.86M     |           |

At list rates that is ~$5,215, of which cache read is 75.3% and output 8.7%.

**Amplification is 51.6×** corpus-wide: every token of new material is re-sent about 52 times
before its session ends. The worst single context reached **111×** — 4.1 MB of unique material,
459M tokens spent.

> **Both figures are too low.** The denominator double-counted output; corrected, corpus-wide
> amplification is **58.6×**. See [correction 2026-09-02](#correction-2026-09-02--the-amplification-denominator-double-counted-output).

### 2. 90% of spend happens at context depths above 100k. 61% above 400k.

| context depth | spend | cumulative |
| ------------- | ----- | ---------- |
| 0–100k        | 136M  | 5%         |
| 100–200k      | 308M  | 17%        |
| 200–300k      | 304M  | 28%        |
| 300–400k      | 276M  | 39%        |
| 400–500k      | 283M  | 49%        |
| 500–600k      | 339M  | 62%        |
| 600–700k      | 336M  | 75%        |
| 700–800k      | 256M  | 84%        |
| 800–900k      | 161M  | 90%        |
| 900k–1M       | 261M  | 100%       |

This is the load-bearing table. Cost per turn _is_ the context size, so total cost is quadratic in
session length. Nothing about _what_ a turn does matters nearly as much as _how deep_ the context
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

| occupies the replayed context                                            | spend  | share     |
| ------------------------------------------------------------------------ | ------ | --------- |
| tool traffic (calls + results)                                           | 1,324M | **49.5%** |
| conversation + injected context                                          | 1,083M | 40.5%     |
| harness preamble (system prompt, tool defs, `CLAUDE.md`, skill listings) | 265M   | 9.9%      |

Halving tool traffic would cut roughly **25%** of total spend. A 20k `Read` at turn 50 of a
500-turn context does not cost 20k; it costs 20k × ~450 replays.

Two sub-findings:

- **`tool_use` inputs are a third of tool traffic** — 1.67M against 5.4M of results. `Write`
  averages 1,329 tokens per call, `Edit` 356. A file you write enters context in full as your own
  tool call, and again if you later read it back.
- **The harness preamble is smaller than expected but never leaves.** Median 55k for a main-loop
  context (range 0–67k), 23k for a subagent. Because it is resident from turn 1 it is replayed on
  every turn: 49% of spend in contexts that stayed under 100k, but only 6% in those that passed
  600k. It is the dominant cost of _short_ sessions and a rounding error in long ones — the exact
  inverse of the usual intuition, and the reason "just start a fresh session" is not free.

### 5. Composition of a real 999k-peak context (mission_control, 2026-08-06)

Excluding transcript bookkeeping that is never sent to the model (`file-history-*`, `mode`,
`last-prompt` — a third of the file, and counting it overstates context badly):

|                            | ~tokens | share |
| -------------------------- | ------- | ----- |
| tool call inputs           | 240k    | 29%   |
| tool results               | 228k    | 27%   |
| assistant text             | 109k    | 13%   |
| user messages              | 67k     | 8%    |
| injected: skill_listing    | 48k     | 6%    |
| injected: edited_text_file | 35k     | 4%    |
| injected: diagnostics      | 33k     | 4%    |
| system notices             | 29k     | 3%    |
| everything else            | ~50k    | 6%    |

The model's own tool calls are the single largest line, ahead of everything it read.

> **Corrected 2026-08-24.** The `injected:*` and `system notices` rows in this table are
> overstated — `context-audit.js` was measuring whole transcript records, metadata included. See
> _Correction, 2026-08-24_ at the end of this report for the revised figures. No other table in this
> report is affected.

### 6. The reset mechanism already exists, works extremely well, and fires far too late.

Every compaction in the corpus — all three of them — carries `"trigger":"auto"`. **Not one was
invoked manually.** Their metadata:

| pre       | post   | dropped |
| --------- | ------ | ------- |
| 1,000,355 | 22,978 | 977,377 |
| 999,757   | 17,920 | 981,837 |
| 1,001,516 | 20,056 | 981,460 |

Auto-compaction fires at the ~1M window ceiling and compresses to **~20k, a 98% reduction** —
_smaller_ than the 25k handoff brief assumed by the simulation in finding #7. The mechanism is not
the problem.

The problem is the trigger. By 1M the quadratic bill is already paid: per finding #2, 90% of spend
happens above 100k, so a reset that fires at the ceiling salvages almost nothing. In the largest
session, context drops 881k → 70k at request ~486; average per-request cost falls from 547k to
407k, a 26% improvement, and context then regrows at a comparable rate (2.07k/turn before,
1.38k/turn after) to 723k by the end. **One reset at the ceiling changes the intercept, not the
slope.**

This is the single most actionable finding in the report: the lever is the **threshold**, not the
mechanism. Firing the same machinery at 200k instead of 1M is finding #7's 66%.

What auto-compaction does _not_ give is durability or inspectability — it produces an in-context
summary, chosen by a process we cannot audit, that vanishes with the session. That is the argument
for a written handoff artifact rather than reliance on compaction alone: a file survives the
session, can be verified mechanically, and can be corrected when wrong.

### 7. Counterfactual: a reset-_threshold_ discipline would have saved 45–77%.

Simulated against the real per-turn growth rates each context exhibited, assuming a reset lands at
a 25k handoff brief and regrows at that same measured rate:

| reset at | simulated | actual | saved   |
| -------- | --------- | ------ | ------- |
| 120k     | 604M      | 2,661M | **77%** |
| 200k     | 896M      | 2,661M | **66%** |
| 300k     | 1,187M    | 2,661M | **55%** |
| 400k     | 1,465M    | 2,661M | **45%** |

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

| proposal                                                    | verdict                                                                                                                                                                                                                                                                                                                                                |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Bound every unbounded command                               | **Confirmed, and larger than it looks.** 55.8% of large shell calls run uncapped. Tool traffic is ~50% of spend, so the prize is a real slice of that, multiplied by how early in the context the call happens.                                                                                                                                        |
| Batch independent tool calls into one message               | **Confirmed, small.** Saves one context replay per merged call. Real; a few percent.                                                                                                                                                                                                                                                                   |
| Split reviewers by model tier (Haiku for mechanical checks) | **Still contradicted as a cost lever**, but for a different reason than first stated. Reading is not cheap — but a cheaper model reading the same files builds the _same_ context and replays it the same number of times. Tiering changes the price of the 8.7% output slice, not the 90% that is replay. Do it for latency or accuracy, not economy. |
| "Resuming an agent is not cheaper than a fresh one"         | **Confirmed, and it generalises.** This is finding #1 restated. It is the single most valuable line in the report.                                                                                                                                                                                                                                     |
| "`/clear` beats compaction; externalize evidence first"     | **Confirmed, and understated.** Findings #6 and #7: compaction moves the intercept, threshold-resetting moves the slope.                                                                                                                                                                                                                               |

The unifying correction: **there is no such thing as a cheap tool call, only an early one.** Cost is
size × remaining lifetime. That is why the two levers compound rather than compete — putting less
into context, and keeping context shorter-lived, multiply.

The report's closing exchange arrives at the right principle by reasoning rather than measurement:
_preserve cheap re-derivability, not evidence._ A claim carrying `file:line` is ~20 tokens and
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
   _delegate reading, keep judgement_ — close to the opposite of "downgrade the reviewer model".
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
byte-identical. Finding #4's _shares_ are also unaffected in the direction that matters, because a
proportional split is invariant to the level of the ratio (see the calibration report for the
distinction that does bite: the ratio _varying between_ categories).

**What changes: finding #5's composition table.** Absolute figures for the four content rows are
unchanged; their shares rise because the denominator shrank by ~65k (~8%).

| row                        | as published | corrected                                      |
| -------------------------- | ------------ | ---------------------------------------------- |
| tool call inputs           | 240k / 29%   | 240k / **31%**                                 |
| tool results               | 228k / 27%   | 228k / **29%**                                 |
| assistant text             | 109k / 13%   | 109k / **14%**                                 |
| user messages              | 67k / 8%     | 67k / **9%**                                   |
| injected: skill_listing    | 48k / 6%     | **38k** / 5%                                   |
| injected: edited_text_file | 35k / 4%     | **33k** / 4%                                   |
| injected: diagnostics      | 33k / 4%     | **31k** / 4%                                   |
| system notices             | 29k / 3%     | **2k / 0.3%** — effectively not context at all |
| injected: task_reminder    | 17k / 2%     | **2k / 0.2%**                                  |
| injected: queued_command   | 12k / 1%     | **5k / 0.7%**                                  |

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

1. **Context dropped** — ~980k tokens of resident material, per #6. This is a _recurring saving_:
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

`cache_read_input_tokens = N` means literally _the first N tokens of the rendered prompt_ — reads
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
  Tools render _before_ system in the prefix, so a changed tool set invalidates from position 0,
  system prompt included. The metadata field exists so the deferred-tool set is re-declared
  identically across the boundary — which would be the reason the read is ~30k and not 0. The
  corollary this suggested has since been tested and **refuted** — see finding #9 below, which also
  says what that does and does not do to this inference.
- **All three fired at ~1.0M `preTokens`**, confirming these sessions run the `[1m]` beta and that
  the ceiling is not ~150k or ~200k. This confirms the `[1m]`-suffix detection path at
  `hooks/handoff-write.sh:144`; it is not a new constraint.

### Reproduction

Not covered by `tools/context-audit.js`. Filter the transcript store for records with
`subtype == "compact_boundary"`, then take the nearest `message.usage` before and after by index —
and parse the JSON structure rather than grepping for field names, per the trap already recorded at
`hooks/handoff-write.sh:105`.

---

## Finding #9, 2026-08-31 — loading a deferred tool mid-session does _not_ rewrite the cache prefix

Numbered as a finding rather than appended to the addendum above because it settles a question the
addendum could only pose, and the answer is the opposite of what was predicted.

**The hypothesis, from the addendum's own trap.** Claude Code defers most tool schemas: they are
named but undefined until `ToolSearch` loads one. Tools render _before_ the system prompt, so a tool
set that changes mid-session should invalidate the cache from position 0 — system prompt included —
making every mid-session tool load cost a full prefix rewrite.

**It is answerable because it is a question about the read's _size_, not its structure.** Reads are
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

| class   | pairs | median survival | read = 0 | median write on the next request |
| ------- | ----- | --------------- | -------- | -------------------------------- |
| NEW     | 132   | 100.0%          | 2 (1.5%) | 2,128                            |
| REPEAT  | 3     | 100.0%          | 0        | 967                              |
| MISS    | 11    | 100.0%          | 0        | 229                              |
| CONTROL | 6,597 | 100.0%          | 6 (0.1%) | 1,040                            |

**Verdict: refuted.** The prefix survives a new deferred-tool load. Outside one workflow discussed
below, 101 of 104 NEW pairs survived at _exactly_ 100%.

**The two collapses are not caused by the tool load, and the corpus proves it.** Both are subagent
contexts inside a single ~100-way parallel workflow (`wf_baccf070-3e3`). Within that workflow, 29
sibling agents made the _identical_ load — `WebFetch` — at near-identical prompt sizes (~23.2k) and
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
now measured is narrower — _`ToolSearch` does not change the rendered tools block at all_, so it
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
trap at `hooks/handoff-write.sh:105`.

---

## Correction, 2026-09-02 — the amplification denominator double-counted output

Appended on the same terms as the 2026-08-24 correction: the original figures stand as what the
tool reported on 2026-08-21, and this section says exactly how they move. Unlike that one, this
correction moves a **headline number**, and it moves it in the direction that strengthens the
report.

**The defect.** `tools/context-audit.js` computed `newMaterial = inp + cc + out`, corpus-wide and
per context. The reasoning was that output enters context and is not cache creation, so it must be
a third source of new material. It is not — it is the _same_ material counted twice. An assistant
turn is re-sent as ordinary **input** on the very next request, where it is billed inside
`cache_creation_input_tokens`. So output already sits in `cc`, and adding it again inflates the
denominator and understates how many times material is actually replayed.

**Why this is a measurement and not an argument.** The alternative was genuinely plausible: the
server computed the KV for those tokens while generating them, so it _could_ retain them and serve
the next prefix as a pure read. Token conservation decides it exactly, with no `CHARS_PER_TOKEN`
anywhere. The tokens sent on a request are `cr + cc + inp`, so between consecutive requests in one
context `Δ(cr + cc + inp) = out(t) + newInput(t+1)`. Then `cc(t+1) ≈ Δ` means the whole increment
was written, output included; `cc(t+1) ≈ Δ − out(t)` means the output rode in free. Measured by
`tools/context-billing.js` (landed 2026-09-02, this correction's instrument): across **1,716** warm
consecutive pairs with `out(t) ≥ 300`, `cc(t+1)` matches the whole `Δ` in **97.0%** of cases — 2.3%
match `Δ − out(t)`, 0.6% neither. For pairs under a minute apart, `cc/Δ = 1.01`.

**The 2.3% minority is real, and one identity explains it and its mirror image.** Because
`Δ = (cr + cc + inp)[t+1] − prevPrefix`, substituting and cancelling gives, for every pair without
exception:

```
cc − Δ  ≡  prevPrefix − read − inp
```

Algebra, not a finding — but it collapses what looked like several phenomena into one question: how
far did request t+1's cache read reach, relative to everything sent on request t. Reaching exactly
`prevPrefix` gives `cc = Δ`. Falling short writes the gap again. Running _past_ it means the
generated tokens were already in the entry and no write was charged — which is the 2.3%. Measured:
of 53,693 shortfall tokens, **51,896** arrive as reads, across 43 of 45 pairs, with `inp` averaging
2 tokens. So the server does sometimes retain the KV it computed while generating and extend the
entry for free; rarely, and for reasons this corpus cannot reach. The three causes of a read
stopping where it does — TTL expiry, breakpoint granularity, free extension — are worked through in
[`docs/design.md`](design.md#why-the-quadratic-is-a-replay-artifact).

**Do not read the near-cancellation as a mechanism.** Split by sign over every warm growing pair:
**+599,096** tokens paid for twice against **−552,709** never written at all, a net of
**+46,502** across 2,671 pairs, aggregate `cc/Δ` = **1.008**. Those are different tokens produced by
unrelated mechanisms, and nothing defers or settles up — the +599,096 really are paid for twice,
cause 1's written again after expiry and cause 2's billed as input on one request and as a write on
the next. An earlier draft of `docs/design.md` called the two directions "one bookkeeping lag seen
from both ends", which implies the same tokens paid once and late. They are not. The magnitudes
landing within 8% of each other is a property of this corpus, not a law, and nothing should be built
on it. `tools/context-billing.js` prints the split on every run.

**Two wrong explanations, and why they are recorded rather than quietly replaced.** The first draft
of this correction, and of the design write-up, explained the sub-1.0 pairs as increment landing in
uncached input because the breakpoint had not advanced. That is exactly the class of claim
`docs/calibration.md`'s measurement-ceiling section forbids — breakpoint placement is not in the
transcript, so no transcript-derived finding can attribute anything to it. A rule stated in one
document did not stop this repository asserting its negation in another, five days later, in a
section whose whole subject was being exact. Both errors have the same shape: an observation tidied
into a neater mechanism than the numbers supported. The durable fix is not better prose but the
instrument — `tools/context-billing.js` prints the `inp`-versus-`cr` decomposition and the signed
split on every run, handing the next reader the discriminating numbers instead of a sentence to
trust.

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

- **A cache write is once per _entry_, not once per token.** Bucketed by the gap between
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

---

## Finding #10, 2026-09-03 — the post-compaction rewrite arrives in two waves, and the second one is cheaper for arriving late

Numbered as a finding rather than folded into the 2026-08-31 addendum because it looks at that
addendum's `create` figure (36–45k tokens, the "one-off charge") at attachment granularity instead
of as one number, and finds it is not one write. It does **not** touch the addendum's other figure —
whether the surviving ~30k read really is the tools-plus-system preamble is still open (see "What
this does not settle" below).

**The write splits into two waves, one immediate and one request later.** Wave 1 — file re-reads,
`compact_file_reference`, `invoked_skills`, `deferred_tools_delta`, `agent_listing_delta`,
`mcp_instructions_delta`, hook messages — lands inside the first post-boundary request's
`cache_creation_input_tokens`, matching the addendum's published figures exactly. Wave 2 —
`nested_memory` (CLAUDE.md files from subdirectories below the project root, e.g. `frontend/CLAUDE.md`
and `frontend/tests/CLAUDE.md`) plus a `skill_listing` delta and small diagnostics/reminder
attachments — shows up as a **second, separate** `cache_creation_input_tokens` charge on the
_following_ request, not the one the addendum measured:

```
                        wave 1 (request 1)       wave 2 (request 2)
kendo-2/7efc5ac2        create=36,473 read=29,600   create=7,397  read=66,073
kendo-2/7359db87        create=45,458 read=31,059   create=8,256  read=76,517
mission-control/29e903e9 create=39,488 read=30,092   (none)
```

Every `read` on the request after a write equals the exact sum of the previous request's `read` and
`create` (29,600+36,473=66,073; 31,059+45,458=76,517) — nothing is double-billed and nothing gets
rewritten, wave 2 purely appends to the prefix wave 1 established.

**Wave 2 is conditional, not universal — mission-control has nothing to append.** Its session has
**zero** `nested_memory` attachments anywhere in its transcript (checked the full file, not just
around the boundary), so there is nothing for a second wave to carry. The absence is not evidence
against the pattern; it is the pattern's own predicted null case, since `nested_memory` only fires
for projects with CLAUDE.md files below the root.

**Wave 2 is not triggered by the request it rides in on.** In both cases where it fires, the tool
call sitting between wave 1 and wave 2 has nothing to do with the paths that reappear: a plain
`git status --short && git log --oneline -1` in the first case, a PowerShell `Get-Process` scan for
stray node processes in the second — neither touches a file. What does line up, checked for the
first case: the 260 lines before that boundary contain 123 tool calls referencing `frontend/`,
ending in an `Edit` to `frontend/tests/integration/.../Show.spec.ts` and a commit of `frontend/`
changes — exactly the two directories (`frontend/`, `frontend/tests/`) whose CLAUDE.md reappears in
wave 2. This reads as the harness restoring a working set the session already had, lagging one
request behind, not as the current turn's tool use discovering new paths. (A separate, unpublished
line of analysis from an earlier session found the same async-settling shape in `skill_listing`'s
`isInitial` flag near session start; not cited further here since it never made it into this
document.) Not independently confirmed for the second case's specific paths, only that its
intervening tool call is equally unrelated.

**The two-wave split is measurably cheaper than an eager single-request bundle would have been, not
neutral.** Counterfactual arithmetic on the numbers above, at the ephemeral-1h rates this report uses
throughout (write 2×, read 0.1×) — not a re-run, the same kind of derivation as the 2026-09-02
correction's headline number:

```
kendo-2/7efc5ac2, requests 1+2
  actual (split):   36,473×2 + 29,600×0.1  +  7,397×2 + 66,073×0.1  =  97,307 effective
  bundled into r1:  43,870×2 + 29,600×0.1  +  0       + 73,470×0.1  =  98,047 effective
  split is cheaper by 740

kendo-2/7359db87, requests 1+2
  actual (split):   45,458×2 + 31,059×0.1  +  8,256×2 + 76,517×0.1  = 118,186 effective
  bundled into r1:  53,714×2 + 31,059×0.1  +  0        + 84,773×0.1 = 119,011 effective
  split is cheaper by 826
```

The reason is the same one behind finding #4's "size × remaining lifetime": every resident token
pays the 0.1× read tax on every subsequent request, so writing wave 2's bytes at request 1 means
they immediately get read back at request 2 for free information they didn't need to carry yet.
Writing them one request later, only once something (here, nothing in particular — see next
paragraph) asks for them, skips that one extra read-forward. This is finding #9's "lazy beats eager"
result again, quantified for a case where the delay is exactly one request instead of arbitrarily
many.

**Caveat: request 2 was not created by the split.** It exists because request 1 ends in a tool call
(`git status`, `Get-Process`) whose result has to be fed back before the agent can continue — that
request happens regardless of what rides along in it. The only free variable is which request wave
2's bytes are written on, not whether a second request occurs. The "bundled" counterfactual above
compares two ways of filling a request that was going to happen anyway, not a bundled-request-vs-two-
requests choice.

**What this does not settle.** Whether the addendum's ~30k surviving read really is the
tools-plus-system preamble is untouched by any of the above — this finding is entirely about the
_write_ side. The cost-arithmetic and causation results are each n=2 (only two of the three
boundaries have a wave 2 to analyze); the null case is n=1. And the delay measured is exactly one
request in every instance seen — whether a longer lag would keep compounding the saving, or whether
something eventually forces wave 2 in sooner, is not tested here.

### Addendum, 2026-09-03 — session-start read is tightly clustered, create is not

The "What this does not settle" paragraph above left one question open: whether the addendum's
~30k surviving post-compaction read really is the tools-plus-system preamble. A session's very
first request — before any compaction, before any project-specific work has happened — offers a
size-only test of that, in the same spirit as `docs/calibration.md`'s distinction between
prefix-_size_ questions (answerable from `usage`) and boundary-_content_ questions (not, per
finding #11 below): if a fixed tools+system block dominates that first read, its size should look
similar across different projects even though the projects' own work differs completely.

It does. First `assistant` record (by unique `requestId`) in each of the same three transcripts:

```
                          request 1 (session start)
kendo-2/7efc5ac2          create=29,942   read=26,417
kendo-2/7359db87          create=32,466   read=27,510
mission-control/29e903e9  create=14,019   read=26,518
```

**Read clusters tightly: 26,417 / 26,518 / 27,510**, a spread of 1,093 tokens (4%) across two
unrelated projects (`kendo-2`, `mission-control`) with nothing in common at the code level.
**Create spreads widely: 14,019 to 32,466**, more than 2×. That split is consistent with — does
not contradict — a reading where the tightly-clustered read is a largely shared, static block
(tool schemas plus the harness's own static system-prompt section) while the widely-spread create
is per-project dynamic material (memory files, CLAUDE.md, project-specific instructions), the same
static/dynamic split `--exclude-dynamic-system-prompt-sections`'s own description names (finding
#11). It is still an inference from size, not an inspection of content.

**One thing this settles by definition, not by inference — and it's not the part worth calling
surprising.** `cache_read_input_tokens` on a session's first-ever request cannot be a from-cold
value: a read is a cache hit, so those 26,417–27,510 tokens were necessarily written by some
_other_ process before this session sent its first request. What is worth noting is what that
implies given the cache is ephemeral (`docs/calibration.md`'s 5-minute and 1-hour tiers, nothing
longer): that other write must have landed recently enough — within whichever tier applies — to
still be alive at this session's start. That is a fact about **usage cadence on this account**
(sessions in different projects running close enough together in time to keep an entry warm across
the gap), not a fact about architecture — the existence of a shared static block is already
established architecturally by `--exclude-dynamic-system-prompt-sections`'s own description
(finding #11) and isn't the notable part of this addendum.

**What this still does not settle.** n=3, a thin basis for "tightly clustered" — nothing here
rules out coincidence at this sample size. Which specific prior session or process wrote the warm
entry each of these three hit is unknown — the transcripts only show that _something_ did, not
what. And whether the content actually read really is the tools-plus-system preamble, versus some
other shared material, is still a content question this corpus cannot answer (finding #11).

### Reproduction

Not shipped as a `tools/` script — built ad hoc for this finding and not saved anywhere durable, so
re-derive from the method rather than hunting for the original: for a given transcript, find the
`system`/`compact_boundary` record, then walk forward through `attachment` records grouping by
contiguous timestamp runs (a "wave" is a burst that shares one timestamp), joining each wave to the
next `assistant` record's `message.usage` to get its `cache_creation_input_tokens` /
`cache_read_input_tokens`. To check causation, look at the `tool_use` between two waves and, for the
directories a `nested_memory` attachment names, grep backward through the same transcript's earlier
`tool_use` records for that path. For the session-start addendum: dedupe `assistant` records on
`requestId` and take the first one's `message.usage`.

---

## Finding #11, 2026-09-03 — the rendered system prompt is not recoverable from anything on disk; the harness's own flag docs are the next-best source

**Question.** `docs/calibration.md:294` already asserts a ceiling: a boundary's _position_ is
observable (a token count) but the _content_ at that position — which block it fell on —
"needs the rendered payload, which these transcripts do not carry." This finding asks whether
that's actually true, by trying the two routes that could plausibly get at the rendered payload
anyway, and finds it holds — then extends it: the ceiling isn't specific to breakpoint placement,
it covers the system prompt's content generally.

**Route 1 — `claude --debug api`.** Captured one real request/response cycle this way (a 29.6KB
log). It is pure operational telemetry: MCP connection timing, permission-rule loading, lines like
`Dynamic tool loading: 0/15 deferred tools included` and `turn 1 end (usage in=2 out=4
cost=$0.0517)`. No request or response body appears anywhere in it. One field is explicitly
redacted — `autocompact: tokens=[REDACTED]` — which reads as a deliberate omission rather than an
oversight; the harness appears to intentionally keep size/content fields out of debug output, not
just skip logging them by accident.

**Route 2 — the transcript files themselves.** Enumerated every distinct `type` /
`subtype` / `attachment.type` combination across the full 7.5MB `kendo-2/7efc5ac2` transcript
(4,720+ records, the same file finding #10 uses). There is no system-prompt-bearing record type —
nothing that carries the literal rendered system prompt or tool schemas. Also checked for an
on-disk snapshot file (the session's own state directory, `~/.claude/sessions/`): nothing
content-bearing there either, only locks and small state files.

**So the ceiling holds, and generalizes.** `docs/calibration.md:294` was written about breakpoint
_placement_ specifically. This finding did not find a narrower gap — the same absence covers the
system prompt's _content_, full stop. Nothing readily available on this machine carries the
rendered bytes.

**What does move the question forward: two flags' own documentation, not measurement.** `claude
--help` describes two flags whose descriptions are, in Anthropic's own words, claims about harness
behavior that this repo's transcripts cannot independently verify but also has no reason to doubt:

- `--exclude-dynamic-system-prompt-sections`: "Move per-machine sections (cwd, env info, memory
  paths, git status) from the system prompt into the first user message. Improves cross-user
  prompt-cache reuse. Only applies with the default system prompt (ignored with
  `--system-prompt`)." The _effect_ stated — cross-user cache reuse improves when this content
  moves out — is itself proof, not inference, that the default system prompt contains
  machine-varying content today: reuse across users can only be incomplete if something in the
  shared prefix currently differs per user/machine. This is the same shared-warm-prefix shape the
  session-start numbers elsewhere in this repo point at, now with a named cause instead of an
  inferred one. What it does **not** say is that these four are the _only_ dynamic sections — the
  parenthetical lists items without "e.g." or "such as," which reads like an enumeration by CLI-help
  convention, but that is a convention-based reading, not a stated exhaustiveness guarantee. Treat
  the list as "at least these," not "only these."
- `--system-prompt-snapshot <on|off>`: "Record the system prompt once per conversation and reuse
  it verbatim on every request and resume... on: an existing record in the conversation is sent
  as-is (a later launch's different `--system-prompt`/`--append-system-prompt` is ignored **until
  compaction**)." This is a direct, textual statement that compaction is the harness's own trigger
  point for re-establishing the system prompt — not something inferred from token-count deltas
  the way finding #10's wave split was.

Both are worth citing by their literal flag text rather than paraphrased, and are a stronger
source than anything derivable from the transcripts, because they describe the mechanism directly
instead of being reverse-engineered from its `usage` side effects.

**A same-session observation sharpens the exhaustiveness question further, with its own caveat.**
Whether the four-item list is complete turns out to matter less than it first looked, because the
benefit is incremental, not binary: cache reuse improves by whatever a given move-out covers,
independent of whether it covers everything dynamic. What's more informative is this: in _this_
conversation, both `currentDate` and `gitStatus` — one of the four named items — arrived as a
`<system-reminder>` block attached to the first user turn, not as anything resembling a
system-prompt field, and this session never set `--exclude-dynamic-system-prompt-sections` (default
`false`). That suggests at least one of the four named items is already kept out of the system
prompt **unconditionally**, regardless of this flag's state — i.e. the flag's real function may be
"extract more of what's already selectively extracted elsewhere," not "extract these four for the
first time." Caveat, and it's a real one: this is an architectural signal observed from this
session's own rendering, not from the `--help` text, and not measurement in the sense the rest of
this document uses the word — the wire-level API payload is exactly the thing finding #11's two
dead-end routes above could not reach, so there is no confirmation that what renders to me as a
`<system-reminder>` corresponds to the same injection point the flag's help text calls "the first
user message," or is some other, unrelated mechanism the harness also happens to use.

**What this does not settle.** These flag descriptions are still documentation, not measurement —
this repo has not run a controlled A/B with `--exclude-dynamic-system-prompt-sections` toggled to
confirm the cache-reuse improvement it claims, and finding #9/#10's own results were reached
without needing it. Nor is the four-item list confirmed exhaustive, or the `currentDate`/`gitStatus`
observation confirmed to share a mechanism with the flag. They narrow _where to look_ and _what the
boundary's content plausibly is_; they do not supply the bytes.

### Reproduction

```
claude --help 2>&1 | grep -A6 "exclude-dynamic-system-prompt-sections"
claude --help 2>&1 | grep -A16 "system-prompt-snapshot"
claude --debug api   # then drive one turn; inspect the emitted log for body content (there is none)
```

For route 2, enumerate record shapes in a transcript with a short jq/node pass over
`type`, `subtype`, and `attachment.type` (or their absence) across every line of the `.jsonl` file,
and separately list `~/.claude/sessions/` to confirm it holds only locks/state, not content.

---

## Finding #12, 2026-09-03 — the A/B test: flag-on relocates bytes into cache-read, not into plain input

**Question.** Finding #11 above left this open: "this repo has not run a controlled A/B with
`--exclude-dynamic-system-prompt-sections` toggled to confirm the cache-reuse improvement it
claims." This finding runs it.

**Method.** Four `claude -p "Reply with just the word OK." --output-format json` single-turn
sessions, flag off/on paired across two unrelated project directories (`context-economy`,
`mission_control`), all under one account within a short window. `--output-format json` returns
`message.usage` for the sole request directly, so no transcript parsing was needed. Prompt text
held constant across all four so only the flag varies within a pair.

**Result.**

```
                     create    read    total   input
context-economy off  11,919  24,467  36,386    2
context-economy on    7,893  28,410  36,303    2   (Δtotal -83)
mission_control  off  21,627  24,467  46,094    2
mission_control  on   16,449  29,562  46,011    2   (Δtotal -83)
```

**Answers the question under test cleanly.** Finding #11's open question had two branches: does
the read side grow because more static content becomes a shared/cacheable prefix once the
per-machine sections move out, or does it stay flat while those bytes just relocate to uncached
first-message `input_tokens`? `input_tokens` is unchanged (2, both flags, both directories) —
ruling out the second branch. Read grows and create shrinks by close to the same amount in both
pairs — supporting the first: the relocated per-machine content still lands inside the _cached_
portion of the request either way; moving it out of the system prompt just makes it more likely to
already match an existing cache entry (a "read") instead of writing a fresh one (a "create").

**What actually matters is cost, not the raw create+read sum.** A create token here bills at the
1h-cache-write rate and a read token at the cache-read rate — 2× and 0.1× base, the same
multipliers finding #10's own arithmetic uses (`docs/calibration.md`) — a 20x spread. Summing
create and read as if they were equally expensive is what makes the shift look like a wash; it
isn't. Re-priced at those rates:

```
                     create×2   read×0.1   effective   Δeffective
context-economy off   23,838      2,447      26,285
context-economy on    15,786      2,841      18,627      -7,658  (-29%)
mission_control  off   43,254      2,447      45,701
mission_control  on    32,898      2,956      35,854      -9,847  (-22%)
```

The flag cuts this single request's effective cost by roughly a fifth to a third. That's what
finding #11's "improves cross-user prompt-cache reuse" claim cashes out to economically: not less
content moving through the request, but 4,000-5,000 tokens per request moving from the most
expensive tier (a fresh 1h write) to the cheapest (a read).

**The flag-off read is identical across both projects: 24,467, in both.** Not project-specific —
this read reflects a shared cache entry independent of which directory the session runs in
(presumably the generic tool-schema/harness-instructions prefix), while create tracks
project-specific content (memory files, CLAUDE.md, skill listings) and varies widely (11,919 vs
21,627).

**The raw create+read total barely moves (Δtotal -83 in both pairs) — noted, not the finding.**
That near-equality just says the relocation is close to like-for-like at the byte level, which is
expected: the same content is still being sent, only reclassified. It has no bearing on cost, which
is the effective-token calculation above, not this sum.

**What this does not settle.** All four runs are under one account within a short window
(~10 minutes), so this confirms cache reuse _within an account's own session pool_, not the flag's
literal claim of _cross-user_ reuse — testing that would need a second, unrelated account, which
this corpus can't provide. It also doesn't test whether the effect holds outside a single-turn,
near-empty prompt, or after the 1-hour ephemeral tier actually expires — `cache_creation`'s
`ephemeral_1h_input_tokens` field was the only non-zero one in every run; `ephemeral_5m` was 0
throughout.

### Reproduction

```
cd <project-a> && claude -p "Reply with just the word OK." --output-format json
cd <project-a> && claude -p "Reply with just the word OK." --exclude-dynamic-system-prompt-sections --output-format json
cd <project-b> && claude -p "Reply with just the word OK." --output-format json
cd <project-b> && claude -p "Reply with just the word OK." --exclude-dynamic-system-prompt-sections --output-format json
```

`--output-format json` returns `message.usage` for the single request directly — no transcript
parsing needed for a one-turn `-p` session.

---

## Finding #13, 2026-09-07 — `PreCompact` can fire with no compaction behind it; when it does lead to compaction, it blocks with no observed timeout

**Question.** A live probe of four claims about the `PreCompact` hook, asked while scoping a
redesign that would write a fresh handoff at compaction time instead of at an earlier, easily-stale
`Stop`-hook boundary: does the harness block compaction (and the paired
`SessionStart(source:"compact")`) on `PreCompact` completing; does that blocking have a timeout;
does `PreCompact`'s live payload match `mission_control`'s report
(`reports/2026-08-24-harness-automation-surface.md`, finding F3), which derived it from static
binary-string extraction rather than a live fire; and is a file `PreCompact` writes just before
returning reliably visible to the `SessionStart(source:"compact")` that follows it.

**Method.** `claude-haiku-4-5-20251001`, `--autocompact 100000` (the CLI's minimum), against an
isolated scratch project with its own `.claude/settings.json` registering a `PreCompact` hook
(logs its full input payload plus entry/exit timestamps, sleeps for a duration set by an env var,
writes a `precompact.done` marker before exiting) and a `SessionStart` hook (on `source:"compact"`
only: logs its own entry timestamp and whether the marker is already present). Resident context was
pushed over the threshold with base64-random filler piped via stdin (per this doc's own finding #9/
#10 methodology — repetitive filler tokenizes far too dense to reach a target size predictably),
using `claude -p` then `claude -p -c` to continue the same session. Six `-p` calls total, ~$0.50.
Scratch project and the `~/.claude/projects/*compact-probe-2*` transcript directories it created
were deleted immediately after, so there is no on-disk artifact to cite by `path:line` — re-derive
via the method above rather than looking for the original logs.

**1. `PreCompact` firing does not mean compaction happens in that request.** Observed twice,
identically: the request that first pushes resident context over the threshold (~119k tokens
against a 100k `--autocompact` window) fires `PreCompact` at the end of that turn, but no
`SessionStart(source:"compact")` follows — the transcript is still uncompacted. The _next_
`-p -c` invocation starts with an ordinary `"resume"`-sourced `SessionStart` (context still ~119k),
fires a **second** `PreCompact` mid-request, and only that second firing is followed by the real
`SessionStart(source:"compact")`. Within a firing that does lead to compaction, ordering is
strictly sequential — the hook's own exit timestamp always precedes the next event, confirming real
blocking there. But firing alone is not evidence that a compaction is about to complete behind it.

**2. No timeout observed.** Reran with the hook sleeping 65s — past the ~60s figure commonly cited
as a hook default. It ran the full 65.04s (entry 09:49:28.913 → exit 09:50:33.951) with no kill, and
`SessionStart(source:"compact")` still followed roughly 10s later. This eliminates the ~60s default
as a ceiling for `PreCompact` specifically; it does not establish where, or whether, one exists.

**3. Payload mostly matches F3, but the "universal base payload" claim doesn't extend to
`PreCompact`.** Live JSON carried `session_id`, `transcript_path`, `cwd`, `prompt_id`,
`hook_event_name:"PreCompact"`, `trigger:"auto"`, `custom_instructions:null` — matching F3's
static extraction. But finding F5 in the same `mission_control` report claims `permission_mode`,
`agent_id`, `agent_type` and `effort` as part of "the base payload every event extends"; all four
were **absent** from the live `PreCompact` payload, not merely null-valued. F5's generalization does
not hold for this event.

**4. No race between the marker and the paired read.** `precompact.done` was written before
`PreCompact`'s own exit in every run, and the `SessionStart(source:"compact")` that followed (same
`prompt_id`, confirming the pairing this doc's earlier compact-injection work established) always
found it present.

**Design implication, not itself a measurement.** Because `PreCompact` can fire on a turn that
never compacts, a handoff-write wired directly to every `PreCompact` firing would sometimes run for
nothing, or run twice for one real compaction. The firing that's safe to act on is the one followed
by compaction — which `PreCompact` itself cannot know in advance, only `SessionStart(source:"compact")`
can confirm after the fact. That reopens rather than closes the question of _where_ the pre-compaction
transcript access `PreCompact` has gets paired with the "a compaction genuinely happened" guarantee
only `SessionStart(source:"compact")` carries.

**What this does not settle.** n=2 for the double-firing pattern and n=1 for the timeout probe — no
attempt was made to find where a real ceiling starts, only that 65s is under it. Whether the
double-firing is deterministic (always exactly one wasted `PreCompact` per compaction) or can chain
further on a slower-growing session is untested. And nothing here establishes _why_ the first
`PreCompact` fires without compacting — only that it does, twice, identically.

### Reproduction

Not preserved on disk (scratch project and its session transcripts were deleted per this repo's own
cleanup discipline) — re-derive from the method paragraph above: a project-local `PreCompact` +
`SessionStart` hook pair that timestamp and log their own payloads, `claude -p` / `claude -p -c` on
`claude-haiku-4-5-20251001` with `--autocompact 100000`, base64-random stdin filler to cross the
threshold, and a `PRECOMPACT_SLEEP` env var to vary the hook's own runtime across probes.

---

## Finding #14, 2026-09-07 — a real handoff-authoring turn costs 13.7k–64.6k tokens, measured from the existing corpus rather than a fresh probe

**Question.** `docs/design.md`'s write-trigger invariant (`T + fat_turn + authoring_turn <
effective_window - 13_000`, D10) names `authoring_turn` — the token cost of the turn a forced
`/handoff` write actually runs — but had never measured it; the only figure on record was F4b's
qualitative "an unscoped Read or a wide grep can add 50k+", about turns in general, not this one
specifically. Since the write-trigger has been firing in production for weeks, this asks whether
the answer already exists in past sessions rather than needing a new live probe.

**Method.** Searched every `*.jsonl` under `~/.claude/projects/` (not just this repo — the shared
hooks run in `kendo`, `kendo-2` and `mission-control` too) for a `Write`/`Edit` to the canonical
handoff store (`*/.claude/context-economy/handoffs/*.md` or the older `*/.claude/handoff/*.md`) or a
`Skill{handoff}` invocation. 61 candidate turns found across 24 sessions; excluded skill-invocation
turns that don't do the write themselves, false positives (turns whose _other_ tool calls merely
touched files like `design.md` or `verify-handoff.sh` that happen to mention "handoff"), and turns
missing a usable pre-turn usage record. **20 clean initial-authoring turns remained**, one per
session. For each: dedupe `assistant` records by `requestId` (this doc's own standing trap, findings
#10/#13), take `before_total` as the last usage sum strictly before the turn starts (a real user
message, or the `Stop`-hook block that forces the write — F4/F10) and `after_total` as the last usage
sum at the write itself; `delta = after - before`.

**Result.**

```
session     project           delta   tools
7658c602    kendo             13,698    3
7310dc74    kendo-2           14,610    3
8fd0710d    kendo             20,064    8
033afa53    mission-control   20,447    5
367aef74    mission-control   21,658    5
7198be60    mission-control   22,125    4
10aaa0fe    mission-control   22,318    7
7db65f0d    mission-control   22,624    7
3b6df54f    kendo-2           23,472    7
49681234    mission-control   23,905    7
4e720b15    mission-control   26,145    6
ccc601ec    mission-control   28,132    8
b298c8fd    context-economy   31,398    9
c597a1b6    context-economy   32,680   12
07dd28fb    context-economy   32,885   18
1ff6cff8    mission-control   38,633   16
45a76607    mission-control   41,274    7
be77ebc2    context-economy   46,630   19
c99b1e61*   mission-control   53,166   25
593f5e02    context-economy   64,618   19
```

**n=20, min=13,698, max=64,618, median=25,025, mean=30,024.** One outlier flagged, not folded into
the headline range: `c99b1e61` (53,166 tokens, 25 tool calls, marked `*`) opens with a
`ScheduleWakeup` call and several `Read`/`Edit` pairs unrelated to the handoff _before_ the write —
mixed work in the same turn, not pure authoring cost. Excluding it: max=46,630, mean=28,435, median
essentially unchanged. Four sessions also had smaller, later same-session _revision_ turns (5,024 /
5,244 / 8,226 / 18,056 tokens) — reported separately since those are follow-up edits, not the forced
initial write the invariant is about.

**What this settles.** `authoring_turn` is not the unbounded "could be anything" the invariant's
naming implied — it is empirically 13.7k–64.6k across a real, varied corpus (three different
projects, 20 independent sessions, tool-call counts from 3 to 25). Combined with F4b's existing
`fat_turn` figure, a write-trigger needs on the order of **90k–115k tokens of slack** below
`compact_threshold` to survive a worst-case authoring turn stacked on a worst-case fat turn — a
concrete number where the invariant previously had a name and a qualitative worry.

**What this does not settle.** The corpus is retrospective and self-selected: it only contains turns
where the write-trigger already fired and completed successfully, so it says nothing about turns
that might have been _larger_ than what a session's own configured `T` allowed for (if any such
turn had blown through the ceiling into an actual compaction race, the resulting handoff would most
likely never have been written cleanly enough to match this measurement's file-path signal, and
would be invisible to this method — a survivorship gap, not a contradiction of the range above). The
outlier's contamination was judged by reading its tool-call sequence, not by an objective threshold;
a stricter or looser contamination bar could move it in or out of the clean sample. And all 20 turns
ran under this repo's own current `/handoff` skill and citation-gate implementation — a heavier or
lighter future version of that skill would shift the range without this measurement knowing.

### Reproduction

```
# For each project directory under ~/.claude/projects/*/*.jsonl:
grep -l 'context-economy/handoffs/\|\.claude/handoff/' *.jsonl        # candidate sessions
# then, per candidate file: locate the Write/Edit tool_use to that path, walk back to the
# preceding real user message or Stop-hook block reason, dedupe assistant usage by requestId,
# and diff the last usage sum before that point against the last usage sum at the write.
```

No script was saved for this pass — re-derive with the method above rather than hunting for one.

---

## Finding #15, 2026-09-07 — `fat_turn` is bimodal; the mid-session tail runs 3–6x above F4b's qualitative "50k+"

**Question.** `docs/design.md`'s write-trigger invariant (`T + fat_turn + authoring_turn <
effective_window - 13_000`, D10) names `fat_turn` — the token cost a single turn can add via a wide
`Read`/grep or similar — but the only figure on record was `mission_control`'s F4b, a qualitative
illustration ("one turn containing an unscoped Read or a wide grep can add 50k+"), not a measured
distribution. This asks whether the historical corpus already answers it, the same way finding #14
answered `authoring_turn`.

**Method.** Corpus-mined, not live-probed (explicit user preference, same as #14). A "turn" is
F4b's own definition: everything between one real `type:"user"` message (never a `tool_result`
wrapper) and the next, spanning 1..N assistant tool-use requests. Per turn: dedupe `assistant`
records by `requestId`, keeping the _last_ occurrence per id (findings #10/#13/#14's standing
trap); `before_total` = last deduped usage sum strictly before the turn's start; `after_total` =
last deduped usage sum at the turn's end; `delta = after_total - before_total`. Sampled the largest
transcript files (by size) across the same four projects finding #14 used — `context-economy`,
`kendo`, `kendo-2`, `mission-control` — 12 sessions each, 48 sessions total, every ordinary turn in
each (not just handoff-authoring turns). 736 turns collected; 2 excluded as post-compaction-boundary
artifacts (the reset itself, not a fat turn).

**Result.** Two populations, and they must not be pooled:

- **Zero-baseline turns (n=12)** — a session's entire run from a cold start to its first real turn
  boundary (autonomous/single-prompt sessions with no further human input in between). Median
  208,403, max 952,946. This is whole-session growth, not what `fat_turn` means in the invariant —
  excluded from the headline figure.
- **Mid-session turns (n=724)** — the population the invariant actually cares about, a turn
  occurring once a session is already substantially along (the realistic scenario near a compaction
  threshold): **median 6,707, p90 34,897, p95 59,367, p99 158,290, max 323,673.**

Every one of the top 10 mid-session turns is a long, uninterrupted autonomous work stretch (22–259
tool calls, `Bash`/`Edit`/`Write`-heavy — e.g. the max, `mission-control/8681a850` at 323,673 tokens
over 259 tool calls: 191 `Bash`, 60 `Edit`, 6 `Write`). None of the top 10 is a single wide
`Read`/grep the way F4b's illustration framed it; the real driver is sustained multi-step agentic
work that never pauses for a final answer, not one big file operation.

**What this settles.** F4b's "50k+" is not a conservative floor — it undercounts the real tail by a
wide margin. It sits just below p90 (34,897) and already below p95 (59,367); p99 (158,290) and max
(323,673) run 3–6x higher. A `T` sized against "50k+" as a worst case is exposed at exactly this
repo's own common working pattern (autonomous refactor/fix/probe stretches), not some rare edge
case. Combined with finding #14's `authoring_turn` (13,698–64,618, median 25,025): designing for
`fat_turn`'s p99 alone (158,290) plus `authoring_turn`'s clean-corpus max (46,630, finding #14's
outlier-excluded figure) is already ~205k tokens of required slack — noise against a 1M window's
~787k slack, but close to the entire budget of a 200k-class window once a margin is added.

**What this does not settle.** _Which_ percentile to design `T` against is not decided by this
measurement — that is a design choice about acceptable failure rate, not a fact to derive. The
corpus is retrospective and self-selected the same way #14's was: it can only contain turns that
completed and got logged, so a turn that grew large enough to race an actual compaction may be
underrepresented (a survivorship gap, not a contradiction of the range above). Sampling picked the
largest transcript files per project by size, which biases toward sessions with more (and likely
more varied) turns, not a uniform random sample of all turns ever recorded — the true population
distribution could differ somewhat, though the bimodal split itself (cold-start vs. mid-session) is
a structural fact of how turns are bounded, not an artifact of this sampling choice.

### Reproduction

```
# For each of context-economy, kendo, kendo-2, mission-control: pick the 12 largest *.jsonl
# files under ~/.claude/projects/<project-dir>/. Within each, walk records in order, splitting
# into turns at each genuine type:"user" message (excluding tool_result-only wrapper messages).
# Per turn: dedupe assistant records by requestId (keep last), diff last usage sum at turn end
# against last usage sum strictly before turn start. Exclude turns that are themselves the
# immediate post-compaction boundary. Report the cold-start (first turn per session) and
# mid-session (all others) populations separately.
```

No script was saved for this pass — re-derive with the method above rather than hunting for one.

---

## Finding #16, 2026-09-07 — the compact read leg's two load-bearing claims hold, confirmed live

**Question.** The compact read leg (`hooks/handoff-inject.sh`'s `compact` branch, `docs/design.md`
D17) rests on two claims that were reasoned from other findings but never freshly, independently
confirmed with a live probe: (1) `session_id` survives auto-compaction, so the sidecar
`hooks/handoff-write.sh` writes keyed by `session_id` is still addressable by the same key after a
compaction; and (2) at the exact moment `SessionStart(source:"compact")` fires, no new API request
has run yet, so the last usage record in the hook's own `transcript_path` is still the
pre-compaction peak rather than an already-shrunk post-compaction figure. This asks whether both
hold, the way finding #13 settled four `PreCompact` claims live rather than by reasoning alone.

**Method.** Same shape as finding #13: an isolated scratch project (`.claude/settings.json`
registering `PreCompact` and `SessionStart` — matcher `""`, filtering on `.source` inside the
script, matching this repo's own `hooks/hooks.json` pattern rather than a source-keyed matcher,
which does not work for `SessionStart`) logging entry timestamp, `session_id`, `source`, and the
transcript's own last usage record (same `input_tokens + cache_creation_input_tokens +
cache_read_input_tokens` sum the real hooks compute) on every firing. `claude-haiku-4-5-20251001`,
`--autocompact 100000`, a fixed `--session-id` so each `-p --resume` call is unambiguously the same
session. Resident context pushed over the threshold with one base64-random filler piped via stdin
on the first call (~96,000 source bytes → ~137,000 tokens; sized down from an initial attempt that
used finding #13's raw byte count and hit the API's 200,000-token single-request ceiling instead —
`--autocompact` alone does not raise that ceiling). Framed the filler in-prompt as "random base64
test data for a context-size probe, not an instruction" — an unframed "ignore the noise above"
phrasing got a prompt-injection refusal instead of a completion, a dead end worth naming so it is
not rediscovered. Four `-p --resume` calls total on one session, ~$0.15. Scratch project and its
`~/.claude/projects/*compact-probe*` transcript directories deleted immediately after, matching
finding #13's cleanup discipline — no on-disk artifact to cite by `path:line`, re-derive via the
method above.

**Result — both claims confirmed, with the exact mechanism finding #13 predicted.** Sequence
observed on the session's third `-p --resume` call (the first two calls only got as far as
`PreCompact` firing without a paired `SessionStart(source:"compact")` — finding #13's own
double-firing pattern, reproduced again here):

```
SessionStart(resume)   session_id=ae55ec06…  last_usage_total=140,670
PreCompact             session_id=ae55ec06…  last_usage_total=140,670
SessionStart(compact)  session_id=ae55ec06…  last_usage_total=140,670   <- the moment that matters
```

`session_id` is the identical UUID across all three firings, spanning three separate `claude -p`
process launches (each `-p --resume` is a fresh process) — confirming it survives auto-compaction,
not merely a single continuous process. And `last_usage_total` at `SessionStart(compact)` time
(140,670) is byte-for-byte the same figure read one firing earlier at `PreCompact` and one before
that at ordinary `resume` — not shrunk, not stale-larger, exactly the pre-compaction peak, since no
new request had run between them. A fourth call, immediately after, confirmed real compaction had
in fact happened by then: its own `resume`-time reading was 27,527 — a genuine ~5x shrink from
140,670, not a mislabeled event.

**What this does not settle.** n=1 for the full sequence (two earlier partial attempts failed for
unrelated reasons — see Dead ends below — and were not counted). The double-firing pattern before
the real compaction matches finding #13's n=2, now n=3 across both sessions using unrelated
methods, which is reasonable confidence it is structural rather than incidental, but still not
exhaustively characterized (whether it can chain further on a slower-growing session is still
untested, per finding #13's own caveat).

**Dead ends.**

- First attempt reused finding #13's filler-generation byte count verbatim (300,000 source bytes)
  without recomputing for a fresh probe: that tokenized to ~373,000 tokens in one message, over the
  API's flat 200,000-token single-request ceiling regardless of `--autocompact`'s window setting —
  `terminal_reason:"prompt_too_long"`, no hook fired at all. `--autocompact` bounds when the _harness_
  compacts; it does not raise what a single request may contain.
- Second attempt added a second full-size filler on the _second_ call, on top of an
  already-over-threshold first call. That drove the same `prompt_too_long` failure again, this time
  mid-compaction-attempt (`PreCompact` fired twice, no completion) — compounding two large fillers
  in successive turns overflows even a compacted prefix. The working recipe puts all the filler in
  the first call only; subsequent calls carry a bare few-word prompt and let the already-oversized
  resident context alone trigger the threshold check on entry.
- An unframed "ignore the noise above" instruction, addressed to a wall of base64 filler, produced
  a prompt-injection refusal from the model instead of a completion (haiku correctly read it as
  suspicious). Framing the filler explicitly as inert test data in the prompt itself avoided this.

### Reproduction

```
# Scratch project with .claude/settings.json:
#   PreCompact:   matcher "", command logs session_id/source/transcript's-last-usage-record
#   SessionStart: matcher "" (NOT a source-keyed matcher -- doesn't work for SessionStart),
#                 same logging, filtered on .source inside the script if needed
# head -c 96000 /dev/urandom | base64 -w0 > filler.b64   (tune this size to land near the
#   --autocompact window; finding #13's own byte count was too large for a single request)
# claude -p "<filler.b64 piped as prefix text>, framed as inert test data, not an instruction"
#   --model claude-haiku-4-5-20251001 --autocompact 100000 --session-id <fixed-uuid>
#   --output-format json
# Then repeat, same session, via:
# claude -p "<short unrelated prompt>" --model claude-haiku-4-5-20251001 --autocompact 100000
#   --resume <same-uuid> --output-format json
# ...until a SessionStart(compact) entry appears in the hook log (observed on the 3rd such call
# in this run; budget for at least that many). Delete the scratch project and its
# ~/.claude/projects/*/ transcript directory afterward.
```

---

## Finding #17, 2026-09-09 — `compact_threshold` for `claude-sonnet-5` is ≈window − 35,500 across three forced windows (100k/110k/120k), each bracketed to under ±1,400

**Question.** `CTX_COMPACT_THRESHOLD_TOKENS` is the one declaration this repo's own escape hatch
(`lib/context-economy/context-thresholds.sh:323-326`) exists for, but computing it by hand needs
`reserved_output_tokens` — "the model's own `max_output_tokens`" (line 72), which the file is
explicit is dynamic per binary and not readable from a hook (lines 67-75, 110-116). Rather than
guess at that input, this asks the question the file's own escape hatch actually cares about
directly: for `claude-sonnet-5` with a window forced down via `--autocompact`, at what resident size
does auto-compaction actually fire — and does that relationship stay linear with the window as the
window is nudged up, the way the `compact_threshold = effective_window - 13,000` model predicts?

**Method.** Same probe shape as findings #13/#16 (isolated scratch project, `PreCompact` +
`SessionStart` hooks logging `session_id`/`source`/the transcript's last usage record), but
bisecting resident size across separate cold-start sessions rather than growing one session
incrementally — each session's first `-p` call is sized with base64-random stdin filler (framed as
inert test data, per finding #13's dead-end note) to land at a target resident total, then a bare
one-line `-p --resume` call checks whether the pre-request resident already crossed the threshold
(`PreCompact` firing, or not, before the new call's own content is added). Repeated at
`--autocompact 100000`, `110000`, and `120000` — deliberately close together (not e.g. 100k vs.
1M) so that if the threshold moves by anything other than very close to the window delta itself,
that shows up clearly against each bracket's own width rather than getting lost in a wide gap.
`claude-sonnet-5` on every call, CLI 2.1.266 (newer than the 2.1.246 build the `13,000`/`3,000`
offset constants in `docs/design.md` D10 were traced against). ~19 `claude -p` calls total across
13 sessions, ≈$3–4. Scratch project and its `~/.claude/projects/*compact-probe-sonnet5*` transcript
directories deleted immediately after each window's runs, matching #13/#16's cleanup discipline —
no on-disk artifact to cite by `path:line`, re-derive via the method above.

**Result.**

```
window_source=100,000
resident (tokens)   fired?
37,035               no
53,722               no
59,545               no
61,388               no
63,084               no
65,863               yes
71,461               yes
91,987               yes
-> compact_threshold bracketed (63,084, 65,863], midpoint ≈64,474, width 2,779

window_source=110,000
resident (tokens)   fired?
70,922               no
74,572               no
78,957               yes
77,098               yes
75,438               yes
-> compact_threshold bracketed (74,572, 75,438], midpoint ≈75,005, width 866

window_source=120,000
resident (tokens)   fired?
80,516               no
82,048               no
82,968               no
83,865               yes
-> compact_threshold bracketed (82,968, 83,865], midpoint ≈83,417, width 897
```

`compact_threshold` for `claude-sonnet-5` is bracketed to **(63,084, 65,863]** at a 100k window,
**(74,572, 75,438]** at 110k, and **(82,968, 83,865]** at 120k. These three brackets are the
headline result and stand on their own: each is a direct observation of the quantity
`CTX_COMPACT_THRESHOLD_TOKENS` declares, not a computation that depends on any constant this repo
measured elsewhere.

**Roughly linear across this range, but not exactly 1:1.** Midpoint deltas: 100k→110k is +10,531
against a +10,000 window step (slope 1.05); 110k→120k is +8,412 against the same +10,000 step
(slope 0.84). Both are within the combined bracket widths of a true 1:1 slope (uncertainty ≈±0.37
and ≈±0.18 respectively), so this does not contradict the `effective_window - 13,000` fixed-offset
model — but the second gap's slope sits close enough to that uncertainty's edge that a fourth window
point (e.g. 130k or 150k) would be worth taking before treating "one token of window buys one token
of headroom" as settled over a wider range than 100k-120k.

**Secondary, more fragile: back-solving `reserved_output_tokens` at each window.** Using
`compact_threshold = min(window_source, model_window) - reserved_output_tokens - 13,000`:
`≈22,526` at 100k, `≈21,995` at 110k, `≈23,583` at 120k — a tighter spread (21,995-23,583) than the
raw bracket widths alone would demand, which is a second, independent piece of evidence the
underlying `reserved_output_tokens` really is roughly constant around **~22,000-23,600** across this
range. Still, this figure does NOT match any of the three candidate numbers reachable elsewhere: not
the `64,000` reported by `modelUsage.maxOutputTokens` in the CLI's own `-p --output-format json`
result for this model (see side finding below), not the generic `default:32000` fragment quoted in
`docs/design.md:584`'s binary-table excerpt, and not the API's advertised `128,000` `max_tokens` cap
for this model. And unlike the headline `compact_threshold` brackets, this figure inherits whatever
uncertainty the `13,000` offset carries on 2.1.266 vs. the 2.1.246 build it was traced against —
untested here. Useful as a data point, not to be treated as more solid than the direct measurements
it's derived from.

**Side finding: `modelUsage.contextWindow`/`.maxOutputTokens` are in the print-mode result, not the
transcript.** Every `-p --output-format json` call in this probe returned
`modelUsage.claude-sonnet-5.contextWindow: 1000000` and `.maxOutputTokens: 64000`, stable across all
13 sessions and all three `--autocompact` values. But `grep -c modelUsage` against the underlying
transcript `.jsonl` for one of these sessions returned `0` — the field is on the CLI's own print
summary (stdout), never written into the transcript itself. This confirms `docs/design.md`'s
existing finding that a real `PreCompact`/`Stop` hook (which only receives `transcript_path`, never
the print-mode stdout) still cannot reach this field — it does not open a new channel for a hook to
read `reserved_output_tokens` from, whatever `maxOutputTokens` itself turns out to mean.

**What this does not settle.** Each bracket is under ±1,400 tokens, not exact — a few more
bisection steps per window would tighten further at proportionally small additional cost. Only three
close-together `window_source` values (100k/110k/120k) were probed; nothing here establishes whether
the near-linear relationship holds at a much larger window (e.g. the 1M default this repo actually
declares in `context-thresholds.sh`) or whether `autoCompactWindow_source` snaps to internal buckets
somewhere between here and there. And only `claude-sonnet-5` was probed — none of this transfers to
any other model.

### Reproduction

```
# Scratch project, same hook shape as findings #13/#16 (PreCompact + SessionStart, matcher "",
# logging session_id/source/transcript's-last-usage-record).
# For each --autocompact window W being probed (100000, 110000, 120000, ...), for each candidate
# resident target R:
#   head -c <N> /dev/urandom | base64 -w0 > filler.b64   (tune N; empirically ~1.0-1.4 tokens per
#     byte of already-base64-encoded submitted content, including a short inert-test-data framing
#     line -- recalibrate from the previous session's actual resulting resident, don't assume a
#     fixed ratio)
#   (printf '<inert-test-data framing>\n\n'; cat filler.b64) |
#     claude -p --session-id <fresh-uuid> --model claude-sonnet-5 --autocompact <W>
#       --output-format json                                    # sets resident to ~R
#   claude -p "<short unrelated prompt>" --resume <same-uuid> --model claude-sonnet-5
#     --autocompact <W> --output-format json                    # triggers the entry-point check
#   # check the hook log: did PreCompact fire at this R or not?
# Bisect R between the largest "no" and smallest "yes" until the bracket is tight enough (a few
# hundred tokens is reachable in 4-5 sessions once the byte/token ratio is calibrated from the
# first probe at that window). Repeat for the next W using the previous window's bracket midpoint
# plus the window delta as the starting guess, rather than re-bisecting from scratch.
# Delete the scratch project and its ~/.claude/projects/*/ transcript directory afterward.
```

---

## Finding #18, 2026-09-14 — a single unattended `/implement-plan` turn added ~549k resident tokens, blowing past `fat_turn`'s calibrated band by more than an order of magnitude; the write trigger declined exactly as D18 predicted, on what looks like its first real firing

**Question.** D18's invariant (`docs/design.md:1000-1001`) rests on a specific claim: "since `Stop`
only observes at turn boundaries, a turn no larger than `fat_turn` cannot leap the band unseen" —
and its converse, left untested until now, is that a turn _larger_ than `fat_turn` can. Finding #15
measured the corpus's mid-session tail (`p95` 59,367, max 323,673) from turns that had already
completed and logged, flagging a survivorship gap: "a turn that grew large enough to race an actual
compaction may be underrepresented." This is that turn, caught live rather than mined after the
fact, and it asks whether the decline path (`hooks/handoff-write.sh:284-293`) actually fires the way
its comment describes when a real one happens.

**Method.** Not a designed probe — an incident, noticed live and analyzed post hoc from the
production transcript
(`~/.claude/projects/c--Users-Bart-Documents-GitHub-kendo/ca7cdaa6-c2b4-471d-8820-b32e17831b4f.jsonl`,
kendo project, session `ca7cdaa6-c2b4-471d-8820-b32e17831b4f`, 2026-09-14, `/implement-plan` on
KD-1472). Same extraction the real hooks use: `jq` over `message.usage`, resident =
`input_tokens + cache_creation_input_tokens + cache_read_input_tokens`, last record per turn.
Turn boundary confirmed two ways — every assistant record from the first API call to the Stop event
carries the identical `promptId` (`0dcedf87-473e-41fd-9137-f1234bf56176`), and the session's sole
`type:"system", subtype:"turn_duration"` record reports `messageCount:1625` for that one turn.

**Result.** The session was a single `Stop`-hook turn from cold start to completion. `/clear` at
08:43:19, `/implement-plan` invoked at 08:43:33, first API call's resident 89,885 (08:43:42, mostly
reused cache from before the clear), last API call's resident 639,367 (08:14:59 / 09:14:59), one
`Stop` event at 09:15:00.222 — the _only_ `hookName:"Stop"` record in the whole transcript.
`turn_duration` logs `durationMs:1,885,429` (~31.4 min) and `messageCount:1625` for that span.
**Single-turn delta: ~549,482 tokens** (639,367 − 89,885). Sampling the intervening per-call
`message.usage` records shows this was a smooth, monotonic climb (e.g. 288,572 → 305,320 → 313,105 →
333,553 → … → 635,263 → 636,279 → 637,715 → 639,367) — no anomalous single-call spike, just ~1,625
ordinary increments compounding with no turn boundary in between to observe any of them.

This machine's active constants (the plugin cache's `context-economy` 0.3.0 build) had `fat_turn`
locally reduced from the checked-in 60,000 to 30,000, and `authoring_turn` from 65,000 to 32,500,
with `CTX_COMPACT_THRESHOLD_TOKENS=400,000` declared via `~/.claude/settings.json`. Trigger
`= 400,000 − 2·30,000 − 32,500 = 307,500`; need at Stop `= 639,367 + 30,000 + 32,500 = 701,867 >
400,000` (ceiling). The hook declined via its `need >= ceiling` branch
(`hooks/handoff-write.sh:284-293`), reporting exactly this arithmetic
("declined to arm at 639k... single turn appears to have jumped past the 307k trigger point"). No
earlier Stop event ever ran to observe resident crossing 307,500 partway through — the turn carried
straight through the entire `[trigger, gate)` band, and the band itself (one `fat_turn` wide, 30,000
at this machine's configuration) was smaller than the single-turn delta by more than 18×.

**What this settles.** The invariant's converse, previously only reasoned about, is now observed
directly: a turn far larger than `fat_turn` does leap the `[trigger, gate)` band unseen, and the
decline path fires exactly as designed when it does — no stale handoff was produced, one loud
message was, matching `docs/design.md`'s stated preference ("the failure is one loud message and a
manual `/handoff`, never a handoff authored from a summary"). It also sharpens finding #15's own
caveat about survivorship: the corpus's mid-session max (323,673, 259 tool calls) is not a ceiling on
how large an unattended turn can get — this one ran to 1,625 messages and ~549k tokens of growth,
nearly double the entire measured corpus's max in a single instance, with nothing in `/implement-plan`
or the harness itself imposing a bound. Turn size for a "run a plan to completion" skill is not
merely heavy-tailed within finding #15's range; it is effectively unbounded, which is a different
(and harder) property than a wider percentile can fix.

**What this does not settle.** n=1 — one session, one skill (`/implement-plan`), one repo. Whether a
turn this large is a rare extreme or a recurring shape for autonomous "implement this whole plan"
skills is unmeasured; finding #15's corpus (724 mid-session turns, 48 sessions, 4 projects) contains
nothing near this size, so this single data point cannot say whether it belongs in that
distribution's tail or represents a distinct population (bounded checklist-style turns vs.
open-ended "run to completion" turns) that corpus didn't sample. The specific figures (307,500
trigger, 701,867 need) are particular to this machine's locally-edited constants and declared
ceiling, not the checked-in defaults (`fat_turn` 60,000, `authoring_turn` 65,000, ceiling 887,000) —
a different configuration would decline at different numbers, though the qualitative result (the
single-turn delta dwarfs any plausible `fat_turn` calibration) does not depend on which configuration
was active. And this incident cannot distinguish whether the fix belongs in `context-economy` at all
(a higher-frequency, non-blocking observation point) versus in the calling skill (bounding how long
`/implement-plan`-shaped work is allowed to run before yielding a turn boundary) — see the open
question this prompted in `docs/design.md`.

### Reproduction

Not a synthesized probe — re-derive from a real transcript that exhibits the same shape:

```
# Given a transcript path suspected of containing one very long turn:
jq -r 'select(.message.usage != null) | .message.usage
       | (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
         + (.cache_read_input_tokens // 0)' <transcript.jsonl>
# Diff first vs. last value between two type:"system" subtype:"turn_duration" records
# (or cold start and the first such record, for a session's opening turn) to get the
# single-turn resident delta. Cross-check messageCount/durationMs on that same record.
# Confirm the turn boundary by checking every assistant record in the span shares one promptId.
```

No script was saved — this was found by inspecting one specific incident's transcript, not by a
scan; a corpus-wide version of this query (largest single-turn resident delta per session, compared
against each session's own `fat_turn` at the time) would be the natural follow-up if this shape
turns out to recur.

---

## Finding #19, 2026-09-14 — `PostToolUse` `decision:"block"` delivers `reason` as an instruction mid-turn, folds into the same turn, and a session latch suppresses re-firing; confirmed live, and a side observation raised then refuted

**Question.** `docs/design.md` O10 (Route 5) rested on three claims reasoned from documented hook
semantics but never confirmed live: (1) `PostToolUse` returning `decision:"block"` actually delivers
`reason` to the model as something it treats as an instruction, not a passive log entry; (2) the
resulting work folds into the _same_ ongoing turn (same `promptId`) rather than the harness spawning
a fresh one, the way `Stop`'s `stop_hook_active` re-entry flag implies happens there; and (3) a
session-scoped on-disk latch (the same mechanism `hooks/handoff-write.sh` already uses) can suppress
the block from re-firing on every subsequent tool call once armed. This asks whether all three hold,
same discipline as findings #13/#16/#17: verify before trusting documentation.

**Method.** Same probe shape as those findings — isolated scratch project, `.claude/settings.json`
registering a `PostToolUse` hook (matcher `""`, fires after every tool call) — but the hook itself
carries the thing under test rather than merely logging: on first firing it writes an on-disk latch
and returns `{"decision":"block","reason":"PROBE-MARKER-7Q2: ...say the single word BANANAFISH...
then continue exactly what you were doing"}`; on every firing after the latch exists, it exits 0
silently. The `claude -p` prompt explicitly forced three separate, un-combined `Bash` tool calls
(`echo step1`/`step2`/`step3`) so the hook would fire three times in one session.
`claude-haiku-4-5-20251001`, fixed `--session-id`, `--allowedTools "Bash(echo *)"` (narrower than a
full permission bypass, which trips this harness's own "Create Unsafe Agents" auto-mode classifier —
a dead end worth naming: `--permission-mode bypassPermissions` on a nested `claude -p` call was
refused outright). A second, control run used an identical setup but a hook that only logs and
always exits 0 (never blocks), to check one incidental observation (below) for confounds — that
single control was inconclusive (see below), so a follow-up batch reran it properly: a fresh scratch
project, 7 interleaved `block`/`allow` pairs (14 `claude -p` calls total), the condition order
alternated across pairs (`block`-then-`allow` for some pairs, `allow`-then-`block` for others) so a
call-position effect couldn't masquerade as a condition effect, each trial grepping its own
transcript for `"Auto Mode Active"`/`"Exited Auto Mode"` counts. CLI 2.1.270 throughout. ~$0.45
total across both batches (16 calls). Both scratch projects and their transcript directories deleted
immediately after each batch — no on-disk artifact to cite by `path:line`, re-derive via the method
above.

**Result — all three claims confirmed.**

1. **`reason` reaches the model and is treated as an instruction.** The block rendered into the
   transcript as a `<system-reminder>` attachment immediately after the tool's own result:
   `"PostToolUse:Bash hook blocking error from command: ...: PROBE-MARKER-7Q2: before your next tool
call, say the single word BANANAFISH..."`. The model's very next output was the standalone text
   `"BANANAFISH"`, then it resumed exactly where it left off (`echo step2`). Framing matters for real
   deployment: the harness reports this as a _"hook blocking error from command"_, not a clean
   freestanding instruction — `reason` text for a real write-trigger should be worded so the model
   does not read it as "the tool call itself just failed."
2. **It folds into the same turn.** Every `user`-role record in the transcript (the real prompt and
   all three tool_results) carries the identical `promptId` — no new synthetic user turn was created
   around the block. This confirms O10's inference for `PostToolUse` specifically; `Stop`'s own
   block mechanism was not exercised here (the kendo session finding #18 mined declined rather than
   fired) and remains unconfirmed live for that hook.
3. **The on-disk latch suppresses re-firing.** The hook's own log shows it was invoked on all three
   tool calls, but the block (and the model's BANANAFISH reply) appeared only once — the second and
   third `echo` calls proceeded with no further interruption.

**A side observation, raised and then refuted by a matched-pair re-run the same day.** The first
blocking run's transcript showed a `"## Auto Mode Active"` reminder at session start and, right after
the block fired, a `"## Exited Auto Mode"` reminder — _"ask clarifying questions... rather than
making assumptions,"_ the opposite disposition from what an unattended write-trigger needs. The
control run available at the time never showed `"Auto Mode Active"` at all, so it could not isolate
cause — flagged as unconfirmed pending a matched re-run. That re-run (7 interleaved pairs, 14 calls
total, `block`/`allow` order alternated across pairs to separate the hook's effect from call
position): **`"Exited Auto Mode"` appeared in every single trial where `"Auto Mode Active"` appeared
at all — 6 of 7 — regardless of condition, including 4 of 4 non-blocking `allow` trials**, and never
appeared when `"Active"` had not. The two counts matched exactly in all 14 runs; not one trial showed
`active=1, exited=0` or the reverse. **The block does not cause the exit — refuted.** What actually
predicted whether `"Auto Mode Active"` showed up at all was call _position_ within the rapid
back-to-back sequence of nested `claude -p` calls (2nd call in a pair: active in 6/7; 1st call: active
in 2/7) — some artifact of running many nested prints in quick succession, unrelated to hooks
entirely, and out of scope for what this probe set out to answer. Not chased further; it does not
bear on Route 5.

**What this does not settle.** n=1 for the three confirmed mechanism claims (one session, three tool
calls, one model, one hook ordering) — the auto-mode question specifically was the one re-run at
higher n (14 calls) precisely because the first pass was inconclusive. Whether "folds into the same
turn" generalizes to a block fired deep into a long-running turn with many prior tool calls, rather
than the third call of a fresh session, remains untested. The call-position artifact behind
`"Auto Mode Active"`'s own appearance is unexplained and was not investigated beyond confirming it is
not the hook's doing.

### Reproduction

```
# Scratch project, .claude/settings.json: PostToolUse hook, matcher "", command:
#   on first firing: write a latch file, then
#     jq -n '{"decision":"block","reason":"<marker instruction>"}'
#   on every firing after: exit 0
# claude -p "<prompt forcing 3+ separate, uncombined tool calls>" --model claude-haiku-4-5-20251001
#   --session-id <fixed-uuid> --allowedTools "Bash(echo *)" --output-format json
# Inspect the resulting transcript: does the block's `reason` appear before the model's next
# assistant message; does the model's next output reflect it; do all user-role records (real
# prompt + tool_results) share one promptId; does a second/third tool call re-trigger the block.
#
# For the auto-mode question specifically, a single matched pair is not enough (a single control
# without "Auto Mode Active" at all isn't a valid comparison): run several interleaved block/allow
# pairs, alternating which condition goes first within each pair, and grep each transcript for
# "Auto Mode Active" / "Exited Auto Mode" counts. If the two counts move together regardless of
# condition (as found here), call position -- not the hook -- is the confound; only trust a
# block-causes-exit conclusion if exited tracks condition once active-at-start is held fixed.
# Delete the scratch project and its ~/.claude/projects/*/ transcript directory afterward.
```

---

## Finding #20, 2026-09-16 — `large_request` (the per-tool-call-round-trip resident delta Route 5 needs) is real, an order of magnitude tighter than `fat_turn`, and still 2-2.4x larger across a turn boundary than within one

**Question.** `docs/design.md` O10 (Route 5) proposes replacing `fat_turn` with `large_request` — the
max resident delta a _single_ tool-call round trip can add — as the bound a `PostToolUse`-based
write-trigger arms against, on the theory that a single round trip is plausibly an actually-bounded
quantity where finding #18 showed `fat_turn` is not. O10's second prerequisite ("measure
`large_request`'s distribution") was unmeasured; no script survived from findings #14/#15 to extend
(both say so explicitly), and O10's own pointer at tooling in `mission_control` turned out not to
exist there either.

**Method.** `tools/measure-large-request.js`, new. Same corpus as findings #14/#15/#18 (this repo,
`kendo`, `kendo-2`, `mission-control`), every transcript found (47 sessions; the per-project cap this
tool also supports made no measurable difference here — the corpus is small enough that "top 12 by
size" is close to "everything"). Per transcript: dedupe assistant records by `requestId` (finding
#14's own trap — the object is identical across every line sharing an id, so first-vs-last occurrence
doesn't matter, only avoiding double-counting does); keep only assistant responses containing at
least one `tool_use` block, since a response with no tool call is not a `PostToolUse` observation
point — the next one is wherever the next tool-call-bearing response is, however far away. Resident =
`input + cache_creation + cache_read` (never `+ output`, same as `hooks/handoff-write.sh`). Delta =
resident at one such observation point minus the previous one. Subagent transcripts excluded
(separate context, per `tools/context-audit.js`'s own trap #2/#3). Negative deltas (compaction/rewind
shrinking the prefix) counted separately and excluded from every percentile, same treatment finding
#15 gave its 2 post-compaction-boundary turns — none occurred in this sample. Each delta is tagged
`crossedTurn`: whether a real user message (a plain string, or a content array with at least one
non-`tool_result` block) intervened since the previous observation point, since that changes what the
delta actually has to cover.

**Result.**

```
                    n     min     median    p90      p95      p99       max
within-turn        449     170     1,657    7,688   11,233   19,654    55,309
cross-turn         114     681    11,959   36,485   54,514  112,265   142,188
combined           563     170     2,448   14,680   22,031   55,309   142,188
```

598 tool-call-bearing observation points collected across 47 sessions; 0 negative deltas. Every one of
the top 10 single deltas (142,188 down to 43,653) has `crossedTurn: true` except one (55,309, a `Read`)
— consistent with the cross-turn population's own median running ~7x the within-turn median: crossing
a turn boundary means the delta absorbs a whole new user message (which can itself be large — a
pasted log, a long file, a tool result quoted back) on top of one ordinary round trip, where a
within-turn delta is just the round trip alone.

**What this settles.** `large_request` is a real, substantially tighter quantity than `fat_turn` at
every percentile: even the _combined_ max (142,188) is well under half of `fat_turn`'s mid-session p95
(59,367) let alone its max (323,673, finding #15), and finding #18's ~549,482-token turn — the incident
that motivated Route 5 — dwarfs every single `large_request` observation here by 4x at the pooled max
and by 3.9x at just the cross-turn max. This is the qualitative claim O10 needed to survive contact
with data: a single tool-call round trip is nowhere near as unbounded as a whole autonomous turn, which
is exactly the gap `PostToolUse`-granularity observation is supposed to close.

**What this sharpens, and changes about the arithmetic O10 sketched.** O10's formula (`trigger =
ceiling − 2·large_request − authoring_turn`) implicitly assumed one `large_request` figure, the way
`fat_turn` was one figure. This measurement shows two populations that must not be pooled into that one
term any more than finding #15's zero-baseline and mid-session turns should be: **within-turn** deltas
(what the margin needs if `Stop` keeps observing every real turn boundary and `PostToolUse` only has to
cover the gaps _inside_ a turn — the O10 "runs alongside Stop" option) versus **combined** deltas (what
the margin needs if `PostToolUse` becomes the _only_ observation mechanism — the "replaces Stop"
option). Sizing the constant at the within-turn p99 (19,654) versus the combined max (142,188) is a
7.2x difference in the term that gets doubled in the trigger formula — not a rounding choice, a
different design decision each answering a different one of O10's still-open prerequisite-3 questions.
**So this finding does not by itself let prerequisite 3 be decided** — it supplies the two numbers that
decision has to choose between, not the choice itself.

**What this does not settle.** n=47 sessions, all ordinary interactive or `/implement-plan`-adjacent
work in four repos this account has used — nothing here specifically re-samples a session shaped like
finding #18's 1,625-message runaway turn (that turn is exactly what made _within_ it unobservable to
`Stop`, but every tool-call-bearing response inside it would still have been an ordinary `PostToolUse`
observation point with its own — presumably unremarkable — `large_request` delta; this measurement
cannot confirm that without mining #18's own transcript at this granularity, which it does not do).
Whether the cross-turn population's tail (p99 112,265, max 142,188) is itself bounded, or merely hasn't
yet produced its own finding-#18-shaped outlier, is exactly finding #15's unresolved survivorship
question one level down — this corpus only contains turns that completed normally, the same caveat
finding #14 raised about its own sample. And the tool attribution in the top-10 table is suggestive
(large deltas cluster on `Bash`/`Edit`/`Write`/`Read`, echoing finding #15's own top-10 shape) but not
causally established — the delta is attributed to whichever tool call _follows_ the growth, not
demonstrated to be its cause.

### Reproduction

```
node tools/measure-large-request.js --all
# or, matching finding #15's exact sampling (top 12 largest transcripts per project):
node tools/measure-large-request.js
```

`tools/measure-large-request.js` is new — see its header for the full method, including why a
`crossedTurn` tag matters and why negative deltas are excluded rather than pooled.

---

## Queued, 2026-09-16 — five probes for a fork-based write mechanism (not yet run)

**Context.** Raised while re-examining Route 5's staleness cost (the gap an auto-written handoff
leaves before real compaction, `2·large_request + authoring_turn`): instead of the parent session
authoring the handoff itself, the trigger could instruct it to **fork** (or spawn a backgrounded
Task) a child that inherits context and writes the handoff off the parent's own critical path,
dropping `authoring_turn` from the trigger formula entirely (`trigger = ceiling − 2·large_request`)
since the writing no longer happens in the session racing the ceiling. The child's own format
would use the existing background-task disposition pattern (F10, `docs/design.md:1502-1527`): the
handoff starts as a structured-but-mostly-empty document with a `Status` line the child rewrites to
`Complete` when done, and the post-compaction read leg is told to wait for that rather than
continue. Five things this rests on are unconfirmed and worth checking live before committing to
the mechanism, in the same discipline as findings #13/#16/#19/#20 — reasoning from documented
semantics is not the same as having fired it. Probe tooling goes in `mission_control` (`tools/`,
alongside `probe-claude-md*.js` and their shared `tools/lib/worktree-probe.js`), the usual place for
this repo's own live-harness probes, not in this repo — findings here cite it, the same pattern
`tools/measure-large-request.js` already broke from once script tooling started being kept instead
of thrown away.

**Recommended run order** (combined where one probe naturally answers two questions; #5 last since
it is a separate track, not a refinement of 1-4):

1. **(combined) Survival + spawn shape.** Does a backgrounded Task/fork spawned _before_ the
   parent's own auto-compaction keep running, and does its completion still reach/wake the _same_
   session _after_ compaction has pruned it — not merely across `/clear` (F10, confirmed) or with
   `session_id` alone surviving (finding #16, confirmed), neither of which tested a live in-flight
   background task crossing a real compaction boundary. Answered together with: should the spawn
   instruction ask for a true **fork** (inherits full context automatically, this session's own
   `Agent` tool semantics) or a plain backgrounded Task (starts fresh, needs an explicit
   self-contained prompt) — decided first because it determines what the survival probe is actually
   testing, and because it changes how cheap issuing the spawn call is (a fork needs no
   context-summarizing prompt; a fresh Task does). This is the kill-switch: if completion does not
   reliably reach the same session, the mechanism is dead regardless of the other four.
2. **Whether the child can be given a raised (or disabled) auto-compact ceiling** — `claude
--autocompact` is a real, working flag (used directly in finding #16's own probe), but nothing
   confirms the spawning mechanism (however `Agent`/Task actually launches a child under the hood)
   exposes it as a settable parameter, and the `Agent` tool's own visible parameters (`subagent_type`,
   `model`, `isolation`, `prompt`, `description`) list nothing like it. Not a strict blocker the way
   #1 is — the child forks at roughly the trigger point, which by construction still has
   `2·large_request` of headroom in front of it before the _parent's_ ceiling — but unconfirmed
   whether that leftover cushion is enough for the child's own write, or whether the child faces the
   same completion-before-compaction race the whole mechanism exists to move off the parent.
3. **Token cost of issuing the spawn call itself**, on the parent side — needed to tighten the
   trigger's remaining `2·large_request` margin the same way `large_request` itself tightened
   `fat_turn`: a fork/Task invocation is plausibly far cheaper and lower-variance than the generic
   worst-case tool call `large_request` bounds (it doesn't echo a large file back), so a
   purpose-specific bound could shrink the margin below `2·large_request`. A refinement, not a
   blocker — falls out for free from whichever of the above probes actually issues a spawn call.
4. _(folded into #1 above — listed here only because it was raised as its own question: fork vs
   plain Task.)_
5. **A different trigger entirely: `PreCompact` spawns the fork, instead of the
   `PostToolUse`/`Stop` polling trigger reaching it.** This is "Route 4" (`docs/design.md:948-952`,
   D17), previously rejected — but Route 4 evaluated running the **full authoring turn synchronously
   inside `PreCompact`**, rejected because `PreCompact` blocks the harness for as long as it runs
   with no observed timeout (finding #13: ran 65s, no kill) and no known ceiling. A `PreCompact` hook
   that only **issues an async spawn and returns** is a different, lighter variant not evaluated
   before. Its own open problem is independent of sync-vs-async: `PreCompact` can fire on a turn that
   never actually compacts (finding #13, observed twice identically — one wasted firing, then a real
   one at the same resident size), so this needs the same one-shot latch already used elsewhere, and
   it is untested whether that double-firing is always exactly one wasted firing or can chain further
   (finding #13's own open item). Kept last and separate because it changes _which hook_ triggers the
   fork, not a tightening of the `PostToolUse`/`Stop` design items 1-3 refine.

Each probe gets its own finding number (#21 onward) as it actually runs; this entry is the
pre-registration, not a substitute for them.

---

## Finding #21, 2026-09-16 — a backgrounded `Agent` spawn genuinely survives its own session's real auto-compaction and delivers a real completion notification, but NOT the specific claim the fork-based mechanism needs; two adjacent traps found along the way

**Question.** Probe #1 from the queued list above: does a background `Task`/`Agent` spawned before
the parent session's own auto-compaction keep running, and does its completion reach/wake the
_same_ session _after_ compaction has pruned it — not merely across `/clear` (F10,
`docs/design.md:1502-1527`, confirmed) and not merely `session_id` surviving alone (finding #16,
confirmed), neither of which tested a live in-flight background task crossing a real compaction
boundary. Folded in per the queued item's own note: which spawn form is actually callable at all
(`Task` vs `Agent`, vs a true "fork").

**Method.** Isolated scratch project, own `.claude/settings.json` registering a `SessionStart` hook
that logs `source`, `session_id`, and the transcript's own last usage total on every firing (same
technique as finding #16, giving hard evidence of real compaction rather than an inference).
`claude-haiku-4-5-20251001`, `--autocompact 100000`, fixed `--session-id`, ~96,000 bytes of
base64-random filler piped via **stdin** (an argv prompt that size hits "Argument list too long" on
Windows — hit this for real, switched to stdin, no such limit there) to push resident to ~109k in
one call. A background agent was then instructed to run a chain of short `sleep 10`s (a single
_leading_ sleep of 60s+ is blocked by the Bash tool's own safety rule — hit this for real too, on
the first attempt at a plain `sleep 70`) totaling ~50-80s, then write a marker file, so its
completion would fall well after the point the parent had already crossed the autocompact
threshold. Persisted as `mission_control/tools/probe-fork-survival.js` (per this repo's own
`docs/design.md` decision, `[O10](../../docs/design.md#o10)`, to keep this kind of tooling rather
than re-derive it every time) — run several times manually while debugging, then re-run clean via
the finished script itself (`node tools/probe-fork-survival.js --sleep-chain 5`) to confirm the
script reproduces the manual result, not just describes it.

**Result.**

1. **Real compaction, confirmed directly, not inferred.** The `SessionStart` hook log showed
   `source=compact` firing at essentially the same resident figure as the immediately preceding
   reading (~110k, matching finding #16's "no async gap" behaviour exactly), and the _next_ call's
   `source=resume` reading was genuinely smaller (e.g. 110,018 → 32,080 in the clean re-run) —
   real compaction, not merely a label.
2. **A background `Agent` spawned before that compaction did complete for real, and its completion
   was delivered as a genuine `<task-notification>` record in the transcript** — but the whole
   spawn→completion→delivery cycle happened _within the one originating `claude -p` process_, not
   across a process boundary. Told explicitly "reply immediately with just the task id, do not wait,
   do not poll," the CLI (not the model choosing to disobey — no polling tool call appears in the
   transcript between spawn and the notification) kept that single invocation open for the task's
   full real duration and delivered the notification into the _same_ turn before it returned. This
   was reproduced identically across four separate attempts.
3. **So the load-bearing question — does the notification survive the spawning _process_ actually
   exiting before the task finishes — is NOT cleanly answered, and what was checked pointed the
   wrong way.** A hard kill (`SIGKILL`) of the spawning process 12 seconds into an 80-second spawned
   task destroyed the in-flight work outright: the marker file it was supposed to write never
   appeared even 2+ minutes later, with no further `claude` call of any kind run in between. Whatever
   keeps a graceful `-p` call open until a task it just spawned resolves is doing real, load-bearing
   work, not a decorative wait — the background task is not independent of its own spawning CLI
   instance the way a detached OS process would be. Route 5's fork idea assumed the parent could
   spawn and move on immediately, unblocked; what was observed instead is closer to "the turn that
   spawns it does not return control until the spawn resolves or is destroyed," which is a
   materially different cost shape than assumed, if it generalizes.

**Two adjacent traps, worth keeping regardless of the mechanism's fate.** (a) The tool callable from
a live session is named **`Agent`**, resolved via `ToolSearch({query:"select:Agent"})` — the bare
name `"Task"` visible in a session's own `system/init` tool list is not directly invocable, and a
prompt that just says "use the Task tool" produces a model that gets confused between `TaskCreate`/
`TaskList`/etc. and never calls anything. (b) **`TaskOutput` is deprecated** — confirmed via a live
`deferred_tools_record` transcript attachment, and via a live call: querying it for a task whose
completion had _already_ been delivered returned `<tool_use_error>No task found with ID: ...
</tool_use_error>`, which looks exactly like "the task vanished" to a probe that doesn't know
better. The real, current delivery path is the Agent tool's own spawn result (carries an
`output_file` path) plus an unprompted later `<task-notification>` transcript record — never poll
`TaskOutput` to check on one.

**What this does not settle.** Whether a spawning turn _can_ be made to return immediately (as
literally instructed, several phrasings tried) while the task keeps running independently, and if
so whether _that_ independent survival crosses a real compaction+process boundary, is untested —
every attempt that got as far as a real spawn stayed open until the notification arrived, and the
one clean test of "the process disappears mid-task" (a hard kill) came back negative. Whether
`subagent_type:"fork"` specifically (full context inheritance, this session's own `Agent` tool
semantics) behaves any differently from the plain `"general-purpose"` type used throughout this
probe is also untested — every spawn here used `"general-purpose"`, since the immediate question
was survival/delivery mechanics, not context inheritance. n=1 machine, n=1 account/subscription
configuration; whether the "stay open until resolved" behaviour is a fixed CLI property or
configuration/version-dependent is unknown.

**Bearing on the queued probe list.** Probes #2 (child `--autocompact` override) and #3 (spawn-call
token cost) are downstream of a fork that can actually hand off control promptly — worth revisiting
scope once/if a way is found to test a genuine graceful-exit-before-completion path. Probe #5
(`PreCompact`-triggered spawn) is unaffected by this finding either way, since it changes which hook
triggers the spawn, not whether spawning itself blocks.

### Reproduction

```
node mission_control/tools/probe-fork-survival.js                    # normal path
node mission_control/tools/probe-fork-survival.js --kill-after 12     # hard-kill stress test
node mission_control/tools/probe-fork-survival.js --keep --json      # keep scratch dir + transcript, machine-readable summary
```

See the script's own header for the full method and the two traps above in more detail.

**Addendum, same day — re-run to check what the "stays open" finding above actually costs in
tokens, not just wall-clock.** The result above establishes the spawning call does not return
early; it does not say whether the parent's own resident count grows substantially while it waits,
which is the thing Route 5's trigger formula actually prices (staleness is a token quantity, not a
latency one). A clean re-run (`--sleep-chain 3`, ~30s wait) with `--json` captured the resident
figure at each step directly rather than only checking survival:

```
call1-filler (push over threshold):  resident 109,009
call2-spawn  (returns after the spawned Agent + wait resolves): resident 32,045
call3-followup (separate later call): resident 34,930
```

The `SessionStart` hook log pins why call2 comes back _lower_, not higher: `source=compact` fired
at resident 109,758 — essentially unchanged from call1 — **while call2 was still in flight**,
consistent with finding #13's already-established "compaction fires mid-request, not only between
requests" behaviour, just now confirmed to also fire while the model is mid-tool-call, blocked
waiting on a spawned agent. So in this run the parent's own token growth during the "stays open"
wait was not authoring_turn-shaped at all — real compaction happened _inside_ the blocking call and
shrank things before it returned, rather than the parent accumulating a large new delta on top of
its pre-spawn peak.

This narrows, rather than overturns, the verdict above: "the invocation does not return early" is
confirmed and real, but whether that costs Route 5 anything depends on whether it manifests as
_wall-clock unavailability_ (confirmed: the session is unresponsive for the spawn's whole duration)
or as _resident-token growth racing the ceiling_ (this one run: no, compaction absorbed it first).
n=1 for this specific angle, and the overlap between "how long the spawn took" and "when
mid-request compaction happened to fire" was a property of this run's own calibration (filler sized
to sit near the threshold, sleep-chain long enough to still be running when the next compaction
check landed) — in Route 5's actual design the spawn fires much earlier (at `ceiling −
2·large_request`), with no guarantee compaction falls inside that particular call rather than well
after it has already returned. Worth another run deliberately varying the gap between "spawn
issued" and "ceiling reached" before treating this as settled either way.

---

## Finding #22, 2026-09-16 — the parent-side token cost of issuing a spawn call, measured cleanly: ~6.7k-7.9k tokens, well under `large_request`'s within-turn p99; but the CLI's own reported `usage` field is not a safe way to measure it when a spawn happened inside the call

**Question.** Queued probe #3: the parent-side token cost of issuing the spawn call itself
(`ToolSearch` + the `Agent` tool call + receiving the completion notification back), needed to
judge whether a purpose-specific bound could shrink Route 5's trigger margin below
`2·large_request` (finding #20) the way `large_request` itself shrank `fat_turn`. Finding #21's
own addendum touched this but was confounded: real compaction happened to fire _inside_ that
run's own spawn call, so its `call1`/`call2` resident readings mix spawn cost with
compaction shrinkage and can't isolate one from the other.

**Method.** Extended `tools/probe-fork-survival.js` (new flags: `--autocompact`,
`--filler-bytes`, `--child-filler-bytes` — `tools/probe-fork-survival.js:120-122`) so the
confound can be removed directly: `--autocompact 900000` (far above anything this run's filler
can reach) keeps real compaction from ever firing, and `--filler-bytes 100` keeps call1 cheap
(it only needs to establish a session, not push resident — that was finding #21's job, not
this one's). `node tools/probe-fork-survival.js --autocompact 900000 --filler-bytes 100
--sleep-chain 1 --json`, run twice.

**Result.** Both runs: `parentCompactedBetweenCall1And2: false` (confirmed via the hooklog, not
inferred) and the SAME direction of surprise. Reading resident directly off the transcript (the
`SessionStart` hook's own tail-bounded read, matching `hooks/handoff-write.sh`'s own technique,
not the CLI's `--output-format json` result):

```
run    baseline (end of call1)   end of call2 (spawn done)   delta ("spawn cost")
A      26,028                    33,935                      7,907
B      26,372                    33,071                      6,699
```

But the script's OWN `resident(r2.usage)` — parsed from the CLI's final JSON result, the exact
figure `probe-fork-survival.js`'s `log()` helper reports and finding #21's own table used —
read **124,889 and 125,256** for the identical two calls: 3.7-3.8x the transcript-verified true
figure, with no compaction to explain the gap this time (ruled out directly, see above). Direct
inspection of the kept run's own transcript (`tools/probe-fork-survival.js`, run B kept) found
why: the completed CLI process tree, walked via `find <session-dir>/subagents/`, contains a
**separate** transcript file for the spawned child
(`<session_id>/subagents/agent-<task_id>.jsonl`, own `.meta.json` alongside it) — not
interleaved into the parent's own `.jsonl` the way a naive reading of "one session" might
suggest. The CLI's final reported `usage` field does not match either file's own last-record
resident alone; it is close to parent-resident-at-end-of-call plus a large share of what the
child itself consumed across its own several turns (its own resident peaked at ~41k, over 2-3
turns) — consistent with, though not proven to be exactly, a **sum across every API call made
during the invocation, parent's and child's combined**, not the resident-context-size-of-the-
last-request quantity `large_request`/`resident_from_transcript` both mean by "resident."

**What this settles.** The parent-side cost of issuing a spawn call and waiting for it to
resolve, measured the way it actually matters (transcript resident, the quantity Route 5's
trigger prices) rather than the CLI's own cost-accounting figure, is **~6.7k-7.9k tokens** here
— well under finding #20's within-turn `large_request` p99 (19,654) and roughly a third of its
p99 combined figure, the qualitative result probe #3 was pre-registered to look for: a
purpose-specific bound on the spawn round trip alone could plausibly tighten Route 5's margin
below the generic `large_request` bound, _if_ the mechanism's kill-switch problem (finding #21:
the call doesn't return early) is ever resolved. n=2, one machine, one `--autocompact` setting
each; not varied across model/prompt-length.

**A trap worth keeping regardless of the mechanism's fate**, alongside finding #21's two: **the
CLI's `--output-format json` result's own `usage` field is not resident, and is not safe to
treat as resident, once a spawn happened during that call** — it appears to fold in a large
share of the child's own separate consumption. Every prior probe in this queue (#20's
`large_request`, #21's own table) either didn't involve a spawn at all or cross-checked against
the `SessionStart` hook's transcript-read resident directly rather than trusting `r.usage`
alone (finding #21's own "109,758... essentially unchanged" claim came from the hooklog, not
`r2.usage`) — so nothing already published is contaminated by this, but a _future_ probe or a
real implementation that reads `claude -p --output-format json`'s own `usage` field to size a
trigger, the way it's tempting to since it's right there in the result, would be measuring the
wrong quantity the moment a spawn is involved.

**What this does not settle.** The exact aggregation rule behind the CLI's reported `usage`
(sum-of-all-calls is the best-fitting guess, not confirmed against the raw byte counts); whether
it changes with `--output-format stream-json` or the non-`-p` interactive CLI; and whether the
~7k spawn-cost figure holds up at a materially different child prompt size or `subagent_type`
(both runs used the same short instruction text and `general-purpose`).

### Reproduction

```
node tools/probe-fork-survival.js --autocompact 900000 --filler-bytes 100 --sleep-chain 1 --keep --json
# then, to see the discrepancy directly: diff the "call2-spawn" resident in the JSON summary
# against the SECOND "source=resume" line in its own hooklog (or the last message.usage record
# in <kept-scratch>/../<session_id>.jsonl) — they should match closely if no spawn happened
# inside the call, and diverge sharply (as above) when one did.
```

---

## Finding #23, 2026-09-16 — no evidence a spawned child goes through the same hooked session lifecycle as the parent at all (so there is nothing to raise or disable); an attempt to push the child's own resident near a real ceiling was blocked by an unrelated `Read`-truncation trap before it could answer the question

**Question.** Queued probe #2: can the spawned child be given a raised or disabled
auto-compact ceiling? The `Agent` tool's own schema (`subagent_type`, `description`, `prompt`,
`model`, `isolation`) already showed no such parameter by inspection (the dead end recorded in
the prior handoff); this probe was meant to go further and check live whether the child
undergoes _any_ compaction-relevant lifecycle event at all, and if so at what size.

**Method.** Same extension to `tools/probe-fork-survival.js` as finding #22, plus
`--child-filler-bytes` (`tools/probe-fork-survival.js:263-269`): writes a filler file the
spawned child is instructed to read via the `Read` tool before running its sleep chain,
independent of the parent's own `--filler-bytes`. The shared `.claude/settings.json` now
registers `PreCompact` alongside `SessionStart` on the SAME hook script
(`tools/probe-fork-survival.js:230-237`), tagging each line with its own `hook_event_name` and
`session_id`, so a child that fired either event under a _different_ `session_id` would show up
as a `foreignSessionLines` entry distinct from the parent's own fixed session id. Two runs:
`--child-filler-bytes 72000` then `--child-filler-bytes 115000` (both with `--autocompact 900000
--filler-bytes 100 --sleep-chain 1 --keep --json`, to isolate the child-only question from
finding #22's own concerns).

**Result.**

1. **`foreignSessionLines` was empty in both runs — no `SessionStart` or `PreCompact` fired
   under any session_id but the parent's, no matter the child's own filler size.** The spawned
   child's own transcript exists (confirmed directly: `<session_id>/subagents/agent-
<task_id>.jsonl`, a real file, per finding #22's own discovery) but nothing about creating or
   growing it triggered the project's registered hooks the way the top-level session's own
   lifecycle does. This is consistent with the child not being a `claude` CLI process going
   through the same session-lifecycle event system at all (it has no visible `--autocompact`
   flag to set because it may not be the kind of thing `--autocompact` even applies to), though
   this probe cannot rule out "it does go through that lifecycle but hooks aren't wired to fire
   for subagent-scoped events" as an alternative explanation — only that, whichever is true,
   there is no hook-visible signal to build a raised-ceiling mechanism against.
2. **The intended stress (push the child's own resident near a real context-window ceiling)
   did not work, for an unrelated, worth-keeping reason.** Both runs' child transcripts peaked
   at essentially the SAME resident (~41,106-41,372) regardless of whether the filler file was
   72,000 or 115,000 bytes. Direct inspection (`jq` over the child's own `.jsonl`, filtering
   `.type=="user"` tool_result content, measuring string length) found why: the `Read` tool's
   returned content topped out at **24,696 characters** in both runs, against source files of
   96,000 and ~154,000 base64 characters respectively — a real, size-independent truncation
   ceiling on a single `Read` call's returned content (**not** a per-line truncation: the filler
   was rewritten with 200-character line breaks — `makeFillerFile()`,
   `tools/probe-fork-survival.js:206-217` — specifically to rule that out after the first probe
   run showed identical truncation against a single-line, ~96,000-char file).
3. Both children completed their task normally (marker written, `DONE`/completion reported,
   `<task-notification>` delivered) at this size — no context-overflow error observed, but this
   says nothing about a real ceiling since the actual content that reached the child never grew
   past ~41k resident regardless of what was asked for.

**What this settles.** No live-visible mechanism (hook-based or flag-based) exists to detect,
let alone raise or disable, a compaction ceiling for a spawned child — consistent with, and now
somewhat strengthened by live evidence beyond, the dead end already recorded from schema
inspection alone. If Route 5's fork idea is ever revisited, "assume the child inherits the
parent's ceiling with no override available" is the safer default than assuming otherwise.

**What this does not settle — the actual probe #2 question is still open.** Whether a child
genuinely CAN be pushed toward a real context-window ceiling (and what happens there — silent
truncation, a hard error, or something else) was not answered; the attempt here was blocked by
the `Read`-truncation trap before it could reach a size worth calling a stress test. Reaching one
would need a different content channel — several smaller `Read` calls across separate files
(each under whatever the per-call cap actually is, unmeasured beyond "at least 24,696
characters get through"), a `Bash`-piped read instead of `Read`, or a multi-turn child
conversation that accumulates size turn over turn rather than in one call. Not attempted here:
per finding #21's own "Bearing on the queued probe list" note, probe #2 is downstream of a fork
that can actually hand off control promptly, which finding #21 already showed this mechanism
cannot do — so this was pursued for completeness (per this session's own explicit instruction
to carry out the queued probes) rather than because closing it changes Route 5's current
disposition.

### Reproduction

```
node tools/probe-fork-survival.js --autocompact 900000 --filler-bytes 100 --child-filler-bytes 115000 --sleep-chain 1 --keep --json
# then inspect the child's own transcript directly:
# find <kept-scratch's transcript project dir>/<session_id>/subagents -name '*.jsonl'
# jq -r 'select(.type=="user") | .message.content[]? | select(.type=="tool_result") | (.content | if type=="string" then . else (.[0].text // "") end) | length' <that file>
```

---

## Finding #24, 2026-09-16 — a `PreCompact` hook that only issues an async, detached spawn and returns does NOT block the harness (contrast Route 4's rejected synchronous form), and the detached work survives even the outer process tree being force-killed shortly after

**Question.** Queued probe #5: is "Route 4, lighter variant" — a `PreCompact` hook that issues
an async spawn and returns, instead of running the full authoring turn synchronously inside the
hook (the already-rejected form, `docs/design.md` D17, confirmed blocking 65s+ with no observed
ceiling, finding #13) — actually non-blocking in practice, and does the detached background work
it starts survive independent of the hook script's own short-lived process? Independent of
whether the `PostToolUse`/`Stop`-polling-based fork idea (probes #1-#3 above) is viable at all —
this changes _which hook_ triggers a spawn, not whether spawning itself blocks (finding #21's own
note).

**Method.** New script, `tools/probe-precompact-async-spawn.js` (mirrors finding #13's own
convention: isolated scratch project, `PreCompact` + `SessionStart` hooks that timestamp and
log, base64 filler over stdin to cross `--autocompact`). The `PreCompact` hook
(`tools/probe-precompact-async-spawn.js:168-182`) checks a one-shot latch file; on first firing,
backgrounds `sleep <N> && echo ASYNC_DONE > marker` via `nohup ... & disown` and returns
immediately; on any later firing this session, logs `SKIPPED` and returns immediately too — the
same one-shot-latch pattern `docs/design.md` D17/D18 already use for the real write trigger.
Deliberately reuses this repo's own established, unavoidable workaround
(`tools/lib/worktree-probe.js`'s own header: `claude -p --output-format json` does not exit on
its own from a scripted spawn here, confirmed across four spawn strategies) rather than treating
it as a stress-test option the way `probe-fork-survival.js --kill-after` does: watch stdout for
the final parseable JSON, then `taskkill /T /F` the whole tree — meaning survival past that kill
is what "normal" looks like for these scripts, not an extra stress condition, and is if anything
a HARDER bar than real production (where the top-level session process doesn't exit at this
point at all — it keeps running into `SessionStart(source:compact)`). `claude -p` (filler,
`--autocompact 100000`) then `claude -p -c` (trivial "reply CONTINUE" prompt, to let
`PreCompact` fire on its own), then a wait (`--post-call2-wait`, default async-sleep+15s) with
NO further `claude` call before checking ground truth. Two runs (`--async-sleep 20` and `25`).

**Result, both runs identical in every qualitative respect:**

```
                                run 1        run 2
PreCompact firings              2            2       (finding #13's double-firing pattern, reproduced)
  - SPAWNED                     1            1
  - SKIPPED                     1            1       (one-shot latch correctly absorbed the wasted firing)
hook entry->exit elapsed        33ms, 18ms   39ms, 13ms   (both firings, both runs -- not 65s+)
SessionStart(source=compact)    seen         seen
whole call2 wall-clock          5,082ms      4,561ms
marker on disk after outer      TRUE         TRUE
  kill + full wait, no further
  claude call
```

1. **The hook itself returns near-instantly on both the wasted and the real firing** (13-39ms
   entry-to-exit both runs) — categorically different from Route 4's confirmed 65s+ synchronous
   block. The WHOLE `-p -c` invocation containing both `PreCompact` firings and the real
   `SessionStart(source:compact)` completed in ~4.6-5.1 seconds total.
2. **The one-shot latch correctly absorbed finding #13's double-firing pattern**: exactly one
   spawn, not two, despite `PreCompact` firing twice per real compaction, identically to finding
   #13's own n=2 observation.
3. **The detached background task survived the outer process tree being force-killed.** In both
   runs, the outer kill happened ~4.5-5s after `PreCompact`'s first (spawning) firing, well
   before the async task's own 20s/25s sleep had elapsed — so the marker file, confirmed present
   only after the FULL wait with no further `claude` call, could only have been written by a
   process that kept running after its own great-grandparent process tree had already been torn
   down by `taskkill /T /F`. This is the opposite result from finding #21's Agent-tool-based
   probe #1, where a hard kill of the spawning process destroyed the in-flight background work
   outright — the mechanics are different enough (a plain OS-level backgrounded shell process
   launched from a short-lived hook script, vs. an `Agent`-tool subagent tied to its spawning
   CLI invocation) that the two findings do not contradict each other; if anything this is
   suggestive of _why_ they differ: by the time the outer kill happens here, the hook's own
   `bash.exe` instance (the immediate parent Windows would need for `taskkill /T`'s tree-walk to
   reach the detached grandchild) has itself already exited, breaking the parent-child chain
   `taskkill` walks — untested directly, offered as the likely mechanism, not confirmed.

**What this settles.** The core premise of "Route 4, lighter variant" holds up live, twice: a
`PreCompact` hook CAN issue background work and return without blocking the harness, and that
work CAN survive independent of both the hook's own process and (a stronger test than needed)
the whole outer `claude -p` process tree being killed shortly after. This directly undercuts
Route 4's original rejection reason (blocking, no ceiling) for THIS variant specifically — the
async form was not evaluated before (D17 only rejected the synchronous form) and this is now a
live-confirmed, not just reasoned, candidate.

**What this does not settle.** This tests OS-level process survival, not delivery of a
completion signal back to a live, continuing interactive session the way finding #21's
`<task-notification>` mechanism does for the `Agent`-tool route — a `PreCompact`-hook-spawned
background process has no equivalent built-in notification path back into the transcript; it
would need to write something (a file, a sidecar) that a LATER hook firing reads, which is
exactly the read-leg pattern D17 already uses for the synchronous case and should carry over
unchanged, but that carry-over itself is untested here. n=2, one machine, `--autocompact 100000`
only, `sleep`-based dummy work only (not a real handoff-authoring turn) — whether a _real_
authoring turn can itself be backgrounded this way (as opposed to a trivial shell command) is a
materially different, unanswered question: the real work Route 5 would want to background is an
LLM turn, not a shell script, and nothing here establishes that an LLM turn can be started
detached from a hook in the first place (the `Agent` tool is the only demonstrated way to start
one, and finding #21 already showed that route blocks). This finding shows the _hook_ half
works; it does not show the _what gets spawned_ half does.

### Reproduction

```
node tools/probe-precompact-async-spawn.js --async-sleep 20 --keep --json
node tools/probe-precompact-async-spawn.js --async-sleep 25 --json
```

See the script's own header for the full method and the reasoning behind treating the outer
process kill as "normal," not a stress-test flag.

---

**Bearing on Route 5's fork idea, all five queued probes now run (#21-#24; #4 was folded into
#21).** Not itself a Decision — that call is left open, this is a summary of where the live
evidence now stands so it isn't scattered across four findings.

- The `PostToolUse`/`Stop`-trigger-spawns-an-`Agent` route (probes #1, #2, #3 — findings #21,
  #23, #22) is **effectively closed for now**, not on the ceiling/cost questions it was designed
  to answer but on its own kill-switch: finding #21 already showed the spawning call does not
  hand off control early, so probes #2 and #3's own refinements (child ceiling, spawn-call
  cost) matter only if that kill-switch problem is separately solved. Both were still run to
  completion this session and both landed clean, reusable findings in their own right (#22's
  CLI-`usage`-field trap, #23's `Read`-truncation trap, and #22's actual "~7k tokens" spawn-cost
  figure, ready to use if the kill-switch problem is ever resolved) — but neither changes this
  route's current disposition.
- **The `PreCompact`-triggers-a-detached-spawn route (probe #5, finding #24) is the one live
  result that came back positive**, and on a different mechanism than the `Agent`-tool route
  entirely (an OS-level detached shell process from a hook script, not a harness-tracked
  subagent) — so it does not inherit probe #1's kill-switch problem. It answers "can the hook
  half of this work at all" cleanly (yes, twice, non-blocking, latch-correct, survives an outer
  kill). It does **not** yet answer "can the thing Route 5 actually needs to background — an
  LLM turn that writes a real handoff — be started this way at all," since the `Agent` tool is
  the only demonstrated way to start a backgroundable LLM turn and finding #21 already showed
  that route blocks. Closing that gap (can a `PreCompact` hook's `block`-style output, the same
  mechanism [O10](../../docs/design.md#o10) already validated for `PostToolUse`, get a _later_
  hook or read-leg to pick up and complete an authoring turn asynchronously, without going
  through the `Agent` tool at all) is the natural next probe if this route is picked back up —
  not queued as one of the original five, since it only became askable once #24 closed out #5.

---

## Finding #25, 2026-09-16 — `SessionStart(source:"compact")` can block the harness for a full 65s polling a file, same as `PreCompact` (finding #13): no observed cutoff, and the harness correctly withholds the model's response until the hook resolves, then proceeds normally

**Question.** Raised directly by finding #24's own "what this does not settle": the read-leg
design already decided on (the async writer rewrites a `Status` field on disk; the read leg —
`SessionStart(source:"compact")`, the hook D17 already dispatches on — polls for `Status:
Complete` rather than reading once, since finding #24's own timing showed real compaction can
land well before a real authoring turn would finish) needs `SessionStart` itself to be able to
block for a nontrivial duration. Finding #13 already answered this exact shape of question for
`PreCompact` (65s+, no observed kill, no known ceiling) — this asks the same question of
`SessionStart` specifically, never tested for blocking duration before.

**Method.** Mirrors finding #13's own method exactly, hook swapped. New script,
`tools/probe-sessionstart-compact-block.js`: isolated scratch project, `PreCompact` hook is
log-only (real compaction should proceed unimpeded, not be re-tested), `SessionStart` hook
(`tools/probe-sessionstart-compact-block.js:156-166`) checks `source` — anything but `"compact"`
returns immediately (so `startup`/`resume` firings stay fast and don't confound timing); on
`"compact"` it polls, once per second, for a marker file that is **deliberately never created**,
up to `--poll-seconds` (default 65, matching finding #13's own chosen figure, past the
commonly-cited ~60s hook-default), logging iteration count and elapsed time either way. `claude
-p` (filler, `--autocompact 100000`) then `claude -p -c` (trivial prompt) then a third `-p -c`,
each script-side call's own timeout raised well past `--poll-seconds` so the script's own
timeout can't be what cuts things off.

**Result.** One run, `--poll-seconds 65`. Direct transcript inspection (`jq` over the kept
session's own `.jsonl`, timestamps plus each `user`/`assistant` record's role and first content
block) gives the real sequence, which split differently across the two `-c` calls than the
script's own per-call token/resident accounting first suggested — worth stating plainly since it
took cross-checking the raw transcript to see: call2 (`"Reply with just the word CONTINUE"`)
completed normally and fast (prompt 13:37:41.689 → response 13:37:42.971, ~1.3s), landing
between the session crossing the `--autocompact` threshold and only the FIRST, _wasted_
`PreCompact` firing (finding #13's own "fires once with no compaction behind it" pattern) — no
compaction happened during call2 at all. Call3 (`"Reply with just the word CHECK"`) is the one
that actually hit real compaction: its own prompt landed at 13:37:46.393, the SECOND (real)
`PreCompact` fired right after (13:37:46.461), a synthetic `"This session is being continued
from a previous conversation..."` summary user-turn was inserted at 13:38:01.939 (direct,
unambiguous evidence of real compaction, not merely a source label), the compact-triggered
`SessionStart` hook then polled the full **65 of 65 requested iterations** (entry 13:38:02.254 →
exit 13:39:08.565, marker never appeared, exactly as configured) with **no cutoff, no kill, no
truncated iteration count** — and only _after_ that hook exited did call3's real response
(`"CHECK"`) finally land, at 13:39:10.431 — call3's own measured wall-clock (87,529ms) matches
this span almost exactly. The harness produced a normal, correct final response; nothing errored
or hung indefinitely.

**What this settles.** `SessionStart(source:"compact")` can block for at least 65 seconds with
no observed ceiling, exactly mirroring finding #13's result for `PreCompact` — the
`~60s-hook-default` figure is not a real ceiling here either. More directly useful than the
duration number itself: **the harness genuinely gates the model's response on the hook
resolving** (the "CHECK" reply did not land until 2s after the hook's own logged exit,
consistent D17's existing reliance on `SessionStart(compact)` running synchronously, now shown to
hold even under a long block, not just the near-instant reads D17 was built around) — so a
Status-field-poll read-leg, the design this probe was raised to de-risk, is viable on the
mechanism this repo already has: no new hook, no new trigger, the same one D17 dispatches on
today.

**What this does not settle.** n=1, one fixed duration (65s), one machine — same epistemic scope
finding #13 itself claimed for the identical question asked of `PreCompact` ("no attempt was made
to find where a real ceiling starts, only that 65s is under it"). Whether a materially longer poll
(the actual worst case: a full authoring turn, finding #14's 13.7k-64.6k tokens, plausibly tens of
seconds to a few minutes wall-clock) stays uncut is untested — but note what this is NOT about:
the poll loop (`tools/probe-sessionstart-compact-block.js:159`) is already `sleep 1` in a
`while` loop, i.e. already a chain of short sleeps, not one long blocking call, so this has
nothing to do with the Bash-**tool**'s own leading-sleep-over-60s guardrail (finding #21) — that
guardrail sits in front of a model's own tool calls inside an agentic turn and doesn't apply to a
hook's plain shell command at all, wrong subsystem entirely. Since every loop iteration here is
identical, there is no structural reason a longer run would get cut differently than this one
wasn't; the only way it plausibly could is a harness-level wall-clock ceiling on TOTAL hook
execution, independent of internal loop granularity — a real, different, still-untested question,
not a sleep-chaining one. Low-priority given the design direction already agreed: a real
implementation would poll with its own bounded timeout (D17's existing "likely-undocumented"
fallback covers the case it's exceeded), so the exact ceiling — if one exists at all — only
matters insofar as the chosen timeout needs to sit under it, and 65s-with-no-cutoff already
supports a modest bound (order 90-120s) with reasonable confidence. Separately: whether polling
every 1s (versus a longer interval) matters to any ceiling that does exist elsewhere is untested.
And this probe's own script initially _looked_ like it had a measurement bug (call2's
script-reported wall-clock, 4,687ms, seemed wildly inconsistent with the hook's own 65s+ block)
until cross-checked against the raw transcript directly — worth flagging as a trap in its own
right: **when a hook-driven turn can split unpredictably across which physical `-c` invocation
ends up "wearing" a long block** (here: the wasted `PreCompact` landed on call2, the real one and
the resulting block landed on call3, one invocation later than finding #13's own framing put it),
a script's own per-call bookkeeping can look self-contradictory even though nothing is actually
wrong — the transcript's own absolute timestamps are the ground truth to reconcile against, not
which call a script attributed a given hook firing to.

### Reproduction

```
node tools/probe-sessionstart-compact-block.js --poll-seconds 65 --keep --json
# then cross-check against the raw transcript directly, not just the script's own per-call
# summary, exactly as this finding's own method required:
# jq -r 'select(.type=="user" or .type=="assistant") | [.timestamp, .type, .message.role,
#   (if .type=="assistant" then (.message.content[0].text // .message.content[0].type // "?")
#    else (if (.message.content|type)=="string" then .message.content
#          else (.message.content[0].type // "?") end) end)] | @tsv' <session>.jsonl
```

---

## Finding #26, 2026-09-16 — a `PreCompact` hook CAN start a real `claude -p` authoring turn via a detached OS-level spawn, entirely without the `Agent` tool: it completes in ~5s, exits cleanly on its own (rc=0, no forced kill needed), and produces genuine on-topic content

**Question.** The single remaining unknown the predecessor handoff (key
`context-economy-main-3033326a`) designated as THE next step, above every other open thread:
finding #24 showed a `PreCompact` hook can issue a detached, OS-level background spawn and
return near-instantly, surviving independent of the hook's own process and even the outer
process tree being killed — but the spawned "work" there was a dummy shell `sleep`, never a real
LLM turn. The `Agent` tool is the only previously-demonstrated way to start a backgroundable LLM
turn, and finding #21 already showed that route blocks (the spawning call doesn't hand off
control early). So: can the _same_ detached-spawn mechanism start a REAL `claude -p` authoring
turn — actual model inference over a prompt, not a shell command — with no `Agent` tool involved
at all?

**Method.** New script, `tools/probe-precompact-real-turn.js`, combining finding #24's
detached-spawn `PreCompact` hook with finding #25's polling `SessionStart(source:"compact")`
read leg, changing WHAT gets spawned. The one-shot-latched `PreCompact` hook backgrounds
`tools/probe-precompact-real-turn.js`'s own `async_turn.sh` (written per-run into the scratch
project), which runs `timeout 80 "$CLAUDE_ABS_PATH" -p "In exactly one sentence, state the
primary purpose of a PreCompact hook in Claude Code." --model claude-haiku-4-5-20251001
--output-format json`, then writes `Status: Complete|Failed rc=... start=... end=...` to a status
file — the same `Status` field name the read-leg design (`docs/design.md` D17) already uses.
Two deliberate departures from every prior probe's `claude -p` invocation, both explained under
**What this does not settle**: the prompt is passed as a CLI argument, not piped over stdin, and
`claude`'s absolute path (`bash -lc 'which claude'`, resolved once at script start) is used
instead of a bare name, since the hook's own spawning context was untested for PATH resolution.
`SessionStart(source:"compact")` polls the status file for a non-`"Running"` value up to
`--poll-seconds` (100, comfortably past the 80s inner timeout), mirroring finding #25's loop
exactly. Two runs, default flags.

**Result, both runs:**

```
                                    run 1                          run 2
PreCompact firings                 2 (1 spawned, 1 skipped)        1 (1 spawned, 0 skipped)
detached claude -p call            rc=0, 13:57:41.840->13:57:47.215 rc=0, 13:58:54.936->13:58:59.721
                                    (~5.4s)                        (~4.8s)
real result text                   "A PreCompact hook executes    "A PreCompact hook runs before
                                    before the conversation        Claude Code automatically
                                    context is compressed,         compresses the conversation
                                    allowing you to save state,    context, allowing you to save
                                    create handoffs, or persist    work or clean up state before
                                    information that would         the summary occurs."
                                    otherwise be lost..."
real cost / tokens                 $0.012289, 218 output          $0.011824, 125 output
                                    (174 thinking)                 (89 thinking)
SessionStart(compact) fired?       yes, 13:58:03.906 (~16.7s      no — real compaction did not
                                    after the detached call had    land within this run's 3-call
                                    already finished)               window at all (finding #13's
                                                                     own noted variability)
SessionStart(compact) poll         0 (Status was already          n/a
iterations needed                  "Complete" when it started
                                    polling)
```

1. **A genuinely real, on-topic LLM turn ran to completion, started entirely from a `PreCompact`
   hook's detached spawn, with no `Agent` tool anywhere in the path.** Both runs' result text is
   substantive, on-topic, and phrased differently between runs (not a cached or canned string) —
   confirmed by real `total_cost_usd` and token usage in each run's captured `--output-format
json`, including genuine thinking tokens. This directly answers the designated question: yes.
2. **The detached `claude -p` call exited cleanly on its own both times** — `rc=0` in both runs,
   meaning the `timeout 80` wrapper never had to fire. This contrasts with the existing,
   established trap (`tools/lib/worktree-probe.js`'s own header, reused by every earlier probe in
   this series including finding #24's own predecessor script): `claude -p --output-format json`
   does not exit on its own when spawned from a plain Node `child_process` with piped stdio,
   which is why every other probe in this repo watches stdout for the final JSON and then force-
   kills the tree. This probe's spawn shape differs in two ways from that established pattern —
   the prompt is passed as a CLI argument rather than piped over stdin, and the process is
   launched from a detached bash script (real file-redirected stdout/stderr, no Node-owned pipe
   handles) rather than from Node's own `child_process.spawn`. Either or both are a plausible
   explanation for the clean exit; not root-caused here, offered as the likely mechanism only.
3. **The one-shot latch and double-firing pattern behaved exactly as finding #24 already
   established** (run 1: fired twice, correctly absorbed to one spawn; run 2: fired only once) —
   no new behavior here, just a second confirmation on a different payload shape.
4. **In run 1, the real turn finished (~5.4s) well before real compaction happened at all**
   (`SessionStart(source:"compact")` didn't fire until ~16.7s after the detached call had already
   written `Status: Complete`) — so the read-leg's poll loop found the answer already sitting
   there and needed zero iterations. This is the best-case timing for the design (finding #24's
   own worry: real compaction can land before a real authoring turn finishes), not yet a test of
   the worse case where the read leg actually has to wait.

**What this settles.** The core premise the handoff named as the single remaining unknown: a
`PreCompact` hook's detached-spawn mechanism (finding #24) CAN start a real, model-generated
authoring turn, not just a shell command, with no `Agent` tool in the path at all — n=2, both
clean. Combined with finding #25 (the read-leg can block long enough to wait for one) and finding
#24 (the hook itself doesn't block and the spawn survives independent of the outer process), the
three pieces of Route 5's fork idea that were each open before this session now each have a live,
positive result on their own terms.

**What this does not settle.** Both runs used a trivial, single-sentence generation prompt
(~125-218 output tokens) — far smaller than a real handoff-authoring turn (finding #14's corpus:
13.7k-64.6k tokens, plausibly tens of seconds to a few minutes). Whether a real, much larger
authoring turn still exits cleanly on its own from this exact spawn shape, and still completes
within a plausible real-compaction window, is untested — a bigger turn is a materially different
question than a bigger `sleep`. **No tool use was tested inside the detached turn** — this probe
only exercised plain text generation; a real handoff-authoring turn needs at minimum a `Write`
call to produce the handoff file, and whether a headless, detached `claude -p` invocation can use
tools at all in this spawn shape (permission prompts, `--dangerously-skip-permissions` or an
allowlist, MCP server startup inside a detached background process) is a wholly separate,
unaddressed question. The clean-exit contrast with the established Node-child_process trap
(point 2 above) is offered as a plausible mechanism, not confirmed — no probe here isolated the
stdin-pipe-vs-argv variable from the Node-spawn-vs-detached-bash variable to say which one (or
both) actually matters. n=2, one machine, one prompt, `--autocompact 100000` only, and the
read-leg's actual _wait_ behavior (point 4) is n=1, not n=2 — run 2's real compaction never
landed within the probe's own call window at all, consistent with finding #13's already-
documented variability, not a new problem.

### Reproduction

```
node tools/probe-precompact-real-turn.js --keep --json
node tools/probe-precompact-real-turn.js --json
# then inspect the kept run's own artifacts directly:
# cat <scratch>/status.txt
# cat <scratch>/async_turn.out.json | jq -r .result
# cat <scratch>/hooklog.jsonl
```

---

**Bearing on Route 5's fork idea, updated.** The gap the prior synthesis (above, before finding
#25) named as "the natural next probe if this route is picked back up" — can a `PreCompact`
hook's detached spawn start a real authoring turn at all, without the `Agent` tool — is now
closed, positively, by this finding. Not a Decision: whether Route 5's fork idea gets built, and
in what shape, is still explicitly left open for a future session, now with all three of its load-
bearing mechanism questions (hook non-blocking + spawn survival, read-leg blocking duration, and
now real-turn spawning) answered live rather than just reasoned about. The two things a future
design session would still need before treating this as implementation-ready are named above
under **What this does not settle**: a real (not trivial) authoring turn's behavior in this spawn
shape, and whether the detached turn can use tools at all.

---

## Finding #27, 2026-09-16 — the detached `PreCompact`-spawned turn CAN execute the actual operation Route 5 needs: `Write`-ing a real handoff-shaped file, under least-privilege `--allowedTools Write` — but it draws from the SAME account usage budget as the interactive session, and can fail outright (immediate `api_error`, zero tokens spent) if that budget is exhausted

**Question.** Direct follow-up to finding #26, narrowed at the user's own suggestion: rather than
probe generic tool use, test the actual thing Route 5's fork idea needs to do — can the detached,
`PreCompact`-spawned `claude -p` turn (finding #26's mechanism) use the `Write` tool to produce a
real handoff-shaped file, under the least-privilege permission configuration a real production
hook would actually want to ship (`--allowedTools Write`, not `--dangerously-skip-permissions`)?

**Method.** New script, `tools/probe-precompact-write-turn.js`, reusing finding #26's
detached-spawn `PreCompact` hook and `Status`-file convention unchanged. The payload prompt
instructs the model to use the `Write` tool to create a two-section handoff-shaped markdown file
(a one-paragraph summary plus a `## Next` section listing one item) at a known path, then reply
`DONE`. Three permission configurations are supported via `--allow-mode`
(`scoped`/`acceptEdits`/`skip`); this run used the default, `scoped` — `--allowedTools Write`
only, nothing broader. Ground truth is the file's actual presence and content on disk, not the
model's claimed success in its text reply — a model can say DONE without the tool call having
landed. Two runs.

**Result.**

Run 1: `rc=0`, ~7.9s wall clock (`$0.0239`, 415 output tokens incl. 179 thinking),
`permission_denials: []`, and the handoff file WAS written with genuine, on-topic, correctly-
shaped content:

```
# Handoff: Migration of Authentication Service

We've completed the refactoring of the legacy authentication middleware to use the new OAuth2
provider. ...

## Next

Coordinate with the DevOps team to schedule the production deployment for Thursday morning, ...
```

`resultText: "DONE"`.

Run 2: `rc=1`, ~1.9s wall clock, `total_cost_usd: 0`, every `usage` field zero,
`terminal_reason: "api_error"`, `resultText: "You've hit your session limit · resets 6pm
(Europe/Amsterdam)"`. The handoff file was NOT written. `permission_denials: []` here too — this
was not a permission failure; the call never reached the model at all.

**What this settles.** On the run that actually reached the model, the detached,
`PreCompact`-spawned turn CAN use the `Write` tool under least-privilege `--allowedTools Write` —
no permission prompt, no hang, no denial — and produce a real, correctly-shaped handoff file on
disk. This closes the "can it use tools at all" gap finding #26 left open, specifically for the
actual operation Route 5 needs, not tool use in the abstract, and specifically under the
scoped permission configuration a real implementation would actually ship (not the broader
`--dangerously-skip-permissions` escape hatch).

**What this does not settle, and a new consideration raised by run 2.** n=1 for the success case,
not n=2 — run 2 failed before reaching the model at all, for a reason unrelated to the mechanism
under test: this machine's account-level usage cap was hit between the two runs, plausibly driven
by this session's own extensive probing today (findings #21-#27 collectively represent many real
`claude -p` invocations) compounding with the live interactive session's own usage. This is itself
a real, load-bearing fact for Route 5's design, not just a probe artifact: **a detached background
authoring turn draws from the SAME account usage budget as the interactive session it is meant to
serve**, and can fail outright — not hang, not silently degrade, an immediate `api_error` with
zero tokens spent — if that budget is exhausted. A production implementation would need to treat
this as a real failure mode of the async writer, distinct from [D17](../../docs/design.md#d17)'s
existing "likely-undocumented" timeout fallback (which covers the read leg giving up after a
bounded wait, not the writer never having started at all) — a read-leg poll that never sees
`Status: Complete` because the writer never got scheduled by the API is indistinguishable, from
the read leg's own vantage point, from a writer that is merely slow, so this doesn't invalidate
[D17](../../docs/design.md#d17)'s fallback design, it just means the fallback needs to cover this
cause too, not only slowness. Separately, still open from finding #26: whether a much larger,
real-sized authoring turn (not a trivial two-paragraph stand-in) behaves the same way in this
exact spawn shape. No further runs attempted this session given the account-level limit; re-run
after the stated reset if more confirmation of the success case is wanted.

User note: Run 2 failed because it hit the session limit. Somehow the parent session was still
able to author this paragraph above before also hitting the session limit.

### Reproduction

```
node tools/probe-precompact-write-turn.js --keep --json
node tools/probe-precompact-write-turn.js --json
# inspect directly:
# cat <scratch>/handoff-output.md
# cat <scratch>/async_turn.out.json | jq '.total_cost_usd, .terminal_reason, .permission_denials'
```

---

**Bearing on Route 5's fork idea, updated again.** Of the two things the prior update (above)
named as still needed before treating this route as implementation-ready, one is now closed with
a caveat: the detached turn CAN use `Write` under least-privilege permissions (n=1, clean) — the
caveat being account-usage-budget contention, a genuinely new risk this session's own probing
surfaced rather than reasoned about in advance. Still open: a real, not trivial, authoring turn's
behavior in this exact spawn shape. Still not a Decision — Route 5's fate remains for a future
session to choose, now against a fuller and slightly less rosy evidence picture than finding #26
alone left it.
