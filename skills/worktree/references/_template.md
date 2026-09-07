# `<repo-name>` — repo reference

**This is a template, not a dependency.** Copy it to `<repo-name>.md` beside this file, where
`<repo-name>` is what `/worktree` resolves from `git remote get-url origin` (last path segment,
`.git` stripped). If no file matches the repo you are standing in, `/worktree` runs on its
defaults — integration-branch detection, the lockfile table, `.env` copying — and says so in the
hand-back. That is a supported outcome, not a gap. You never need a file here to use the skill.

A file here **overrides the defaults outright**, including the setup detection. So write down
only what you verified in that repo, with the reason it is true. A rule without its *why* goes
stale silently, and the skill follows it anyway.

---

One or two lines: what the repo is, and who this file is for. If most of the team does not use
worktrees, say that — it explains why the file is narrow.

## Scope check

How to confirm you are really in this repo, from the filesystem alone. A worktree or a clone can
carry any directory name, so name a layout or a file instead.

> *Example:* two stack directories side by side at the repo root. If they are not there, this
> file does not apply — you are in a different repo.

## Base

The integration branch, when detection would get it wrong. Add the issue-key format if the
tracker auto-links branches, and say how the key must appear — a truncated key silently breaks
the link.

## Worktree location

Only when the default `$REPO/.claude/worktrees/<slug>` is wrong for this repo. Two reasons it
can be:

- **Tooling that sweeps from the repo root** — a docker build context, a test runner globbing
  from `/`, IDE indexing. Then put the worktree in a sibling directory instead.
- **The ignore entry.** If the path is already in the repo's own `.gitignore`, say so — the skill
  can skip its `info/exclude` write.

Say which one applies and why, so the next reader can tell whether it still holds.

## Setup

The exact commands, in order:

```bash
cp "$REPO/<path>/.env" "$WT/<path>/.env"
<install command aimed at "$WT">
```

Then the **do-nots**, each with its cost. This half matters more than the commands, because the
default is to add setup, not to leave it out:

- **No `<thing>`.** <What it would buy, and why that is nothing here.> A step that patches a
  tracked file leaves a permanent dirty diff in `git status`.

Note any hook that runs on session start inside the worktree and does part of this on its own.

## House rules once you are in there

**Working** — what applies to every edit:

- Every file write goes to `$WT`. Never edit the checkout you came from.
- Hooks that **block** an edit until a skill is loaded — name the hook and the skill, so the
  session loads it before the block fires rather than after.
- Formatters that run on Edit/Write, and therefore must never be run by hand.
- Coverage expectations, and which skill to load for each side.

**Gates** — for the side you touched, judged by exit code:

| Touched | Commands (from `$WT`) |
|---|---|
| `<side>` | `<command>`, `<command>` |

Call out any script whose base variant hangs. A watch-mode test runner never returns, and a
session that starts one waits forever.

**Running the app** — only if it needs care. Shared ports, a shared database, or one-stack-at-a-
time constraints belong here.

**Shared state** — anything a worktree mutates that the primary checkout also sees: a shared
database, a shared cache, a shared tenant. Say what is harmless and what breaks the other
branch, and how to recover.

**Plan docs** — the directory convention, how the slug is derived from the branch name, and
which skills refuse to run without them.

**Shipping** — the order of skills, and anything that acts on the *current* branch and therefore
needs `cd "$WT"` first.
