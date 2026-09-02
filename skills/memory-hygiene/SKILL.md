---
name: memory-hygiene
description: |
  Audit and clean the Claude Code project memory store at `~/.claude/projects/<key>/memory/` —
  flagging stale entries (referenced files or agents gone), codified entries (rule now in
  CLAUDE.md or an agent file), duplicates, and contradictions. Defaults to dry-run: produces
  a per-memory verdict report and waits for explicit approval before deleting or editing
  anything. Trigger whenever the user says "clean memory", "audit my memories", "memory
  hygiene", "/memory-hygiene", asks whether Claude's memories are stale or outdated, or wants
  to curate the file-based memory store after a refactor, agent rename, or major CLAUDE.md
  update. Adapted from Anthropic's managed-agents Dreams feature, but adds verification
  against the live repo state — the killer feature Dreams can't do because it has no
  filesystem access. Also syncs sibling git-worktree memory stores: discovers every
  worktree of the current repo, salvages any stray memories they hold back into the
  canonical store, then hydrates each worktree store from canonical so a session in any
  worktree recalls the same memories. Trigger also on "sync worktree memories", "hydrate
  worktree memory", "my worktrees have stale memories", or after creating/removing a worktree.
---

# Memory hygiene

Claude Code stores per-project memories under `~/.claude/projects/<project-key>/memory/` as individual `.md` files indexed by `MEMORY.md`. Over time these accumulate: entries describing rules now codified in `CLAUDE.md` or agent files, entries citing files or agents that have since been deleted or renamed, near-duplicates from parallel sessions, and contradictions when later corrections didn't update earlier memories.

This skill audits the active project's memory store, classifies each memory against the live repo state, surfaces a proposal report, and applies the approved changes. **Default is dry-run** — nothing is deleted or edited without an explicit user "go".

## When to use

- Direct request: "audit my memories", "clean my memory store", "/memory-hygiene"
- Suspicion-driven: user notices Claude citing a rule that's already in `CLAUDE.md`, or referencing an agent that no longer exists
- Post-refactor: after a session in which `.claude/agents/`, `CLAUDE.md`, or core conventions changed substantially
- Periodic check: on long-lived projects with active development
- Worktree sync: "sync worktree memories", "hydrate my worktrees", or after `git worktree add`/`remove` — multi-worktree repos drift because memories written in a worktree strand there. Even when the canonical store needs no cleaning, the hydration pass alone is worth running.

## When NOT to use

- The user is asking about `CLAUDE.md` itself — different file; use a CLAUDE.md-auditing skill such as `claude-md-improver` if one is installed.
- The user wants to *add* a memory — they should just say so in conversation; the auto-memory system handles writes.
- The user is asking about session transcripts, plans, retrospectives, or task lists — those aren't memory.
- The store has fewer than three entries — not worth a five-phase pipeline; just look at it together with the user.

## Phases

This is a five-phase pipeline. The gate between phase 4 (proposal) and phase 5 (apply) is the only structural protection against destructive auto-action — don't skip phases or apply edits inline mid-audit.

### Phase 1 — Locate the store(s)

Claude Code encodes the project key by replacing `/` with `-` in the absolute working directory. A git **worktree** is a distinct directory, so each worktree of one repo gets its own project key and its own memory store — memories written from inside a worktree strand there, invisible to the main store. Phase 1 resolves the **canonical** store and discovers every **sibling worktree** store that should mirror it.

**Canonical store = the main worktree's store.** Resolve it from anywhere (works even when run from inside a worktree) via the repo-identity key, not a path-name guess:

```bash
MAIN_WT=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")  # main worktree path
CANON_KEY=$(echo "$MAIN_WT" | sed 's|/|-|g')
CANON_DIR="$HOME/.claude/projects/$CANON_KEY/memory"
```

If the user passes an explicit scope (`/memory-hygiene <project-key>`), audit that store instead and skip worktree sync. If `CANON_DIR` doesn't exist or holds only `MEMORY.md` with no entries, there's nothing to propagate — fall back to single-store behaviour.

If `MEMORY.md` is missing but memory files exist, surface that as a structural issue first — the index is the entry point for context loading, so missing-index memories are effectively orphaned. Propose rebuilding the index as part of the audit.

**Discover sibling worktree stores — via git, never by name.** Enumerate worktrees with `git worktree list`; every non-main worktree maps to a hydrate target:

```bash
git worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r wt; do
  [ "$wt" = "$MAIN_WT" ] && continue
  key=$(echo "$wt" | sed 's|/|-|g')
  echo "$HOME/.claude/projects/$key/memory"   # hydrate target (may not exist yet → create on apply)
done
```

> **Do NOT discover worktrees by globbing `~/.claude/projects/*<reponame>*`.** Name-matching is the brittle trap: it sweeps in **separate repositories that merely share a name prefix** (e.g. `<repo>-docs`, a different repo with its own distinct memory store) and would clobber them during hydration. `git worktree list` returns only true co-members of *this* repo — `git rev-parse --git-common-dir` differs per repo, so a separate clone can never masquerade as a worktree. If a target's decoded path resolves to a directory with its own `.git` that is *not* in `git worktree list`, exclude it and flag it; never hydrate it.

Carry forward two sets into the later phases: `CANON_DIR` (the store to audit and treat as source of truth) and the list of worktree store dirs (the hydrate targets, some of which may not exist yet).

### Phase 2 — Load and parse

Read `MEMORY.md` and every `*.md` file in the directory. For each memory file, parse:

- **Frontmatter**: `name`, `description`, `metadata.type` (and any other fields the user's local format includes)
- **Load-bearing claims in the body**:
  - File path references — `<dir>/<file>`, `.claude/agents/<name>.md`, `CLAUDE.md:<line>` patterns
  - Agent or skill names — bare references like `engineer`, `inspector`, `/issue-writer`
  - Rule statements — short claims like "Skip inspector on mechanical rewrites" or "Run the full pre-push CI surface before push"
  - Cross-links — `[[other-memory-name]]` references between memories

Keep the raw inventory in working memory for phase 3. Don't pre-summarise.

### Phase 3 — Verify against the live repo

For each memory, check three categories of claim against the live state at `cwd`.

**Entity existence — mechanical:**
- Each referenced file path: does the file still exist? Use `Read` or `ls`.
- Each referenced agent: does `.claude/agents/<agent>.md` exist?
- Each cross-link `[[name]]`: does `<name>.md` exist in the memory store?

**Codification — load-bearing:**
- Does `CLAUDE.md` (root or `.claude/CLAUDE.md`) contain the rule the memory states? Grep for distinctive phrases from the memory body, not generic words.
- Does any file under `.claude/agents/` contain the rule?
- Does any file under `.claude/skills/` contain the rule?
- If yes — the memory has been codified; the codified version is canonical and the memory is now redundant.

**Duplication and contradiction — cross-memory:**
- Are two memories making the same claim with different framing? Candidate for merge.
- Are two memories making contradictory claims? Surface to user; the newer one usually wins but the user decides.

Verify carefully. False positives here cost the user real memory. When in doubt, lean toward "keep" and surface the doubt in the proposal — don't silently classify as delete.

**Worktree strays — pull up before push down.** For each sibling worktree store from Phase 1, diff every `*.md` against the canonical store. Hydration (Phase 5) overwrites worktree stores with canonical, so anything classified wrong here gets destroyed — be conservative. Classify each worktree file:

- **In-sync** — byte-identical to the canonical file of the same name. No action; hydration is a no-op for it.
- **Stale-draft** — same name as a canonical file but older/diverged, and the canonical version is a superset or clearly supersedes it (check `originSessionId`, dates, and whether canonical's body contains the stray's claims). Safe to overwrite on hydrate.
- **Novel** — a filename absent from canonical, OR a same-name file whose body carries claims the canonical version lacks. **This is the dangerous one.** Treat it as a candidate to **salvage into canonical first** (the pull-up), exactly as you would a Phase-3 new observation: verify its claims against the live repo, then stage it as an add/merge into canonical. Never let hydration delete a Novel stray that hasn't been salvaged.

Use `diff -q` for the identical check and a full `diff` to judge stale-vs-novel. When a same-name file diverges, read both fully — don't assume the higher mtime wins (a file copied during a worktree setup carries a misleading mtime).

### Phase 4 — Propose

Produce a verdict table. Use this exact structure so it reads consistently across runs:

```markdown
## Memory hygiene · proposal for <project-key>

| # | Memory | Verdict | Reasoning |
|---|--------|---------|-----------|
| 1 | `name-one.md` | Keep | Valid; all references resolve; not codified |
| 2 | `name-two.md` | Edit | References deleted agent `scout`; rule still valid — rewrite to drop `scout` |
| 3 | `name-three.md` | Delete | Codified in CLAUDE.md:102 ("Skip inspector on mechanical-rewrite PRs") |
| 4 | `name-four.md` | Merge | Duplicates `name-five.md` with slightly different framing — fold both into one |

**Summary:** N keep · N edit · N delete · N merge
**Index changes:** N entries removed from MEMORY.md, N entries updated
```

After the table, list the **proposed edits in detail** — exactly which lines change in each "edit" memory, the merged content for each "merge" pair, and the new `MEMORY.md` index lines. The user must be able to read the proposal and understand exactly what will happen before they say go.

**Worktree sync section (only when sibling worktree stores exist).** Append a second table so the user sees the propagation plan separately from the canonical-store audit:

```markdown
## Worktree memory sync · N worktrees discovered via `git worktree list`

| Worktree store | In-sync | Stale-draft (overwrite) | Novel (salvage→canonical) | Missing dir |
|----------------|---------|-------------------------|---------------------------|-------------|
| `…-<repo>-wt1/memory` | — | — | — | will create + hydrate 75 files |
| `…-<repo>-wt2/memory` | 0 | 2 (`project_issue_workflow`, `reference_api_docs`) | 0 | — |
| `…-<repo>-wt3/memory` | — | — | — | will create + hydrate 75 files |

**Salvage first:** <list each Novel stray + its staged add/merge into canonical, or "none">
**Then hydrate:** copy the cleaned canonical store (N `*.md` + `MEMORY.md`) into each worktree store, overwriting stale-drafts and removing canonical-absent files. Excluded (separate repos, never touched): <list any name-adjacent non-worktree dirs, e.g. `…-<repo>-docs`>
```

**Stop after this phase and wait for explicit approval.** Don't apply anything yet, don't half-apply the "obvious" ones, don't propose-and-immediately-execute. The dry-run gate is the contract — and it now also guards destructive hydration, which overwrites whole worktree stores.

### Phase 5 — Apply (only after explicit user "go")

Only after the user explicitly approves — words like "go", "apply", "do it", "approved", "yes":

1. For each "edit" memory: apply the rewrite. Update the frontmatter `description` if its body claim has changed materially.
2. For each "delete" memory: remove the file with `rm`.
3. For each "merge" pair: write the merged content to the chosen target, delete the other.
4. Rewrite `MEMORY.md` to reflect the current set of memory files — preserve the order and one-line-per-memory format.

**Then — and only then — hydrate the worktrees** (order matters: the canonical store must be fully cleaned and salvaged *before* it overwrites anything):

5. **Salvage first.** Apply every approved Novel-stray pull-up into the canonical store (add the new file + `MEMORY.md` line, or merge into the existing canonical file). After this step the canonical store contains everything worth keeping from every worktree.
6. **Hydrate each target.** For each sibling worktree store, mirror canonical into it — create the `memory/` dir if missing, copy all canonical `*.md` + `MEMORY.md` over the top, and remove any file present in the target but absent from canonical (those are the stale-drafts/obsolete strays, already accounted for in the proposal):

   ```bash
   mkdir -p "$TARGET_DIR"
   rsync -a --delete "$CANON_DIR"/ "$TARGET_DIR"/   # mirror; --delete prunes canonical-absent strays
   # no rsync? → rm -f "$TARGET_DIR"/*.md && cp "$CANON_DIR"/*.md "$TARGET_DIR"/
   ```

   Never run the mirror against a path that isn't in `git worktree list` — re-confirm each target's membership immediately before the `--delete` mirror, since `--delete` is irreversible.

After applying, surface a one-line summary: `Applied: N deleted, N edited, N merged. Index updated. Hydrated K worktrees (J files each), salvaged S strays.` Don't re-show the full table — the user already approved it.

If the user approves *some* but not others ("delete 3 and 5, keep 7"), apply only those and re-stage the rest into a new proposal. Don't apply the unapproved ones.

## Heuristics — when to keep vs delete

The single most common failure mode for memory hygiene is **over-deletion**. Memories are point-in-time observations the user chose to preserve; "I haven't cited this recently" is not evidence of staleness. Delete only when one of these holds:

- **Codified upstream** — the rule is now in `CLAUDE.md` or an agent file in equivalent form. The codified version supersedes; the memory is redundant.
- **All referenced entities gone AND rule doesn't generalize** — every file/agent the memory references has been deleted or renamed AND the underlying rule doesn't apply beyond those entities. If the rule generalizes, prefer **edit** over delete.
- **Strict duplicate** — another memory states the same claim with the same framing. Merge or delete the redundant one.

Don't delete because:
- The memory is old. Memories are durable; age alone is not staleness.
- The memory describes a historical incident. Historical incidents teach lessons — the "Why:" line is often the load-bearing content.
- The memory hasn't been "needed" recently. There's no usage telemetry; you can't know this.
- The memory is opinionated and you'd phrase it differently. It's the user's memory, not yours.

## Heuristics — when to edit vs leave alone

Edit when:
- The memory cites a renamed agent or file but the underlying rule still applies (e.g. memory says "scout cites repo paths", but `scout` is now `/issue-writer` — rule about specs-as-pointers still holds, just rewrite the agent name).
- The memory's frontmatter `description` no longer matches the body (drift after a partial update).
- The memory has dead `[[cross-links]]` to memories that have been deleted — drop or repoint them.

Leave alone when:
- The memory has minor stylistic quirks but is still useful as-is.
- The memory has a framing the user might disagree with — don't edit toward your preferences; flag and ask.
- The memory cites an old date or session ID. Those are historical anchors, not staleness signals.

## Heuristics — when to merge

Merge when two memories:
- State substantively the same rule with similar framing
- Were written in close succession from the same incident (same `originSessionId` if present)
- Cross-reference each other with blurred boundaries

Don't merge:
- Memories with overlapping topics but materially different rules — keep them separate.
- Memories written months apart from independent incidents. Those represent two observations, not one — preserve the distinction.

## Format conventions

Preserve the conventions the local store already uses — different users format memories differently. Before writing, sample 2-3 existing memories to see:

- Whether `metadata.originSessionId` is present
- Whether bodies use a `**Why:**` / `**How to apply:**` structure or freeform paragraphs
- Whether cross-links use `[[name]]` or `[name](name.md)` or both

Match the local style. Don't impose a global standard.

`MEMORY.md` is an index, not a memory. It has no frontmatter. Each line is `- [Title](file.md) — one-line hook` and stays under ~150 characters. When updating `MEMORY.md`, only change the lines that need to change — don't rewrite from scratch.

## What this skill is NOT

- **Not the auto-memory writer.** The user's auto-memory system writes new memories during normal conversation. This skill only audits and cleans existing memories.
- **Not a session-transcript miner.** Anthropic's Dreams feature mines past session transcripts for patterns; this skill only reads the memory store and the live repo. Mining `~/.claude/projects/<key>/sessions/*.jsonl` is a possible v2 feature, not in scope here.
- **Not a CLAUDE.md improver.** If the user wants to improve `CLAUDE.md` itself, point them at a CLAUDE.md-auditing skill such as `claude-md-improver` if one is installed.
- **Not destructive without approval.** The dry-run gate at phase 4 is non-negotiable. If you find yourself about to skip it "just for the obvious cases", stop.

## Design lineage

The workflow shape is adapted from Anthropic's managed-agents [Dreams](https://platform.claude.com/docs/en/managed-agents/dreams) feature, which curates managed-agent memory stores asynchronously. Dreams reads `(memory_store, sessions)` and produces a new `memory_store` with duplicates merged, contradicted entries replaced, fresh insights surfaced.

This skill mirrors the curation step but trades off differently:

- **Synchronous, in-thread** — runs in the current Claude Code session, minutes not tens of minutes
- **No session-transcript input** — only reads the memory store + the live repo (v2 candidate: session-mining)
- **+ Live-repo verification** — Dreams has no filesystem access; this skill greps actual `CLAUDE.md` / agent files / skill files to detect codification, which is the highest-value check for an active codebase
- **In-place after approval** — Dreams writes to a separate store; this skill writes to the same store after explicit user approval. The dry-run report is the safety equivalent of Dreams' separate-store output.
