# Changelog

Entries are written at release time from `git log <last-tag>..HEAD`, not maintained
incrementally — see `RELEASING.md` for why. Format follows [Keep a Changelog](https://keepachangelog.com/),
versioning follows [Semantic Versioning](https://semver.org/), scoped to this plugin's own
convention in `RELEASING.md`.

## [0.3.0] - 2026-09-11

### Changed

- **The handoff skill's write-mode Step 4 branches on why the write happened, not on who is
  attending** (`docs/design.md` D19). A Stop-hook-fired write now reports in one line and lets the
  session keep working, matching D18's own assumption that an automatic handoff is insurance
  against real auto-compaction, not a checkpoint to pause at — its ~120k-token gap at compaction
  was already "doing exactly what it was designed to do." A directly-invoked write (a human, or an
  orchestrator instructing a subagent it's watching from outside) still stops, since asking for one
  manually is itself the request for a pause; attendance now only changes whether the stop message
  tells a human what to run or confirms to an absent one that it's safe to reset externally. Closes
  O3 in full.

### Added

- `README.md`: a user-facing overview of the plugin — goal, `/handoff`'s manual and automatic
  triggers, handoff structure, and how to set the auto-compact window.
- `docs/measured.md` finding #17: `CTX_COMPACT_THRESHOLD_TOKENS`'s relationship to the real
  `--autocompact` ceiling, measured directly (`compact_threshold` ≈ window − 35,500 tokens for
  `claude-sonnet-5`, bracketed under ±1,400) across three forced windows rather than assumed.

## [0.2.1] - 2026-09-09

### Fixed

- **`skills/handoff/SKILL.md` probed the wrong paths for the verify gate and handoff store,
  missing a plugin-installed checkout.** The probe order is now a plugin-cache glob
  (`~/.claude/plugins/cache/*/context-economy/*/lib/`, newest version wins — the same pattern
  `statusline.sh` already used) first, then the target checkout's own `lib/`, then
  `~/.claude/lib/` for a pre-plugin symlink install, then the retired vendored path as a last
  resort. Previously the probe never checked the plugin cache, so a plugin install fell through
  to `gate=NONE` and wrote unverified handoffs even when a real gate was installed.

## [0.2.0] - 2026-09-09

### Changed

- **The automatic handoff trigger is derived from the compaction ceiling, not fixed at 200k**
  (`docs/design.md` D18). `hooks/handoff-write.sh` now arms at
  `ceiling - 2*fat_turn - authoring_turn`, the latest point that still leaves room to write, with
  the gate one fat turn above it and `CTX_NOTICE_TOKENS` as the floor beneath it. The old fixed
  trigger failed in both directions: on a 1M window it armed at 20% of the window and let the
  session run on to ~887k, so compaction met a handoff hundreds of thousands of tokens stale;
  on a 200k window, where compaction fires near 187k, it never armed at all.
- **`hooks/handoff-urge.sh` is renamed to `hooks/handoff-write.sh`.** BREAKING for anything
  referencing the path. "Urge" described an advisory a human acted on; since D18 the hook blocks
  on `Stop` and hands the model an instruction. Urging is now exactly what `CTX_URGE_TOKENS`
  does, and that constant keeps the name.
- **`CTX_URGE_TOKENS` (200k) is the statusline's alone.** It is no longer read by any hook — it
  remains the passive advisory and the point at which a human may choose to run `/handoff` by
  hand. Cost stays a human judgement; continuity became an automatic constraint.
- **`CTX_FAT_TURN_TOKENS` moves from the corpus maximum (325,000) to p95 (60,000).** Forced, not
  preferred: at the maximum the derived trigger evaluates to 174,654, below the 200k advisory it
  is meant to sit far above. "Too large" stops being conservative once the term sets the
  trigger's position rather than only vetoing.
- **The session-end marker's `urge_fired` field is renamed `trigger_fired`.** The read side in
  `hooks/handoff-inject.sh` accepts both keys, so markers written by a 0.1.0 install are still
  read correctly until it is updated.
- `docs/design.md` records D18 and the alternatives it beat, including why `PreCompact` stays
  rejected and why `min(absolute, relative)` is a no-op in every shipped configuration.

### Fixed

- **The read side judged handoff coverage against the wrong constant.** `hooks/handoff-write.sh`
  now records `expected_gap_tokens` alongside the handoff, so `hooks/handoff-inject.sh` measures
  the gap against what the trigger deliberately reserved rather than against a threshold
  calibrated for a handoff a human wrote.
- **Shallow sessions were nagged about an unknown compaction ceiling.** A cheap
  `CTX_NOTICE_TOKENS` pre-filter now runs before ceiling resolution, so a session too small to be
  worth handing off never reaches the decline path.
- **The stated justification for the checked-in 1M ceiling was stale.** It rested on
  `CTX_URGE_TOKENS` gating every consumer at 200k, which is no longer true of anything; the
  conclusion holds on the derived trigger instead, and the comment says so.

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
