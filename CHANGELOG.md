# Changelog

Entries are written at release time from `git log <last-tag>..HEAD`, not maintained
incrementally — see `RELEASING.md` for why. Format follows [Keep a Changelog](https://keepachangelog.com/),
versioning follows [Semantic Versioning](https://semver.org/), scoped to this plugin's own
convention in `RELEASING.md`.

## [0.1.0] - 2026-09-07

First tagged release. Everything up to this point.

### Added

- `skills/handoff`: writes a machine-verifiable handoff before a context reset, and locates,
  verifies, and reads one back at the start of a fresh session.
- `hooks/handoff-inject.sh`: `SessionStart` hook that finds the right handoff for the current
  checkout/branch and verifies its citations before surfacing it.
- `hooks/handoff-urge.sh`: `Stop` hook that fires a one-shot advisory to write a handoff before
  context runs out, driven by `lib/context-economy/context-thresholds.sh`.
- `hooks/session-end-marker.sh`: records how a session ended, so the read leg can judge whether
  an existing handoff likely covers it.
- `lib/context-gauge.sh`: renders context-headroom status against the shared thresholds.
- `lib/handoff-store.sh`: resolves the machine-local, cross-checkout handoff store path.
- `lib/verify-handoff.sh` / `lib/verify-citations.sh`: the gate that gives a handoff's citations
  a pass/fail verdict against a checkout.
- `tools/context-audit.js`: measures where a Claude Code session's tokens actually went, from
  the transcript store.
- `tools/context-billing.js`: measures how a token is billed over its lifetime in a context.
- `tools/context-calibrate.js`: calibrates the chars-per-token and related constants against
  measured usage.
- Bash test suites under `tests/`, with `tests/gate.sh` as a structural gate ensuring every
  suite actually asserts something.
- `docs/design.md`, `docs/measured.md`, `docs/calibration.md`: the research and measurements the
  thresholds and tooling claims are built on.
