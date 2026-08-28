
## 2026-08-24 — the filename collides on a trunk-only repo

**Format failed to hold:** task identity. `D15` slugs the filename from the branch
(`.claude/handoff/<branch>.md`), which is right for a project where one branch is one task — kendo,
emmie. `mission_control` has no feature branches: every task runs on `main`. So the write-mode Step 1
path resolved to `.claude/handoff/main.md`, which already held the **spent** handoff from build-order
item 3, and a straight `Write` would have destroyed it with no trace. Caught only because the tool
refused to overwrite a file this session had not read.

Two things follow, and they are separable:

- **The collision is real and silent.** Nothing in Step 1 checks whether the target exists, and nothing
  in the format records which task a handoff is for beyond its `#` heading. A monitor, or a resumed
  session, cannot tell a fresh handoff from a stale one at the same path.
- **Overwriting is usually correct** — a handoff is disposable, one per task, and item 3's was spent. So
  the fix is not "never overwrite"; it is to make the overwrite *visible and deliberate*. Cheapest
  version: Step 1 reports whether the path is already occupied and prints that file's heading line, so
  the author decides with one extra line of orientation and no read of the body.

**Not fixed here**, because it is a change to Step 1's contract rather than to this run's document. The
spent handoff was preserved to the session scratchpad as `spent-handoff-item3-main.md` and the current
one notes the overwrite in `### Traps`.

### 2026-08-24 — retracted the same day, by the user

**Not a defect.** Handoffs are unique *within a branch*, and a handoff is meant to be replaced by the
next one in a chain of sessions — item 3's was spent, so overwriting it was the format working, not
failing. The entry above mistook the intended lifecycle for a collision because it reasoned from
"kendo/emmie have one branch per task" and read `mission_control`'s trunk-only shape as a degenerate
case of that, rather than as the normal case of a different one.

The suggested Step 1 change (report the occupied path and print its heading) is therefore **not
wanted**: it would spend a line of orientation, every run, on making the expected outcome look like a
decision. `D15`'s branch slug stands as written.

What survives is narrower and is left standing above only as a record of the reasoning: nothing in
the format states which task a handoff is *for* beyond its `#` heading. That is a real gap only if
someone wants to tell a fresh handoff from a stale one without opening it — no one has, so it is not
being fixed either.

### 2026-08-27 — the `D15` pointer above is stale; the retraction's substance is not

Noted while merging. `f015abd` ("Handoffs: key by the target tree, declare the checkout") moved the
document out of every checkout entirely — `~/.claude/context-economy/handoffs/<repo>-<branch>-<hash8>.md`,
computed by `handoff_store_path` (`lib/handoff-store.sh`), never hand-built — and `SKILL.md` no longer
cites `D`-labels at all. So "`D15`'s branch slug stands as written" now points at a decision whose
**location half has been superseded**: `docs/design.md:486` still reads
"the **main** working tree" and still rejects putting the file outside the repo, which is what the new
store does. The **slug** half did survive — `skills/handoff/SKILL.md:93` still slugs `/` out of branch
names.

**The retraction itself stands unchanged.** It never rested on where the file lives: the new store is
still one document per repo+branch, so a spent handoff is still replaced by the next one in the chain,
which was the entire point. Flagged as an append rather than an edit, per `CLAUDE.md` — a superseded
pointer in someone's reasoning is reviewable; a rewritten one is not.
