---
name: worktree
description: >
  Cut a fresh git worktree in the current repo and set it up — branch, dependencies, env files,
  ready to work. Project-agnostic: auto-detects the integration branch and the setup steps, and
  reads .claude/project-context.md's Worktrees section for this project's own overrides and
  house rules when one exists. Handles new work off the integration branch and existing branches
  you want to resume, fix, or review. Then hands back the path and stops; what you do in there is
  yours.
  Use whenever the user says "cut a worktree", "new worktree", "/worktree", "fresh worktree for
  ABC-####", "work on this in a worktree", "let me fix that branch somewhere else", or is
  starting any parallel piece of work in any git repository.
---

# worktree — cut one and get out of the way

This skill does one thing — produce a working checkout of the **current repo** at a new path. It
does not decide what you build there. Feature, bug, refactor, CI fix, spike, review of someone
else's branch: all the same job up to the hand-back.

Project-specific overrides and house rules come from `.claude/project-context.md` at the root of
the project this skill is running in — see Step 0. Missing file, or a missing field/section
within it, means "run on the generic defaults below" — never a hard failure.

## 0 · Identify the repo

```bash
git rev-parse --show-toplevel
```

Not inside a git repository — stop: *"worktree needs a git repo to cut from."*

Then look for `.claude/project-context.md` at the repo root. If it exists, read its
`integration_branch` and `worktree_dir` frontmatter fields and its `## Worktrees` body section
now — they override the defaults in Steps 1–3 below. If it does not exist, run on the defaults
and say so in the hand-back. Never refuse a repo just because it has no file — the no-file path
is the normal one for a project that hasn't needed an override yet.

## 1 · Name it and pick the base

`$ARGUMENTS` is free text. Resolve it to a **branch**, a **slug**, and a **base**:

| What you were given | Branch | Base |
|---|---|---|
| Issue key — `ABC-1163` | `ABC-1163-<slug>` from the issue title | integration branch |
| Free text — "fix the density pipeline" | `<slug>` — `fix-density-pipeline` | integration branch |
| An existing branch name | that branch, unchanged | the branch itself |
| A PR number or URL | that PR's head branch | the branch itself |

Slug: kebab-case, max ~5 words. With an issue key, keep the full key first (`ABC-1163`, not
`ABC-163`) so trackers that auto-link branches still match.

**Integration branch** — first match wins:

1. `integration_branch` in `.claude/project-context.md`, if set.
2. `origin/development`, then `origin/develop`, if either exists after a `git fetch origin`.
3. The remote default branch: `git symbolic-ref --short refs/remotes/origin/HEAD` (run
   `git remote set-head origin -a` first if that ref is unset).

Ask only if `$ARGUMENTS` is empty or genuinely ambiguous between a new branch and an existing
one. Otherwise pick and say what you picked.

## 2 · Cut it

```bash
REPO=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
WT="$REPO/<worktree_dir, {slug} substituted, or the default .claude/worktrees/<slug>>"
git -C "$REPO" fetch origin
```

**Make sure the worktree root is ignored** — without touching any tracked file (skip this if
`.claude/project-context.md`'s House rules say the path is already covered by the project's own
`.gitignore`):

```bash
git -C "$REPO" check-ignore -q <worktree-parent-dir> || \
  echo "<worktree-parent-dir>/" >> "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
```

`info/exclude` is a local-only ignore list: same syntax as `.gitignore`, never committed, never
seen by teammates. Caveat: tools that sweep the whole repo root (a docker build context, a test
runner globbing from `/`, IDE indexing) will still *see* a nested worktree. If a project's
tooling does that, set `worktree_dir` in `.claude/project-context.md` to a sibling directory
instead — note it there once you find out.

**New branch** — off the integration branch:

```bash
git -C "$REPO" worktree add -b <branch> "$WT" <base>
git -C "$WT" branch --unset-upstream
```

`--unset-upstream` is load-bearing. Branching from `origin/<integration>` makes git track that
remote branch, so a later `git push` would update the integration branch itself.

**Existing branch** — resuming work, fixing CI, reviewing someone else's PR:

```bash
git -C "$REPO" worktree add "$WT" <branch>
```

No `-b`, no `--unset-upstream` — the branch already tracks its own remote, which is what you want
for a push-back-to-the-same-PR fix. If the branch is only on the remote, use
`git -C "$REPO" worktree add "$WT" -b <branch> origin/<branch>` and leave the upstream alone.

A branch can only be checked out in one worktree. If git refuses because it is already checked
out, say where it is and stop — do not force it.

If the *path* exists, append `-2`, then `-3`. Never reuse a dirty worktree.

## 3 · Set it up

`.claude/project-context.md`'s Worktrees → Setup section wins outright when it exists — run its
commands, respect its do-nots, skip the detection below. Otherwise, detect:

**Env files** — copy every gitignored `.env*` file from the primary checkout to the same
relative path in the worktree:

```bash
git -C "$REPO" ls-files --others --ignored --exclude-standard --directory \
  | grep -E '(^|/)\.env[^/]*$' \
  | while read -r f; do mkdir -p "$WT/$(dirname "$f")"; cp "$REPO/$f" "$WT/$f"; done
```

**Dependencies** — for each lockfile in the repo root or one level down (skip ignored
directories like `node_modules/`, `vendor/`):

| Lockfile | Command (aimed at its directory) |
|---|---|
| `composer.lock` | `composer install -d <dir>` |
| `package-lock.json` | `npm install --prefix <dir>` |
| `pnpm-lock.yaml` | `pnpm install -C <dir>` |
| `yarn.lock` | `yarn --cwd <dir>` |
| `uv.lock` | `uv sync` from `<dir>` |
| `poetry.lock` | `poetry install` from `<dir>` |
| `Cargo.lock`, `go.sum` | nothing — the build fetches |

Skip the installs when the lockfiles are unchanged from the primary and you are only reading.

Do not invent setup beyond this — no services, no databases, no port juggling. If a project needs
more (or explicitly less), that belongs in its `.claude/project-context.md`, not in guesswork.

## 4 · Hand back and stop

Report:

```
Worktree: <path>
Branch:   <branch>  (base: <base>)
Deps:     <what was installed>
Rules:    <one line per house rule from .claude/project-context.md's Worktrees section — or "no project-context.md, ran on defaults">
Next:     cd <path>
```

Then **stop**. Do not start the work. Do not guess whether this is a feature, a bug, or a CI fix.
The developer picks from here.

If they asked for a worktree *and* named the work in the same breath, go straight on into that
work — but from `$WT`, and only the work they named.

## Cleaning up

When a branch is merged:

```bash
git -C "$REPO" worktree remove "$WT"
git -C "$REPO" worktree prune
```

`worktree remove` refuses on uncommitted changes. That refusal is a feature — look before you
pass `--force`.

## Adding project context for worktrees

When a project earns verified, repeatable knowledge — an integration branch that is not
detectable, setup beyond the lockfile table, hazards, house rules — add it to that project's
`.claude/project-context.md`, under `## Worktrees` (plus the `integration_branch`/`worktree_dir`
frontmatter fields if either default is wrong). This plugin ships a starter template at
`references/project-context-template.md` — copy from there if the project doesn't have the file
yet.

Only write down what was verified in that project, with the reason it is true. A rule without its
*why* goes stale silently — and because this section overrides the setup detection outright, the
skill follows a wrong line rather than falling back.

## What this skill never does

- Never writes into the checkout it was invoked from.
- Never edits a tracked file to make room for a worktree (`info/exclude`, not `.gitignore`).
- Never leaves a *new* branch tracking the integration branch.
- Never forces a branch out of a worktree that already has it.
- Never starts the work unless the developer named it.
- Never invents project-specific setup that is not in `.claude/project-context.md` or the
  lockfile table.
