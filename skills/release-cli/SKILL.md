---
name: release-cli
description: >
  Release a new version of a Go CLI tool by tagging and pushing to trigger GoReleaser.
  Use whenever the user wants to release the CLI, tag a CLI version, publish the CLI, cut a CLI
  release, or says "release cli", "tag cli", "new cli version". Also use when the user asks about
  the CLI release process or how to ship a new CLI version.
---

# Release CLI

Tag and release a new version of a Go CLI tool. Pushing the configured release tag triggers a
GitHub Actions workflow that runs GoReleaser to build cross-platform binaries and create a
GitHub Release.

This skill assumes the project has:

- A `.goreleaser.yaml` (or `.goreleaser.yml`) — anywhere in the repo
- A GitHub Actions workflow that runs GoReleaser on tag push
- A `version` variable in the CLI source, injected at build time via `-ldflags -X <pkg>.version=<version>`

## Step 1 — Discover the project's CLI conventions

Detect the relevant paths and tag scheme before doing anything else.

```bash
# Find the goreleaser config
find . -name '.goreleaser.y*ml' -not -path './node_modules/*' -not -path './.git/*'

# Find the release workflow
find .github/workflows -name '*release*.yml' 2>/dev/null

# Inspect previous release tags to learn the prefix scheme
git tag -l --sort=-v:refname | head -10
```

From those, determine:

| Question | How to find out |
|----------|----------------|
| Where does the Go module live? | Directory containing the `.goreleaser.yaml` (often `.` or `cli/`) |
| What's the tag prefix? | Inspect the most recent tags (e.g. `v1.2.3`, `cli/v1.2.3`, `myapp/v1.2.3`). If there are no tags yet, ask the user. |
| Which branch should releases be cut from? | Inspect the workflow file (`on.push.branches` for protections), or ask the user. Most projects release from `main`. |

In the rest of this skill, `<module-dir>` is the directory holding the goreleaser config (use `.` if at repo root) and `<tag>` is the new release tag in the project's prefix scheme (e.g. `v0.3.0` or `cli/v0.3.0`).

## Step 2 — Determine the next version

Run in parallel:

- `git tag -l "<prefix>v*" --sort=-v:refname | head -5` — find the latest tag in this scheme
- `git log <latest-tag>..HEAD --oneline -- <module-dir>` — see what changed since last release
  (if no tags exist yet, use `git log --oneline -- <module-dir>` to see all CLI commits)

If there are **no new commits** to `<module-dir>` since the last tag, tell the user there's nothing to release and stop.

Present the changelog to the user and suggest a version bump based on conventional commits:
- **patch** (0.1.0 → 0.1.1): only `fix:` commits
- **minor** (0.1.0 → 0.2.0): any `feat:` commits
- **major** (0.1.0 → 1.0.0): breaking changes (rare, user should confirm)

If the user passed an argument (e.g., `/release-cli 0.3.0`), use that version directly.

## Step 3 — Pre-flight checks

a. **Ensure the release branch is up to date** — the tag should sit on the branch the workflow releases from (usually `main`).

```bash
git fetch origin <release-branch>
git log --oneline origin/<release-branch>..origin/<dev-branch> -- <module-dir> | head -10
```

If there are commits on the dev branch not yet on the release branch, warn the user and don't proceed until that's reconciled.

b. **Run tests locally** as a quick sanity check:

```bash
( cd <module-dir> && go test ./... )
```

If tests fail, stop and help fix them.

## Step 4 — Create and push the tag

```bash
git checkout <release-branch> && git pull origin <release-branch>
git tag <tag>
git push origin <tag>
```

Then switch back to the previous branch:

```bash
git checkout -
```

## Step 5 — Monitor the release

Check that the GitHub Actions workflow started:

```bash
gh run list --workflow=<workflow-file> --limit 1
```

Tell the user:
- The tag that was created
- That the workflow is running
- Where to find the release: `gh release view <tag>` or on GitHub's Releases page

## Step 6 — Optionally wait for completion

If the user wants to confirm the release succeeded:

```bash
gh run watch <run-id>
gh release view <tag>
```

## Notes

- If the project uses a path-prefixed tag (e.g. `cli/v*`) but is on GoReleaser OSS, the workflow typically creates a local semver tag (`v<version>`) so GoReleaser can parse it (the `monorepo` config is GoReleaser Pro only). Inspect `.github/workflows/<workflow-file>` to see how the project handles this.
- GoReleaser injects the version into the binary via `-ldflags -X <pkg>.version=<version>` — check the goreleaser config to confirm the variable name and package path.
- The auto-generated changelog uses conventional commits but on GoReleaser OSS includes all repo commits between tags (not just `<module-dir>` changes).
