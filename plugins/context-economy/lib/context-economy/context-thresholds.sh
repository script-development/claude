#!/bin/bash
# Context-reset thresholds, in resident input tokens.
#
# SINGLE SOURCE OF TRUTH. lib/context-gauge.sh renders against these. Consumers source this
# file; they never restate the numbers, not even as a fallback default. A missing file means
# "no advisory", not "guess" — degrade capability, never execution.
#
# Kept beside the research that produced the numbers rather than beside a consumer, because a
# number separated from its justification is how a stale threshold survives. install.sh
# symlinks it to ~/.claude/lib/ so a global consumer can reach it without hardcoding a
# checkout path. (It lived in the separate claude-dotfiles repo until the 2026-08-27 merge;
# that split is what the sibling-checkout wording here used to be about.)
#
# WHY TOKENS AND NOT PERCENT: the statusline payload's `context_window.used_percentage`
# is an integer against `context_window_size`. On a 1M window that is 10k tokens per point
# of granularity, and 200k renders as 20%. A percentage threshold therefore means a
# different number of tokens on every model — 200k here, 40k on a 200k-window session —
# while looking like one stable rule. Threshold on tokens; display whatever reads best.
#
# WHY NOT THE PAYLOAD'S `exceeds_200k_tokens`: it ships in the statusline payload and
# coincides with CTX_URGE_TOKENS today. That is a coincidence, not a definition — it is a
# pricing-tier flag owned by Claude Code, which can be removed or redefined without notice,
# taking our threshold with it. Never consume it, not even as a cross-check: a cross-check
# against a field we do not control is still a dependency on it.
#
# WHERE THE NUMBERS COME FROM: docs/measured.md finding #7 — simulated against each context's
# own measured growth rate, a reset discipline would have saved 77% at 120k, 66% at 200k, 55% at
# 300k and 45% at 400k. Two stages because the evidence supports two, picked as the next pair up
# the same grid by [D25](../../docs/design.md#d25): 200k is where the saving is still large enough
# to act on for how real sessions run today, 300k is where it is smaller but the session is
# unambiguously deep. (120k/200k, the original pair, is D18's own choice below, superseded but not
# deleted — see D25 for why the grid moved rather than being re-measured.)
#
# BUT THAT GRID IS A BOUND, NOT AN OPTIMUM -- NEITHER PAIR IS A DERIVED NUMBER, ONLY A JUDGEMENT
# CALL AGAINST IT. Labelled 2026-09-09 ([D18](../../docs/design.md#d18)) after the wording here was
# read as though finding #7 had derived it. It samples four points and is monotonic (lower always
# looks cheaper) because it explicitly prices none of the costs that would create an optimum: the
# authoring turn, the re-reading a fresh session must do, or work lost to a bad handoff. Its own
# words: "the size of the prize, not a forecast".
#
# Nor does adding the one such term this file already has rescue it. Extending the handoff-budget
# model further down (mean cost per turn of work = (T+H)/2) with the authoring turn A gives
# (T+H)/2 + A*g/(T-H), whose optimum is T = H + sqrt(2*A*g) ~= 14k: a reset every five turns. That
# is absurd as advice, and the absurdity is the useful part -- it localises the single missing term
# as RE-DERIVATION COST after a reset, which nothing in the corpus prices. Until that is measured
# this threshold can be BOUNDED but not DERIVED, and saying so is cheaper than implying otherwise.
#
# CONSEQUENCE: BOTH OF THESE ARE ADVISORY ONLY, and display is their only job. They feed the
# statusline gauge, and URGE is where a HUMAN is invited to run /handoff by hand -- a judgement
# the cost model provably cannot make and a person can. NEITHER IS AN AUTOMATIC TRIGGER: the
# automatic path is Claude Code's own compaction, which `hooks/register.ts` answers with the
# handoff (docs/design.md D29, D31), rather than predicting one from these thresholds -- a fixed absolute value
# was never going to be the right automatic point on a window that can be anywhere from 100k to
# 1M, which is exactly why nothing here arms anything.
# shellcheck disable=SC2034  # read by the scripts that source this file, not here
CTX_NOTICE_TOKENS=200000
# shellcheck disable=SC2034  # read by the scripts that source this file, not here
CTX_URGE_TOKENS=300000

# ── Handoff budget ─────────────────────────────────────────────────────────
#
# Added by build-order item 3 (/handoff). Same file for the same reason as above:
# these come out of the same report, and a number kept beside its justification
# is the only kind that does not go stale unnoticed. `tools/verify-handoff.sh`
# sources this; nothing else restates the figures, and `skills/handoff/SKILL.md`
# deliberately speaks of the budget only in vague prose so it cannot become a
# second copy.
#
# WHERE THE NUMBERS COME FROM, and why the budget is denominated in TURNS:
# with the reset threshold T fixed, a segment's total cost is ~(T^2 - H^2)/2g and
# the turns of work it buys are (T - H)/g, so mean cost per turn of work is simply
# (T + H)/2. A handoff of size H therefore does not add a one-off cost — it makes
# every turn of the session it seeds dearer, and it costs H/g turns of work
# outright. At g below, every ~2.07k tokens of handoff costs ONE turn of work.
# That is the unit the author should think in, so the tool prints turns, not just
# tokens.
#
# g = 2.07k/turn is finding #6's measured pre-compaction growth rate in the
# largest context in the corpus. Post-compaction it measured 1.38k/turn, which
# would make the budget *more* generous; the stricter figure is used deliberately.
# shellcheck disable=SC2034  # read by the scripts that source this file, not here
CTX_GROWTH_TOKENS_PER_TURN=2070

# Finding #6's simulation assumed a 25k handoff — ~12 turns of work per reset, and
# 12.5% on every turn's cost. TARGET is ~2 turns; CEILING ~4, past which the tool
# says so loudly. Both are ADVISORY and never fail the gate: a size gate would
# push an author to cut the non-citable half to fit, which is exactly the
# inversion D6 exists to prevent. Cut Pointers instead — they re-derive.
# shellcheck disable=SC2034  # read by the scripts that source this file, not here
HANDOFF_TARGET_TOKENS=4000
# shellcheck disable=SC2034  # read by the scripts that source this file, not here
HANDOFF_CEILING_TOKENS=8000

# The 4-chars-per-token rule is too generous for code, JSON and diffs; the report
# calibrated character counts against measured context size and got a median of
# 2.68. Kept as an integer x100 so the tool needs no floating point. A handoff is
# more prose than code, so this UNDER-states its token count slightly — the
# conservative direction for a budget.
# shellcheck disable=SC2034  # read by the scripts that source this file, not here
CTX_CHARS_PER_TOKEN_X100=268

# v2.0.0 removed the constants that served only v1's command hooks: CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS
# (the compact read leg's coverage check), CTX_FORK_TIMEOUT_SECONDS and
# CTX_FORK_LIVENESS_WINDOW_SECONDS (the detached writer's kill bound and liveness window). The
# compaction now writes the handoff itself, in-band (docs/design.md D30).
