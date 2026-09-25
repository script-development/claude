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
# The same discipline CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS applies to its own floated constant.
#
# CONSEQUENCE: BOTH OF THESE ARE ADVISORY ONLY, and display is their only job. They feed the
# statusline gauge, and URGE is where a HUMAN is invited to run /handoff by hand -- a judgement
# the cost model provably cannot make and a person can. NEITHER IS AN AUTOMATIC TRIGGER: the
# automatic path is `PreCompact` (`hooks/handoff-fork-write.sh`), which fires off Claude Code's
# own compaction event rather than predicting one from these thresholds -- a fixed absolute value
# was never going to be the right automatic point on a window that can be anywhere from 100k to
# 1M, which is exactly why nothing here arms anything.
CTX_NOTICE_TOKENS=200000
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
CTX_GROWTH_TOKENS_PER_TURN=2070

# Finding #6's simulation assumed a 25k handoff — ~12 turns of work per reset, and
# 12.5% on every turn's cost. TARGET is ~2 turns; CEILING ~4, past which the tool
# says so loudly. Both are ADVISORY and never fail the gate: a size gate would
# push an author to cut the non-citable half to fit, which is exactly the
# inversion D6 exists to prevent. Cut Pointers instead — they re-derive.
HANDOFF_TARGET_TOKENS=4000
HANDOFF_CEILING_TOKENS=8000

# The 4-chars-per-token rule is too generous for code, JSON and diffs; the report
# calibrated character counts against measured context size and got a median of
# 2.68. Kept as an integer x100 so the tool needs no floating point. A handoff is
# more prose than code, so this UNDER-states its token count slightly — the
# conservative direction for a budget.
CTX_CHARS_PER_TOKEN_X100=268

# ── The compact read leg's coverage check ──────────────────────────────────
#
# `handoff-inject.sh`'s `source: compact` branch has no async gap the way `clear` does (the
# same transcript survives compaction, so it reads its own last usage record synchronously
# rather than waiting on a marker another hook wrote) -- but it still needs to say whether the
# handoff on disk, written earlier in the SAME session, is likely to have missed recent work.
# Unlike `clear`'s COVERAGE_WINDOW_SECONDS (wall-clock, sized for "how long ago was the reset"),
# this is TOKEN-distance: staleness here is driven by how much got done between the write and
# the eventual compaction, not by how much time passed -- an hour idle loses nothing, two minutes
# of a 40k-token autonomous stretch loses a lot, and a clock-based check scores those backwards.
#
# ANCHOR, FLOATED RATHER THAN MEASURED: 5 turns at CTX_GROWTH_TOKENS_PER_TURN (2,070/turn,
# finding #6). "5 turns" is a judgement call about how much unrecorded work still reads as
# "recent enough" for a reader to reconstruct from context alone, not a quantity anything in
# this repo has measured directly -- revisit this constant, specifically, before trusting it the
# way the corpus-derived figures above are trusted.
#
# THIS VALUE GOVERNS EVERY COMPACT-LEG COVERAGE CHECK TODAY, MANUAL OR AUTOMATIC. A predecessor
# design (the `Stop`/`PostToolUse` trigger, since removed -- see CHANGELOG) had its own write leg
# computing an `expected_gap_tokens` figure per write and stashing it in a sidecar for
# `handoff-inject.sh` to prefer over this constant when present, on the theory that an
# automatically written handoff lands a known, larger distance below the ceiling than a human
# choosing their own moment would. The current automatic path (`PreCompact` ->
# `hooks/handoff-fork-write.sh`) writes no such sidecar, so `handoff-inject.sh`'s fallback to this
# constant is now the only path taken, for every handoff regardless of how it was triggered.
CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS=10350

# ── The fork write's timeout, and the read leg's abandoned-write threshold (D23) ──────────
#
# ONE number, TWO consumers, deliberately: `hooks/handoff-fork-write.sh` uses it as the detached
# turn's own `timeout` bound; `hooks/handoff-inject.sh` uses the SAME number to decide whether a
# `progress: writing` placeholder (docs/design.md D23) is still plausibly in flight or has been
# sitting there long enough that the authoring turn almost certainly died before finishing. Two
# copies of this number would let the read leg's patience drift out of step with the write leg's
# own kill bound -- exactly the drift this file exists to prevent everywhere else.
#
# `${CTX_FORK_TIMEOUT_SECONDS:-600}` rather than a bare assignment: this line must not clobber an
# operator's own override if it is already exported, since sourcing this file after the export
# would otherwise win and silently discard it. Read `hooks/handoff-fork-write.sh`'s own header for
# why 600s is not a reliably ENFORCED bound on every platform this runs on (`timeout` was observed
# still running well past it once, on Windows/Git-Bash) -- which is precisely why the read leg
# treats crossing this threshold as "likely abandoned", a probabilistic judgement call for a
# reader to act on, never a hard fact.
CTX_FORK_TIMEOUT_SECONDS=${CTX_FORK_TIMEOUT_SECONDS:-600}

# ── The read leg's liveness window, past CTX_FORK_TIMEOUT_SECONDS (D28) ────────────────────
#
# `progress:`'s own mtime never moves again once the skeleton is written, so once
# CTX_FORK_TIMEOUT_SECONDS has elapsed against it, the read leg cannot tell "still working, just
# slower than the nominal budget" from "died" by looking at the handoff file alone -- exactly the
# open question `hooks/handoff-fork-write.sh`'s own header names (finding #26/#28's "what this does
# not settle"). When a `--session-id` was pinned to the detached turn, its own transcript CAN tell
# the two apart: still being written to recently means genuinely alive. This is how recently counts
# as "recently" for that check -- short on purpose, since it only ever EXTENDS a wait that already
# has independent evidence of life, never substitutes for it.
CTX_FORK_LIVENESS_WINDOW_SECONDS=${CTX_FORK_LIVENESS_WINDOW_SECONDS:-90}
