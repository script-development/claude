# `<repo-name>` — repo reference

**This is a template, not a dependency.** Copy it to `<repo-name>.md` beside this file, where
`<repo-name>` is what `/shepard` resolves from `git remote get-url origin` (last path segment,
`.git` stripped). If no file matches the repo you are standing in, `/shepard` runs on its
defaults and says so — that is a supported outcome, not a gap. You never need a file here to
use the skill.

This file holds the repo. The reviewer's contract is not repeated here: it lives once in
`../reviewers/crit.md`, and only what is specific to this repo about the reviewer goes below.

Delete every section you cannot fill from something you verified. A half-remembered rule is
worse than no rule: the skill trusts this file over its own defaults, so a wrong line here is
followed silently.

---

One or two lines: what the repo is, its stack, and where its architecture lives.

## Scope check

How to confirm you are really in this repo, from the filesystem alone — not from the directory
name, which a worktree or a clone can change. Name a directory layout, a lockfile arrangement,
or a file only this repo has.

> *Example:* two workspace directories side by side at the root, with a single lockfile above
> them.

## Integration branch

Only if `gh pr view --json baseRefName` would get it wrong. Say which branch, and say plainly
which branch it is **not** when the wrong one is plausible.

> *Example:* `development`. Never `main`.

## Gates — step 7's narrow checks

The exact commands, per side touched. Step 7 runs the narrowest set that covers the change, not
the full suite — CI owns the full suite.

| Touched | Narrow checks |
|---|---|
| `<side>` | `<command>`, then `<command>`, then the narrowest `<test command>` |

State how to judge a run. Exit code plus the summary line is the usual answer; a test count is
not, because a collection failure reports zero tests while the count stays green.

## Auto-fixers

Which tools fix their own CI row, and which do not. A formatter with a write mode belongs here.
A linter whose rules are not auto-fixable belongs here too, saying so — that is the line that
stops a session burning a cycle on `--fix`.

## Board

What a finding outside the diff becomes — an issue or a report — and who decided that. A repo
admin may say "always reports"; with no line here, `/shepard` asks the developer once per PR.
Then the tracker, the tool or CLI that reaches it, the issue key format, and the template. If the
branch name must carry the key for the tracker to auto-link it, say that here.

Name the instance explicitly when more than one exists, and the tenant when one MCP server name
can reach several. A ticket filed on a staging tracker is invisible to whoever would fix it.

> *Example:* Outside the diff: always a report, through `create-report-tool` with
> `project_id: 1`. File an issue only when the developer says so for that finding.

## Reviewer

What is specific to this repo about crit — its contract is `../reviewers/crit.md` and is not
repeated here. Usually two lines:

- **The review state crit submits here and the merge signal.** In one repo crit submits as
  `COMMENTED`, so GitHub never shows an approval and the merge is an admin merge on "CI green and
  Crit approves at the current head". In another it submits real review states and is a code
  owner, so its approval satisfies the branch rule. Say which, verified on one PR.
- **Where a nitpick report goes** when that differs from the Board line above.

## House rules

Everything a session must know once it is working, each with the reason it is true:

- **Style** — the conventions that are enforced or reviewed, not the whole style guide.
- **Branch names** — prefix convention and key placement.
- **Hooks and formatters** — what runs on edit, and therefore what never to run by hand.
- **Testing skills** — which to load before touching a test, and whether a hook blocks the edit
  until it is loaded.
- **Anything that surprised you once.** A rule without its *why* goes stale silently, and the
  next reader cannot tell whether it still applies.
