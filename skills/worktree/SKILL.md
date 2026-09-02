---
name: worktree
description: >
  Cut a fresh git worktree in the current repo and set it up — branch, dependencies, env files,
  ready to work. Repo-agnostic: auto-detects the integration branch and the setup steps, and
  loads per-repo house rules from references/<repo>.md when that file exists (kendo has one).
  Handles new work off the integration branch and existing branches you want to resume, fix, or
  review. Then hands back the path and stops; what you do in there is yours.
  Use whenever the user says "cut a worktree", "new worktree", "/worktree", "fresh worktree for
  ABC-####", "work on this in a worktree", "let me fix that branch somewhere else", or is
  starting any parallel piece of work in any git repository.
---

# worktree — cut one and get out of the way

This skill does one thing — produce a working checkout of the **current repo** at a new path. It
does not decide what you build there. Feature, bug, refactor, CI fix, spike, review of someone
else's branch: all the same job up to the hand-back.

## 0 · Identify the repo

```bash
git rev-parse --show-toplevel
```

Not inside a git repository — stop: *"worktree needs a git repo to cut from."*

Resolve the **repo name**: the last path segment of `git remote get-url origin` (strip `.git`);
no remote, use the toplevel directory's basename.

Then look for `references/<repo-name>.md` **in this skill's directory**. If it exists, read it
now — it overrides every default below and carries the repo's house rules. If it does not exist,
run on the defaults and say so in the hand-back. Never refuse a repo just because it has no file.

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

1. The base named in the repo's reference file.
2. `origin/development`, then `origin/develop`, if either exists after a `git fetch origin`.
3. The remote default branch: `git symbolic-ref --short refs/remotes/origin/HEAD` (run
   `git remote set-head origin -a` first if that ref is unset).

Ask only if `$ARGUMENTS` is empty or genuinely ambiguous between a new branch and an existing
one. Otherwise pick and say what you picked.

## 2 · Cut it

```bash
REPO=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
WT="$REPO/.claude/worktrees/<slug>"
git -C "$REPO" fetch origin
```

**Make sure the worktree root is ignored** — without touching any tracked file:

```bash
git -C "$REPO" check-ignore -q .claude/worktrees || \
  echo ".claude/worktrees/" >> "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
```

`info/exclude` is a local-only ignore list: same syntax as `.gitignore`, never committed, never
seen by teammates. Caveat: tools that sweep the whole repo root (a docker build context, a test
runner globbing from `/`, IDE indexing) will still *see* a nested worktree. If a repo's tooling
does that, its reference file should move `WT` to a sibling directory instead — note it there
once you find out.

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

The repo's reference file wins outright when it exists — run its setup, respect its do-nots,
skip the detection below. Otherwise, detect:

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

Do not invent setup beyond this — no services, no databases, no port juggling. If a repo needs
more (or explicitly less), that belongs in its reference file, not in guesswork.

## 4 · Hand back and stop

Report:

```
Worktree: <path>
Branch:   <branch>  (base: <base>)
Deps:     <what was installed>
Rules:    <one line per house rule from the repo file — or "no repo file, ran on defaults">
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

## Adding a repo reference file

When a repo earns verified, repeatable knowledge — a base branch that is not detectable, setup
beyond the lockfile table, hazards, house rules — write `references/<repo-name>.md` in this
skill's directory. Structure it as:

- **Scope check** — how to confirm you are really in that repo.
- **Base** — the integration branch, if detection would get it wrong.
- **Setup** — exact commands, plus explicit do-nots with the *why*.
- **House rules** — what matters once work starts (gates, hooks, shipping flow).

Only write down what was verified in that repo, with the reason it is true. A rule without its
why goes stale silently. `references/kendo.md` is the model.

## What this skill never does

- Never writes into the checkout it was invoked from.
- Never edits a tracked file to make room for a worktree (`info/exclude`, not `.gitignore`).
- Never leaves a *new* branch tracking the integration branch.
- Never forces a branch out of a worktree that already has it.
- Never starts the work unless the developer named it.
- Never invents repo-specific setup that is not in the reference file or the lockfile table.
