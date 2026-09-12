# The live watch — every line `pr-watch.sh` prints, and what to do with it

`pr-watch.sh` reads two surfaces: GitHub (checks, reviews, comments, head) and the town-crier
review bus. It prints only changes, so a quiet PR produces nothing. Read this file when the first
line lands after arming, or when a line is not in the short list in SKILL.md.

## The lines

| line | means | do |
|---|---|---|
| `[bus] review N by <who>` | a reviewer submitted on the town-crier bus | full cycle |
| `[bus] gate X -> Y` | the derived merge gate moved | cycle if it went blocked |
| `[bus] trial …` | the bus's view of the `ci-passed` check moved | cycle if red |
| `[ci]  FAILING: <jobs>` | GitHub checks went red | full cycle |
| `[bus] attached #N` | the review request landed; the bus surface is live from here | nothing on its own |
| `[pr]  +N review(s)` / `+N comment(s)` | reviewer activity GitHub can see — **only emitted while no bus row is attached**, or always under `--source gh` | read it, then cycle if it raises work |
| `[pr]  head moved` | someone else pushed | re-snapshot before doing anything |
| `(STALE — bus read X, PR head Y)` | the verdict is about replaced code | **not** a result about the diff now |
| `[warn] …` | a surface went unreadable | the watch is blind on that side — say so |
| `[hb]  alive` | nothing has happened for 30 min | nothing |
| `[end] …` | terminal, the script exited | report and stop |

## The bus half

The bus half is optional, and most repos will never use it. town-crier is a review ledger a repo
can announce onto; a repo that does not is watched through GitHub alone and loses nothing. Every
repo that is announced appears in the same ledger, whichever repo it is. The bus token is read
from `$TOWN_CRIER_TOKEN`, else from the env file named by `$TOWN_CRIER_ENV_FILE`; that variable's
built-in default points at one personal checkout, so set it yourself or export the token. No token
is a degradation, not an error.

**The bus is the review surface; GitHub is kept for the per-job CI names.** Once a row is attached
the script stops emitting the `[pr]` review, comment and decision lines, because the bus row is
the reviewer's own record and reporting both duplicates every round. Where there is no row those
lines fire as before, so a repo off the bus loses nothing.

**A reviewer that never reports to its row leaves the watch blind.** On emmie #1297 (2026-09-10)
crit posted round 2 on GitHub while bus row #3245 stayed `open` with 0 reviews, so nothing fired
for an hour. Where a row does not move when the reviewer posts, re-arm with `--source gh`. After
an hour of silence past a green push, read `gh pr view --json reviews` once before trusting it.

**The watch attaches to the bus late, and that is normal.** The row is created when the PR is
dispatched for review, which always lands after the PR itself opens — so arming a watch right
after `gh pr create` is early by design and the first resolve misses. The script retries every
tick until it attaches, then prints `[bus] attached #N`. Read the arming line: `bus pending` means
the row has not appeared yet, `github only (…)` names the reason there will never be one. If the
arming line says `bus pending` and no `[bus] attached` follows, the review surface is not covered
— say so rather than reporting the PR as watched.

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
