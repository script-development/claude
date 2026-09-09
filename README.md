# Content economy

## Goal

A plugin bundling tools and skills intended to control over context growth and reduce token usage.

## Contents

# /handoff

The /handoff skill builds on Claude's (auto)compaction mechanism. Compaction summarizes the session's history, but loses the evidence that decisions, implementations and dead-ends are based on. The skill complements the compaction summary with a handoff containing decisions, implementations, dead-ends with relevant citations so the next session does not rederive supporting evidence. The handoff ends with a Next (work items) and Traps section to give the next session direction.

## Manual trigger

/handoff invokes the skills write branch manually. Use it instead of /compact whenever you want to pro-actively shrink your context.

The write branch produces the handoff and will end with an instruction to /clear, and then start the next session with /handoff --read. However, you can replace /handoff -read with anything starts a session: e.g. starting with a "." prompt will also start the handoff skill's read branch.

The handoff skill automatically injects the handoff and standard compaction summary into the next session.

## Automatic trigger

The handoff skill's write branch automatically triggers when you near your auto-compaction threshold. Unlike manual invocation, an automatic trigger of the write branch does not replace compaction but adds to it. The write branch produces a handoff, then auto-compaction triggers and writes the summary. Auto-compaction starts a new session, consuming the summary and handoff as part of the same request.

### Automatic vs manual trigger

Upside: Fully hands off, configurable through the auto-compact threshold.

Downside: The automatically triggered handoff is slightly stale compared to its manually triggered counterpart. The automatic handoff must be written before auto-compaction triggers. If not, compaction itself interrupts the handoff writing process and only the summary survives.

### Setting the auto-compact window

CLAUDE_CODE_AUTO_COMPACT_WINDOW - A Claude Code harness setting (100k to model_max -> 1M for a 1M plan). Actual compaction takes place when context grows to the compact_threshold=min(CLAUDE_CODE_AUTO_COMPACT_WINDOW, model_max) − reserved_output_tokens − safety margin. Current measurements suggest that the compact_threshold is at least 36K below CLAUDE_CODE_AUTO_COMPACT_WINDOW.  
CTX_COMPACT_THRESHOLD_TOKENS - A constant in context-thresholds.sh (part of the plugin). Hooks cannot access CLAUDE_CODE_AUTO_COMPACT_WINDOW because it is part of the harness. The value must be supplied either by default (887K) or by an env variable in the user's settings.json.

Advice: Set CTX_COMPACT_THRESHOLD_TOKENS below compact_threshold by a generous safety margin.

Reason: The handoff must be written before auto-compaction kicks in. Writing the handoff can push context past the auto-compaction threshold. Auto-compaction interrupts the handoff writing process.

An example settings.json block:

"env": {
"CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000",
"CTX_COMPACT_THRESHOLD_TOKENS": "350000"
},

These settings mean:

- The harness aims to keep context below 400K, but since it builds in a safety margin and needs to reserve tokens for output compactions triggers around 364K context.
- The skill aims to have finished written a handoff by 350K context, a 14K safety margin to auto-compaction.
- The handoff skill triggers well before 350K context is reached, because 1) it triggers at the start of a turn (and must thus have slack to account for the current turn`s work) , and 2) writing the handoff adds to pre-compact context.

## Handoff structure

Sections:
1 Preamble: branch, checkout, compacted, status
2 Do not re-derive: Decisions(/implementation), Dead-ends, Traps
3 Next
4 Pointers
5 Unverifiable

##

###
