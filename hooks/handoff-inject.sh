#!/bin/bash
#
# SessionStart hook: the READ leg of the automated handoff cycle, plus the surface for the
# /clear marker (build-order item 4, pieces 2 and 4).
#
# Pairs with handoff-urge.sh (the write leg) and session-end-marker.sh (which records a /clear).
# This one hands the document back, already verified, to the session that comes after the reset --
# and says what the previous session was doing if it was cleared without handing off.
#
# ── WHY THE GATE RUNS HERE, RATHER THAN INJECTING THE FILE ALONE ───────────────────────────
#
# Injecting the document by itself would be strictly WORSE than the model opening it, not better.
# A file the model chose to read is a file it knows it has not checked; the same text arriving as
# system-supplied context reads as authoritative. Citations rot -- lines move, files are renamed,
# a pointer written from memory was never right in the first place -- so injecting unverified
# claims into turn one of a fresh session launders stale text into apparent fact. The verdicts
# are what make the injection safe, and they must travel WITH the document, never separately.
#
# If the gate cannot be found the document is still injected, under an explicit UNVERIFIED
# banner. Degrade capability, never execution -- but say which happened, because "verified clean"
# and "never checked" must never look alike.
#
# ── WHY THE /CLEAR MARKER IS SURFACED HERE AND NOT BY ITS OWN HOOK ─────────────────────────
#
# Because the only question worth answering needs both halves at once: DOES THE HANDOFF ON DISK
# DESCRIBE THE SESSION THAT WAS JUST THROWN AWAY, OR AN OLDER ONE? A stale handoff injected with
# no such note is worse than no handoff at all -- it reads as coverage. Two separate hooks would
# emit two blobs and leave the reader to join them, at the one moment in a session when spending
# attention on a join is most expensive.
#
# ── SCOPE: `clear` ONLY, DELIBERATELY ──────────────────────────────────────────────────────
#
# SessionStart fires with source in startup / resume / clear / compact / fork. Only `clear`
# is handled here, and the others are not oversights:
#
#   resume, fork  -- context SURVIVES. The transcript is appended to, so the session already
#                    holds everything the handoff would tell it. Injecting would be pure cost.
#   startup       -- a fresh session in a repo that happens to have an old handoff on this
#                    branch. Nothing says the human means to resume it, and firing here would
#                    tax every session in the repo forever.
#   compact       -- context was REPLACED by a summary, so this genuinely wants the handoff.
#                    It is left to a later build step: wiring it needs the compaction corpus
#                    (compaction-capture.sh) to say whether the summary already covers it.
#
# The list is one `case` below so adding `compact` later is one word, not a restructure.
#
# ── WHAT THIS DOES NOT DO ──────────────────────────────────────────────────────────────────
#
# `additionalContext` does not start a turn (F6): the injected text sits in the fresh session and
# is consumed on the next prompt. Interactively that is the human's next message, however short.
# So this is zero-TYPING, not zero-touch, and it must not be described as the latter.

set -uo pipefail

# How close to a `/clear` a handoff must be written to be treated as covering the session that
# clear discarded. Used twice -- to corroborate a guessed pick, and to word the coverage sentence
# -- and it is the same judgement both times, so it is one constant.
COVERAGE_WINDOW_SECONDS=600

input=$(cat)

source_kind=$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null | tr -d '\r')
case "$source_kind" in
    clear) ;;
    *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
[ -n "$cwd" ] || cwd=$PWD
if command -v cygpath >/dev/null 2>&1; then
    cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
fi
[ -d "$cwd" ] || exit 0

# ── Locate this session, for the marker key ────────────────────────────────────────────────
#
# `main` and `slug` describe the SESSION, not the work. They still key the /clear marker (a
# clear happened to this session, in this repository) and they are the exact-match hint the
# store resolver prefers -- but they no longer decide where the handoff is.
main=$(git -C "$cwd" worktree list 2>/dev/null | head -1 | awk '{print $1}')
here=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -n "$main" ] || exit 0
[ -n "$here" ] || exit 0

ref=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$ref" = HEAD ] && ref=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
[ -n "$ref" ] || exit 0

# Branch names contain `/`; the filename slugs it (fix/foo -> fix-foo).
slug=$(printf '%s' "$ref" | tr '/' '-')

# ── Resolve the handoff, by ENUMERATING the store ──────────────────────────────────────────
#
# THE FILE AND ITS CITATIONS LIVE IN DIFFERENT TREES, and conflating them is the failure that
# makes every verdict come back MISSING. This hook has only `cwd`, so it cannot DERIVE the path
# of a handoff whose work happened in a sibling checkout -- which is the normal case when a
# mission_control session drives one with `git -C` and never moves. The store is centralised
# precisely so this can list candidates instead of computing one; see lib/handoff-store.sh.
#
# Sourced relative to this hook, which works installed (~/.claude/hooks -> ~/.claude/lib) and
# in-repo (dotfiles/hooks -> dotfiles/lib) without either path being written down here.
#
# If the lib is absent the hook falls back to the pre-store location. Degrade capability, never
# execution: a half-finished install must not silence the read leg entirely.
hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
handoff=""
handoff_checkout=""
handoff_branch=""
handoff_others=""
handoff_pick=""
if [ -r "$hook_dir/../lib/handoff-store.sh" ]; then
    # shellcheck source=../lib/handoff-store.sh
    . "$hook_dir/../lib/handoff-store.sh"
    handoff_store_resolve "$main" "$slug"
    handoff=$HANDOFF_FILE
    handoff_checkout=$HANDOFF_CHECKOUT
    handoff_branch=$HANDOFF_BRANCH
    handoff_others=$HANDOFF_OTHERS
    handoff_pick=$HANDOFF_PICK
else
    handoff="$main/.claude/handoff/$slug.md"
fi

handoff_present=false
if [ -n "$handoff" ] && [ -r "$handoff" ] && [ -s "$handoff" ]; then
    handoff_present=true
fi

# The tree the citations resolve against. The document's own `checkout:` header is the
# authority; `here` is the fallback, and is right only when the session happens to be standing
# in the work's own repository. Never the other way round: preferring `here` would aim the gate
# at mission_control for every handoff about a sibling checkout and report a page of MISSING.
gate_checkout=${handoff_checkout:-$here}

# ── The /clear marker ──────────────────────────────────────────────────────────────────────
#
# CONSUMED, not merely read. The marker is news about one specific reset; reporting it again at
# the next clear would be noise, and worse, would attribute an old loss to a new event.
state_dir="${LAST_CLEAR_STATE_DIR:-$HOME/.claude/state/last-clear}"
key=$(printf '%s' "$main" | md5sum 2>/dev/null | cut -c1-32)
marker=""
[ -n "$key" ] && marker="$state_dir/$key-$slug.json"

marker_present=false
if [ -n "$marker" ] && [ -r "$marker" ] && [ -s "$marker" ] \
   && jq -e . "$marker" >/dev/null 2>&1; then
    marker_present=true
    m_resident=$(jq -r '.resident_tokens // empty' "$marker" 2>/dev/null | tr -d '\r')
    m_transcript=$(jq -r '.transcript_path // empty' "$marker" 2>/dev/null | tr -d '\r')
    m_ended=$(jq -r '.ended_at // empty' "$marker" 2>/dev/null | tr -d '\r')
    m_ended_epoch=$(jq -r '.ended_at_epoch // empty' "$marker" 2>/dev/null | tr -d '\r')
    m_handoff_mtime=$(jq -r '.handoff.mtime // empty' "$marker" 2>/dev/null | tr -d '\r')
    m_urge=$(jq -r '.urge_fired // false' "$marker" 2>/dev/null | tr -d '\r')
fi

# ── A GUESSED PICK NEEDS EVIDENCE ──────────────────────────────────────────────────────────
#
# Enumeration is what lets this hook find a handoff for a sibling checkout. Unchecked, it also
# means every `/clear` anywhere surfaces the newest handoff on the machine -- clear a session in
# an unrelated repo and you get last week's work in another one, injected as authoritative
# context. That is strictly worse than the derivation it replaced, which at least said nothing.
#
# So an `exact` pick stands on its own, and a `recent` pick must be corroborated: the /clear
# marker has to exist, and the handoff has to have been written close to that clear. That is the
# only available evidence that THIS session lineage wrote it and then discarded its context --
# which is the entire situation the cross-repo case is about. Absent that, the guess is demoted
# to nothing rather than softened with a warning; a hedged injection still costs the tokens and
# still frames unrelated work as the thing to resume.
#
# The window is the same constant the coverage sentence uses below, deliberately: "recent enough
# to be worth surfacing" and "recent enough to have covered that session" are one judgement, and
# two numbers would drift into a state where a handoff is injected and then described as
# predating the clear it was chosen for.
if [ "$handoff_present" = true ] && [ "$handoff_pick" != exact ]; then
    corroborated=false
    if [ "$marker_present" = true ] && [ -n "${m_ended_epoch:-}" ] && [ -n "${m_handoff_mtime:-}" ]; then
        pick_gap=$(( m_ended_epoch - m_handoff_mtime ))
        [ "$pick_gap" -lt 0 ] && pick_gap=0
        [ "$pick_gap" -le "$COVERAGE_WINDOW_SECONDS" ] && corroborated=true
    fi
    if [ "$corroborated" = false ]; then
        handoff_present=false
        handoff=""
    fi
fi

# Neither half means nothing to say. This is the ordinary case on a branch nobody has handed off
# and nobody has cleared mid-work, and it must stay silent.
if [ "$handoff_present" = false ] && [ "$marker_present" = false ]; then
    exit 0
fi

# ── The gate ───────────────────────────────────────────────────────────────────────────────
#
# Probed beside this hook first -- one path that holds in-repo, installed and as a plugin --
# then the in-repo path for a session already inside mission_control. It used to lead with
# $HOME/.claude/lib, which a plugin install never creates. Never through a sibling path like
# `<project>/../mission_control/tools/`, which is layout config of exactly the kind this repo
# refuses to make configurable.
verdicts=""
status_line=""
if [ "$handoff_present" = true ]; then
    gate="${VERIFY_HANDOFF_GATE:-}"
    if [ -z "$gate" ]; then
        for g in "$hook_dir/../lib/verify-handoff.sh" "$here/plugins/context-economy/lib/verify-handoff.sh"; do
            [ -x "$g" ] && gate=$g && break
        done
    fi

    if [ -n "$gate" ] && [ -x "$gate" ]; then
        # Both arguments, always -- even though the gate would now read `checkout:` itself. The
        # hook has already resolved which tree it believes the verdicts describe, and passing
        # that explicitly means the two cannot silently disagree about it.
        verdicts=$(bash "$gate" "$handoff" "$gate_checkout" 2>&1)
        case "$?" in
            0) status_line="GATE: OK — every citation resolved against this checkout." ;;
            1) status_line="GATE: FAILED (exit 1) — at least one citation is MISSING or CHANGED, or a claim cites a path:line absent from ## Pointers." ;;
            2) status_line="GATE: MALFORMED (exit 2) — the document violates the format contract, so its citations were NOT checked at all. Treat every pointer below as unverified." ;;
            *) status_line="GATE: unexpected exit status; treat every pointer below as unverified." ;;
        esac

        # The gate's WARN lines are AUTHORING-side advice -- "this Pointer is unreferenced", "this
        # mention is path-shaped but unchecked". They exist to help whoever WRITES a handoff tighten
        # it, and there is nothing the reader of one can do about them. Injecting them spends real
        # tokens at the most expensive moment in a session to report a problem that is not the
        # reader's. Measured on this repo's own handoff: nine WARN lines against twelve verdicts.
        #
        # So they are dropped -- but COUNTED AND ANNOUNCED. Silently discarding part of a verdict
        # block is precisely the quiet edit that makes a gate untrustworthy, and a reader who cannot
        # tell a filtered block from a complete one has to assume the worst of both.
        warn_count=$(printf '%s\n' "$verdicts" | grep -c '^WARN' || true)
        verdicts=$(printf '%s\n' "$verdicts" | grep -v '^WARN' || true)
        if [ "${warn_count:-0}" -gt 0 ]; then
            verdicts="$verdicts

($warn_count authoring-side WARN line(s) omitted: they address the handoff's author, not its reader.)"
        fi
    else
        status_line="GATE: NOT RUN — verify-handoff.sh was not found. Every pointer below is UNVERIFIED; none of them has been checked against the tree."
    fi

    # Age is stated rather than acted on. A cutoff would have to guess whether a three-week-old
    # handoff on a long-lived branch is stale work or simply slow work, and guessing wrong in the
    # silent direction loses the document entirely. The reader can judge; give them the number.
    #
    # An unreadable mtime prints "unknown", never a number. Falling back to 0 would have rendered as
    # a confident "20000 day(s) ago" -- a fabricated fact, and this is a document whose entire job is
    # telling a reader what to trust. An admitted gap is always cheaper than an invented figure.
    mtime=$(stat -c %Y "$handoff" 2>/dev/null)
    case "${mtime:-}" in
        ''|*[!0-9]*) age_phrase="at an unknown time (mtime unreadable)" ;;
        *) age_phrase="$(( ( $(date +%s) - mtime ) / 86400 )) day(s) ago" ;;
    esac
fi

# Renders a second count as the coarsest unit that still says something useful. Deliberately
# imprecise: the reader needs "minutes vs days", not arithmetic.
human_gap() {
    local s=$1
    if [ "$s" -lt 90 ]; then printf '%s second(s)' "$s"
    elif [ "$s" -lt 5400 ]; then printf '%s minute(s)' "$(( s / 60 ))"
    elif [ "$s" -lt 172800 ]; then printf '%s hour(s)' "$(( s / 3600 ))"
    else printf '%s day(s)' "$(( s / 86400 ))"
    fi
}

# ── Compose ────────────────────────────────────────────────────────────────────────────────
#
# The two rules below are a DELIBERATE, MINIMAL restatement of the skill's read-mode Step 3.
# They are here because this hook fires when the skill has NOT been invoked -- the model has no
# other copy -- and because they are the two that change what the reader does. Everything else
# is left to the skill so this does not quietly become a second copy of it.
compose() {
    printf '# Context reset (SessionStart, source: clear)\n\n'

    if [ "$marker_present" = true ]; then
        printf -- '## The session you just cleared\n\n'
        printf 'It ended at %s by `/clear`' "${m_ended:-an unrecorded time}"
        if [ -n "${m_resident:-}" ]; then
            printf ', with **%sk of resident context**' "$(( m_resident / 1000 ))"
        fi
        printf '.\n\n'

        if [ "${m_urge:-false}" = "true" ]; then
            printf 'The write trigger HAD already fired for that session, so a handoff was asked for.\n'
        else
            printf 'The write trigger never armed for that session — the `/clear` came first, so nothing\nasked for a handoff.\n'
        fi
        printf '\n'

        # The one judgement worth making, and the reason both halves are read in one hook.
        if [ "$handoff_present" = false ]; then
            printf -- '**No handoff exists for `%s`, so that work is undocumented.**\n' "$ref"
        elif [ -n "${m_ended_epoch:-}" ] && [ -n "${m_handoff_mtime:-}" ]; then
            gap=$(( m_ended_epoch - m_handoff_mtime ))
            [ "$gap" -lt 0 ] && gap=0
            if [ "$gap" -le "$COVERAGE_WINDOW_SECONDS" ]; then
                printf 'The handoff below was written %s before that clear, so it very likely does\ncover that session.\n' "$(human_gap "$gap")"
            else
                printf -- '**The handoff below predates that clear by %s.** It describes earlier work, and\nshould not be read as covering the session just discarded.\n' "$(human_gap "$gap")"
            fi
        else
            printf 'A handoff exists for `%s`, but there is not enough recorded to tell whether it covers\nthe cleared session. Treat its coverage as unknown.\n' "$ref"
        fi
        printf '\n'

        if [ -n "${m_transcript:-}" ]; then
            printf -- '**The cleared session'"'"'s transcript survives** at `%s`.\n' "$m_transcript"
            printf 'That file is the only remaining record of it. Read it ONLY if the work turns out to matter —\n'
            printf 'it is large, and opening it at turn one is the most expensive moment available.\n\n'
        fi
        printf -- '---\n\n'
    fi

    if [ "$handoff_present" = true ]; then
        # WHICH handoff, and WHY THIS ONE. The store holds handoffs for every target on this
        # machine, so naming the branch is no longer enough to identify what arrived: an `exact`
        # pick is about the repository this session is standing in, a `recent` pick is the
        # resolver's guess, and a reader must be able to reject the second without being told to
        # go looking for the first.
        case "$handoff_pick" in
            exact)
                printf 'A handoff for the current branch (`%s`) was found at\n' "$ref"
                printf '`%s`, last written %s, and is reproduced in full below.\n\n' "$handoff" "$age_phrase"
                ;;
            recent)
                printf 'No handoff exists for this session'"'"'s own branch (`%s`). **The most recent one in\n' "$ref"
                printf 'the store was picked instead** — for branch `%s`, describing the tree at\n' "${handoff_branch:-unknown}"
                printf '`%s`. Written %s, it is reproduced in full below.\n\n' "${handoff_checkout:-unknown}" "$age_phrase"
                printf 'That is a GUESS, made on recency alone. Nothing in a fresh session identifies which\n'
                printf 'work is being resumed, so check the branch above is the one you meant before acting on\n'
                printf 'anything below it.\n\n'
                ;;
            *)
                printf 'A handoff was found at `%s`, last written %s,\n' "$handoff" "$age_phrase"
                printf 'and is reproduced in full below.\n\n'
                ;;
        esac
        printf '%s\n\n' "$status_line"

        # The candidates NOT picked, one line each. This is the whole reason the store is
        # enumerated rather than pointed at: when the resolver has to guess, the alternatives it
        # rejected are the cheapest possible correction -- a reader who recognises the right one
        # says so in a sentence instead of hunting for it. Suppressed on an `exact` pick, where
        # there is nothing to correct and the list would be pure noise on every reset.
        if [ "$handoff_pick" = recent ] && [ -n "$handoff_others" ]; then
            printf 'Other handoffs in the store, not picked:\n\n'
            now=$(date +%s)
            while IFS='|' read -r o_path o_branch o_checkout o_mtime; do
                [ -n "$o_path" ] || continue
                o_path=$(printf '%s' "$o_path" | sed -E 's/[[:space:]]+$//')
                o_branch=$(printf '%s' "$o_branch" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
                o_checkout=$(printf '%s' "$o_checkout" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
                o_mtime=$(printf '%s' "$o_mtime" | tr -d '[:space:]')
                case "${o_mtime:-0}" in
                    ''|0|*[!0-9]*) o_age="age unknown" ;;
                    *) o_age="$(human_gap $(( now - o_mtime ))) ago" ;;
                esac
                printf -- '- `%s` in `%s` — %s — `%s`\n' \
                    "$o_branch" "$o_checkout" "$o_age" "$o_path"
            done <<< "$handoff_others"
            printf '\nSay which one you meant and it can be read directly; none of them has been verified.\n\n'
        fi

        printf 'Two rules govern how to use it:\n\n'
        printf -- '- **A citation verdict can only ever demote the cheap half.** MISSING or CHANGED means a\n'
        printf '  *pointer* rotted and must be re-derived, along with any body claim joined to it by the same\n'
        printf '  `path:line` string. It says nothing about Decisions, Dead ends or Traps: those record what\n'
        printf '  was chosen, tried and learned, and a moved line does not un-decide a decision. Do not treat a\n'
        printf '  red verdict as licence to reopen the expensive half.\n'
        printf -- '- **Do not re-derive eagerly.** Resist opening every pointer to get oriented. A pointer costs\n'
        printf '  its size times the remaining life of the session, so resume is the most expensive moment to\n'
        printf '  resolve one and the point of use is the cheapest. Open each when the step you are on needs it.\n\n'
        printf 'Then start the first `## Next` item that is **not** blocked on a task that has yet to report —\n'
        printf 'not simply item 1 — and say which path you took: verified clean, verified with rot in listed\n'
        printf 'pointers, or unverified. Note `compacted:`; on `yes` or `unknown` the Decisions were\n'
        printf 'reconstructed from a summary and may be lossy. Run `/handoff --read` for the full contract.\n\n'

        if [ -n "$verdicts" ]; then
            printf -- '---\n\n## Gate output\n\n```\n%s\n```\n\n' "$verdicts"
        fi

        printf -- '---\n\n## The handoff\n\n'
        cat "$handoff"
    fi
}

# `jq -Rs` slurps the composition and emits it as one correctly-escaped JSON string. That is the
# only part of this that has to be exactly right: the document contains backticks, quotes,
# backslashes and possibly CRLF, and hand-rolling the escaping is how a hook silently emits
# invalid JSON and gets discarded with no error the human ever sees.
compose | jq -Rs --arg e "SessionStart" \
    '{hookSpecificOutput: {hookEventName: $e, additionalContext: .}}'

# Consumed only after a successful emit, so a hook that died composing does not also destroy the
# only record that the clear happened.
[ "$marker_present" = true ] && rm -f "$marker" 2>/dev/null

exit 0
