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
6. `claude plugin tag --dry-run` to preview, then `claude plugin tag --push` to create and push
   the `context-economy--vX.Y.Z` tag.

## Version bump rule

- **MAJOR** — a breaking change to a hook/skill interface or file layout (something a consumer
  or another plugin could depend on).
- **MINOR** — a new hook, skill, or constant.
- **PATCH** — everything else: fixes, internal refactors, doc/comment changes.

## Staying pre-1.0

Stays `0.x.y` indefinitely by default. `1.0.0` is reserved for if/when this repo moves under an
organization — not a fixed date, and not required to ever happen. Nothing above depends on
which one occurs.

## Deliberately deferred, and why

- **No `tools/release.sh`.** Three manual steps, done occasionally, don't earn an abstraction
  yet. Revisit once doing this by hand is actually annoying.
- **No conventional-commit prefixes.** This repo's commit messages are narrative by
  convention (e.g. "Confirm the compact read leg's two load-bearing claims with a live probe"),
  not machine-parseable ones. Bump type and changelog content are a judgment call at release
  time, not derived from commit prefixes.
- **No GitHub Releases page.** Cosmetic only — has no effect on Claude Code's own update
  mechanics. Add it later if a nicer browse/download experience is wanted.
- **No `marketplace.json`.** Not needed while this plugin is installed by direct git checkout /
  `--plugin-dir`. Only add one if `/plugin marketplace add` support or being depended on by
  another plugin's `dependencies` list becomes a real need — see
  [plugin dependencies](https://code.claude.com/docs/en/plugin-dependencies), which is also
  where `context-economy--vX.Y.Z` tags actually get consumed (version-constraint resolution
  for dependents), not from the update-detection path, which uses `plugin.json`'s `version`
  field directly.
