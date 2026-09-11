# `<repo-name>` — repo reference

**This is a template, not a dependency.** Copy it to `<repo-name>.md` beside this file, where
`<repo-name>` is what `/shepard` resolves from `git remote get-url origin` (last path segment,
`.git` stripped). If no file matches the repo you are standing in, `/shepard` runs on its
defaults and says so — that is a supported outcome, not a gap. You never need a file here to
use the skill.

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

Where a FOLLOW-UP disposition is filed: the tracker, the tool or CLI that reaches it, the issue
key format, and the template. If the branch name must carry the key for the tracker to auto-link
it, say that here.

Name the instance explicitly when more than one exists. A ticket filed on a staging tracker is
invisible to whoever would fix it.

## Answering this repo's reviewer

Only when the repo's reviewer has a contract that changes what you do. The two questions worth
answering:

- **Who resolves a thread?** If the reviewer resolves its own, say so and say what breaks when
  you resolve one yourself. In some setups a resolved thread is treated as settled forever, so
  resolving it buries a live defect permanently.
- **What does the reviewer read?** If it reads plan docs, decision records or waivers, name the
  file it reads and what a record must say to count.

## Hazards

Only when the repo keeps a mined list of its bug classes, or has earned one. Each entry names the
mechanism, where it bit, and the construct that ends it: a helper, a gate, a test that fails while
the class is present. `/shepard` step 3 matches findings against it and recommends that construct
over a local patch. Point at the repo's own list rather than copying it here; a copy goes stale
the day the list gains a row.

> *Example:* stale in-flight response — a fetch re-issued before the previous answer lands, and the
> handler assigns whatever resolves. Ended by a latest-request wrapper, not a per-site guard.

## House rules

Everything a session must know once it is working, each with the reason it is true:

- **Style** — the conventions that are enforced or reviewed, not the whole style guide.
- **Branch names** — prefix convention and key placement.
- **Hooks and formatters** — what runs on edit, and therefore what never to run by hand.
- **Testing skills** — which to load before touching a test, and whether a hook blocks the edit
  until it is loaded.
- **Anything that surprised you once.** A rule without its *why* goes stale silently, and the
  next reader cannot tell whether it still applies.
