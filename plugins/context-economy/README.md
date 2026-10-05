# Content economy

A plugin bundling the /handoff skill and a hooks module (Claude Code function hooks, "mods") that writes and delivers handoffs automatically. Requires a Claude Code build with function hooks; developed against 2.1.287.

The /handoff skill aims to reduce context growth post-compaction by providing the post-compaction session with references to decisions, traps and dead-ends from the pre-compaction session, which would otherwise be lost in compaction and then re-derived.

## /handoff

The /handoff skill writes a handoff file to a location outside the work tree, ... by default.

### Handoff structure

The handoff file is structured as follows:
1 Preamble -> Metadata and session outline

- Branch | Branch name
- Checkout | Path the branch is checked out in
- Status | Verification status
- Progress | Lifecycle stage of the handoff: complete / consumed

2 Do not re-derive -> What the post-compaction session needs to know to prevent re-deriving it - Decisions(/implementation) - Dead ends - Traps
3 Next -> Ordered work items for the post-compaction session
4 Pointers -> Where evidence can be found
5 Unverifiable -> What not to bother looking for

### Automatic trigger

Every compaction of the main conversation becomes a handoff. When Claude Code compacts (at the auto-compact threshold, or on `/compact`), the plugin's `session.compact` hook:

1. forks the live session, which is served from its prompt cache, and asks the fork for a handoff in the format above, written only from what is already in context;
2. runs the format gate (`lib/verify-handoff.sh`) on it, with one corrected retry if it fails;
3. saves it to the store, and returns it as the compacted conversation **in place of** Claude Code's own summary.

The session carries on from the handoff. Nothing runs in the background, and there is nothing to wait for. If no handoff can be written (outside a git checkout, the fork returns nothing, or the document is malformed twice), the compaction falls back to Claude Code's own summary.

To choose when a handoff is written, set the auto-compact threshold:

`claude  --autocompact <auto|tokens>           Auto-compact window size (auto, or 100k–1M tokens)`

or `/autocompact` inside a session. The plugin has no threshold of its own.

### Manual trigger

/handoff invokes the skills write branch manually. Use it instead of /compact whenever you want to pro-actively shrink your context.

The write branch produces the handoff and ends with an instruction to `/clear`. The first prompt after the `/clear` carries the handoff automatically, verified by the gate. If the cleared session wrote no handoff, it says so instead, and how to `claude --resume` the cleared conversation. `/handoff --read` remains for reading a handoff by hand, for example one belonging to another checkout.

#### Orchestrated trigger

An agent may also invoke the handoff skill "manually". This can be useful when you want an orchestrator agent to monitor (and intervene in) their subagents' context growth.

A subagent cannot instruct itself to clear or compact its session, but its parent agent can do so.
