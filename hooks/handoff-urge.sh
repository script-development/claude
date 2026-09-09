#!/bin/bash
#
# Stop hook: the WRITE leg of the automated handoff cycle (build-order item 4).
#
# At the LAST turn boundary where the session can still finish writing a handoff before
# auto-compaction takes it, this returns control to the model with an instruction to run
# /handoff. `decision: "block"` on a Stop hook is not a veto -- `reason` becomes the model's next
# instruction -- so this is what makes a handoff survive a compaction without the human having to
# watch a number and act on it.
#
# It fires AT MOST ONCE PER SESSION, and it DECLINES ENTIRELY unless it can establish where
# compaction will fire. The decline is the important half; see "THE TRIGGER IS DERIVED" below.
#
# Thresholds are SOURCED from this bundle's lib/context-economy/context-thresholds.sh, never
# restated. If that file is missing this hook does nothing at all -- degrade capability, never
# execution, the same rule the gauge follows when its thresholds are absent.
#
# ── THE TRIGGER IS DERIVED FROM THE CEILING, NOT FIXED AT CTX_URGE_TOKENS ──────────────────
#
# Changed 2026-09-09 by [D18](../docs/design.md#d18); this hook used to fire at an absolute
# CTX_URGE_TOKENS (200k) and treat the compaction ceiling only as a veto. Two failures, opposite
# in direction and both traceable to expressing a compaction-relative decision as a constant:
#
#   On a 1M window it fired at 20% of the window and then let the session run on to ~887k
#   regardless, so what compaction actually met was a handoff hundreds of thousands of tokens
#   stale. On a 200k-window session compaction fires ~187k -- BELOW 200k -- so it never fired at
#   all, silently, and could not have: the old worst-case margin alone exceeded the whole window.
#
# So the trigger is now `ceiling - 2*fat_turn - authoring_turn`, the latest point that is still
# safe, with the gate one fat turn above it and CTX_NOTICE_TOKENS as a floor beneath it. 200k
# remains what it always usefully was -- the statusline's passive advisory, and the point at which
# a HUMAN may choose to run /handoff. This hook no longer reads it.
#
# WHY IT DECLINES RATHER THAN WARNS, unchanged from the original design: an armed trigger with
# negative slack loses the race to compaction every time, and the handoff it then produces is
# authored from a compaction summary. That is the `compacted: yes` degradation the handoff format
# exists to RECORD, manufactured on purpose. An unarmed trigger is merely the status quo, so
# declining is strictly the cheaper failure.
#
# Rejected alternatives, all of which look cheaper: an install-time check (cannot know the
# runtime window -- it varies per model, per org, per session); a statusline warning (hot path,
# ~4x per tool call, must stay pure); "warn and proceed"; and silently lowering the threshold.
#
# ── CLOUD-SESSION CAVEAT ───────────────────────────────────────────────────────────────────
#
# This file is installed by SYMLINK into ~/.claude/hooks/, and a hook whose realpath lands inside
# a repo the cloud session has synced is held by the `in_reach` check regardless of settings
# scope. Defining it in USER settings clears `project_configured` but NOT `in_reach`. So for
# calls served to a cloud session this hook is skipped (reported via a systemMessage, not
# silently) and no handoff is written. LOCAL SESSIONS ARE UNAFFECTED. If that ever needs fixing
# it needs a real file outside any synced checkout, not a settings change.

set -uo pipefail

input=$(cat)

# ── Env override, captured BEFORE sourcing ─────────────────────────────────────────────────
# context-thresholds.sh assigns CTX_COMPACT_THRESHOLD_TOKENS unconditionally (to empty), so
# sourcing it would clobber an environment value. Capturing first lets a machine declare its
# real ceiling without editing a file that is checked in and shared across every machine.
declared_ceiling="${CTX_COMPACT_THRESHOLD_TOKENS:-}"

# RESOLVED BESIDE THIS HOOK, NOT FROM $HOME. One expression, correct in all three positions
# this hook can occupy: in-repo (hooks/ -> ../lib), installed
# (~/.claude/hooks -> ~/.claude/lib), and inside a plugin (${CLAUDE_PLUGIN_ROOT}/hooks -> ../lib).
# `pwd` WITHOUT -P is deliberate, exactly as handoff-inject.sh does it: through the install
# symlink that dirname must stay ~/.claude/hooks rather than resolving back to the checkout.
#
# It reaches the NESTED context-economy/ subpath, which is what retired the flat
# ~/.claude/lib/context-thresholds.sh that install.sh used to create for this one line. A
# plugin has no ~/.claude/lib to read, so the old path could never have worked there.
hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CTX_THRESHOLDS_FILE="${CTX_THRESHOLDS_FILE:-$hook_dir/../lib/context-economy/context-thresholds.sh}"
[ -f "$CTX_THRESHOLDS_FILE" ] || exit 0
# shellcheck source=/dev/null
. "$CTX_THRESHOLDS_FILE"
[ -n "$declared_ceiling" ] && CTX_COMPACT_THRESHOLD_TOKENS="$declared_ceiling"

# Every number this hook acts on must have arrived from that file. A missing one means the file
# loaded but is older than this hook, which is indistinguishable from "no opinion" -- and `-n`
# rather than `${VAR:-0}` for the reason the file states at length: a :-0 default would read as
# a real threshold of zero, which fails OPEN in a check that must fail closed.
# CTX_NOTICE_TOKENS rather than CTX_URGE_TOKENS since D18: URGE is advisory-only now (the
# statusline renders it, a human acts on it) and this hook no longer reads it at all, while NOTICE
# gained a second job here as both the cheap pre-filter and the floor beneath the derived trigger.
for v in CTX_NOTICE_TOKENS CTX_FAT_TURN_TOKENS CTX_AUTHORING_TURN_TOKENS CTX_1M_COMPACT_THRESHOLD_TOKENS; do
    [ -n "${!v:-}" ] || exit 0
done

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')

[ -n "$session_id" ] || exit 0
[ -n "$transcript" ] || exit 0

# Hooks receive a native Windows path here; jq and test(1) accept it, but normalising keeps the
# path in one form for the readability test and any diagnostics.
if command -v cygpath >/dev/null 2>&1; then
    transcript=$(cygpath -u "$transcript" 2>/dev/null || printf '%s' "$transcript")
fi
[ -r "$transcript" ] || exit 0

latch_dir="$HOME/.claude/state/handoff-trigger"
latch="$latch_dir/$session_id"

if [ -e "$latch" ]; then
    # ── The written_at_tokens sidecar, for the compact read leg's coverage check ────────────
    #
    # This session already asked (or declined) once; there is nothing left to arm. But the
    # `compact`-sourced read leg (`handoff-inject.sh`) needs to know how big this session was
    # AT THE MOMENT the handoff actually got written, so it can measure how much grew between
    # that write and an eventual auto-compaction. That figure does not exist until the model
    # complies, which can take more than the one turn `stop_hook_active` covers -- so this
    # checks on EVERY Stop after the latch is set, not only the stop-hook-induced one, and it
    # stops checking for good once the sidecar exists. Modelled on the existing `/clear` marker
    # (`session-end-marker.sh`, `$HOME/.claude/state/last-clear/`): the same kind of external
    # hook-to-hook plumbing, and for the same reason -- a value this specific does not belong in
    # the handoff document's own envelope ([D16](../docs/design.md#d16)).
    sidecar="$latch_dir/$session_id.written"
    if [ ! -e "$sidecar" ]; then
        cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
        [ -n "$cwd" ] || cwd=$PWD
        if command -v cygpath >/dev/null 2>&1; then
            cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
        fi
        if [ -d "$cwd" ]; then
            main=$(git -C "$cwd" worktree list 2>/dev/null | head -1 | awk '{print $1}')
            ref=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
            [ "$ref" = HEAD ] && ref=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
            if [ -n "$main" ] && [ -n "$ref" ] && [ -r "$hook_dir/../lib/handoff-store.sh" ]; then
                slug=$(printf '%s' "$ref" | tr '/' '-')
                # shellcheck source=../lib/handoff-store.sh
                . "$hook_dir/../lib/handoff-store.sh"
                handoff_store_resolve "$main" "$slug"
                # Only an EXACT match is this session's own handoff. A "recent" pick can be an
                # unrelated branch's document, and misreading its mtime as THIS session's write
                # would poison the sidecar with a figure that describes someone else's work.
                #
                # `-ge`, not `-gt`: both timestamps are second-granularity (`stat -c %Y`, same as
                # every other mtime comparison in this bundle), and a fast write can land in the
                # same second the latch did. Treating a tie as "written" is the safe direction --
                # the alternative is silently never recording a sidecar for a handoff that (by
                # every other signal) is clearly this session's own.
                latch_mtime=$(stat -c %Y "$latch" 2>/dev/null); latch_mtime=${latch_mtime:-0}
                if [ "$HANDOFF_PICK" = exact ] && [ -n "$HANDOFF_FILE" ] && [ -n "$HANDOFF_MTIME" ] \
                   && [ "$HANDOFF_MTIME" -ge "$latch_mtime" ]; then
                    written_resident=$(jq -r 'select(.message.usage != null)
                                      | .message.usage
                                      | (.input_tokens // 0)
                                        + (.cache_creation_input_tokens // 0)
                                        + (.cache_read_input_tokens // 0)' "$transcript" 2>/dev/null | tail -1)
                    case "${written_resident:-}" in
                        ''|*[!0-9]*) ;;
                        *)
                            # `expected_gap_tokens` is what makes the read leg's verdict
                            # meaningful for an automatically written handoff (D18). The trigger
                            # deliberately fires 2*fat_turn below the ceiling, so a gap of about
                            # that size at compaction is NOMINAL, not staleness -- judged against
                            # CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS (10,350) it would be flagged every
                            # single time. Recorded here rather than recomputed there because only
                            # the writing side knows which trigger wrote this handoff; a sidecar
                            # lacking the field is pre-D18 and the reader falls back to the
                            # constant.
                            jq -n --argjson w "$written_resident" --argjson t "$(date +%s)" \
                                --argjson g "$(( 2 * CTX_FAT_TURN_TOKENS ))" \
                                --arg h "$HANDOFF_FILE" \
                                '{written_at_tokens: $w, written_at_epoch: $t, handoff_path: $h, expected_gap_tokens: $g}' \
                                > "$sidecar" 2>/dev/null
                            ;;
                    esac
                fi
            fi
        fi
    fi
    exit 0
fi

# The harness's own re-entry flag. It covers exactly one case -- we are already inside the
# continuation this hook caused -- and it is NOT a session latch: a background task waking the
# session later arrives with it false and the threshold still crossed. The on-disk latch above
# is what makes this fire once. Both are needed; neither substitutes for the other. Checked only
# here, AFTER the latch branch above, so a stop-hook-induced continuation still gets its sidecar
# chance rather than being turned away before ever reaching it.
[ "$stop_active" = "true" ] && exit 0

# ── T: resident context in tokens ──────────────────────────────────────────────────────────
# The last `usage` record in the transcript. Streamed with a per-line filter rather than slurped:
# these files reach tens of MB and this runs at every turn boundary.
#
# TRAP: never grep the transcript for a field name. It also matches the session TALKING about
# that field -- measured, 22 apparent `context_window` hits in a session whose only source was
# this repo's own statusline being read into context. Match parsed structure, as here.
resident=$(jq -r 'select(.message.usage != null)
                  | .message.usage
                  | (.input_tokens // 0)
                    + (.cache_creation_input_tokens // 0)
                    + (.cache_read_input_tokens // 0)' "$transcript" 2>/dev/null | tail -1)

case "${resident:-}" in ''|*[!0-9]*) exit 0 ;; esac

# ── The cheap pre-filter, BEFORE the ceiling is resolved ───────────────────────────────────
# The real trigger is derived from the ceiling and cannot be evaluated yet, but it can never sit
# below CTX_NOTICE_TOKENS -- the floor below enforces exactly that -- so this is a sound necessary
# condition and it costs one integer comparison.
#
# It is here for two reasons beyond speed. Resolving the ceiling can mean a second `jq` pass over a
# transcript that reaches tens of MB, at every turn boundary of every session; and the "ceiling
# unknown" decline below would otherwise be emitted at the FIRST Stop of a five-thousand-token
# session, which is a nag about a threshold nothing was approaching. Shallow sessions must be left
# alone by every path through this hook, not merely by the arming one.
[ "$resident" -ge "$CTX_NOTICE_TOKENS" ] || exit 0

# ── The ceiling: declared, else detected, else decline ─────────────────────────────────────
ceiling=""
ceiling_basis=""
if [ -n "${CTX_COMPACT_THRESHOLD_TOKENS:-}" ]; then
    # A human who measured beats a heuristic that inferred, so this wins over detection.
    ceiling="$CTX_COMPACT_THRESHOLD_TOKENS"
    ceiling_basis="declared"
else
    # Detect the 1M beta from the `[1m]` suffix on modelUsage KEYS. Preferred over
    # `message.model`, which drops the suffix -- measured: one session shows
    # `"model":"claude-opus-5"` on assistant lines and `claude-opus-5[1m]` in modelUsage. The
    # suffix is what REQUESTS the beta, so its presence is evidence the beta was GRANTED for
    # those requests: an observation rather than a model-to-window table that rots.
    #
    # The test runs inside jq, on parsed keys, for the same reason as above -- a grep for `[1m]`
    # over the raw transcript also matches an ANSI escape or the session discussing this file.
    #
    # MEASURED 2026-08-26, AND THIS SIGNAL IS THINNER THAN THE DESIGN ASSUMED: modelUsage appears
    # only on `cost-state` lines, which are a 2.1.246 addition and sporadic even there -- present
    # in 1 of 4 transcripts on that version and 0 of 26 on 2.1.235/2.1.228. So the decline below
    # is the COMMON path, not the exceptional one, and a machine that wants this hook armed
    # should declare CTX_COMPACT_THRESHOLD_TOKENS rather than wait for detection to succeed.
    detected=$(jq -r 'select(.type == "cost-state" and .modelUsage != null)
                      | if (.modelUsage | keys | any(test("\\[1m\\]"))) then "1m" else "no" end' \
                  "$transcript" 2>/dev/null | tail -1)
    if [ "${detected:-}" = "1m" ]; then
        ceiling="$CTX_1M_COMPACT_THRESHOLD_TOKENS"
        ceiling_basis="detected the 1M beta from a [1m] suffix in modelUsage"
    fi
fi

mkdir -p "$latch_dir" 2>/dev/null

if [ -z "$ceiling" ]; then
    # Decline, naming the signal that was missing -- an unexplained silence is indistinguishable
    # from a broken hook. Latched like the fire itself, so this is said once per session rather
    # than at every subsequent turn boundary.
    : > "$latch" 2>/dev/null
    jq -n --arg m "handoff trigger declined to arm at $((resident / 1000))k: the compaction ceiling is unknown — no CTX_COMPACT_THRESHOLD_TOKENS declared, and no [1m] suffix found in the transcript's modelUsage keys. Not arming is the safe failure; run /handoff by hand when convenient." \
        '{systemMessage: $m}'
    exit 0
fi

# ── The derived trigger, its floor, and the gate ───────────────────────────────────────────
# All three come from context-thresholds.sh's arming block; see there for why the trigger carries
# two fat turns and the gate one. In short: the gate is the real constraint (the authoring turn
# must finish before compaction), the trigger sits exactly one fat turn below it so that firing
# cannot fail its own check on arrival, and the fat turn between them is the band a single turn
# would have to exceed to leap past unobserved.
trigger=$((ceiling - 2 * CTX_FAT_TURN_TOKENS - CTX_AUTHORING_TURN_TOKENS))
need=$((resident + CTX_FAT_TURN_TOKENS + CTX_AUTHORING_TURN_TOKENS))

if [ "$trigger" -lt "$CTX_NOTICE_TOKENS" ]; then
    # THE WINDOW IS TOO SMALL FOR PREDICTION AT ALL, and this is the honest thing to say. The
    # margin is fixed while the ceiling is not, so under a ceiling of ~305k the trigger lands
    # below the depth at which a handoff has anything to record. Firing anyway would write one
    # from a near-empty context; staying silent (the pre-D18 behaviour on these windows) leaves a
    # human wondering why the automation never ran. So: say it once, name the arithmetic, and
    # point at the path that does work here.
    : > "$latch" 2>/dev/null
    jq -n --arg m "handoff trigger declined to arm: compaction fires at ~$((ceiling / 1000))k ($ceiling_basis), and writing a handoff safely needs ~$(( (2 * CTX_FAT_TURN_TOKENS + CTX_AUTHORING_TURN_TOKENS) / 1000 ))k of that, which would put the trigger at $((trigger / 1000))k — below the $((CTX_NOTICE_TOKENS / 1000))k depth where a handoff has anything to record. This window cannot be served automatically; run /handoff by hand at a point of your choosing." \
        '{systemMessage: $m}'
    exit 0
fi

# Not due yet. Deliberately NOT latched: this is the common outcome for most of a session's life,
# and the next turn re-evaluates it. The ceiling resolution above is free on the declared path
# (a variable read), so re-reaching this line costs nothing on the default configuration.
[ "$resident" -ge "$trigger" ] || exit 0

if [ "$need" -ge "$ceiling" ]; then
    # Past the band. Since the trigger sits one fat turn below the gate, arriving here means a
    # single turn leapt the whole band between two Stop events -- expected for roughly the 5% of
    # turns above p95 (see CTX_FAT_TURN_TOKENS). One loud message and a manual /handoff is the
    # designed cost of that, and it is strictly cheaper than a handoff authored from a summary.
    : > "$latch" 2>/dev/null
    jq -n --arg m "handoff trigger declined to arm at $((resident / 1000))k: writing a handoff needs ~$((need / 1000))k of headroom but compaction fires at ~$((ceiling / 1000))k ($ceiling_basis). A single turn appears to have jumped past the $((trigger / 1000))k trigger point. Arming here would lose the race and produce a handoff authored from a compaction summary, which is worse than none." \
        '{systemMessage: $m}'
    exit 0
fi

# ── Fire ───────────────────────────────────────────────────────────────────────────────────
: > "$latch" 2>/dev/null

# Background work outlives a /clear and its completion notification lands in the FRESH session,
# which otherwise has no idea what it was for. The handoff format has sections for exactly this,
# by disposition -- so name the in-flight work in the instruction rather than leaving the model
# to remember it. Both fields, not one: `session_crons` is the same signal by another mechanism.
#
# The `tr -d` is not decoration: jq writes its stdout in TEXT MODE on Windows, so a multi-line
# string pulled back into a shell variable returns with CRLF endings (measured while building the
# PostCompact capture, where the same round trip was silently rewriting the artifact). The stakes
# here are far lower -- a stray CR inside an instruction renders harmlessly -- but the failure is
# invisible either way, and a guard costs one pipe.
pending=$(printf '%s' "$input" | jq -r '
    [ (.background_tasks // [])[] | (.description // .type // "task") ]
    + [ (.session_crons // [])[]  | ("scheduled: " + (.prompt // "wake")) ]
    | if length == 0 then ""
      else "\n\nIn flight, and it will outlive the reset: " + join("; ")
           + ". Record each one in the handoff by disposition — blocks a Next step, feeds one without blocking, or feeds nothing."
      end' 2>/dev/null | tr -d '\r')

jq -n --arg r "Context has reached $((resident / 1000))k, at or past the $((trigger / 1000))k point where this session must hand off to beat auto-compaction (~$((ceiling / 1000))k, $ceiling_basis) — and there is still room to do it.

This is the last safe turn boundary, not an early advisory: the margin below the ceiling is reserved for one wide turn plus the authoring turn itself, so deferring risks the write landing after compaction instead of before it.

Run the /handoff skill now, before anything else. Write it from what is already in context — do not read, grep or list anything in order to author it; anything you would have to re-open is by definition re-derivable and belongs in ## Pointers as a citation instead.${pending}

This fires once per session. If a handoff already covers the current state of this work, say so and stop rather than writing a second one." \
    '{decision: "block", reason: $r}'
