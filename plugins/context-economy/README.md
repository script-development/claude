# Content economy

A plugin bundling the /handoff skill and supporting hooks.

The /handoff skill aims to reduce context growth post-compaction by providing the post-compaction session with references to decisions, traps and dead-ends from the pre-compaction session, which would otherwise be lost in compaction and then re-derived.

## /handoff

The /handoff skill writes a handoff file to a location outside the work tree, ... by default.

### Handoff structure

The handoff file is structured as follows:
1 Preamble -> Metadata and session outline

- Branch | Branch name
- Checkout | Path the branch is checked out in
- Status | Verification status
- Progress | Lifecycle stage of the handoff: writing / complete / consumed

2 Do not re-derive -> What the post-compaction session needs to know to prevent re-deriving it - Decisions(/implementation) - Dead ends - Traps
3 Next -> Ordered work items for the post-compaction session
4 Pointers -> Where evidence can be found
5 Unverifiable -> What not to bother looking for

### Automatic trigger

The automatic trigger hooks into Claude's auto-compaction mechanism through a PreCompact hook. At the latest possible moment before compaction, the hook does two things
1 Create a skeleton handoff file - mostly empty with two notable exceptions:

- Progress (field) | Lifecycle stage of the handoff: Writing / Complete / Consumed
- Next (section) | Contains an instruction to wait for the progress field to be overwritten to "Complete"

By design the skill uses one handoff file per worktree, and overwrites stale handoffs with the skeleton for a fresh handoff.

2 Spawn a detached session forked just before auto-compaction

After this point there are two sessions, which do the following:

A - Main session: Starts writing the auto-compacting summary
B - Forked session: Starts drafting the handoff

The forked session is run without a binding auto-compaction threshold as it must keep its context to write the handoff.

The Main session generally completes compaction before the Forked session finishes the handoff process. When the post-compaction session starts, a SessionStart hook detects the skeleton's Progress field still says "writing" and, instead of blocking itself, hands the model a bounded Bash poll loop to run as its own first tool call — waiting until Progress flips to "Complete" before continuing.

The Forked session drafts a handoff per the /handoff skill and writes it to the skeleton file only when finished overwriting the Progress field with "Complete".

From the Main session's perspective new Next items appear at the same time as Progress flips to Complete, the signal to start the first real Next item.

To configure when a handoff is written simply change the auto-compact threshold:

`claude  --autocompact <auto|tokens>           Auto-compact window size (auto, or 100k–1M tokens)`

### Manual trigger

/handoff invokes the skills write branch manually. Use it instead of /compact whenever you want to pro-actively shrink your context.

The write branch produces the handoff and will end with an instruction to /clear, and then start the next session with /handoff --read.

Using /handoff --read is just as suggestion. Any prompt after /clear has finished works, e.g. starting with a "." prompt will also activate the handoff skill's read branch.

The handoff file is automatically injected into the post-compaction session.

#### Orchestrated trigger

An agent may also invoke the handoff skill "manually". This can be useful when you want an orchestrator agent to monitor (and intervene in) their subagents' context growth.

A subagent cannot instruct itself to clear or compact its session, but its parent agent can do so.
