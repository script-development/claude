# Plan — PR screenshots: shared reference + per-user cost setting

## Goal

Screenshots in a PR stay correct as the branch and its base move, and cost each developer only
what they chose to spend. Today `/pr` takes after-only screenshots in one go, and a later run
rebuilds the whole section. Decisions and measurements are in [`DECISIONS.md`](DECISIONS.md).

Done when:

- **Before/after per screen.** `/pr` attaches one combined before/after image per changed screen,
  and honours `CORE_SKILLS_PR_SCREENSHOTS`.
- **Only stale screens are retaken.** When `/pr` runs again, or `shepard` runs after a frontend
  fix, they retake the screens that went stale — against the branch or against the base — and
  keep the rest.
- **The two copies agree.** The catalog and core-skills copies of `pr` and `shepard` match, apart
  from the catalog's placeholders and its Docs accuracy gate. `fix-bug` and `implement-plan` point
  to the reference's Look part when they drive the browser.
- **Version.** core-skills is 0.32.0.

## Steps

Step 1 comes first: every later step depends on it.

### 0. Tell Jasper and the team lead

- **Jasper:** the step he added in PR #85 moves into the new reference (D1).
- **The team lead:** D14 narrows the approved scope. The PR's screenshots no longer come from `fix-bug`
  and `implement-plan`.

### 1. `templates/pr-screenshots.md`: the reference

Give it a header comment in the same pattern as `browser-reference-template.md`'s. It says that:

- this file is the canonical source;
- the shipped copy is a generated mirror;
- it is read by `pr` and `shepard` (all of it), and by `fix-bug` and `implement-plan` (Look only).

Sections:

- **Setting.** Read `CORE_SKILLS_PR_SCREENSHOTS`. Values and the fallback are in D5.
- **Folder and manifest.**
  - The folder is `.playwright-mcp/pr/<branch>/`, and it holds `shots.md` (D13).
  - Each manifest entry has exactly the PR-body entry's form (D8), including `base=`.
  - A file the developer dropped in without an entry gets one when attached: `sha=HEAD`, `files`
    from the diff for the screen it shows, and no "before".
- **Swap marker.** Check it first, at the start of every reader. If the marker is there, run
  `git checkout HEAD -- <files listed in the marker>` before anything else (D12).
- **Capture, part Look.** Any skill that drives the browser can use this part.
  1. Read the browser reference.
  2. Log in find-first: use `browser_find`, never a whole-page snapshot (D6).
     - Type a 2FA code with `slowly: true`. A plain fill keeps only the first digit.
     - A code can't be used again within its 30-second window.
  3. Pick the screens from the diff.
  4. For each screen, look at it, read the console and take a screenshot.
  5. Close the browser.
- **Capture, part Record.** Only `pr` and `shepard` use this part. For each screen, Look's
  screenshot is the "after". Then:
  1. Take the "before" (the swap in D12).
  2. Join the two into one labelled image (D11).
  3. Add a manifest entry.

  The "No screenshots: …" lines from today's `/pr` move here unchanged. Add the lines for the
  cases where the "before" is left out (D12).
- **Attach.**
  1. Read the entries already in the current PR body.
  2. Compare them with the screens the diff now changes. Staleness is defined in D9; a stale
     `base=` also counts.
  3. Retake, add, drop or keep each entry. Take missing screens as the setting says.
  4. Splice only `## Screenshots`, with one `--attach` per new file.
     - Keep the existing fallback for a `gh` without `--attach`.
  5. Clear the folder.

### 2. Mirror

- Add `pr-screenshots.md` to the loop in `.githooks/pre-commit`, and update the hook's header
  comment.
- Commit with the hook active. The hook generates
  `plugins/core-skills/references/pr-screenshots.md`.

### 3. `pr`, catalog and plugin copies

- **Step 1.** Check for the swap marker before checking for uncommitted changes.
- **Step 5, Screenshots.**
  - Replace items 1–6 and the Attach paragraph with: follow Capture and Attach in the reference.
  - Keep the trigger (the diff glob).
  - Keep the rule that an empty section still says why it's empty.
- **Refreshing an existing PR body.**
  - `## Screenshots` uses Attach's per-entry merge.
  - The check that a present section may not disappear stays.
- **Body example.** Show one entry, including its hidden comment.
- **Catalog copy.** It keeps `{{BROWSER_REFERENCE}}` and `## Docs accuracy`. The two copies are
  meant to differ, so don't make them byte-identical.
- **Links.**
  - Catalog copy: `../../templates/pr-screenshots.md`.
  - Plugin copy: `../../references/pr-screenshots.md`.

### 4. `shepard`, both copies

- **Step 7.** When the cycle changed frontend files, run the reference's Capture and Attach on
  `## Screenshots`, after the push. This is the stated exception to "never rewrite another
  section" (D10).
- **Start of a cycle.** Check for the swap marker.

### 5. `fix-bug` and `implement-plan`, both copies: one pointer each

- **`fix-bug` Phase 8.5 and `implement-plan` step 6.** When driving the browser, follow the
  reference's Look part. Screenshots taken there are for the developer's check during the build:
  they don't go in the manifest or the PR (D14).

### 5b. Housekeeping

- README: update the catalog and templates mentions, and add a short paragraph on the setting.
- `plugins/core-skills/.claude-plugin/plugin.json`: version 0.32.0. Update the description if it
  names the screenshot step.

### 6. Verify

**Emmie results (2026-11-20).** Done:

- **Swap and restore** through Vite's live reload: correct "before", clean `git status`.
- **Joined image.** A spare tab holds both screenshots between calls, and one code call joins
  them.
- **All five staleness rules** give the right verdict.
- **Marker recovery** works after an interrupted swap.

The run found three things, all fixed in the reference:

- **Both halves are taken the same way.** One open-and-keep snippet takes both. A redirect after
  login hid emmie's welcome dialog, which a fresh load showed.
- **The MCP only writes inside its own workspace.**
- **`browser_take_screenshot` with a filename returns only a link,** so to look you open the
  file.

Not tested: the API-change case. Its check stays a judgement on errors.

**Test PR results (#86, closed, 2026-11-20).** Done:

- **Hidden entries survive.** GitHub stores the body as sent, and the hidden entries survive
  `gh pr edit` and `--attach`.
- **Uploads replace the path in place.** gh 2.105.0 swaps the local path for an asset URL and
  leaves the lines around it alone.
- **A second run behaves.** It keeps an entry word for word, retakes a stale one and adds a new
  one.

Found and fixed:

- **The footer was dropped.** Splicing the last section "through EOF" took the
  `🤖 Generated with` footer with it.
- **Headings must be matched at the start of a line.**

`--attach` needs gh 2.99.0 or later.


- **On emmie, with a frontend branch.**
  - The swap gives a correct "before" through Vite HMR.
  - After the restore, `git status` is clean.
  - The Playwright session can make the combined labelled image, with a canvas in
    `browser_run_code_unsafe` or with a side-by-side page.
  - `files=` gives the right staleness verdict after a commit that touches one screen and not
    another.
  - An entry whose `base=` the base branch has since changed gets retaken.
  - After an interrupted swap, the marker check restores the files.
  - A branch that changes an API a screen uses: the "before" is left out, and the line says why.
- **On a test PR, in this repo and not in a consumer.**
  - The `<!-- shot … -->` entries survive `gh pr edit --body` and the URL rewrite that
    `--attach` does.
  - A second run retakes only the stale entry.
- **Each setting value, once:** `live`, `ask`, `collect-only`, `off`, and an unknown value.
- **`command claude plugin test` on core-skills.** The `claude` alias breaks the plain command.

### 7. PR

One PR in this repo. Propagating the change to consumers is a manual step after merge.

The PR description also mentions two changes made along the way:

- `core-skills:install` now offers a committed `.playwright-mcp/` line in `.gitignore` when
  `references.browser` is set. The reference falls back to the local `info/exclude` and suggests
  that committed fix.
- This repo got its first `.gitignore` (`.playwright-mcp/`, `.claude/worktrees/`), in a commit of
  its own.

## Out of scope

- **`fix-bug` and `implement-plan` feeding the PR** (D14). They get the Look pointer and nothing
  more.
- **mc-core's ports.**
- **Test-suite screenshots.**
- **The emmie browser-reference fix.** Its "it spreads" holds only for typed keys. That's a
  suggestion for emmie, not part of this branch.

## Delegation

One builder, no conductor group. Steps 3 and 4 are short edits that depend on step 1. Step 6 needs
the emmie session.
