---
name: sync-worktrees
description: Sync every secondary git worktree with the primary one. Copies every gitignored `.env*` file from the primary into each secondary worktree at the same relative path, and refreshes dependencies (composer install where a composer.json exists, npm install where a package.json exists). Optionally fast-forwards worktrees that sit on the integration branch or detached HEAD. Use this skill whenever the user says "sync worktrees", "refresh worktrees", "update worktrees", "refresh my worktree envs", "align worktrees", or any variant of wanting to catch secondary worktrees up with the main repo. Also trigger proactively after a PR lands that touched `.env.example`, dependency lockfiles, or added new migrations — those changes need to propagate to idle worktrees before the user picks up work in them. Works regardless of how individual developers name their worktrees (generic slots like `<repo>-wt1`, feature-named like `<repo>-feat-xyz`, or anything else).
---

# Sync Worktrees

Keeps every secondary git worktree aligned with the primary one. Works for any worktree layout — generic slots (`<repo>-wt1`, `<repo>-wt2`), feature-named clones (`<repo>-feat-xyz`), or whatever convention the user or team has picked.

This skill reads `integration_branch` from `.claude/project-context.md` — see this plugin's
README for how that file and its notation work. No file, or no field: the bundled script
auto-detects (see below).

The script targets **all** secondary worktrees by design. Naming conventions vary across developers, so filtering to a specific pattern would silently skip legitimate worktrees for anyone not using that pattern. The safety net against unwanted changes to a worktree that's actively being worked on is the refuse-on-divergence rule below, not a naming filter.

The main risk this skill guards against: env files drift silently. You add a new `FOO_API_KEY=…` to an `.env` in the main repo, then a week later pick up an issue in `<repo>-wt2`, and nothing works because that worktree still has the old env. This skill makes catching up a one-shot command.

## When to use

- User explicitly says "sync worktrees" / "refresh worktrees" / "update worktrees"
- After a PR that touched `.env.example`, `composer.lock`, `package-lock.json`, or added a migration that requires new env vars
- When setting up a new generic worktree and you want parity with the primary

## What it syncs

1. **Env files** from the primary worktree → each secondary worktree:
   - every gitignored `.env*` file found in the primary (any depth, skipping `node_modules/`, `vendor/`, every registered secondary worktree, and any `.before-sync-*` file left behind by the version of this script that made backups)
   - copied to the same relative path in each secondary worktree
   - tracked files such as `.env.example` are never copied — they come from git
2. **Dependencies** in each worktree, discovered per manifest (depth ≤ 3, same skip list):
   - every directory holding a `composer.json`: `composer install --no-interaction`
   - every directory holding a `package.json`: `npm install`
3. **Fast-forward to the integration branch** (opt-in via `--pull`):
   - Only when the worktree is on the integration branch or detached HEAD
   - Never when on a feature branch (would pull the integration branch *into* the feature branch, surprising)
   - Never with uncommitted changes (would risk mixing states)

**Integration branch** — first match wins:

1. An explicit `--base <branch>` passed for this run (see below) — a one-off override, use when
   the user names a branch in the moment.
2. `integration_branch` in `.claude/project-context.md`, if set.
3. The script's own auto-detection: `origin/HEAD`, falling back to `main`, then `master`.

**`--base` is refused without a real branch name** — an omitted value used to fall through to
detection, and `--base --pull` used to take the flag *as* the branch name and swallow it, both
silently and both exiting 0. Naming a base and asking for one to be detected are two different
requests.

## How to run

First, ask the user whether to also fetch + fast-forward (default: no). Most worktree slots sit on feature branches, where pulling is the wrong move.

Resolve `<skill dir>` (see below), then read `integration_branch` from
`.claude/project-context.md` if set, and pass it as `--base` unless the user is overriding it
for this run:

```bash
bash <skill dir>/scripts/sync.sh                                      # env + deps only
bash <skill dir>/scripts/sync.sh --pull                               # + fast-forward where safe
bash <skill dir>/scripts/sync.sh --base <integration-branch>          # explicit override, or from project-context.md
```

The script auto-detects the primary worktree (always the first entry in `git worktree list --porcelain`), so no hardcoded paths.

### Resolving `<skill dir>`

A repo may ship its own checked-in copy under `.claude/skills/sync-worktrees/`; that wins over
every other source, since its team maintains it. Otherwise, in order — checked-in copy, then
this plugin's install, then a user-level install — keep the first match:

```bash
skill_dir=
[ -d .claude/skills/sync-worktrees ] && skill_dir=$(cd .claude/skills/sync-worktrees && pwd)
if [ -z "$skill_dir" ]; then
  # Highest cached version wins: sort -V, not the glob's lexical order (0.3.0 > 0.22.0).
  skill_dir=$(for d in "$HOME"/.claude/plugins/cache/*/core-skills/*/skills/sync-worktrees; do
    [ -d "$d" ] && printf '%s\n' "$d"
  done | sort -V | tail -n 1)
fi
[ -z "$skill_dir" ] && [ -d "$HOME/.claude/skills/sync-worktrees" ] && skill_dir="$HOME/.claude/skills/sync-worktrees"
echo "skill_dir=$skill_dir"
```

No match on any of the three — stop: *"sync-worktrees can't find its own bundled script;
reinstall the skill or plugin."*

## Safety rules the script enforces

These exist because each one maps to a real way you can lose work:

- **Diverged env = refuse, don't clobber.** Before writing a worktree's env file the script compares it byte-for-byte with the primary's. If they differ it copies nothing, names the file in its report, and moves on. A divergent env file is a deliberate local override far more often than it is drift, and only the developer knows which — so copy it over by hand when it was drift. This replaced a backup-then-overwrite rule, where a `.before-sync-<timestamp>` copy was what made the overwrite safe: that backup could fail, could be raced by a same-minute rerun, and left a second copy of the secret in the worktree for `git add -A` to stage. Refusing the write needs none of it.
- **A write lands inside the worktree, on a real file, or not at all.** Three shapes are refused rather than reasoned about: a destination that is a symlink (following it writes wherever it resolves), a destination whose *resolved* parent sits outside the worktree (a symlinked parent stays traversable through `mkdir -p` and `cp`, so spelling alone does not keep the write inside), and a destination that exists and is not a regular file — a directory named `.env` would otherwise take `cp` *into* itself as `.env/.env`, and a symlink nested in that directory carries the secret out anyway.
- **A failed step is a non-zero exit.** A refused symlink, an out-of-bounds destination, a failed copy, a composer/npm install failure and a failed fetch or fast-forward all set it. **Two cases deliberately do *not*, and they are one rule, not two exceptions**: a diverged env file, and a worktree that is registered but no longer on disk. Both are *reported skips* — named in a `⚠️` block with the fix beside them — because both are permanent conditions of that repo, so failing on either would make every later sync exit non-zero, which is how a caller learns to ignore the exit status. What a reported skip must never do is let the closing line speak for it: a missing worktree used to be skipped in silence while the report still said every worktree's env files matched primary.
- **Only primary's own env files travel.** A secondary worktree nested inside primary at a gitignored path is not part of primary, so the scan leaves every registered secondary out, by literal path rather than by glob (a worktree name may contain `*`, `?` or `[`). A file git tracks under an ignored directory is not copied either: `check-ignore` answers about the path, not about tracking state.
- **Feature branches are not auto-pulled.** If a worktree is on `KD-0412-something`, the script does not pull the integration branch into it. That's a merge/rebase decision the user makes deliberately, not something a sync job should do implicitly.
- **Uncommitted changes skip the pull step.** The env copy and dep install still run (they don't touch tracked files), but `git` operations are skipped to avoid entangling the sync with in-flight work.
- **Only gitignored files are copied.** A `.env*` file that git tracks is left alone — copying it would create a spurious diff in the target worktree.

## Output format

Report per-worktree, one block each. Surface any env file left untouched, so the user knows which worktree still needs a hand:

```
=== <repo>-wt1 (detached HEAD f84f88258) ===
  env:      3 copied, 1 left untouched (differs: backend/.env)
  composer: backend ok
  npm:      frontend ok
  pull:     skipped (--pull not set)

=== <repo>-wt2 (KD-0412-xyz, 3 commits ahead of <integration-branch>) ===
  env:      4 files copied (no differences)
  composer: backend ok
  npm:      frontend ok
  pull:     skipped (on feature branch)

=== <repo>-wt3 (<integration-branch>, clean) ===
  env:      4 files copied (no differences)
  composer: backend ok
  npm:      frontend ok
  pull:     fast-forwarded to origin/<integration-branch> (2 new commits)
```

A worktree with no `composer.json` or no `package.json` prints `skipped (no composer.json)` / `skipped (no package.json)` on that line instead.

After running, if any env file was left untouched, tell the user which worktree and which file. That worktree is still on its own configuration: either the difference was a deliberate override and nothing needs doing, or it was drift and the file has to be copied over by hand. The script will not decide that for them.

## Why not just `npm ci` / why `npm install`?

`npm ci` refuses to run if `package-lock.json` is out of sync with `package.json`. After a `git pull` that updates either file, `npm install` reconciles gracefully; `npm ci` would fail and force the user to resolve it. For a sync skill that should "just work," `npm install` is the right default.

## Why the first worktree in `git worktree list` is always the primary

`git worktree list` is documented to list the main working tree first, then linked worktrees in creation order. The script relies on this to auto-detect the primary without hardcoding the primary's path, which keeps the skill portable to any developer who clones the repo and uses worktrees.
