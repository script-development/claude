# Decisions — PR screenshots: shared reference + per-user cost setting

Source: the proposal the team lead approved in full, "PR screenshots"
(https://claude.ai/artifact/8ikkjjdx98MhJ1BTopRFHZ, private). D12 was settled after approval and
is not in the doc. D14 narrows the approved scope: the screenshots in the PR no longer come from
`fix-bug` and `implement-plan`. The team lead is told.

## D1 — Extend `/pr`'s existing step; don't start over

**Context.** `/pr` already has a Screenshots step (PR #85, commit 459361f, core-skills 0.31.0,
by Jasper Boerhof): look at each changed screen in the running app, take one screenshot per
screen, attach it with `gh --attach`.

**Chosen.** Keep that step's behaviour and wording, and move it into a shared reference (D2)
that more skills can use. Jasper is told before his step moves.

## D2 — A shared reference, not a nested skill

**Chosen.** One procedure file: canonical `templates/pr-screenshots.md`, shipped as the generated
mirror `plugins/core-skills/references/pr-screenshots.md`, kept identical by `.githooks/pre-commit`
the same way as `browser-reference-template.md`. Two parts:

- **Capture**: take screenshots, both before and after, and record them.
- **Attach**: put them in the PR body, one screen at a time.

Capture has two parts:

- **Look**: log in, open the screens, read the console, take screenshots. Any skill that drives
  the browser can use it.
- **Record**: manifest entries, the before/after swap (D12) and the combined image (D11).

`/pr` and `shepard` use all of it. `fix-bug` and `implement-plan` use Look only (D14).

Catalog skills link to it as `../../templates/pr-screenshots.md`. A consumer that adopts them
copies the file too, as with the browser reference template.

**Rejected — a `/screenshots` skill.** Skills can't call one another mid-flow, and this repo
already shares procedures by reference.

## D3 — Scope

Catalog and core-skills copies of `pr` and `shepard` (narrowed by D14).
mc-core (mission_control) is out of scope for now, by choice.

## D4 — `/pr` stays self-contained

`/pr` takes every screen it needs itself. The only screenshots it uses from elsewhere are ones a
developer dropped in the folder by hand (D13).

## D5 — Per-user cost setting: `CORE_SKILLS_PR_SCREENSHOTS`

**Chosen.** An env var in the `env` block of Claude Code settings. Claude Code applies the
precedence itself: `.claude/settings.local.json` wins over `~/.claude/settings.json`.

| Value | Missing screens are… |
|---|---|
| unset / `live` (default) | taken live by `/pr` |
| `ask` | taken only after the user says yes |
| `collect-only` | not taken: `/pr` attaches what is already in the folder |
| `off` | not taken, nothing attached: the section says so |

An unknown value falls back to the default, and the output names the value it didn't recognise.

**Rejected — `project-context.md`.** That file is committed, so the value would apply to the whole
team. What a look costs matters per person, because each person has their own plan.

**Why `live` is the default.** A look measured cheap (D7).

## D6 — Engine: the Playwright MCP, used find-first

**Chosen.** Keep the Playwright MCP. Use `browser_find` to locate elements; never take a whole-page
`browser_snapshot`.

**Rejected — `playwright-cli`.** It measured the same. Since `@playwright/mcp` 0.0.86, automatic
snapshots go to a file and only a link comes back, which is what the CLI does too.

**Rejected — MCP startup flags** (`--snapshot-mode none`, `--image-responses omit`,
`--storage-state`):

- They're set when the server starts, so a skill can't choose them per run.
- Logging in still needs element references.
- With `omit`, nothing looks at the screen at all.

**Rejected — `npx playwright screenshot`.** It has no console check and can't click its way to a
state. At most a later `collect-only` tier.

## D7 — Measurements (emmie: planner login with 2FA, then one screen)

Token counts are approximate (bytes ÷ 4).

| Mode | Login | One screen |
|---|---|---|
| MCP `browser_find` | 4.6 KB | 1.5 KB |
| `playwright-cli find` | 4.6 KB | 1.5 KB |
| MCP, reading the snapshot file | 8.9 KB | 1.5 KB |
| MCP, inline `browser_snapshot` | 9.3 KB | 1.5 KB |

- One whole page tree: dashboard 11.5 KB, `/gebruikers` 21.4 KB.
- Viewing one 1280×720 screenshot costs about 1.2k tokens.
- So a look costs about 1.5k tokens for the login, plus about 1.2k per screen.

## D8 — The PR body is the record

**Chosen.** Each screen in `## Screenshots` gets one entry:

- a hidden comment `<!-- shot screen=… role=… sha=… base=… files=… -->`, where `base` is the base
  commit the "before" half shows (D12);
- the image line with its uploaded URL.

Updates go one screen at a time:

- retake an entry that went stale (D9);
- add a screen the branch now changes;
- drop a screen it no longer changes;
- keep everything else.

**Rejected — rebuilding the whole section each time.** That loses screenshots already attached.

## D9 — Stale means a file that renders the screen changed after the shot

An entry is stale when `git log <sha>..HEAD -- <files>` is non-empty, using the entry's `sha` and
`files`.

**Rejected — retaking on every move of HEAD.** It wastes looks on commits that don't touch the
screen.

## D10 — Who refreshes the section

- **`/pr`.**
- **`shepard`, when its cycle changed frontend files.** This is the one exception to shepard's rule
  of never rewriting a section other than `## Summary`.
- **`commit` doesn't.** It stays Summary-only.

## D11 — Before/after: one combined, labelled image per screen

**Chosen.** Both halves are made in the same browser session and joined into one labelled image.

**Rejected — a two-column table.** Clicking it opens one image at a time, so the two are never
seen side by side.

## D12 — Where the "before" comes from: base frontend swapped in, by `/pr` only, after the push

**Chosen.** By the time `/pr` reaches its Screenshots step, step 1 has made sure the work is
committed and step 2 has pushed it. The branch's changed files are therefore safe in HEAD, and for
each modified screen `/pr` can:

1. take the "after";
2. write the swap marker;
3. `git checkout origin/<base> -- <changed frontend files>` and remove the files the branch added;
4. reload the page in the same session and take the "before";
5. `git checkout HEAD -- <files>`, confirm `git status` is clean, and delete the marker.

`shepard` does the same when it refreshes, because it has also just committed and pushed.

**The marker guards a run that stops partway.** Without it, the swapped-in base files would show
up as uncommitted changes, and `/pr`'s step 1 would offer to commit them, quietly reverting the
branch. So `/pr` step 1, `shepard`, and the start of Capture check for the marker and restore
first.

**When the "before" is left out** (the PR body says why, in one line):

- the screen is new on the branch;
- the base frontend errors against the branch's backend: an API, a migration or seeded data it
  depends on changed, and the local database is migrated for the branch;
- the user declined `/pr`'s offer to commit uncommitted work.

**A "before" already in the PR body can go stale.** The base branch moves, so each entry records
`base=<sha of origin/<base> when the shot was taken>`. When
`git log <base>..origin/<base> -- <files>` is non-empty, the next refresh retakes it with the
swap.

**Rejected — swapping inside `fix-bug` or `implement-plan`.** Mid-build the tree isn't clean, so a
restore could lose work.

**Rejected — a worktree on the base with its own dev servers.** It needs minutes of installs and
free ports, and it shares a database already migrated for the branch.

**Rejected — checking out the whole base branch.** That moves the backend too and puts the working
tree at risk.

## D13 — Local folder, manual screenshots, test-suite screenshots

- **Folder.** `.playwright-mcp/pr/<branch>/`, which git doesn't track. A `shots.md` manifest in it
  uses the same entry lines as D8. `/pr` clears the folder after attaching.
- **Manual screenshots.** The developer drops them in the folder. `/pr` asks about them only when
  screens are missing and the setting isn't `live`.
- **Test-suite screenshots.** Not in the first version.

## D14 — Only `/pr` and `shepard` take screenshots

**Chosen.** `fix-bug` and `implement-plan` keep their own browser checks (Phase 8.5's visual gate,
step 6's drive), but they record nothing. Every screenshot comes from `/pr` or `shepard`.

**Why.** The "before" should show the base branch as it is now, and only a capture made at PR time
can do that.

- An early "before", from `fix-bug`'s reproduction or the start of `implement-plan`, shows the base
  as it was when the build started. It would need the same staleness check, and that check only
  sees files: a base change to the backend or data behind a screen slips past it.
- An early "after" would usually be stale by `/pr` time anyway, and a look is cheap (D7).
- The scope halves, and the manifest no longer has to carry screenshots between sessions.

**Cost accepted.** When a feature changes an API, a migration or seed data that a screen depends
on, the swap can break the "before". That screen then gets the "after" only, with a line saying
why.

**They still use the reference's Look part.** `fix-bug` Phase 8.5 and `implement-plan` step 6
follow Look when they drive the browser: find-first login, the 2FA traps, the console check.
That makes their existing checks cheaper and more reliable, and the screenshots they take help
the developer confirm a screen during the build. Nothing they take goes into the manifest or the
PR.

**Rejected — early captures in `fix-bug` and `implement-plan`.** This was the approved doc's
design, and the reasons above replace it. The approved scope narrows; nothing is added.
