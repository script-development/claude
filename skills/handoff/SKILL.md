---
name: handoff
description: |
  Writes a context handoff — the small document that lets a fresh session resume this task without
  re-deriving what this one learned — and reads one back at the start of a resumed session. Two
  modes: write (the default) composes the handoff from what is already in context and puts it
  through the format gate; `--read` verifies a handoff's citations before trusting it, then acts on
  the verdicts. Use when context is running out and the work isn't finished ("write a handoff", "I'm
  about to /clear", "hand this off", "save state before compacting"), when the statusline flags that
  a reset is due, or at the start of a session that is picking up someone else's unfinished task
  ("read the handoff", "resume from the handoff", "where did we leave off").
argument-hint: "[--read] [handoff-file]"
allowed-tools: Read, Grep, Glob, Bash, Write
---

# Handoff

A handoff exists to carry the half of a session that does not survive summarisation. Decisions and
what they beat, dead ends and why they were abandoned, traps — none of that re-derives from the tree
at any price, while anything with a `path:line` re-derives on demand for the cost of one read. So the
document is deliberately lopsided: it spends its words on the irrecoverable half and reduces the
recoverable half to pointers.

There is no Phase Alpha or Omega here. This skill picks up no tracked issue, mutates no tracker and
creates no worktree, so there is nothing to prepare and nothing to tear down. Every step still
prints its marker per `CLAUDE.md`, annotated with the mode, because both modes have a Step 1 and a
monitor reading markers cannot otherwise tell which one it is watching:

```
>> STEP: handoff — 1 (write)
>> STEP: handoff — 1 (read)
```

## The one rule that shapes everything

**Write the handoff from what is already in context. Do not read, grep, or list anything to author
it.**

Not primarily frugality, though it is that too — this skill runs at maximum context depth by
construction, so each of its own tool calls is among the most expensive calls of the session, and
those calls, not the file, are the dominant cost of authoring. The deeper reason is that the rule is
a *content* test, and it survives being paraphrased in a way a budget never does:

> Anything you have to re-read in order to write it down is, by definition, re-derivable. So it
> belongs in `## Pointers` as a pointer, not in the body as a claim.

If you find yourself wanting to open a file to describe what it does, that is the format telling you
the description is not worth its tokens. Cite it instead.

The two exceptions are mechanical, not substantive: Step 1's single orientation call, which resolves
paths and never file contents, and Step 3's gate. In `--read` mode the rule does not apply at all —
reading is the entire job there.

## Where the file goes

`~/.claude/context-economy/handoffs/<repo>-<branch>-<hash8>.md` — a machine-local store outside
every checkout, keyed by the **target**: the repository and branch the work is in, never the
repository the session happens to be sitting in. Step 1 computes the name; don't hand-build it.

Three things forced this, in order of how expensive getting them wrong was:

**The session's repo is not the work's repo.** A mission_control skill drives a sibling checkout
with `git -C` and never moves its cwd (`CLAUDE.md`, Phase Alpha). Deriving the location from cwd
wrote the document to mission_control, keyed to *mission_control's* branch — so two runs against
different tickets overwrote each other's handoff, and the gate defaulted to verifying citations
against the wrong repository entirely.

**Only a central store can be enumerated.** The read leg is a `SessionStart` hook, and a hook knows
its cwd and nothing else. Putting the file in the *target* repo fixes the keying and makes the
document undiscoverable: no path derived from cwd can reach a sibling checkout. Listing one known
root can. That is the whole reason the store is centralised rather than distributed — see
`lib/handoff-store.sh` for the resolution order.

**It must survive its own worktree.** An automated run works inside a throwaway worktree that its
caller's Phase Omega deletes (`skills/prepare-agent-run/SKILL.md:99`). A handoff written there dies
with the run that wrote it, which is the one failure mode that leaves no trace: the work looks
handed off and the document is gone. Outside every checkout, this cannot happen — and unlike the old
main-worktree rule, it also holds when the target repo is deleted or re-cloned.

Machine-local, and **not** committed: a handoff carries Dead ends and Traps, which is exactly where
candid remarks about a project's tooling live, and committing that to a client repo puts it in
`git log` permanently. Same argument that put the compaction corpus outside every checkout; the
store sits beside it for that reason. The cost is that handoffs do not travel between machines —
accepted, and recoverable later by syncing the store through a private repo if it ever matters.

**Therefore `checkout:` is a required header field.** Nothing else in the document identifies the
tree its citations describe: `branch:` names a ref, and the same ref name exists in every sibling
checkout on the machine. Omit it and the gate falls back to `$PWD` and reports a full page of
MISSING that is indistinguishable from real rot. The gate always prints which checkout it used,
where that came from, and that checkout's HEAD — read that line before believing any verdict under
it.

One mechanical consequence: branch names contain `/`, so the filename slugs it (`fix/foo` →
`fix-foo`; detached HEAD falls back to the short SHA).

## The format

Sections in file order, which is also **authoring order — by irrecoverability**. It is a
machine-checked contract, not a template to remember: the gate refuses a malformed handoff, so write
it from the shape below and let the tool correct you.

```
# Handoff — <task>
branch: / checkout: / compacted: / status:
                                    envelope + one-line orientation
## Do not re-derive                 the reason the file exists (heading only; a container)
### Decisions                       what was chosen AND what it beat
### Dead ends                       what was tried, why it was abandoned
### Traps                           what will bite the next session
## Next                             1-5 concrete steps
## Pointers                         fenced block of citations
## Unverifiable                     optional: real files the gate cannot resolve
```

- `compacted: no | yes | unknown` is gated for one reason: it says whether the expensive half of the
  document is first-hand. If the session auto-compacted before writing, its decisions were
  reconstructed from a summary produced by the very process that drops them. `unknown` is a
  legitimate answer; omitting it is the only answer that tells a reader nothing.
- **Decisions record what the decision beat**, not just what it was. A decision without its rejected
  alternative gets re-litigated by the next session, which is the expensive failure this document
  exists to prevent.
- The three `###` subsections must be non-empty. **`None.` is a real answer and passes**; silence is
  not an answer and fails. An absent section cannot be distinguished from a run that never looked.
- `## Next` names files the resumed session is about to *create*. That is a plan, not a claim, so it
  is exempt from citation coverage — as is `## Unverifiable`, which is cross-repo by definition.
- **Background work that outlives the reset goes in these same sections, by disposition.** A clear
  kills running *foreground* tasks and **preserves** backgrounded ones — they keep running, stay
  registered, and their completion notification (`status`, `summary`, and an `output_file` path; never
  the body) lands in the *fresh* session, which otherwise has no idea what they were for. The task list
  itself re-derives from `/tasks`, so what belongs here is only the intent, and the section is the
  disposition:

  - **blocks a step** → that `## Next` step says so, and carries a fallback: *"if it hasn't reported
    by then, `TaskOutput <id>` for status; if dead, re-derive by X."* A bare wait is an unbounded
    instruction, and unattended that is a hang — the one outcome worse than a bad handoff.
  - **feeds a step without blocking** → that step says to fold the result in when it lands. Deferring
    the read is the point: the body enters context only if something reads it, and turn one of a fresh
    segment is the most expensive moment to spend that.
  - **feeds nothing** → one `### Traps` line, so an unprompted report reads as expected rather than as
    a live thread.

### Pointers

One citation per line, `#` comments allowed:

```
# what this cluster is for
path/to/file.php:756 | expected substring on that line
path/to/other.sh | expected substring anywhere in the file
```

The expected substring is the point — it is what turns "the file still exists" into "the claim is
still true". Keep it short and distinctive.

**Never write `path:symbol`.** The resolver's trailing-reference rule matches digits only, so a
non-numeric anchor stays glued to the path and a real file reports MISSING. The gate refuses the form
outright (exit 2). Write `Foo.php:24 | someMethod` instead, which is the stronger claim anyway: it
verifies line 24 still holds the symbol, where `Foo.php:someMethod` could at best confirm the file
exists.

**Every body claim carrying a `path:line` must appear in Pointers.** A citation the gate never sees
reads as verified precisely because everything around it was — so that is a gate failure, not a
warning. The join between a claim and its citation is the `path:line` string itself; keep it exact,
because a CHANGED verdict names a line and nothing else tells a reader which conclusion just became
suspect.

## Write mode — Step 1: locate the gate, the tree, and the file

Print `>> STEP: handoff — 1 (write)` before doing anything else in this step.

**Name the target tree first.** `TARGET` is the checkout the work is in and whose branch the
citations describe — *not* the session's cwd, and the two differ whenever a mission_control skill
drives a sibling checkout. If the work happened in a worktree this run created, `TARGET` is that
worktree. Get this wrong and everything below is keyed to the wrong repository.

**Then one bash call, and it resolves paths only — never file contents.**

```bash
TARGET=<absolute path of the checkout the work is in>   # cwd only if that is genuinely where it is

main=$(git -C "$TARGET" worktree list | head -1 | awk '{print $1}')
here=$(git -C "$TARGET" rev-parse --show-toplevel)
ref=$(git -C "$TARGET" rev-parse --abbrev-ref HEAD)
[ "$ref" = HEAD ] && ref=$(git -C "$TARGET" rev-parse --short HEAD)
slug=$(printf '%s' "$ref" | tr '/' '-')
# Plugin-cache glob first, last match wins (newest version) -- the same pattern
# statusline.sh already uses for context-thresholds.sh, so a plugin bump (a new cache
# directory) can never dangle this the way a version-embedding path would.
gate=
for g in "$HOME"/.claude/plugins/cache/*/context-economy/*/lib/verify-handoff.sh; do
    [ -x "$g" ] && gate=$g
done
if [ -z "$gate" ]; then
    for g in "$here/lib/verify-handoff.sh" \
             "$HOME/.claude/lib/verify-handoff.sh" \
             "$PWD/plugins/context-economy/lib/verify-handoff.sh"; do
        [ -x "$g" ] && gate=$g && break
    done
fi
store=
for s in "$HOME"/.claude/plugins/cache/*/context-economy/*/lib/handoff-store.sh; do
    [ -r "$s" ] && store=$s
done
if [ -z "$store" ]; then
    for s in "$here/lib/handoff-store.sh" \
             "$HOME/.claude/lib/handoff-store.sh" \
             "$PWD/plugins/context-economy/lib/handoff-store.sh"; do
        [ -r "$s" ] && store=$s && break
    done
fi
if [ -n "$store" ]; then
    . "$store"
    mkdir -p "$(handoff_store_dir)"
    echo "handoff=$(handoff_store_path "$main" "$slug")"
else
    echo "handoff=STORE-LIB-MISSING"
fi
echo "checkout=$here"
echo "branch=$ref"
echo "gate=${gate:-NONE}"
```

The filename is computed by `handoff_store_path`, never hand-built. It is a contract shared with
two hooks that must find the same file — `handoff-inject.sh` to surface it and
`session-end-marker.sh` to measure whether it covered the discarded session — and a hand-assembled
name that differs by one character is not a broken filename, it is a handoff nothing will ever read.

`checkout=` goes verbatim into the `checkout:` header. `here` rather than `TARGET` because git
normalises the path (and on Windows returns a different notation than the shell does); the gate
compares against git's form.

The gate is found by probing, in order: the plugin-cache glob (newest installed version wins),
then the target checkout's own `lib/` (a session already inside this repo), then `~/.claude/lib/`
(a pre-plugin symlink install), then the retired vendored path as a last-resort fallback. Not
through a sibling path like `<project-root>/../mission_control/tools/`, which is layout config of
exactly the kind this repo refuses to make configurable; and not by asking the model where its own
skill file lives, which it cannot reliably know.

If `gate=NONE`, **write the handoff anyway** and mark it unverified in `status:`. Degrade capability,
never execution — an unverified handoff is worth far more than no handoff.

If `handoff=STORE-LIB-MISSING`, the install is incomplete — `lib/handoff-store.sh` never reached
the place the hooks look for it. Write to `~/.claude/context-economy/handoffs/<repo>-<slug>-<hash>.md` with
`hash` = the first 8 characters of `printf '%s' "$main" | md5sum`, say in `status:` that the name was
built by hand, and flag the install — a name built by hand is exactly the failure the paragraph
above describes.

## Write mode — Step 2: compose

Print `>> STEP: handoff — 2 (write)` before doing anything else in this step.

One `Write` call, to the path Step 1 printed. Author in section order, which is irrecoverability
order: do Decisions, Dead ends and Traps *first* and best, while there is still budget for them.
`## Next` and `## Pointers` are the cheap half, and the half that survives without you.

Recall the one rule — if a sentence needs a file open to write, it is a Pointer.

## Write mode — Step 3: verify

Print `>> STEP: handoff — 3 (write)` before doing anything else in this step.

```bash
bash "$gate" "$handoff" "$checkout"
```

Both arguments, always. The second is the checkout the citations belong to, and letting it default is
how a session ends up reading a page of verdicts about the wrong tree.

Read the exit code, because the two failures need different work from different people:

- **exit 2 — contract violation.** The document is malformed: a required section missing or empty, no
  closed Pointers fence, a `path:symbol` anchor. Citations were *not checked at all*. Fix the
  structure and re-run.
- **exit 1 — gate failure.** A citation is MISSING or CHANGED, or a claim cites a `path:line` that
  never made it into Pointers. Fix the citation, or add the entry. A MISSING here usually means the
  path was written from memory — the one thing the no-reading rule cannot protect against — so
  correct it against the verdict rather than deleting the claim.
- **exit 0.** Done. WARN lines never change the exit code.

Warnings are advisory, and some are *supposed* to fire — a path the plan is about to create, a
pointer only `## Next` refers to. **Never weaken a warning to silence it.** A wrong warning is worse
than a missing one, because it is the whole reason people stop reading warnings; a correct one is the
tool working. The general test, and the one to apply to any check added here later: *a warning earns
its place by being actionable, not by being true.*

The `size` line reports the file in turns of work, against a target and a ceiling the tool sources
for itself. **Do not restate those figures here or in the handoff** — a second copy is exactly what a
single source of truth exists to prevent, and reconciling it would cost an extra tool call at the
worst possible moment. Size can never fail the gate: a size gate makes cutting the non-citable half
the cheapest way to pass, inverting the entire design. **When over budget, the line to cut is a
Pointer** — pointers re-derive from the tree; a decision does not re-derive at all. If it genuinely
had to be long, say why in the handoff.

## Write mode — Step 4: hand back — or don't

Print `>> STEP: handoff — 4 (write)` before doing anything else in this step.

No tool call. Report the path, the exit status, and any warning worth acting on. What happens next is
decided by **why this write is happening, not by who is watching**:

**Fired by the Stop hook itself** — this turn opens with `Stop hook feedback:` and tells you to run
this skill "now, before anything else." This path exists to be as invisible as real auto-compaction:
nobody asked for a pause, only for insurance against one. Report the write in one line and **keep
going with whatever was in flight.** Do not tell anyone to `/clear`. The handoff may be stale by the
time anything reads it back — that is the accepted cost of the margin `CTX_COMPACT_THRESHOLD_TOKENS`
keeps against racing real auto-compaction, not a defect in this step to correct for.

**Invoked directly** — a human asked for one, or an orchestrator watching this session's growth from
outside sent the instruction. Either way, someone chose the manual path *because* they want the pause,
so give it to them. A model cannot reset its own context — there is no tool for it, `/clear` and
`/compact` are user commands — so this step ends in an instruction or a confirmation, never an action,
and which one depends on who is there to receive it:

- **A human is attending:**

  > Handoff written to `<path>` (gate: OK). Run `/clear`, then `/handoff --read` in the fresh session.

- **Nobody is attending** (the ask came from an orchestrator, a driver script, anything that is not a
  live human at the keyboard): there is no one to instruct and no self-reset tool either, so say only
  that it is safe to act on:

  > Handoff written to `<path>` (gate: OK). Ready for reset.

  That confirmation is what lets whatever asked for the write kill and relaunch this run against the
  handoff it just produced — the same clear-then-read cycle, performed from outside the process
  instead of inside it.

## Read mode — Step 1: locate and verify, before reading

Print `>> STEP: handoff — 1 (read)` before doing anything else in this step.

Verify **first**, in the same call that locates things. Reading an unverified handoff spends the
tokens and only then discovers which parts were false; verifying first tells you what to trust before
you pay for it.

Locate by **listing the store**, not by deriving a path — the handoff you want may belong to a
sibling checkout, and nothing about the session you are in can name it:

```bash
ls -t ~/.claude/context-economy/handoffs/*.md 2>/dev/null \
  | while read -r f; do
        printf '%s\t%s\t%s\n' "$f" \
            "$(grep -m1 '^branch:' "$f" | cut -d' ' -f2-)" \
            "$(grep -m1 '^checkout:' "$f" | cut -d' ' -f2-)"
    done
```

Newest first. Pick by the branch and checkout, not by position: several may be live at once, and if
the SessionStart hook already surfaced one it says in its own output whether that was an exact match
or a guess made on recency.

Then verify with **one argument**:

```bash
bash "$gate" "$handoff"
```

One, not two — unlike write-mode Step 3. The document declares its own `checkout:`, and the reader
has no independent knowledge of the right tree to pass. Supplying a second argument here overrides
the only authoritative statement of it with a guess drawn from wherever this session happens to be
standing. Pass one only to verify deliberately against a *different* tree, in which case the gate
announces the override.

If the gate is unreachable, read the handoff anyway and treat every pointer as unverified.

## Read mode — Step 2: read

Print `>> STEP: handoff — 2 (read)` before doing anything else in this step.

One `Read` of the handoff. Note `compacted:` — on `yes` or `unknown` the body was reconstructed from
a summary, so its Decisions may be lossy.

## Read mode — Step 3: act on the verdicts

Print `>> STEP: handoff — 3 (read)` before doing anything else in this step.

**A citation verdict can only ever demote the cheap half.** MISSING or CHANGED says a *pointer*
rotted: that pointer must now be re-derived, and any body claim joined to it by the same `path:line`
string is suspect until it is. It says nothing about Decisions, Dead ends or Traps. Those are not
derived from the tree's current state — they record what was chosen, what was tried, and what bites.
A moved line does not un-decide a decision. Do not treat a red verdict as licence to reopen the
expensive half; that is the re-derivation this document was written to prevent.

**Do not re-derive eagerly.** Having read the handoff, resist opening every pointer to "get
oriented". A pointer's cost is its size multiplied by the remaining lifetime of the session, so
resolving it at resume is the most expensive moment available, and resolving it at the point of use is
the cheapest. Open a pointer when the step you are on needs it — the rotted ones included.

Then start the first `## Next` item that is **not** blocked on a task that has yet to report — not
simply item 1. A blocked step names the task it waits on and what to do if it never lands; check that
before assuming the step is ready. Say which path the run took: verified clean, verified with rot in
listed pointers, or unverified.

## Feedback — a deliberate divergence, stated so it does not read as an omission

`CLAUDE.md` requires every skill that consumes a human-authored artifact to close with a *required*
feedback section, never omitted, because an absent section cannot be distinguished from a run that
never looked. This skill does not do that, on purpose.

The reason is that an unconditional feedback write lands its cost at precisely the moment this skill
exists to relieve: one more expensive tool call at maximum depth, taxing the very thing being fixed.
So: **write to `skills/handoff/handoff-improvement-feedback.md` only when the format failed to hold
something** — a decision with nowhere to go, a gate verdict that was wrong, a required section that
could not honestly be filled. Route by audience as usual; findings about the *task* belong in the
handoff itself, which is already being written.

The "did you look" guarantee is preserved inside the artifact instead, at no extra cost: **the
handoff's own `status:` line states whether the format held.** Put that clause in `status:` rather
than in a new field, because `status:` is gated and so cannot silently vanish. An empty feedback file
therefore remains distinguishable from a run that never checked — the handoff says which.
