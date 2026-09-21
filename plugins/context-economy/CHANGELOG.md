# Changelog

Entries are written at release time from `git log <last-tag>..HEAD`, not maintained
incrementally — see `RELEASING.md` for why. Format follows [Keep a Changelog](https://keepachangelog.com/),
versioning follows [Semantic Versioning](https://semver.org/), scoped to this plugin's own
convention in `RELEASING.md`.

## [1.0.0] - 2026-09-21

`1.0.0` was earmarked in `RELEASING.md` for if/when this plugin moved under an organization; the
`script-development/claude` migration already happened, and this release is the deliberate bump
to match, not a claim of new breaking surface beyond what's listed below.

### Added

- `progress:` header field on the handoff (`writing` / `complete` / `consumed`), with a synchronous
  placeholder skeleton written before the detached authoring turn even exists — closing a race
  where a `SessionStart(source: compact)` read could arrive before the fork had produced anything,
  and either find a stale `complete` document from a previous cycle or nothing at all (D23).
- `write_session:` header field and `--session-id` pinning on the detached authoring turn
  (`uuidgen`, falling back to an `openssl`-derived id when absent), giving the read leg a liveness
  signal independent of `progress:`: past the nominal `CTX_FORK_TIMEOUT_SECONDS` budget, a
  still-advancing transcript — found by exact filename via the new `handoff_store_find_transcript`,
  never by reconstructing Claude Code's own unpublished project-directory naming — keeps a write
  classified active instead of abandoned, and its path is surfaced so a reader can check on it
  directly (D28). New `CTX_FORK_LIVENESS_WINDOW_SECONDS` threshold (90s default) governs it.

### Changed

- `hooks/handoff-inject.sh` and `hooks/session-end-marker.sh` now key off `write_attempted`
  (whether `hooks/handoff-fork-write.sh`'s own dedup lock exists for a session) instead of the
  retired `trigger_fired`/`urge_fired` pair. Fixes a real bug: the dead latch those two read was
  never written by the current write leg, so the injected text unconditionally claimed "the write
  trigger never armed this session" directly above a real handoff the current mechanism had just
  produced (D27).
- `compacted:` header field dropped entirely — the gate only ever checked it was present, never
  what it said, so it was pure ceremony (D24).
- The statusline's advisory grid moved up one step: NOTICE 120k→200k, URGE 200k→300k (D25).
- The read leg now waits for the detached write to finish before continuing, on explicit
  instruction — implemented as an executable poll the model runs itself, never as a block inside
  the hook (D26).
- `skills/handoff/SKILL.md` Write mode Step 4 no longer describes a "fired by the Stop hook
  itself" case; nothing registers `Stop` on this skill any more (D27).

### Removed

- `hooks/handoff-write.sh` and its test suite, deleted outright rather than left as an
  unregistered backstop — D22's original reversibility deliberately traded away (D27) — along with
  the ~190-line ceiling-detection/trigger-derivation block in
  `lib/context-economy/context-thresholds.sh` that only it consumed.
- `tools/measure-large-request.js`, its sole subject (`large_request`) no longer existing anywhere
  in the codebase (D27).

## [0.4.0] - 2026-09-17

### Changed

- **The automatic write leg no longer runs in-band.** `hooks/handoff-fork-write.sh`, registered on
  `PreCompact`, spawns a detached, headless `claude -p` turn that reads the session's own
  transcript (`transcript_path`) and authors the handoff completely out of band — its tokens never
  touch the interactive session's own context window (`docs/design.md` D22). This replaces
  `handoff-write.sh`'s `Stop`/`PostToolUse` in-band trigger entirely, per the explicitly stated
  intent that this release supersede that mechanism rather than ship alongside it (`O12`).
  `handoff-write.sh` is left in the repo, unregistered, as a possible future backstop — not deleted.
- **The handoff store root moved from `~/.claude/context-economy/` to
  `${XDG_DATA_HOME:-~/.local/share}/context-economy/`** (`docs/design.md` D21) — a breaking
  file-layout change, forced by a permission-layer guard on `.claude` paths that refused the real
  automatic write outright (`docs/measured.md` finding #28). The 8 real handoffs on this machine
  were migrated; `lib/handoff-store.sh`, its test fixtures, `SKILL.md`'s path literals, and the
  sibling `compaction-capture.sh` hook were all updated to match.

### Added

- `lib/handoff-store.sh`: portable `handoff_store_md5`/`handoff_store_mtime` helpers, fixing a
  silent failure on non-GNU (BSD/macOS) systems where `md5sum`/`stat -c` don't exist (`docs/design.md`
  D20).
- `docs/measured.md` findings #28-#33 and `docs/design.md` D20-D22: the full, unvarnished account
  of building and verifying the detached-spawn mechanism above, including real blockers found and
  fixed along the way (the `.claude` guard, ~15 MCP servers initializing on a bare headless spawn,
  an unprompted environment-investigation tangent) and confirmation — against a real, decision-rich
  transcript, not just a degenerate one — that the mechanism produces a genuinely good handoff, not
  merely a passing one.

## [0.3.1] - 2026-09-14

### Fixed

- **`lib/verify-citations.sh` stripped backticks from a citation's fragment but not from the target
  line, so a markdown target could never match a fragment that crossed a real backtick**
  (`docs/design.md` O11). Invisible for the script's whole life until now — every prior citation
  target was source code, which never contains a literal backtick — but this repo's own docs
  (`docs/design.md`, `docs/measured.md`) are markdown and are cited from handoffs routinely. A
  fragment crossing a real backtick in the target reported CHANGED on a line that had not changed
  at all. Fixed by stripping backticks from the target too, in both the per-line and whole-file
  checks; four new regression assertions in `lib/verify-citations.test.sh`.

### Added

- **`docs/design.md` O10**: a proposed "Route 5" for the automatic handoff trigger — move the
  arming check from `Stop` (which only observes at true turn boundaries) onto `PostToolUse` (which
  fires after every tool call), replacing `fat_turn` (a whole uninterrupted turn's growth, shown
  unbounded by finding #18) with `large_request` (one tool-call round-trip's growth, plausibly
  bounded). Mechanism confirmed live (`docs/measured.md` finding #19): `PostToolUse`
  `decision:"block"` does deliver `reason` as the model's next instruction mid-turn, folds into the
  same turn, and a session latch suppresses re-firing; one candidate cost (an "Exited Auto Mode"
  side effect) was raised and then refuted by a matched-pair re-run. Not yet built — the remaining
  prerequisite is measuring `large_request`'s real distribution.
- `docs/measured.md` finding #18: a real, unattended `/implement-plan` turn added ~549k resident
  tokens in one uninterrupted stretch (1,625 messages, one turn) — the incident that prompted Route
  5, and confirmation that the automatic write-trigger's own `[trigger, gate)` invariant can be
  leapt unseen when a turn has no boundary for that long. The hook's decline in that case (rather
  than a stale write) was exactly the designed-safe outcome, not a bug.
- `docs/measured.md` finding #19: live verification of the `PostToolUse` mechanism above, plus the
  matched-pair probe that refuted the auto-mode side effect.

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
