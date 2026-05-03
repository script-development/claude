---
name: release-cli
description: >
  Release a new version of the kendo Go CLI tool by tagging and pushing to trigger GoReleaser.
  Use whenever the user wants to release the CLI, tag a CLI version, publish the CLI, cut a CLI
  release, or says "release cli", "tag cli", "new cli version". Also use when the user asks about
  the CLI release process or how to ship a new CLI version.
---

# Release CLI

Tag and release a new version of the kendo Go CLI tool. Pushing a `cli/v*` tag triggers the
GitHub Actions workflow (`.github/workflows/cli-release.yml`) which runs GoReleaser to build
cross-platform binaries and create a GitHub Release.

**Key files:**
- `cli/.goreleaser.yaml` — build config, version injection via ldflags
- `.github/workflows/cli-release.yml` — release workflow (tests + GoReleaser)
- `cli/cmd/root.go` — `version` variable (default `"dev"`, injected at build time)

## Workflow

### 1. Determine the next version

Run in parallel:
- `git tag -l "cli/v*" --sort=-v:refname | head -5` — find the latest CLI tag
- `git log <latest-tag>..HEAD --oneline -- cli/` — see what changed since last release
  (if no tags exist yet, use `git log --oneline -- cli/` to see all CLI commits)

If there are **no new CLI commits** since the last tag, tell the user there's nothing to release
and stop.

Present the changelog to the user and suggest a version bump based on conventional commits:
- **patch** (0.1.0 → 0.1.1): only `fix:` commits
- **minor** (0.1.0 → 0.2.0): any `feat:` commits
- **major** (0.1.0 → 1.0.0): breaking changes (rare, user should confirm)

If the user passed an argument (e.g., `/release-cli 0.3.0`), use that version directly.

### 2. Pre-flight checks

a. **Ensure `main` is up to date** — the tag should be on `main` so releases match the
   production-ready branch:
```bash
git fetch origin main
git log --oneline origin/main..origin/development -- cli/ | head -10
```

If there are CLI commits on `development` not yet on `main`, warn the user that `main` needs
to be updated first (merge `development` into `main` or create a PR). Don't proceed until `main`
has the changes they want to release.

b. **Run tests locally** as a quick sanity check:
```bash
cd cli && go test ./... && cd ..
```

If tests fail, stop and help fix them.

### 3. Create and push the tag

```bash
git checkout main && git pull origin main
git tag cli/v<version>
git push origin cli/v<version>
```

Then switch back to the previous branch:
```bash
git checkout -
```

### 4. Monitor the release

Check that the GitHub Actions workflow started:
```bash
gh run list --workflow=cli-release.yml --limit 1
```

Tell the user:
- The tag that was created (e.g., `cli/v0.2.0`)
- That the workflow is running
- That GoReleaser will build binaries for linux/macOS/windows (amd64 + arm64)
- Where to find the release: `gh release view cli/v<version>` or on GitHub's Releases page

### 5. Optionally wait for completion

If the user wants to confirm the release succeeded:
```bash
gh run watch <run-id>
```

Then verify the release was created (note: GoReleaser creates the release under the semver tag `v<version>`, not `cli/v<version>`):
```bash
gh release view v<version>
```

## Technical notes

- The workflow creates a local `v<version>` git tag (not pushed) so GoReleaser OSS can parse it as semver. The `monorepo` config is GoReleaser Pro only.
- GoReleaser injects the version into the binary via `-ldflags -X cmd.version=<version>`
- The changelog is auto-generated from conventional commits but includes all repo commits between tags (not just CLI changes) — GoReleaser OSS can't filter by path.
