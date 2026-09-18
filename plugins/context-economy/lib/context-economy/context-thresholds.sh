#!/bin/bash
# Context-reset thresholds, in resident input tokens.
#
# SINGLE SOURCE OF TRUTH. lib/context-gauge.sh renders against these; hooks/handoff-write.sh
# decides its one-shot advisory for unattended runs against the same numbers. Two copies
# would drift silently — and worse, drift in
# different units (one in tokens, one in percent) — with nothing failing to announce it.
# Consumers source this file; they never restate the numbers, not even as a fallback
# default. A missing file means "no advisory", not "guess" — degrade capability, never
# execution.
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
# 300k and 45% at 400k. Two stages because the evidence supports two: 120k is where the saving
# becomes large, 200k is where it is still large and the session is unambiguously deep.
#
# BUT THAT GRID IS A BOUND, NOT AN OPTIMUM -- 200k IS A JUDGEMENT CALL, NOT A DERIVED NUMBER.
# Labelled 2026-09-09 ([D18](../../docs/design.md#d18)) after the wording here was read as though
# finding #7 had derived it. It samples four points and is monotonic (lower always looks cheaper)
# because it explicitly prices none of the costs that would create an optimum: the authoring turn,
# the re-reading a fresh session must do, or work lost to a bad handoff. Its own words: "the size
# of the prize, not a forecast".
#
# Nor does adding the one such term this file already has rescue it. Extending the handoff-budget
# model further down (mean cost per turn of work = (T+H)/2) with the authoring turn A gives
# (T+H)/2 + A*g/(T-H), whose optimum is T = H + sqrt(2*A*g) ~= 14k: a reset every five turns. That
# is absurd as advice, and the absurdity is the useful part -- it localises the single missing term
# as RE-DERIVATION COST after a reset, which nothing in the corpus prices. Until that is measured
# this threshold can be BOUNDED but not DERIVED, and saying so is cheaper than implying otherwise.
# The same discipline CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS applies to its own floated constant.
#
# CONSEQUENCE: BOTH OF THESE ARE ADVISORY ONLY. They feed the statusline gauge, and URGE is where a
# HUMAN is invited to run /handoff by hand -- a judgement the cost model provably cannot make and a
# person can. NEITHER IS AN AUTOMATIC TRIGGER. D18 moved the automatic write onto a relative, late
# trigger derived from the compaction ceiling, because 200k was never reasoned as an automatic point
# on a 1M window: it fires at 20% of the window and then lets the session run to 887k regardless.
# CTX_NOTICE_TOKENS keeps one non-display job, described at the arming block below -- it is also the
# floor beneath the automatic trigger, the depth below which a handoff is not worth writing.
CTX_NOTICE_TOKENS=120000
CTX_URGE_TOKENS=200000

# CEILING CONSTRAINT — T IS ONLY VALID ON A LARGE ENOUGH WINDOW. Measured 2026-08-26 against
# claude.exe 2.1.246 (`vHe`, `iL`, `uCt`; constants 13000 / 3000). Auto-compaction fires at a
# FIXED OFFSET below the window, not a percentage of it:
#
#     effective_window  = min(autoCompactWindow_source, model_window) - reserved_output_tokens
#     compact_threshold = effective_window - 13_000
#
# BOTH OPERANDS OF THAT `min` ARE DYNAMIC -- DO NOT BAKE A MODEL-TO-WINDOW TABLE INTO A CONSUMER.
# model_window is static per binary (compiled-in model table) EXCEPT for the 1M beta, which is gated
# on the beta header plus the model's own supports_1m_beta -- that is what the `[1m]` suffix requests.
# autoCompactWindow_source, when `auto`, is delivered BY THE SERVER PER ORGANISATION (bootstrap
# response `auto_compact_windows`, keyed by org UUID, first-party auth only; null on bedrock/vertex/
# etc). reserved_output_tokens is the model's own max_output_tokens. So the ceiling can differ between
# two accounts on the same binary, and change between two sessions of one account with no upgrade.
# (Subscription tier: the client knows it, but no path was found reading it to compute a window. The
# dependence is indirect -- per-org config and beta entitlement. Do not assume a plan-to-window map.)
#
# THEREFORE: FAIL CLOSED -- AND DO NOT TRY TO READ THE WINDOW, BECAUSE YOU CANNOT. Probed
# 2026-08-26 against a real transcript and ~/.claude.json. The window is the one value NOT reachable
# from a hook: the model-to-window map is compiled into the binary with no CLI to query it, and
# `context_window_size` is absent from the transcript. So the instruction is not "read the ceiling"
# but the narrower:
#
#   1. DETECT the `[1m]` suffix in the transcript's `modelUsage` KEYS (e.g. "claude-opus-5[1m]").
#      Prefer this over `message.model`, which drops the suffix -- measured: the same session shows
#      `"model":"claude-opus-5"` on assistant lines and `claude-opus-5[1m]` in modelUsage. The suffix
#      is what requests the 1M beta, so its presence is EVIDENCE THE BETA WAS GRANTED for those
#      requests -- an observation, not a lookup table that can go stale.
#      BUT THE CHANNEL IS THIN, AND THINNER THAN THIS INSTRUCTION ORIGINALLY ASSUMED. Measured
#      2026-08-26 while building the Stop hook: modelUsage appears ONLY on `cost-state` lines,
#      which are a 2.1.246 addition and sporadic even on that version -- present in 1 of 4
#      transcripts there, and 0 of 26 on 2.1.235 / 2.1.228. A session can therefore be deep,
#      genuinely on the 1M beta, and carry no evidence of it. So step 3 (DECLINE) is the COMMON
#      outcome of this path, not its edge case, and a machine that wants an armed trigger should
#      DECLARE the ceiling below rather than wait for detection to succeed. Detection stays first
#      because it is free and cannot go stale; it is simply not something to rely on.
#   2. ACCEPT `CTX_COMPACT_THRESHOLD_TOKENS` (declared at the end of this block) and trust it over any
#      detection. MIND WHICH QUANTITY THAT IS -- three values in this block could each be called a
#      "ceiling" and they differ by 13_000 plus the output reserve:
#          (a) window_source      -- what a human sets in env/settings; A WINDOW, NOT A CEILING
#          (b) effective_window   -- min(window_source, model_window) - reserved_output_tokens
#          (c) compact_threshold  -- effective_window - 13_000   <-- CTX_COMPACT_THRESHOLD_TOKENS IS THIS ONE
#      CLAUDE_CODE_AUTO_COMPACT_WINDOW is (a). Using it directly as the ceiling overshoots by
#      13_000 + reserved_output_tokens, which on a tight window IS the negative-slack case this
#      block exists to prevent. Subtract the offset and the reserve before it can be used here.
#   3. DECLINE otherwise, naming which signal was missing.
#
# Assuming the large window is the unsafe direction: it is precisely what manufactures the
# negative-slack case described below. An unknown window reads as "do not arm", never "probably 1M".
#
# What a hook CAN read, all verified: resident size from the last `usage` record in `transcript_path`
# (input_tokens + cache_creation_input_tokens + cache_read_input_tokens); the suffixed model id from
# `modelUsage`; CLAUDE_CODE_AUTO_COMPACT_WINDOW and friends from the environment -- hooks inherit the
# parent env, and the omit list CANNOT strip a CLAUDE_* var (verified: it is empty for local
# sessions, and where it applies it is a 58-entry code-execution-hijack denylist -- LD_PRELOAD,
# NODE_OPTIONS, BASH_ENV, PROMPT_COMMAND and the like -- with zero CLAUDE* entries); and
# `autoCompactEnabled` from settings.
#
# CLOUD-SESSION CAVEAT -- USER SETTINGS HELPS BUT DOES NOT SOLVE IT. Traced 2026-08-26; corrects an
# earlier note here that said "define it in user settings" as though that were sufficient.
#
# SCOPE: this applies ONLY to a call served to a cloud session (log: "hook not run for a call served
# to a cloud session"; telemetry `tengu_remote_tool_serve_hook_held`). Local sessions are unaffected,
# so if you never run cloud sessions none of this bites.
#
# For a `Stop` hook the outcome is SKIP, not a prompt: only PreToolUse gets permissionBehavior:"ask";
# every other event gets outcome:"success" plus a systemMessage saying the hook was not run. So it is
# reported rather than silent -- but the write trigger still does not fire, and no handoff is written.
#
# FOUR reasons a hook is held, and user settings clears exactly ONE:
#   project_configured -- CLEARED by user/managed settings; that is literally the condition. Caveat:
#                         "as it stands ... or it changed since launch", so editing it mid-session
#                         re-trips this.
#   in_reach           -- NOT cleared. Tests where the SCRIPT lives, resolving PATH, following
#                         symlinks (readlink -> realpath) and testing the path, the link target AND
#                         the realpath against the synced project. Also trips on a hardlinked
#                         non-binary, and on a `#!` script past one level of resolution.
#   unreadable         -- NOT cleared. Same axis: could not pin the command to a single script
#                         outside the synced project.
#   model_hook         -- NOT cleared. An agent or prompt hook cannot run for a cloud call at all.
#
# THE HAZARD IS `in_reach`, AND WHICH WAY IT FALLS DEPENDS ON HOW THIS BUNDLE WAS INSTALLED. Under a
# symlink install -- ~/.claude/hooks/* and ~/.claude/lib/* pointing into a checkout -- a hook whose
# realpath lands inside whichever repo the cloud session has synced is held regardless of settings
# scope. A plugin install sidesteps it: the cache copy under ~/.claude/plugins/cache/ is a copy, and
# sits outside every synced checkout. If item 4's hook must survive cloud-served calls, it needs a
# real file outside any synced checkout -- not a symlink into one.
#
# NOT VERIFIED: what populates the "synced project" reach set, and whether a file the hook SOURCES
# (this file, for instance) is examined alongside the script itself. Plausible, untraced.
#
# DO NOT build on ~/.claude.json's `autoCompactWindowsCache`. Readable, but the bootstrap schema
# types it `record(string, unknown)` -- the values are unvalidated by the client's OWN parser, so
# reading it is guessing at a blob. Optional hint at most. (It is also null on a first-party account
# with no org override, so an implementation tested only here would never exercise the populated path.)
#
# TRAP FOR ANY TRANSCRIPT PARSER: grepping a transcript for a field name also matches the session
# TALKING about that field. Measured: 22 hits for `context_window` in a session whose only source was
# this repo's own statusline.sh being read into context. Match on parsed JSON structure, never on a
# substring of the raw line.
#
# ── THE AUTOMATIC TRIGGER IS RELATIVE AND LATE, NOT ABSOLUTE ───────────────────────────────
#
# Rewritten 2026-09-09 by [D18](../../docs/design.md#d18); the absolute-trigger design this
# block used to describe is recorded there as what it replaced. The failure it fixes: an absolute
# 200k trigger fires at 20% of a 1M window and then lets the session run on to 887k regardless,
# while on a 200k-window session compaction fires ~187k -- BELOW 200k -- so the same trigger never
# fires at all. Neither is thin headroom. One is early, one is dead code, and both come from
# expressing a compaction-relative decision as a window-independent constant.
#
# Rewritten AGAIN 2026-09-16 -- Route 5 ([O10](../../docs/design.md#o10),
# [docs/measured.md](../../docs/measured.md) findings #18/#19/#20). D18's trigger observed at
# `Stop`, which only fires at true turn boundaries -- and finding #18 caught the failure that
# leaves open: a single uninterrupted turn (~549k tokens, 1,625 tool calls, no `Stop` event until
# the very end) can leap the WHOLE [trigger, gate) band unseen, because nothing observes anything
# in between. `fat_turn` was never a real bound on a turn like that; it was a bound on turns that
# had already ended, measured from turns that had already ended (finding #15's own survivorship
# caveat, which finding #18 then confirmed by example).
#
# So the check now also runs on `PostToolUse` (fires after every tool call), and `large_request`
# -- the max resident delta a SINGLE tool-call round trip can add, finding #20 -- replaces
# `fat_turn` in the same formula:
#
#     trigger  =  compact_threshold - 2*large_request - authoring_turn   fire at or above this
#     gate     =  resident + large_request + authoring_turn  <  compact_threshold
#     floor    =  trigger  >=  CTX_NOTICE_TOKENS                         else the window is too small
#
# WHY `Stop` IS STILL REGISTERED, NOT RETIRED. `PostToolUse` only fires after a tool call -- a
# turn with none (a plain back-and-forth turn, no `Read`/`Edit`/`Bash`) is invisible to it, and a
# run of several such turns compounds unobserved for the same structural reason `fat_turn` failed
# inside one turn, just spread across turns instead of tool calls. `Stop` fires unconditionally at
# every turn boundary regardless of tool use, so it stays registered as the backstop for exactly
# that case -- running the SAME check, against the SAME `large_request` constant and the SAME
# on-disk latch (`hooks/handoff-write.sh`), not a second system with its own margin. That was
# considered and rejected: a turn with zero tool calls produces a delta of the same ORDER as any
# other single-observation-to-observation gap, so there is no case for a second, wider margin --
# only for a second place to check.
#
# WHY TWO large_requests IN THE TRIGGER AND ONE IN THE GATE -- unchanged reasoning from D18, at
# finer granularity. The gate is the real constraint: once fired, the NEXT turn is the authoring
# turn, and it must complete before compaction. The trigger has to sit strictly BELOW the gate or
# firing would fail its own check on arrival. It sits exactly one large_request below, which makes
# [trigger, gate) a band of that width -- and since something now observes after every tool call
# AND at every turn boundary, a single OBSERVATION GAP no larger than large_request cannot leap the
# band unseen. That is the whole role of the second term: the resolution of the check, not a
# second safety margin.
#
# WHEN THE GATE FAILS, DECLINE AND SAY SO -- do not lower the trigger silently and do not warn and
# proceed. An armed trigger with negative slack loses the race to compaction every time, and the
# handoff it produces is authored from a summary: exactly the `compacted: yes` degradation the
# format exists to record, manufactured on purpose. An unarmed trigger is merely the status quo.
# Degrade capability, never execution -- the same rule the statusline follows when this file is
# missing entirely. Reaching the gate now means a single observation gap exceeded large_request --
# and since Route 5's constants are SET rather than sized at a corpus tail (see below), this is
# NOT expected to be rare in the way D18's ~5%-at-p95 figure for fat_turn was: finding #20's own
# cross-turn distribution puts 20,000 well short of that population's p90, so a real turn-boundary
# gate breach should be a regular occurrence late in a session, not an edge case. That is an
# accepted, deliberate trade for a tighter (less stale) trigger, not an oversight -- but it means
# the decline path will be seen in practice, not just in theory. The failure is one loud message
# and a manual /handoff, not a bad handoff.
#
# WHEN THE FLOOR FAILS, THE WINDOW CANNOT BE SERVED BY PREDICTION AT ALL, and the hook says that
# rather than firing uselessly early. The margin (2*large_request + authoring_turn = 70,000) is
# fixed while the ceiling is not, so below a ceiling the margin exceeds, the trigger lands under
# CTX_NOTICE_TOKENS and the handoff would be written on a near-empty context that has nothing to
# hand off. A 200k-window session (ceiling ~187k) is such a case: it gets the statusline advisory
# and the manual path, and an explicit message saying why, instead of the silence it used to get.
#
# The statusline is exempt from all of this: it only DISPLAYS CTX_NOTICE_TOKENS/CTX_URGE_TOKENS,
# and it is a hot path that must stay pure -- and there is no shortcut through it for the hooks
# either: its `context_window` field is specific to the Statusline hook's OWN payload schema
# (mission_control's F5, re-confirmed while scoping Route 5), not a field every hook payload
# carries, so `PostToolUse` cannot read the count the statusline does and must derive it itself.
# Install time is exempt because it cannot know the runtime window. The arming decision belongs in
# the hook, where the ceiling is resolvable.

# The compact threshold in RESIDENT TOKENS -- quantity (c) above, NOT a window. This is the value the
# `T + large_request + authoring_turn < compact_threshold` comparison uses, so it is the only form a
# consumer may take on trust; anything derived from a window must have the 13_000 offset and the
# output reserve subtracted first.
#
# EMPTY IS A MEANINGFUL ANSWER: it means "this machine has not declared a ceiling", and a consumer
# must then fall back to detection (step 1) or decline (step 3). Set it only where the real ceiling
# is known and stable -- and then it wins over detection, because a human who measured beats a
# heuristic that inferred.
#
# SINCE [D18](../../docs/design.md#d18) THIS VALUE IS LOAD-BEARING IN A SECOND WAY: the automatic
# trigger is DERIVED from it (`ceiling - 2*large_request - authoring_turn`), where before it only
# vetoed a trigger fixed elsewhere. A wrong declaration no longer merely waves through a race it
# should have declined -- it aims the trigger itself at the wrong point. The direction of the error
# is unchanged (too large is unsafe) but its consequence is larger, so the "declare only what you
# measured" instruction above is now the stronger of the two reasons to read this block.
#
# It is assigned empty HERE and declared (or left empty) at the END of this file, after the constant
# a declaration would reference. Ordering, not indecision: `CTX_1M_COMPACT_THRESHOLD_TOKENS` is
# defined further down, so a declaration written here would expand to nothing and read as "no
# opinion" -- the one failure this variable cannot afford, since empty is itself a meaning.
#
# Guard it with `-n`, never `${CTX_COMPACT_THRESHOLD_TOKENS:-0}`: a :-0 default would read as a ceiling of zero
# and hold every session below it, which is the same fail-OPEN reasoning the statusline uses for
# CTX_URGE_TOKENS. Empty must mean "no opinion", never "zero".
CTX_COMPACT_THRESHOLD_TOKENS=

# ── Terms for the trigger, the gate and the floor ──────────────────────────
#
# All three expressions in the arming block above are built from these two addends, and they live
# here for the same reason every other number does: a consumer that restated them would be the
# second copy this file exists to prevent.
#
# SET VALUES, NOT DERIVED ONES -- changed 2026-09-16 while scoping Route 5's re-fire question, and
# dropping the pretense that either constant is a measured, representative bound. Both were
# previously taken at a corpus max (docs/measured.md findings #14 and #20) on the theory that a
# worst-case bound was free to oversize -- "too large costs nothing" beyond wasted margin. That
# theory turned out to be wrong on two counts:
#
#   1. An oversized authoring_turn/large_request does not just waste margin -- it widens the exact
#      gap (2*large_request + authoring_turn, see below) that leaves an auto-written handoff stale
#      by the time compaction actually hits, and that gap turned out to dominate the TYPICAL case,
#      not just the worst one: a one-shot trigger sized for the worst case leaves most of its
#      margin unspent on an ordinary session.
#   2. The corpus behind both maxes was small and skewed toward this repo's own meta/tooling work
#      (context-economy, mission-control) rather than representative day-to-day engineering
#      (kendo, kendo-2). Of finding #14's 20 authoring-turn samples, the four smallest
#      (13,698-23,472) were the only kendo/kendo-2 ones; the entire 31k-64k tail was
#      context-economy/mission-control. Neither problem is fixable by choosing a different
#      percentile of that same corpus -- n=4 for the population that actually matters is too thin
#      to trust as a bound in either direction.
#
# So: neither constant below is claimed to be measured, representative, or derived any more. The
# probes were not wasted -- finding #14 and #20 established the right ORDER OF MAGNITUDE (tens of
# thousands of tokens, not hundreds or single thousands) and ruled out a naively small guess -- but
# pinning a value on top of that order of magnitude is a judgement call, made here, to be revised
# BY PATCH as real sessions demonstrate the trigger firing too early (stale handoffs) or too late
# (lost the race to compaction). Revise in either direction against real operating experience, not
# against a recomputed statistic from the same small corpus.
CTX_LARGE_REQUEST_TOKENS=20000

# AUTHORING TURN -- same status as CTX_LARGE_REQUEST_TOKENS above: a set value, order-of-magnitude
# informed by docs/measured.md finding #14 (20 samples, 13,698-64,618, median 25,025), but not
# claimed to be its max, its median, or otherwise derived from it, for the representativeness
# reason given above. Revise by patch, in either direction, against real sessions -- not against a
# recomputed statistic from this same corpus.
CTX_AUTHORING_TURN_TOKENS=30000

# THE 1M-BETA FALLBACK, used only when `[1m]` was detected in the transcript's modelUsage keys
# and no CTX_COMPACT_THRESHOLD_TOKENS was declared. A DELIBERATE LOWER BOUND on quantity (c),
# not a computation of it: detection establishes that the beta was GRANTED, never the model's
# reserved_output_tokens, so the exact threshold stays unknown and a lower bound is the only
# honest form. 1_000_000 - 13_000 (the measured offset) - 100_000 (a reserve chosen generously
# larger than any current model's max_output_tokens).
#
# PRECISION MATTERS MORE SINCE [D18](../../docs/design.md#d18) THAN IT DID BEFORE, though still not
# much. This used to decide a fixed T~200k against a bound near 887k, where being wrong by 50k
# changed nothing. Now the trigger is derived from the bound, so a 50k error moves the trigger by
# 50k -- from ~817k to ~867k. Both are comfortably inside the safe band and neither risks the
# gate, so the lower bound stands; but the error no longer cancels out, and if a session ever needs
# the trigger placed precisely, declare the real ceiling rather than widening this.
CTX_1M_COMPACT_THRESHOLD_TOKENS=887000

# ── THE DECLARED CEILING FOR THIS CHECKOUT ─────────────────────────────────
#
# Declared 2026-08-26. Without it the `Stop` trigger almost never arms: detection depends on
# `cost-state` lines, which are a 2.1.246 addition and sporadic even there (measured: 1 of 4
# transcripts on that version, 0 of 26 on 2.1.235/2.1.228), so DECLINE was the common outcome
# rather than the edge case.
#
# WRITTEN AS A REFERENCE, NEVER AS A REPEATED LITERAL. Spelling `887000` again -- here, or in a
# settings.json `env` block, which was the first plan -- would be the second copy this whole file
# exists to prevent, and the drift would be silent AND biased: a declared ceiling WINS over
# detection, so a stale duplicate would quietly override the corrected constant it was copied from.
# One number, one definition, one place carrying its justification.
#
# WHY THE 1M BOUND IS THE RIGHT DECLARATION HERE, and why it is safe despite being checked in and
# shared: it is a conservative LOWER bound, and nothing reachable on a smaller window consumes it.
# `CTX_URGE_TOKENS` is NOT what makes that true -- since D18 it gates nothing, it urges, exactly as
# its name says: the statusline renders it and a human decides. What makes this declaration safe is
# the derived trigger itself. At this bound the automatic write arms at `887000 - 2*20000 - 30000
# = 817,000`, and a 200k-window session auto-compacts near 187k, so it never comes close -- the
# declaration is unreachable there, not merely harmless. The one case it could get wrong is an
# INTERMEDIATE window (say 500k), where a real ceiling near 425k would decline a case this bound
# waves through. If such a session becomes normal here, declare that ceiling instead of widening
# the 1M constant above.
#
# TO OVERRIDE PER MACHINE without touching this shared file, export CTX_COMPACT_THRESHOLD_TOKENS in
# the environment: the hook captures it BEFORE sourcing, precisely so this assignment cannot clobber
# it. That is the escape hatch for a machine whose real ceiling differs.
CTX_COMPACT_THRESHOLD_TOKENS=$CTX_1M_COMPACT_THRESHOLD_TOKENS

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
# THIS VALUE IS FOR A HANDOFF A HUMAN WROTE, NOT ONE THE TRIGGER WROTE. Scoped 2026-09-09 by
# [D18](../../docs/design.md#d18), which found the two jointly incoherent: an automatically written
# handoff lands up to `2*large_request + authoring_turn` below the ceiling BY CONSTRUCTION -- see
# hooks/handoff-write.sh's own derivation of that figure (re-checked while scoping Route 5: the
# worst case is the UPPER end of the reserved band, `2L+A`, not `2L` alone -- a distinction this
# repo's own code got wrong in the same way both before and immediately after Route 5, until asked
# to justify the arithmetic directly). At today's values that is 70,000 (2*20,000+30,000) -- far
# more than this number either way. Judged against this constant every auto-written handoff would
# be flagged "likely-undocumented", which is not a staleness finding but a category error: the gap
# is nominal, and the verdict would be reporting the design as a defect.
#
# So the automatic path carries its OWN expected gap instead. `handoff-write.sh` records
# `expected_gap_tokens` into the sidecar when the handoff lands, and `handoff-inject.sh` judges
# against whichever is larger. A sidecar without the field (written before D18) falls back to this
# constant, which is the pre-D18 behaviour and errs toward flagging -- the safe direction for a
# verdict a reader acts on. THIS NUMBER THEREFORE GOVERNS THE MANUAL PATH, where a person ran
# /handoff at a moment of their own choosing and the gap really is a free variable worth judging.
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
