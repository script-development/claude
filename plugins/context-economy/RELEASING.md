# Releasing

How versions of this plugin get cut, and what was deliberately decided against.

## Process

1. Work lands on `main` via ordinary commits. Nothing here changes day-to-day development.
2. When it's time to cut a release, review what's landed since the last tag:
   `git log <last-tag>..HEAD`.
3. Pick a bump using the rule below, and update `"version"` in `.claude-plugin/plugin.json`.
4. Add a `## [X.Y.Z] - YYYY-MM-DD` entry to `CHANGELOG.md` summarizing what changed, written
   from the git log in step 2 — not maintained incrementally as commits land.
5. Commit the version bump and changelog entry together as the release commit.
6. From the repo root, `claude plugin tag plugins/context-economy --dry-run` to preview, then
   `claude plugin tag plugins/context-economy --push` to create and push the
   `context-economy--vX.Y.Z` tag (equivalently, `cd plugins/context-economy` and drop the path
   argument).

## Version bump rule

- **MAJOR** — a breaking change to a hook/skill interface or file layout (something a consumer
  or another plugin could depend on).
- **MINOR** — a new hook, skill, or constant.
- **PATCH** — everything else: fixes, internal refactors, doc/comment changes.

## Staying pre-1.0

Stays `0.x.y` indefinitely by default. `1.0.0` was earmarked for if/when this plugin moved under
an organization — as of the `script-development/claude` migration, that's now true, but the bump
itself is still a separate, deliberate decision, not automatic. Nothing above depends on which
version line is current.

## Deliberately deferred, and why

- **No `tools/release.sh`.** Three manual steps, done occasionally, don't earn an abstraction
  yet. Revisit once doing this by hand is actually annoying.
- **No conventional-commit prefixes.** This repo's commit messages are narrative by
  convention (e.g. "Confirm the compact read leg's two load-bearing claims with a live probe"),
  not machine-parseable ones. Bump type and changelog content are a judgment call at release
  time, not derived from commit prefixes.
- **No GitHub Releases page.** Cosmetic only — has no effect on Claude Code's own update
  mechanics. Add it later if a nicer browse/download experience is wanted.
- **`marketplace.json` lives one level up, not here.** Added once `/plugin marketplace add`
  support became a real need (the `script-development/claude` migration) — see
  `.claude-plugin/marketplace.json` at the repo root. It's shared across every plugin that repo
  hosts, so it isn't this plugin's file to own. `context-economy--vX.Y.Z` tags are what
  version-constraint resolution for dependents actually consumes — see
  [plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies) — not the
  update-detection path, which reads `plugin.json`'s `version` field directly.
