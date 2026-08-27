#!/bin/bash
# Context-reset thresholds, in resident input tokens.
#
# SINGLE SOURCE OF TRUTH. lib/context-gauge.sh renders against these; the
# threshold hook that will later inject a one-shot advisory for unattended runs decides
# against the same numbers. Two copies would drift silently — and worse, drift in
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
# WHERE THE NUMBERS COME FROM: reports/2026-08-21-context-economy-measured.md finding #7 —
# simulated against each context's own measured growth rate, resetting at 120k would have
# saved 77% and at 200k 66%. Two stages because the evidence supports two: 120k is where the
# saving becomes large, 200k is where it is still large and the session is unambiguously deep.
# NOTICE is informational; URGE is actionable.
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
# THE HAZARD FOR THIS REPO IS `in_reach`, BECAUSE WE INSTALL BY SYMLINK. ~/.claude/hooks/* point into
# mission_control and ~/.claude/lib/* do too, so a hook whose realpath lands
# inside whichever repo the cloud session has synced is held regardless of settings scope. If item 4's
# hook must survive cloud-served calls, it needs a real file outside any synced checkout -- not a
# symlink into one.
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
# CTX_URGE_TOKENS is absolute (see WHY TOKENS AND NOT PERCENT above) and that decision stands --
# but its cost is here. On the 1M default, compaction fires ~987k and 200k leaves ~787k of slack:
# a fat turn is noise. On a 200k-window session compaction fires ~187k, which is BELOW 200k, so a
# consumer gated on CTX_URGE_TOKENS never fires at all. Not a race, not thin headroom: dead code.
#
# So any consumer that ACTS on this threshold (as opposed to merely displaying it) owes a headroom
# check at the moment it runs, where the real window is known:
#
#     T + one_fat_turn + one_authoring_turn  <  compact_threshold
#
# Three terms, because a bare `T < ceiling` undercounts twice. The check's resolution is one turn
# (the Stop event fires once per turn, never at the intermediate requests where context actually
# grows), and one turn that reads widely adds 50k+. And the handoff-authoring turn is itself wide
# by construction -- writing citations means reading the files being cited.
#
# WHEN THE CHECK FAILS, DECLINE TO ARM AND SAY SO -- do not lower T silently and do not warn and
# proceed. An armed trigger with negative slack loses the race to compaction every time, and the
# handoff it produces is authored from a summary: exactly the `compacted: yes` degradation the
# format exists to record, manufactured on purpose. An unarmed trigger is merely the status quo.
# Degrade capability, never execution -- the same rule the statusline follows when this file is
# missing entirely.
#
# The statusline is exempt: it only DISPLAYS, and it is a hot path that must stay pure. Install
# time is exempt because it cannot know the runtime window. The check belongs in the hook.

# The compact threshold in RESIDENT TOKENS -- quantity (c) above, NOT a window. This is the value the
# `T + fat_turn + authoring_turn < compact_threshold` comparison uses, so it is the only form a
# consumer may take on trust; anything derived from a window must have the 13_000 offset and the
# output reserve subtracted first.
#
# EMPTY IS A MEANINGFUL ANSWER: it means "this machine has not declared a ceiling", and a consumer
# that acts on CTX_URGE_TOKENS must then fall back to detection (step 1) or decline (step 3). Set it
# only where the real ceiling is known and stable -- and then it wins over detection, because a human
# who measured beats a heuristic that inferred.
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

# ── Headroom terms for the arming check ────────────────────────────────────
#
# The `T + fat_turn + authoring_turn < compact_threshold` check above needs both addends, and
# they live here for the same reason every other number does: a consumer that restated them
# would be the second copy this file exists to prevent. BOTH ARE BOUNDS, NOT MEASUREMENTS, and
# are labelled as such -- the safe direction for a term inside a fail-CLOSED check is too
# LARGE, which is the opposite of the safe direction for a displayed figure.
#
# FAT TURN: reports/2026-08-24-harness-automation-surface.md F4b(1) -- Stop fires once per TURN,
# never at the intermediate requests where context actually grows, so the check's resolution is
# one whole turn, and one turn containing an unscoped Read or a wide grep "can add 50k+". Taken
# at that stated 50k rather than the 2.07k mean, because a mean is precisely the wrong statistic
# for a worst-case margin.
CTX_FAT_TURN_TOKENS=50000

# AUTHORING TURN: the /handoff run the trigger is about to demand. Estimated, not measured --
# from the skill's own deliberately small shape (one orientation bash call, one Write, one gate
# run) plus the skill text, the gate's output and the document itself. That lands near 20k; 30k
# is carried so an unusually long handoff, or a gate re-run after an exit 1, does not eat the
# margin. Revise DOWNWARD only against a measurement.
CTX_AUTHORING_TURN_TOKENS=30000

# THE 1M-BETA FALLBACK, used only when `[1m]` was detected in the transcript's modelUsage keys
# and no CTX_COMPACT_THRESHOLD_TOKENS was declared. A DELIBERATE LOWER BOUND on quantity (c),
# not a computation of it: detection establishes that the beta was GRANTED, never the model's
# reserved_output_tokens, so the exact threshold stays unknown and a lower bound is the only
# honest form. 1_000_000 - 13_000 (the measured offset) - 100_000 (a reserve chosen generously
# larger than any current model's max_output_tokens). Precision is neither available nor needed:
# the case this decides is T~200k against a bound near 887k, where being wrong by 50k changes
# nothing. If that ever stops being true, declare the real ceiling instead of widening this.
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
# shared: it is a conservative LOWER bound, and `CTX_URGE_TOKENS` gates every consumer at 200k. A
# 200k-window session auto-compacts near 187k and so never reaches that gate at all, which means
# this declaration cannot mislead there -- it is unreachable, not merely harmless. The one case it
# could get wrong is an INTERMEDIATE window (say 500k), where a real ceiling near 425k would decline
# a case this bound waves through. If such a session becomes normal here, declare that ceiling
# instead of widening the 1M constant above.
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
