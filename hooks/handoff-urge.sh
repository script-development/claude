#!/bin/bash
#
# Stop hook: the WRITE leg of the automated handoff cycle (build-order item 4).
#
# At the first turn boundary where resident context has reached CTX_URGE_TOKENS, this returns
# control to the model with an instruction to run /handoff. `decision: "block"` on a Stop hook
# is not a veto -- `reason` becomes the model's next instruction -- so this is what turns the
# statusline's passive `handoff?` advisory into something that happens without the human having
# to notice the number and act on it.
#
# It fires AT MOST ONCE PER SESSION, and it DECLINES ENTIRELY unless it can establish that the
# session has room to write the handoff before auto-compaction takes it. The decline is the
# important half; see "WHY THE HEADROOM CHECK IS HERE" below.
#
# Thresholds are SOURCED from this bundle's lib/context-economy/context-thresholds.sh, never
# restated. If that file is missing this hook does nothing at all -- degrade capability, never
# execution, the same rule the gauge follows when its thresholds are absent.
#
# ── WHY THE HEADROOM CHECK IS HERE, AND WHY IT DECLINES RATHER THAN WARNS ──────────────────
#
# CTX_URGE_TOKENS is absolute (200k) while auto-compaction fires at a fixed offset below the
# *window*, which is dynamic. On the 1M default that leaves ~787k of slack and a fat turn is
# noise. On a 200k-window session compaction fires around 187k -- BELOW the threshold -- so this
# hook can never fire there and is simply dead code. In between lies the case that matters: an
# armed trigger with negative slack loses the race to compaction every time, and the handoff it
# then produces is authored from a compaction summary. That is the `compacted: yes` degradation
# the handoff format exists to RECORD, manufactured on purpose. An unarmed trigger is merely the
# status quo, so declining is strictly the cheaper failure.
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
# this hook can occupy: in-repo (plugins/context-economy/hooks -> ../lib), installed
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
for v in CTX_URGE_TOKENS CTX_FAT_TURN_TOKENS CTX_AUTHORING_TURN_TOKENS CTX_1M_COMPACT_THRESHOLD_TOKENS; do
    [ -n "${!v:-}" ] || exit 0
done

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
stop_active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false')

# The harness's own re-entry flag. It covers exactly one case -- we are already inside the
# continuation this hook caused -- and it is NOT a session latch: a background task waking the
# session later arrives with it false and the threshold still crossed. The on-disk latch below
# is what makes this fire once. Both are needed; neither substitutes for the other.
[ "$stop_active" = "true" ] && exit 0

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
[ -e "$latch" ] && exit 0

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
[ "$resident" -ge "$CTX_URGE_TOKENS" ] || exit 0

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

need=$((resident + CTX_FAT_TURN_TOKENS + CTX_AUTHORING_TURN_TOKENS))

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

if [ "$need" -ge "$ceiling" ]; then
    : > "$latch" 2>/dev/null
    jq -n --arg m "handoff trigger declined to arm at $((resident / 1000))k: writing a handoff needs ~$((need / 1000))k of headroom but compaction fires at ~$((ceiling / 1000))k ($ceiling_basis). Arming here would lose the race and produce a handoff authored from a compaction summary, which is worse than none." \
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

jq -n --arg r "Context has reached $((resident / 1000))k, at or past the $((CTX_URGE_TOKENS / 1000))k reset threshold, and there is room to hand off before auto-compaction (~$((ceiling / 1000))k, $ceiling_basis).

Run the /handoff skill now, before anything else. Write it from what is already in context — do not read, grep or list anything in order to author it; anything you would have to re-open is by definition re-derivable and belongs in ## Pointers as a citation instead.${pending}

This fires once per session. If a handoff already covers the current state of this work, say so and stop rather than writing a second one." \
    '{decision: "block", reason: $r}'
