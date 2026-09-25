# The live watch — every line `pr-watch.sh` prints, and what to do with it

`pr-watch.sh` reads two surfaces: GitHub (checks, reviews, comments, head) and the town-crier
review bus. After one `[watch] now:` line at arming it prints only changes, so a quiet PR produces nothing more. Read this file when the first
line lands after arming, or when a line is not in the short list in SKILL.md.

## The lines

| line | means | do |
|---|---|---|
| `[bus] review N by <who>` | a reviewer submitted on the town-crier bus | full cycle |
| `[bus] gate X -> Y` | the derived merge gate moved | cycle if it went blocked |
| `[bus] trial …` | the bus's view of the `ci-passed` check moved | cycle if red |
| `[ci]  FAILING: <jobs>` | GitHub checks went red | full cycle |
| `[ci]  red checks re-running, not green yet` | a red job went back to the queue | nothing yet; wait for the next `[ci]` line |
| `[ci]  needs attention (neutral/stale): <lanes>` | a workflow lane finished with no verdict (NEUTRAL) or its result belongs to another commit (STALE); a stale required check does not satisfy branch protection. A check an app posts with no workflow behind it (a tracker card, NEUTRAL forever) is excluded, so this names lanes only. A SKIPPED lane is not here: path-filtered repos skip ten lanes per PR, and `ci-failures.sh` names each skip | not green: read the lane, then cycle if it raises work |
| `[ci]  required check(s) never reported: <checks>` | every listed check passed and no run on the head is still going, but a check the base branch's rulesets require is not in the rollup — an always-green placeholder stood in for it, or no workflow that produces it fires on this PR (a base- or path-filtered CI). While a run is still in flight a missing gate is only not queued yet, and the state stays pending | not green, and waiting will not change it: find why the gate never ran (`ci-failures.sh` says the same as `INCOMPLETE`) and report it; do not call the PR mergeable |
| `[ci]  all checks green` | every check completed, none is red, every workflow run on the head has finished — so a gate job that `needs:` every other lane has reported too — and every check the base's rulesets require is present | nothing on its own; the cycle already knows |
| `[ci]  no checks reported yet` | the rollup is empty | nothing yet |
| `[watch] now: ci <STATE> …` | printed once, on the first tick: where the PR stands at arming, since every later line is a change against it | act on the state as if its own line had landed: RED or MISSING mean work |
| `[bus] attached #N` | the review request landed; the bus surface is live from here | nothing on its own |
| `[pr]  +N review(s)` / `+N comment(s)` | reviewer activity GitHub can see; fires whether or not a bus row is attached, so a round shows as one `[bus]` and one `[pr]` line | read it, then cycle if it raises work |
| `[pr]  head moved` | someone else pushed | re-snapshot before doing anything |
| `(STALE — bus read X, PR head Y)` | the verdict is about replaced code | **not** a result about the diff now |
| `[warn] …` | a surface went unreadable | the watch is blind on that side — say so |
| `[hb]  alive` | nothing has happened for 30 min | nothing |
| `[end] …` | terminal, the script exited | report and stop |

## What the watch cannot see

- **Branch protection that is not a ruleset.** Required checks come from `rules/branches/<base>`, readable by anyone who can read the repo. Classic branch protection needs admin to read, so a repo that requires its checks only there gets no `required check(s) never reported` line. An unreadable ruleset is treated the same way: the rollup alone decides.
- **A job that failed but let the run pass.** A job with `continue-on-error: true` fails without failing its run. Whether GitHub then lists it in the rollup as a failure has not been observed; if it does, the watch goes RED on a lane the repo marked report-only (kendo `Frontend Fallow (report only)`). Read the lane before cycling on it.
- **A job waiting on an environment approval.** It stays in the rollup as pending, and its run stays unfinished, so the watch holds at pending until someone approves it. Nothing the loop pushes will move it; say so rather than waiting.
- **Checks from outside GitHub Actions** (Cloudflare Pages, a tracker app). They count in the rollup, so their red and their pending are seen. But "every workflow run has finished" covers only Actions, and `ci-failures.sh` lists and reads only Actions runs: an external red check has no log there, so read it on the PR.

## The bus half

The bus half is optional, and most repos will never use it. town-crier is a review ledger a repo
can announce onto; a repo that does not is watched through GitHub alone and loses nothing. Every
repo that is announced appears in the same ledger, whichever repo it is. The bus token is read
from `$TOWN_CRIER_TOKEN`, else from the env file named by `$TOWN_CRIER_ENV_FILE`; neither set
means no request leaves for town-crier at all. No token is a degradation, not an error, and so is
a host without curl: the bus half is the only thing that needs it.

**GitHub's review lines always fire, bus row or not.** They used to stop once a row was attached,
and on emmie #1297 (2026-09-10) crit posted round 2 on GitHub while bus row #3245 stayed `open`
with 0 reviews, so nothing fired for an hour; an unreadable row did the same. A round now shows as
one `[bus]` line and one `[pr]` line, and that duplicate is the price of never being blind.

**The watch attaches to the bus late, and that is normal.** The row is created when the PR is
dispatched for review, which always lands after the PR itself opens — so arming a watch right
after `gh pr create` is early by design and the first resolve misses. The script retries every
tick until it attaches, then prints `[bus] attached #N`. Read the arming line: `bus pending` means
the row has not appeared yet, `github only (…)` names the reason there will never be one. Either
way GitHub's review lines fire, so a review is never missed for want of a row; what a missing row
costs is the gate and trial state the bus alone reports.

**A crit row never carries findings.** crit's bus submit sends stance, verdict URL and note, no
`findings[]`, so a crit round reads `gate clear` with empty finding counts whatever crit posted.
`gate clear` on a crit round is not an approval; the script prints `findings not submitted` for
it. Go by the posted GitHub review.

## Why not a cron

`CronCreate` on this host is session-only — its own docs say the job is gone when Claude exits,
and its `durable` parameter has no effect. It also fires only while the REPL is idle, adds up to
10% jitter, and auto-expires after 7 days. It buys nothing Monitor does not do sooner. Earlier
versions of this skill claimed the cron was "durable across sessions" and passed
`foreground: true`; neither was true of the scheduler actually present.
