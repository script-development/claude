<!--
PR screenshots reference. The procedure for looking at changed screens in the running app, taking
before/after screenshots of them, and keeping a PR body's `## Screenshots` section current one
screen at a time.

Read by: pr (step 5, Screenshots) and shepard (step 7) use all of it: Look, Record and Attach.
fix-bug (Phase 8.5) and implement-plan (step 6) use Look only, for their own checks; nothing
they take reaches a PR. Decisions behind it: docs/plans/pr-screenshots/DECISIONS.md in the
claude-2 catalog.

Canonical source: templates/pr-screenshots.md in the claude-2 catalog. core-skills ships an
identical mirror at plugins/core-skills/references/pr-screenshots.md. The mirror is generated:
.githooks/pre-commit copies this file over it whenever this file changes. Edit only this copy;
never hand-edit the shipped mirror. A project holding checked-in catalog skills copies this file
next to them, unchanged.
-->

# PR screenshots

Four parts. The calling skill says which ones it runs.

- **Swap check**: run first, by every caller, before anything else touches the working tree.
- **Look**: log in, open the changed screens, check them, take a screenshot of each. Anyone can
  use it.
- **Record**: add a "before" to each screenshot, join the two into one image, record it. `pr` and
  `shepard` only, and only after the branch is committed and pushed.
- **Attach**: bring the PR body's `## Screenshots` section up to date, one screen at a time. `pr`
  and `shepard` only.

The caller supplies `<base>`: the PR's base branch, already fetched, so `origin/<base>` is current.

## The setting

Each developer chooses what screenshots cost them with the environment variable
`CORE_SKILLS_PR_SCREENSHOTS`, set in the `env` block of Claude Code settings. Claude Code applies
the precedence itself (`.claude/settings.local.json` over `~/.claude/settings.json`), so read it
with:

```bash
printenv CORE_SKILLS_PR_SCREENSHOTS
```

| Value | Screens that need a new screenshot are… |
|---|---|
| unset, or `live` | taken now. This is the default. |
| `ask` | taken only after the user says yes (see Attach). |
| `collect-only` | not taken. Attach uses what the developer dropped in the folder. |
| `off` | not taken, and Attach changes nothing. |

Any other value: use `live`, and say in one line that the value wasn't recognised, naming it.

Look on its own (`fix-bug`, `implement-plan`) ignores the setting: those skills already decided to
drive the browser.

What a look costs, measured: about 1.5k tokens to log in, plus about 1.2k per screenshot Claude
views. The "before" adds nothing Claude views (Record compares it by bytes, not by eye).

## Folder

Screenshots for a PR live in `.playwright-mcp/pr/<folder>/`, where `<folder>` is the branch name
with `/` replaced by `-` (`git branch --show-current | tr '/' '-'`). Never commit anything in it.
If git doesn't already ignore it, ignore it locally, not in a committed `.gitignore`:

```bash
git check-ignore -q .playwright-mcp/pr/x.png || echo '.playwright-mcp/' >> "$(git rev-parse --git-path info/exclude)"
```

When that adds the local line, say once in the run's output that the lasting fix is a committed
`.playwright-mcp/` line in the project's `.gitignore` (`/core-skills:install` offers it), since the
local line covers this machine only. Ignore the whole folder, not just `pr/`: the Playwright MCP
writes its own snapshots and logs at the folder's root.

File names: `<screen>--<role>.png` (see Pick the screens). A developer adding a screenshot by hand
drops it in this folder under that name.

Paths given to the Playwright MCP resolve against its workspace root, normally the repo root, and
it refuses to write outside that root. After writing a file, check that it exists where you
expect.

## Swap check

Record briefly puts the base branch's frontend files into the working tree. Normally it puts the
branch's files back right after. If a run stopped in between, the base files are still there,
and they look like uncommitted changes. Committing them would quietly revert the branch. So first:

```bash
ls .playwright-mcp/pr/*/SWAP 2>/dev/null
```

No file: go on. A file: its first line is `head=<sha>`, the rest are paths.

- `<sha>` is the current `git rev-parse HEAD`: restore (the commands in Record, step 5),
  tell the user in one line, then go on.
- Anything else: stop. Tell the user a swap from another commit was left unfinished, and show
  them the marker. Don't guess which version of those files they want.

## Look

1. **Read the browser reference**, the file the calling skill names. It holds the local URL, the
   login, the seeded accounts per role, the 2FA code command, and what the local stack can't
   show. No reference: `No screenshots: this project has no browser reference.`
2. **Pick the screens.** From the diff, name each screen a changed file renders: the route or page
   that shows the changed component or style, and the role that sees it. For each, write down:
   - `screen`: a short slug for the route (`customers-index`);
   - `role`: a slug for the account (`admin`);
   - `files`: the changed files that render it.

   A change that shows nothing on screen gets no screen. Examples: a style for a state the local
   data can't reach, or a template only a mail renders. Then:
   `No screenshots: <why the change shows nothing locally>.` Use the reference's list of what the
   local stack can't show where it applies.
3. **Open the app** with the Playwright MCP: `browser_navigate` to the reference's URL. Load the
   `mcp__plugin_playwright_playwright__browser_*` tools first if they are deferred. No skill here
   starts the app. The first load can be slow while the dev server compiles: wait up to 30 s for
   the login page.
   - Not answering: `No screenshots: the app does not run locally (<URL> did not answer).`
   - No Playwright MCP in this session: `No screenshots: no Playwright MCP in this session.`
4. **Log in, find-first.** Locate fields and buttons with `browser_find`. Never take a whole-page
   `browser_snapshot`: one page tree costs 10–20 KB, a find costs a fraction of that.
   - Log in as the account for the role the screen needs.
   - On a 2FA prompt, run the reference's code command and type the code at once with
     `browser_type` and `slowly: true`. A plain fill can keep only the first digit.
   - A code can't be used twice. A second login within about 30 s needs the next code: wait for
     it.
   - The code stays in this session: never in the PR body, a commit or a comment.
   - A setup screen for 2FA, or a wrong password, stops the look:
     `No screenshots: <what the login showed>.`
5. **Look at each screen.** Open it with a fresh page load, never by following the app's own
   redirect after login. A page reached by a redirect can differ from a fresh load: on emmie, a
   one-time welcome dialog appears on a fresh load only. A "before" is always a fresh load (Record,
   step 4), so the "after" must be one too.
   - **Look on its own:** `browser_navigate` to the screen, wait for the part that changed
     (`browser_find` or `browser_wait_for`), then `browser_take_screenshot` (`scale: "css"`).
     With a `filename`, that tool returns only a link to the file: open the file to look at it.
     Save it wherever the calling skill says, or in the MCP's default output folder, never in
     `.playwright-mcp/pr/`.
   - **Look for Record:** run the open-and-keep snippet below, with key `after:<screen>--<role>`
     and the file `.playwright-mcp/pr/<folder>/<screen>--<role>.png`. Then open that file to look
     at it.

   Either way, check that the change is there and looks right, and read the console
   (`browser_console_messages`). A screen that looks broken, or a console error the reference
   doesn't list as expected, is a finding: the calling skill says what happens next. `pr` stops
   before the PR opens.
6. **Close the browser** (`browser_close`) when the calling skill is done with it. Record still
   needs it open.

### Open and keep: the snippet both halves use

The two halves of a before/after image compare fairly only when they're taken the same way. The
code tool (`browser_run_code_unsafe`; `browser_run_code` in older versions) can't read files, and
nothing it holds survives to the next call, but a browser tab does. So one snippet opens the
screen, lets it settle, takes the screenshot, and keeps a copy in a spare tab, `about:blank#shots`.
Use it for the "after" in Look and the "before" in Record, with the same `url` and `ready` each
time:

```js
async (page) => {
  const url = '<the screen's URL>';
  const ready = '<text the screen shows once loaded, in both versions: not the changed part>';
  const key = 'after:<screen>--<role>';                       // 'before:<screen>--<role>' in Record
  const file = '.playwright-mcp/pr/<folder>/<screen>--<role>.png';   // null for the "before"
  await page.goto(url);
  await page.getByText(ready).first().waitFor({ timeout: 30000 });
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForTimeout(1000);                            // late dialogs and animations
  const png = await page.screenshot({ scale: 'css', ...(file ? { path: file } : {}) });
  const ctx = page.context();
  let shots = ctx.pages().find(p => p.url().endsWith('#shots'));
  if (!shots) { shots = await ctx.newPage(); await shots.goto('about:blank#shots'); }
  await shots.evaluate(([k, d]) => { (window.shots ??= {})[k] = d; }, [key, png.toString('base64')]);
  return 'kept';
}
```

It returns no image, so the "before" costs no viewing tokens. Opening the spare tab doesn't change
which tab the other browser tools act on. If a later call seems to act on the wrong page, check
with `browser_tabs`.

## Record

Only after the calling skill has committed and pushed. Then every change on the branch is in
HEAD, so putting the branch's files back can't lose anything.

1. **Which screens get a "before".** All the screens Look just took, except:
   - a screen the branch adds: every file in its `files` is new on the branch
     (`git diff --name-status origin/<base>...HEAD` shows `A`). Note it as
     `Before left out: new on this branch.`;
   - every screen, when the files the swap would replace have uncommitted changes (step 2). Note
     it as `Before left out: uncommitted changes in files the swap would replace.`
2. **List the files to swap.** That is every frontend file that differs between HEAD and the base
   as it is now:

   ```bash
   git diff --no-renames --name-only HEAD origin/<base> -- '*.vue' '*.tsx' '*.jsx' '*.ts' '*.js' '*.mjs' '*.css' '*.scss' '*.blade.php'
   ```

   No paths: the branch's frontend already matches the base, so there is nothing to swap. Leave
   every "before" out: `Before left out: the frontend files match the base.`
   Otherwise `git status --porcelain -- <those paths>` must be empty. If it isn't, leave the
   "before" out (step 1).
3. **Swap.** Write the marker first, then the files:

   ```bash
   dir=.playwright-mcp/pr/<folder>
   { echo "head=$(git rev-parse HEAD)"; printf '%s\n' <paths>; } > "$dir/SWAP"
   for p in <paths>; do
     if git cat-file -e "origin/<base>:$p" 2>/dev/null; then git checkout "origin/<base>" -- "$p"
     else rm -f -- "$p"; fi
   done
   ```

4. **Take each "before".** The dev server picks up the swapped files, so log in again only if the
   session ended.
   - For each screen, run the open-and-keep snippet with the same `url` and `ready` as its "after",
     key `before:<screen>--<role>`, and `file` null. If `ready` never appears, the base renders
     the screen differently: see the cases below.
   - Read the console. Don't take a `browser_take_screenshot` here: the "before" isn't viewed.
   - The base answers the route with "not found": the screen is new after all.
     `Before left out: new on this branch.`
   - The page errors, shows the framework's error screen, or logs a console error that "after"
     didn't: `Before left out: the base frontend does not run against this branch's backend.`
     This is expected when the branch changed an API, a migration or seed data the screen
     depends on.
5. **Restore**, as soon as the last "before" is taken, even if some failed:

   ```bash
   tail -n +2 "$dir/SWAP" | while read -r p; do
     if git cat-file -e "HEAD:$p" 2>/dev/null; then git checkout HEAD -- "$p"
     else git reset -q -- "$p"; rm -f -- "$p"; fi
   done
   git status --porcelain -- $(tail -n +2 "$dir/SWAP")
   ```

   The status output must be empty. A file that exists only on the base was staged by the swap's
   checkout, which is why the restore unstages it before deleting it. Only then delete
   `$dir/SWAP`. If it isn't empty, stop and show
   the user. Never commit while the marker exists.
6. **Join each pair into one image.** One code call per screen. It reads both copies from the
   `#shots` tab and lays them side by side with labels. The "before" goes left, labelled
   `Before: <base> @ <short base sha>`; the "after" goes right, labelled
   `After: <branch> @ <short HEAD sha>`. It writes the result over the Look screenshot:

   ```js
   async (page) => {
     const shots = page.context().pages().find(p => p.url().endsWith('#shots'));
     const s = await shots.evaluate(() => window.shots);
     const b = s['before:<screen>--<role>'], a = s['after:<screen>--<role>'];
     if (b === a) return 'same';
     const fig = (label, png) => `<figure style="margin:0"><figcaption style="padding:0 0 8px">${label}</figcaption>`
       + `<img style="display:block;border:1px solid #999" src="data:image/png;base64,${png}"></figure>`;
     const view = await page.context().newPage();
     await view.setContent(`<body style="margin:0;padding:16px;display:inline-flex;gap:24px;background:#fff;font:600 22px system-ui">`
       + fig('<before label>', b) + fig('<after label>', a) + `</body>`);
     const width = await view.evaluate(() => Math.ceil(document.body.getBoundingClientRect().width));
     await view.setViewportSize({ width, height: 900 });
     await view.screenshot({ path: '.playwright-mcp/pr/<folder>/<screen>--<role>.png', fullPage: true });
     await view.close();
     return 'joined';
   }
   ```

   - `same`: the two copies are identical, so the swap changed nothing on screen. Most likely the
     dev server doesn't serve source files live. Keep the "after" alone:
     `Before left out: the page looked the same with the base's files.`
   - A screen without a "before" keeps its Look screenshot as it is.

   Close the `#shots` tab when done. Don't view the joined image: its two halves are images
   already seen or compared by bytes.
7. **Write the manifest**, `.playwright-mcp/pr/<folder>/shots.md`: one entry per screen, in the
   exact form it takes in the PR body (Attach, below), with the local path where the uploaded URL
   will go.
   - `sha` is HEAD.
   - `base` is `git rev-parse --short origin/<base>` for an entry with a "before", and `-` for one
     without.

## Attach

The PR body is the record. `## Screenshots` holds one entry per screen:

```markdown
## Screenshots

<!-- shot screen=customers-index role=admin sha=1a2b3c4 base=9f8e7d6 files=resources/js/pages/Customers/Index.vue,resources/js/components/StatusBadge.vue -->
![Admin, /customers: the status column. Before: main @ 9f8e7d6, after: this branch @ 1a2b3c4](https://github.com/user-attachments/assets/…)

<!-- shot screen=customer-edit role=admin sha=1a2b3c4 base=- files=resources/js/pages/Customers/Edit.vue -->
![Admin, /customers/1/edit: the status field](https://github.com/user-attachments/assets/…)
Before left out: the base frontend does not run against this branch's backend.
```

How an entry is written:
- The hidden comment holds the facts the next run compares. Values have no spaces: `files` is
  comma-separated, and a space in a path is written `%20`.
- The image line's caption gives the role, the URL and what the screen shows.
- A line under the image says why a "before" is missing, when one is.
- Lines that aren't part of an entry are status lines. Each run writes them anew:
  `No screenshots: …`, `Not taken: …`, and the unrecognised-setting line.

Steps:

1. **Read the setting.** `off`: change nothing. On a new PR, the section is the single line
   `No screenshots: turned off with CORE_SKILLS_PR_SCREENSHOTS=off.` Stop here.
2. **Read the current entries**, if the PR exists: `gh pr view <n> --json body --jq .body`, then
   the `<!-- shot … -->` entries under `## Screenshots`.
3. **Decide per screen.** The screens are the ones the current diff renders (Look, step 2). Use
   the hidden comment's own `files`, and the current `files` where the rule says so:

   | The screen… | Do |
   |---|---|
   | has no entry | **add**: needs a screenshot |
   | has an entry, and `git cat-file -e <sha>` fails (the branch was rebased), or its `base` ≠ `-` and `git cat-file -e <base>` fails | **retake** |
   | has an entry, and `git diff --quiet <sha> HEAD -- <files>` fails, or the current `files` differ from the entry's | **retake**: the "after" is stale |
   | has an entry with `base` ≠ `-`, and `git diff --quiet <base> origin/<base> -- <files>` fails | **retake**: the "before" is stale |
   | has an entry, and none of the above apply | **keep**, word for word |
   | is no longer changed by the branch, but has an entry | **drop** |

4. **Take what is needed.** The screens marked add or retake are the screens to take.
   - **None:** go to step 5.
   - **`live`:** run Look on those screens, then Record.
   - **`ask`:** ask once (AskUserQuestion). Name the screens and the cost: about
     1.5k + 1.2k × screens tokens. Offer three answers: take them now; I'll drop them in
     `.playwright-mcp/pr/<folder>/` as `<screen>--<role>.png`; skip.
   - **`collect-only`:** name the expected files and ask whether the user wants to drop them in
     now or skip.

   A screenshot the developer dropped in is used as it is, with no "before": `sha` is HEAD, `files`
   is the screen's current `files`, and `base` is `-`.

   A screen still without a screenshot when this step ends is not attached. If it had an entry,
   keep that entry (it is stale, but better than nothing) and add the status line
   `Not taken: <screen> (<role>) changed since this screenshot.` A screen with no entry gets
   `Not taken: <screen> (<role>), <why>.`
5. **Write the section.** It holds the entries in diff order (kept ones word for word, new ones
   from the manifest), the "before left out" lines under their entries, and the status lines last.
   An empty result never leaves the section empty: it says why there are no screenshots, in one
   line.
6. **Upload.** `--attach` is new in `gh`. Check for it with
   `gh pr create --help | grep -q -- --attach`.
   - **gh has it:** pass each new file to the same `gh pr create` or `gh pr edit` as
     `--attach '<path>#<caption>'`, and reference it in the section as `![<caption>](<path>)`
     with the same path. gh uploads the file and rewrites that reference to the uploaded asset.
     Kept entries already have their URL: don't attach them again.
   - **gh lacks it:** the PR still opens or updates. New entries are left out. The section gets
     `Screenshots taken, not attached: this gh has no --attach. Files: <path>, <path>.`, and the
     user drags the files into the PR by hand or upgrades `gh`.

   On an existing PR, splice the body as the calling skill's "Refreshing an existing PR body"
   recipe says. Only `## Screenshots` changes here.
7. **Clean up.** After a successful upload, read the body back and check that each new entry's
   image line now holds a URL. Then delete `.playwright-mcp/pr/<folder>/`. If gh lacked
   `--attach`, keep the folder: the user still needs the files.
