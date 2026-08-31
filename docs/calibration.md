# Context calibration: per-category chars/token, and the hole in character accounting

Companion to `docs/measured.md`. That report attributed spend by
splitting each context's non-preamble remainder **by measured character proportions**, using a
single chars-per-token ratio (`context-audit.js` uses 4, `context-thresholds.sh` carries a
calibrated 2.68). This report tests that assumption and re-does the attribution without it.

Tool: `tools/context-calibrate.js`. Reproduce with `node tools/context-calibrate.js --boot 300`.
Figures below are the corpus as of 2026-08-24: **8,887 usable requests across 185 contexts**.

## Why one ratio is not enough — and why the 4-vs-2.68 discrepancy is _not_ the problem

A single ratio is invariant under a proportional split. Change 4 to 2.68 and every share in
finding #4's table is unchanged. That discrepancy is cosmetic and finding #4 survives it intact.

What a single ratio is _not_ invariant to is the ratio **varying between the categories being
split**. JSON tool payloads, English prose and markdown tokenize differently, so one ratio
silently transfers share from the badly-tokenizing categories to the well-tokenizing ones. That is
the assumption tested here, and it does not hold.

## Method: solve for the ratios instead of assuming them

No tokenizer, no API call, no `tiktoken` (OpenAI's, and wrong for Claude by 15–20% on prose, more
on code — and unavailable here regardless: this machine has no Anthropic credentials, so
`count_tokens` was not an option). Every request's transcript already records **exact** resident
input tokens as `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Rebuild the
cumulative per-category composition of the context at that same request and each request becomes
one equation:

```
resident_tokens_i  =  preamble  +  SUM_c  beta_c · chars_(i,c)        beta_c = 1 / (chars per token)_c
```

Fit by non-negative least squares, with **per-context fixed effects** (demean within each context)
so the coefficients are identified purely by within-context growth — the right source of variation,
since a context that gains 5k chars of tool results gains 5k/ratio tokens. Confidence intervals by
**cluster bootstrap over contexts**, because consecutive requests inside one context share nearly
all their content and an iid bootstrap would report absurdly tight intervals.

Reaching a specification whose every coefficient is physically possible took four corrections. Each
is documented as a numbered "burn" in the tool's header; the first four are mechanical (snapshot
before not after, resets break the cumulative sum, cluster the bootstrap, collinearity is the real
limit). The four that changed the answer:

### 1. `textLen(r)` on a whole record measures the transcript, not the context

Inherited from `context-audit.js`, where it is a live defect:

| category                     | old measure  | corrected                    | overstated by                                                                                                    |
| ---------------------------- | ------------ | ---------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `attachment` (6,179 records) | 11.33M chars | 8.50M chars (`r.attachment`) | **33.4%** — 459 chars/record of `uuid`/`timestamp`/`cwd`/`sessionId`/`gitBranch`                                 |
| `system` (1,283 records)     | 0.76M chars  | 0.04M chars (`r.content`)    | **1,785%** — **84% of these records have no `content` field at all**, only `durationMs`/`messageCount`/`subtype` |

Combined phantom material: **3.55M characters, 7.4% of all old-measure characters.** The first NNLS
run pinned `system notices` at beta = 0 — the fit correctly detecting a regressor that was never
sent to the model. That is a useful sanity check on the method and a bug report for the other tool.

### 2. Per-message framing is an omitted variable, and it lands on `assistant text`

Structural tokens per message scale with turn count; assistant-text characters are the design
matrix's best proxy for turn count, so that coefficient absorbed them and returned 0.79 chars/token
— below the floor for any real text. Needs its own count column, not a better ratio.

### 3. One pooled intercept bends every coefficient

The preamble is not one constant (finding #4: 55k main loop vs 23k subagent, plus variation with
which MCP servers and skills a session loaded). Pooling forces a compromise — 41k measured — which
under-fits exactly the deep main-loop contexts where the spend is, and the fit repays the shortfall
by inflating whatever grows with context depth. Fixed effects remove every per-context constant
whether or not we can name it.

### 4. Thinking is billed, resident, and transcribed as an empty string

This is the one no amount of better character accounting can fix, and it decides the specification.
On Opus 5 (and Fable 5 / Opus 4.8 / 4.7 / Sonnet 5) `thinking.display` defaults to `"omitted"`:
blocks arrive with empty text. Measured here: **5,660 of 5,660 thinking blocks carry zero
characters.** The tokens were generated, charged, and remain in context.

The size of the hole is visible in corpus arithmetic: **6.60M exact assistant output tokens against
9.97M visible characters — 1.51 chars/token**, below the floor for any real text. A large share of
assistant output is invisible to character counting. That hole is what held `assistant text` near
1.0 chars/token across every earlier specification: the column was proxying for thinking.

> **Corrected 2026-08-24 (same day), and the correction has its own section below.** The share was
> first inferred here as "roughly half". It is directly measurable after all —
> `usage.output_tokens_details.thinking_tokens` exists on Claude Code 2.1.229+ — and the measured
> value is **36.4%**. See _Correction: thinking is directly measurable on 2.1.229+_ at the end.
> The mechanism above is unchanged; only the magnitude was wrong.

The fix is to stop using a character proxy where exact counts already exist. `usage.output_tokens`
is the assistant's exact production per turn — thinking, text and `tool_use` together — so one
cumulative-output-tokens column replaces three character columns.

**Stated cost:** `tool_use` inputs live inside `output_tokens` and can no longer be priced as their
own line, so finding #4's sub-finding ("`tool_use` inputs are a third of tool traffic; `Write`
averages 1,329 tokens/call") loses its direct confirmation here. But the char-based figure it
replaces was contaminated by thinking, so that resolution was illusory rather than lost.
`--char-assistant` restores the old columns for comparison.

## Results

Final specification: per-context fixed effects, exact assistant tokens.
**Within-context R² = 0.9978, RMSE 7k tokens** (against 23k under the first specification).

| category                                            | chars/token | 90% CI      | note                                                  |
| --------------------------------------------------- | ----------- | ----------- | ----------------------------------------------------- |
| tool RESULTS                                        | **2.15**    | 1.98 – 2.30 | tightest coefficient in the fit; the load-bearing one |
| user messages                                       | **1.89**    | 1.67 – 3.82 |                                                       |
| injected (skill listings, diagnostics, file echoes) | **4.35**    | 3.39 – 5.64 | JSON keys vs rendered prose — treat as an upper bound |
| system notices                                      | —           | —           | phantom; not context (see correction 1)               |

| non-character coefficient  | value     | 90% CI        | reading                                                                                      |
| -------------------------- | --------- | ------------- | -------------------------------------------------------------------------------------------- |
| assistant output retention | **0.964** | 0.836 – 1.035 | **CI covers 1.0** — assistant output, thinking included, stays resident essentially verbatim |
| per-message framing        | 0 tok/msg | 0 – 40        | the earlier 202 tok/msg was thinking being absorbed; once measured exactly, nothing is left  |

Two independent validations, neither of which the fit was shown:

- **Recovered preamble** — `mean(y) − mean(X)·beta` per context: **main loop median 40k, subagent
  median 21k**, against finding #4's independently measured **55k / 23k**. Same ordering, same
  magnitude, subagent figure near-exact.
- **Retention CI covering exactly 1.0**, the theoretically expected value for material replayed
  verbatim.

## Re-attribution

Both columns are replay-weighted token shares over the same rows with the same measured preamble.
The only difference is per-category ratios versus one flat ratio.

| occupies the replayed context                           | measured  | flat ratio | shift         |
| ------------------------------------------------------- | --------- | ---------- | ------------- |
| assistant output (exact — thinking + text + tool calls) | **36.6%** | 46.0%      | −9.4 pts      |
| tool RESULTS (read-in material)                         | **34.1%** | 23.0%      | **+11.1 pts** |
| user messages                                           | **10.4%** | 6.2%       | +4.2 pts      |
| injected                                                | **9.5%**  | 12.9%      | −3.5 pts      |
| harness preamble                                        | **9.4%**  | 11.8%      | −2.4 pts      |

## What this changes, and what it does not

**Unchanged: the ranking of design implications.** Session-lifecycle discipline (#1) is a claim
about the quadratic, independent of composition. Nothing here touches it.

**Strengthened: input hygiene (#4) and subagents-as-firewalls (#3).** Read-in tool results are
**34.1%** of replayed context, not the 23% a flat ratio reports — because they tokenize at 2.15
chars/token, the worst of any real category measured. Bounded output and scoped reads are worth
about half again what finding #4 credited them with. "Delegate reading, keep judgement" is the
correct rule and the margin is larger than stated.

**New, and actionable: effort level is a resident-context lever, not just an output lever.**
Finding #4's verdict on model tiering held that tiering "changes the price of the 8.7% output slice,
not the 90% that is replay." That is right about _tiering_ but it leaves a gap: retention beta of
0.964 means thinking tokens are replayed like everything else, and assistant output is **36.6%** of
resident context. A high-effort turn therefore pays twice — once at output rates, then again on
every subsequent turn at replay rates. Effort belongs on the list of controllable levers, and the
asymmetry is worth measuring directly: `low` effort on mechanical stages is cheap in a way that
choosing a cheaper _model_ is not.

**Corrected: two rows of finding #5's composition table.** `system notices` (29k, 3%) should be
deleted rather than shrunk — it is bookkeeping that was never sent. The three `injected:*` rows
(48k + 35k + 33k) are overstated by at least a third on metadata alone.

## Follow-ups

1. `tools/context-audit.js` — fix `textLen(r)` → `textLen(r.attachment)` / `textLen(r.content)`
   (correction 1). Live defect, one line each.
2. `tools/context-audit.js` — replace `CHARS_PER_TOKEN = 4` with the per-category table above, and
   report the assistant side from `output_tokens` rather than characters. Its "all tool traffic
   ~XM tok = Y% of new material" line compares a char-derived stock against exact tokens, so it is
   wrong by the ratio error in a way the proportional splits are not.
3. `tools/context-economy/context-thresholds.sh` — `CTX_CHARS_PER_TOKEN_X100=268` is used by
   `verify-handoff.sh` to size a handoff. A handoff is prose, and prose is not 2.68. The measured
   `user messages` coefficient (1.89) is the closest analogue in this corpus and is _stricter_, so
   the current value under-states handoff cost — the same conservative direction the file already
   documents choosing, but for a reason it does not yet state. Worth re-deriving against handoff
   text specifically rather than inheriting a corpus median.
4. The `injected` coefficient (4.35) is the weakest real number here: character-counting a JSON
   payload the harness renders as prose is a poor proxy in both directions. If it ever matters,
   measure it against `count_tokens` on rendered examples rather than refining the regression.
5. **Consume `output_tokens_details.thinking_tokens` in `context-calibrate.js`** (see the correction
   below). It splits the `assistant output (exact)` column into thinking and visible on the 29% of
   the corpus that reports it, which restores the `tool_use` resolution correction 4 gave up.

---

## Correction: thinking is directly measurable on 2.1.229+

Correction 4 above claimed no thinking-specific field exists, and inferred the share from character
arithmetic. Both halves need amending. The field exists:

```json
"output_tokens":5674,"output_tokens_details":{"thinking_tokens":1506}
```

**Why it was missed:** the key scan behind correction 4 ran over a single context dated 2026-08-06,
which predates the field, and the result was generalised to the corpus. A per-version sweep shows
the actual boundary:

| Claude Code       | requests with the field | without |
| ----------------- | ----------------------- | ------- |
| 2.1.199 – 2.1.226 | 0                       | 6,070   |
| 2.1.229           | 406                     | 174     |
| 2.1.231 – 2.1.238 | 2,367                   | 471     |

**2,773 of 9,488 deduped requests (29%)** carry it, all from 2026-08 onward. `iterations[]` never
carries it (max length seen: 1).

**It is a subdivision of `output_tokens`, not an addition.** `output_tokens` already includes
thinking; adding them double-counts.

**What the direct measurement says**, on the subset that reports it (n = 2,778 requests):

|                                     | value                        |
| ----------------------------------- | ---------------------------- |
| output tokens                       | 2.44M                        |
| thinking tokens (direct)            | 0.89M — **36.4% of output**  |
| visible output tokens               | 1.55M                        |
| visible chars (text + tool_use)     | 3.41M                        |
| **visible assistant chars/token**   | **2.20**                     |
| naive chars/token, thinking ignored | 1.40 (the impossible number) |
| visible split by chars              | 26% text / 74% `tool_use`    |

Three things follow.

1. **The inferred magnitude was wrong; the mechanism was not.** "Roughly half" → **36.4%** measured.
   On the older 71% of the corpus that lacks the field, applying the measured visible ratio implies
   ~28%. Thinking blocks still carry zero characters (5,660 of 5,660) and are still billed and
   resident — that part stands.
2. **Nothing in the fit changes.** The specification consumed exact `output_tokens`, which already
   included thinking. Retention beta = 0.964, the 36.6% assistant-output share, the per-category
   ratios and the preamble recovery are all unaffected. Only this report's prose overstated the
   share.
3. **Correction 4's stated cost is partly refundable.** It gave up pricing `tool_use` inputs as
   their own line because they sit inside `output_tokens`. With `thinking_tokens` available, visible
   output tokens are known directly and the 26/74 char split apportions them — so on 2.1.229+ data
   that line comes back. `2.20` chars/token for visible assistant output also lands next to the
   independently fitted `2.15` for tool results, which is a mutual sanity check neither number was
   fitted to produce.

**Derived, and useful for the effort lever:** thinking is ~36% of assistant output, and assistant
output is ~37% of resident context, so thinking is roughly **13% of everything replayed**. Note the
two denominators differ — that is a composition, not a restatement of either figure.

\*\* Note: Thinking is on by default on Opus 5, and thinking: {type: "disabled"} is only accepted at effort high or below (400 at xhigh/max). But it has two documented failure modes, and the first one lands squarely on Claude Code: with thinking disabled, the model
occasionally writes a tool call into its visible text instead of emitting a tool_use block. The turn succeeds, the call never runs, no error is raised, and in an agentic loop that text pollutes every later turn. Claude Code is nothing but an agentic loop. The second
is <thinking> tags leaking into responses. The supported lever is effort, not disabling. Lower effort cuts thinking tokens while keeping the mechanism intact — and it compounds in your favour, because lower effort also means fewer and more-consolidated tool calls and less preamble, which is less tool
traffic, which is less replayed context. Two of your report's levers move together.

---

## Measurement ceiling, 2026-08-31: breakpoint placement is not in the transcript

Recorded here because this document is where the holes in the accounting live, and because the hole
is permanent rather than a defect to fix. Prompted by the cache-side measurement in
`docs/measured.md` (addendum, 2026-08-31), which answered what it could and stopped here.

**The limit.** A transcript's `usage` object records what was *read* and what was *written* —
`cache_read_input_tokens`, `cache_creation_input_tokens` — and never where the cache breakpoints
were placed. So two mechanisms that this corpus cannot tell apart:

- an outer, longer cache entry being read, and that nested read refreshing the TTL of the shorter
  entry contained within it;
- the shorter entry simply being re-declared explicitly on every request.

Both produce **byte-identical** `usage` records. No amount of care with the existing fields
separates them, because the discriminating variable was never written down.

**What follows.** Any claim about *breakpoint strategy* — how many to place, where, whether a nested
read keeps an inner entry warm — is unfalsifiable from this corpus. That is not a reason to hold no
view; it is a reason to label the view as sourced from documentation rather than from measurement,
and to stop before designing further transcript analyses against it. The TTL semantics this repo
relies on (a read refreshes the timer; lifetime is measured from request *start*, so generation time
counts against it; writes bill 1.25× at 5 minutes and 2× at the hour; 4 breakpoints maximum; a
20-block lookback window) come from the bundled `claude-api` skill's `shared/prompt-caching.md`, not
from anything measured here.

**What is still measurable, and worth the run.** Questions phrased as *"does the prefix read
collapse?"* rather than *"which entry was refreshed?"* stay inside what `usage` can answer, because
they only need the size of the read, not its structure. The worked example is the `ToolSearch`
hypothesis: a mid-session deferred-tool load should invalidate from position 0, which would show up
as `cache_read_input_tokens` collapsing on the following request. Being a prefix-*size* question it
was answerable, and it has since been answered — **refuted**, in `docs/measured.md` finding #9. The
breakpoint question above stays out of reach, and the contrast is the useful part: the two questions
look equally empirical and only one of them is.

**Follow-up 6, for the list above:** do not add a breakpoint-strategy analysis to
`tools/context-calibrate.js`. It would produce numbers that look like evidence for whichever
mechanism the author already believed.
