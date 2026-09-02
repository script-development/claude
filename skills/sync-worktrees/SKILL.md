---
name: sync-worktrees
description: Sync every secondary git worktree with the primary one. Copies every gitignored `.env*` file from the primary into each secondary worktree at the same relative path, and refreshes dependencies (composer install where a composer.json exists, npm install where a package.json exists). Optionally fast-forwards worktrees that sit on the integration branch ({{DEFAULT_BRANCH}}) or detached HEAD. Use this skill whenever the user says "sync worktrees", "refresh worktrees", "update worktrees", "refresh my worktree envs", "align worktrees", or any variant of wanting to catch secondary worktrees up with the main repo. Also trigger proactively after a PR lands that touched `.env.example`, dependency lockfiles, or added new migrations — those changes need to propagate to idle worktrees before the user picks up work in them. Works regardless of how individual developers name their worktrees (generic slots like `<repo>-wt1`, feature-named like `<repo>-feat-xyz`, or anything else).
---

# Sync Worktrees

Keeps every secondary git worktree aligned with the primary one. Works for any worktree layout — generic slots (`<repo>-wt1`, `<repo>-wt2`), feature-named clones (`<repo>-feat-xyz`), or whatever convention the user or team has picked.

The script targets **all** secondary worktrees by design. Naming conventions vary across developers, so filtering to a specific pattern would silently skip legitimate worktrees for anyone not using that pattern. The safety net against unwanted changes to a worktree that's actively being worked on is the env-backup rule below, not a naming filter.

The main risk this skill guards against: env files drift silently. You add a new `FOO_API_KEY=…` to an `.env` in the main repo, then a week later pick up an issue in `<repo>-wt2`, and nothing works because that worktree still has the old env. This skill makes catching up a one-shot command.

## When to use

- User explicitly says "sync worktrees" / "refresh worktrees" / "update worktrees"
- After a PR that touched `.env.example`, `composer.lock`, `package-lock.json`, or added a migration that requires new env vars
- When setting up a new generic worktree and you want parity with the primary

## What it syncs

1. **Env files** from the primary worktree → each secondary worktree:
   - every gitignored `.env*` file found in the primary (any depth, skipping `node_modules/`, `vendor/` and earlier `.before-sync-*` backups)
   - copied to the same relative path in each secondary worktree
   - tracked files such as `.env.example` are never copied — they come from git
2. **Dependencies** in each worktree, discovered per manifest (depth ≤ 3, same skip list):
   - every directory holding a `composer.json`: `composer install --no-interaction`
   - every directory holding a `package.json`: `npm install`
3. **Fast-forward to `origin/{{DEFAULT_BRANCH}}`** (opt-in via `--pull`):
   - Only when the worktree is on `{{DEFAULT_BRANCH}}` or detached HEAD
   - Never when on a feature branch (would pull the integration branch *into* the feature branch, surprising)
   - Never with uncommitted changes (would risk mixing states)

The integration branch is detected from `origin/HEAD`, falling back to `main`, then `master`. Pass `--base <branch>` when the repo integrates somewhere else (for example a `development` branch).

## How to run

First, ask the user whether to also fetch + fast-forward (default: no). Most worktree slots sit on feature branches, where pulling is the wrong move. Then run:

```bash
bash .claude/skills/sync-worktrees/scripts/sync.sh                      # env + deps only
bash .claude/skills/sync-worktrees/scripts/sync.sh --pull               # + fast-forward where safe
bash .claude/skills/sync-worktrees/scripts/sync.sh --base development   # non-default integration branch
```

The script auto-detects the primary worktree (always the first entry in `git worktree list --porcelain`), so no hardcoded paths.

## Safety rules the script enforces

These exist because each one maps to a real way you can lose work:

- **Diverged env = backup, don't clobber.** Before overwriting a worktree's env file, the script compares byte-for-byte with the primary. If they differ, the old one gets saved to `<file>.before-sync-<timestamp>` so you can recover any intentional local overrides. The sync still proceeds — the backup is your safety net, not a block.
- **Feature branches are not auto-pulled.** If a worktree is on `{{ISSUE_KEY_PREFIX}}-0412-something`, the script does not pull the integration branch into it. That's a merge/rebase decision the user makes deliberately, not something a sync job should do implicitly.
- **Uncommitted changes skip the pull step.** The env copy and dep install still run (they don't touch tracked files), but `git` operations are skipped to avoid entangling the sync with in-flight work.
- **Only gitignored files are copied.** A `.env*` file that git tracks is left alone — copying it would create a spurious diff in the target worktree.

## Output format

Report per-worktree, one block each. Surface any backups created so the user knows where to look if they had local overrides:

```
=== <repo>-wt1 (detached HEAD f84f88258) ===
  env:      4 files copied (1 backed up: backend/.env → backend/.env.before-sync-2026-04-18-1432)
  composer: backend ok
  npm:      frontend ok
  pull:     skipped (--pull not set)

=== <repo>-wt2 ({{ISSUE_KEY_PREFIX}}-0412-xyz, 3 commits ahead of {{DEFAULT_BRANCH}}) ===
  env:      4 files copied (no differences)
  composer: backend ok
  npm:      frontend ok
  pull:     skipped (on feature branch)

=== <repo>-wt3 ({{DEFAULT_BRANCH}}, clean) ===
  env:      4 files copied (no differences)
  composer: backend ok
  npm:      frontend ok
  pull:     fast-forwarded to origin/{{DEFAULT_BRANCH}} (2 new commits)
```

A worktree with no `composer.json` or no `package.json` prints `skipped (no composer.json)` / `skipped (no package.json)` on that line instead.

After running, if any backups were created, remind the user that those `.before-sync-*` files exist and will accumulate over time — they can safely delete them once they've confirmed no important overrides were lost.

## Why not just `npm ci` / why `npm install`?

`npm ci` refuses to run if `package-lock.json` is out of sync with `package.json`. After a `git pull` that updates either file, `npm install` reconciles gracefully; `npm ci` would fail and force the user to resolve it. For a sync skill that should "just work," `npm install` is the right default.

## Why the first worktree in `git worktree list` is always the primary

`git worktree list` is documented to list the main working tree first, then linked worktrees in creation order. The script relies on this to auto-detect the primary without hardcoding the primary's path, which keeps the skill portable to any developer who clones the repo and uses worktrees.
