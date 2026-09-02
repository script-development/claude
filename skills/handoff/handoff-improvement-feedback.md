
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

### 2026-09-02 — the gate probe never learned it was a plugin

Measured while installing this bundle as a real plugin (`context-economy@mission-control`, user
scope, `gitCommitSha 434c7ae`) on a machine that had never had it. The install, the hooks and the
49/49 gate all pass. `SKILL.md`'s own dependency resolution does not.

`skills/handoff/SKILL.md:187` probes two candidates for the citation gate, and
`:192` two for the store:

```
for g in "$HOME/.claude/lib/verify-handoff.sh" \
         "$PWD/plugins/context-economy/lib/verify-handoff.sh"; do
```

**Neither is `${CLAUDE_PLUGIN_ROOT}/lib`.** The second is the *retired* vendored path — mission_control
deleted `plugins/context-economy/` in `7edc6e7`, so it cannot resolve anywhere any more. The first is
a symlink someone else has to have created; on this machine it was dangling, because it pointed into
`mission_control/tools/`, which the extraction emptied. So a clean plugin install yields
`GATE: NOT RUN` and every pointer in every handoff reads UNVERIFIED — the exact silent downgrade
`install.sh`'s own comment (lines 258–260) warns about, now reachable by doing nothing wrong.

**The hooks got this right and the skill did not**, which is what makes it a drift rather than an
oversight: `hooks/handoff-inject.sh:124` computes `hook_dir` from `${BASH_SOURCE[0]}` and resolves
`$hook_dir/../lib/...`, and its comment at `:119` states the intent outright — "works as a bundle
(hooks/ -> lib/) and as a plugin (`${CLAUDE_PLUGIN_ROOT}/hooks` -> `../lib`) without any of". The same
reasoning was never applied to `SKILL.md`, whose probe list still describes the pre-extraction layout.

**Suggested fix:** put `${CLAUDE_PLUGIN_ROOT}/lib/...` first in both loops, keep
`$HOME/.claude/lib/...` as the second candidate for the bundle install, and drop the
`$PWD/plugins/context-economy/...` candidate — it names a directory that no longer exists in any
repository. `SKILL.md:217`'s prose ("found by probing `~/.claude/lib/` first, then the in-repo path
for a session already") needs the same correction; as written it documents the broken order as
intentional.

**Worked around, not fixed, on this machine:** the four `~/.claude/lib/` links were repointed at the
installed cache copy, which makes candidate one hit. Verified — `handoff-inject.sh` fed a
`jq -n`-built `{source:"clear"}` payload emits 12260 bytes of valid JSON and reports
`GATE: FAILED (exit 1)` on a 6-day-old handoff, i.e. the gate *ran* and found drifted citations.
That workaround is version-pinned to `…/cache/mission-control/context-economy/0.1.0/`, so
`claude plugin update` re-dangles all four silently. The probe order is the real fix.

**Also found, same run:** `~/.claude/lib/handoff-store.sh` had been pointing at
`claude-dotfiles/dotfiles/lib/handoff-store.sh` (163 lines) while the plugin ships its own (178
lines) — fully diverged. Since `SKILL.md:192` probes `$HOME/.claude/lib/` *first*, the stale copy
would have won for the skill while the hook used the current one. Two copies of the store, disagreeing,
in one session. Reordering the probe fixes this half too.
