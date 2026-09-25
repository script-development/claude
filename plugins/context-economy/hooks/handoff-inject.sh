#!/bin/bash
#
# SessionStart hook: the READ leg of the automated handoff cycle, plus the surface for the
# /clear marker (build-order item 4, pieces 2 and 4).
#
# Pairs with handoff-fork-write.sh (the write leg) and session-end-marker.sh (which records a
# /clear).
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
# ── SCOPE: `clear` AND `compact`, DELIBERATELY -- NOT `resume` OR `fork` OR `startup` ──────
#
# SessionStart fires with source in startup / resume / clear / compact / fork. `clear` and
# `compact` are handled here; the others are not oversights:
#
#   resume, fork  -- context SURVIVES. The transcript is appended to, so the session already
#                    holds everything the handoff would tell it. Injecting would be pure cost.
#   startup       -- a fresh session in a repo that happens to have an old handoff on this
#                    branch. Nothing says the human means to resume it, and firing here would
#                    tax every session in the repo forever.
#
# `compact` (Route 1, `docs/design.md`): context was just REPLACED by a summary, in the SAME
# session (`session_id` is preserved across a compaction, unlike `clear`'s fresh one), so this
# genuinely wants the last handoff written this session. It reuses the existing write-trigger
# leg wholesale rather than needing `PreCompact`/`PostCompact` at all -- see the ── COMPACT ──
# section below for how it differs from `clear`'s marker-based coverage check.
#
# The list was one `case` below for exactly this reason: adding `compact` was one word, not a
# restructure.
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

# Every field extraction below is a jq call. Without jq, `.source // empty` fails, `2>/dev/null`
# swallows the error, and source_kind comes back empty -- indistinguishable from "not a clear
# event" to the case below, so this hook would exit 0 exactly as silently on a machine missing jq
# as it does on an ordinary `startup`/`resume`. That is the "guard that skips without saying so"
# failure downstream consumer repos are expected to call out for their own install.sh, reproduced
# here. A plain-text grep for the one field this early check needs is enough to tell those two
# cases apart and say so.
if ! command -v jq >/dev/null 2>&1; then
    case "$(printf '%s' "$input" | tr -d '\r')" in
        *'"source"'*'"clear"'*)
            # `\\n`, not `\n`: printf itself interprets escapes in its own argument regardless of
            # shell quoting, so a bare `\n` here would emit a raw newline byte -- an unescaped
            # control character inside a JSON string, which a strict parser rejects outright.
            printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"# Context reset (SessionStart, source: clear)\\n\\nGATE/INJECT: NOT RUN -- `jq` is not installed, or not on PATH for this hook, so the handoff read leg could not look for a handoff or verify one. Install jq (winget install jqlang.jq / brew install jq), then start a fresh session to restore this.\\n"}}'
            ;;
    esac
    exit 0
fi

source_kind=$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null | tr -d '\r')
case "$source_kind" in
    clear|compact) ;;
    *) exit 0 ;;
esac

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null | tr -d '\r')

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
# of a handoff whose work happened in a sibling checkout -- which is the normal case when an
# orchestrating session drives one with `git -C` and never moves. The store is centralised
# precisely so this can list candidates instead of computing one; see lib/handoff-store.sh.
#
# Sourced relative to this hook, which works installed (~/.claude/hooks -> ~/.claude/lib), in the
# bundle (hooks/ -> lib/) and as a plugin (${CLAUDE_PLUGIN_ROOT}/hooks -> ../lib) without any of
# those paths being written down here.
#
# If the lib is absent the hook falls back to the pre-store location. Degrade capability, never
# execution: a half-finished install must not silence the read leg entirely.
hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# CTX_HANDOFF_ACCEPTABLE_GAP_TOKENS, for the `compact` branch's coverage verdict below. Sourced
# from the one place this bundle's numbers live (lib/context-economy/context-thresholds.sh),
# never restated here. Missing or unreadable degrades to "no verdict, state the gap and let the
# reader judge" rather than silencing the whole branch -- the same capability-not-execution rule
# every other consumer of this file follows.
CTX_THRESHOLDS_FILE="${CTX_THRESHOLDS_FILE:-$hook_dir/../lib/context-economy/context-thresholds.sh}"
if [ -r "$CTX_THRESHOLDS_FILE" ]; then
    # shellcheck source=../lib/context-economy/context-thresholds.sh
    . "$CTX_THRESHOLDS_FILE"
fi

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

# ── D23: is this a real handoff, or the write leg's own in-flight placeholder? ─────────────
#
# `handoff_present=true` above only means "a non-empty file exists at the resolved path" — it
# says nothing about whether that file is a document to inject or the bare `progress: writing`
# skeleton `hooks/handoff-fork-write.sh` writes SYNCHRONOUSLY, before its own detached authoring
# turn has produced anything (`docs/design.md` D23). Checked here, once, before the gate or the
# body-injection logic below ever sees the file: neither should run against a placeholder, and a
# reader is owed a different message than either "here is a handoff" or silence.
#
# `writing_since` carries the raw epoch rather than a phrase — `human_gap()` is not defined yet at
# this point in the script, and compose() (which is) already has everything it needs to render it.
#
# `writing_session`/`writing_transcript` are D28's liveness signal, resolved here (once) rather
# than at each use below: `write_session:` is only ever present on a `writing` placeholder (the
# real, finished document never carries it — see `lib/handoff-store.sh`'s own comment on why), so
# this is the one place in the script that already knows it is looking at one.
handoff_progress=""
writing_active=false
writing_abandoned=false
writing_since=""
writing_session=""
writing_transcript=""
writing_slow=false
if [ "$handoff_present" = true ] && [ -r "$hook_dir/../lib/handoff-store.sh" ]; then
    handoff_progress=$(handoff_store_field "$handoff" progress)
    if [ "$handoff_progress" = writing ]; then
        handoff_present=false   # never gate or inject a placeholder's own (deliberately empty) body
        writing_since=$(handoff_store_mtime "$handoff" 2>/dev/null)
        writing_session=$(handoff_store_field "$handoff" write_session)
        [ -n "$writing_session" ] && writing_transcript=$(handoff_store_find_transcript "$writing_session")
        case "${writing_since:-}" in
            ''|*[!0-9]*)
                # An unreadable mtime cannot support an age judgement either way — same "an
                # admitted gap beats an invented figure" rule age_phrase follows further down.
                writing_active=true
                writing_since=""
                ;;
            *)
                if [ $(( $(date +%s) - writing_since )) -le "${CTX_FORK_TIMEOUT_SECONDS:-600}" ]; then
                    writing_active=true
                else
                    # Past the nominal budget on the SKELETON's own mtime — which never moves again
                    # after it is written, so on its own this cannot distinguish "still working,
                    # just slower than the budget assumed" from "died". The transcript's own mtime
                    # can, when a session id was pinned to find it (D28): still advancing inside
                    # CTX_FORK_LIVENESS_WINDOW_SECONDS is real, independent evidence of life: the
                    # write leg's own `--allowedTools` restricts it to Bash and Write, so nothing
                    # else on the machine touches this exact file.
                    transcript_mtime=""
                    [ -n "$writing_transcript" ] && transcript_mtime=$(handoff_store_mtime "$writing_transcript" 2>/dev/null)
                    case "${transcript_mtime:-}" in
                        ''|*[!0-9]*) writing_abandoned=true ;;
                        *)
                            if [ $(( $(date +%s) - transcript_mtime )) -le "${CTX_FORK_LIVENESS_WINDOW_SECONDS:-90}" ]; then
                                writing_active=true
                                writing_slow=true
                            else
                                writing_abandoned=true
                            fi
                            ;;
                    esac
                fi
                ;;
        esac
    fi
fi

# The tree the citations resolve against. The document's own `checkout:` header is the
# authority; `here` is the fallback, and is right only when the session happens to be standing
# in the work's own repository. Never the other way round: preferring `here` would aim the gate
# at the orchestrating checkout for every handoff about a sibling one and report a page of MISSING.
gate_checkout=${handoff_checkout:-$here}

marker_present=false
write_attempted=false
if [ "$source_kind" = clear ]; then
    # ── The /clear marker ────────────────────────────────────────────────────────────────
    #
    # CONSUMED, not merely read. The marker is news about one specific reset; reporting it
    # again at the next clear would be noise, and worse, would attribute an old loss to a new
    # event.
    state_dir="${LAST_CLEAR_STATE_DIR:-$HOME/.claude/state/last-clear}"
    # 2>/dev/null on the whole substitution, not just inside the function: handoff_store_md5 is
    # only defined when the lib above was readable, and an undefined-function error would
    # otherwise leak to this hook's own stderr in the degraded install case.
    key=$(printf '%s' "$main" | handoff_store_md5 2>/dev/null)
    marker=""
    [ -n "$key" ] && marker="$state_dir/$key-$slug.json"

    if [ -n "$marker" ] && [ -r "$marker" ] && [ -s "$marker" ] \
       && jq -e . "$marker" >/dev/null 2>&1; then
        marker_present=true
        m_resident=$(jq -r '.resident_tokens // empty' "$marker" 2>/dev/null | tr -d '\r')
        m_transcript=$(jq -r '.transcript_path // empty' "$marker" 2>/dev/null | tr -d '\r')
        m_ended=$(jq -r '.ended_at // empty' "$marker" 2>/dev/null | tr -d '\r')
        m_ended_epoch=$(jq -r '.ended_at_epoch // empty' "$marker" 2>/dev/null | tr -d '\r')
        m_handoff_mtime=$(jq -r '.handoff.mtime // empty' "$marker" 2>/dev/null | tr -d '\r')
        # `write_attempted` replaces the retired `trigger_fired`/`urge_fired` pair (2026-09-18):
        # it answers a different question now ("did the current PreCompact write leg ever run
        # for this session") than they did ("did the old in-band Stop/PostToolUse threshold
        # arm"), so it is not a pure rename and the old keys are not read as a fallback here. A
        # marker written by a stale install still carrying an old key simply reads as false --
        # the same quiet framing either key would have produced for a session where nothing
        # automatic happened.
        m_write_attempted=$(jq -r '.write_attempted // false' "$marker" 2>/dev/null | tr -d '\r')
    fi

    # ── A GUESSED PICK NEEDS EVIDENCE ────────────────────────────────────────────────────
    #
    # Enumeration is what lets this hook find a handoff for a sibling checkout. Unchecked, it
    # also means every `/clear` anywhere surfaces the newest handoff on the machine -- clear a
    # session in an unrelated repo and you get last week's work in another one, injected as
    # authoritative context. That is strictly worse than the derivation it replaced, which at
    # least said nothing.
    #
    # So an `exact` pick stands on its own, and a `recent` pick must be corroborated: the
    # /clear marker has to exist, and the handoff has to have been written close to that clear.
    # That is the only available evidence that THIS session lineage wrote it and then
    # discarded its context -- which is the entire situation the cross-repo case is about.
    # Absent that, the guess is demoted to nothing rather than softened with a warning; a
    # hedged injection still costs the tokens and still frames unrelated work as the thing to
    # resume.
    #
    # The window is the same constant the coverage sentence uses below, deliberately: "recent
    # enough to be worth surfacing" and "recent enough to have covered that session" are one
    # judgement, and two numbers would drift into a state where a handoff is injected and then
    # described as predating the clear it was chosen for.
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
elif [ "$source_kind" = compact ]; then
    # ── COMPACT: was an automatic write attempted for this session? ────────────────────────
    #
    # No async gap here, unlike `clear`: `session_id` survives a compaction (the same session
    # continues, it is not a fresh one with a blank transcript), so `hooks/handoff-fork-write.sh`'s
    # own per-session dedup lock -- keyed by THIS session's session_id, written to
    # `$HOME/.claude/state/handoff-fork/` the first time it fires -- is readable directly, with no
    # separate marker-writing hook needed the way `SessionEnd` is for `clear`.
    #
    # (Superseded 2026-09-18: the previous write leg, `handoff-write.sh`, recorded its own latch
    # and a `written_at_tokens`/`expected_gap_tokens` sidecar under `$HOME/.claude/state/
    # handoff-trigger/`, and this branch judged a token-distance gap against them. Removed along
    # with that file -- the current write leg has no in-band trigger to predict, so there is
    # nothing left to reserve a gap for. The handoff's own mtime (`age_phrase`, computed below,
    # generic to every handoff_present case) carries the freshness judgement instead.)
    #
    # And there is no cross-repo "recent pick" story here at all: an EXACT pick is the only one
    # trusted, full stop. Compaction happens mid-session, on the branch the session is already
    # standing in -- if this branch has no handoff of its own, the store's newest handoff for
    # some OTHER branch is not evidence of anything about THIS session, unlike `clear`'s cross-
    # checkout case, which exists because an orchestrating session can legitimately drive work
    # in a sibling tree it never `cd`s into.
    if [ "$handoff_pick" != exact ]; then
        handoff_present=false
        handoff=""
    fi

    [ -n "$session_id" ] && [ -e "${HOME}/.claude/state/handoff-fork/$session_id.lock" ] && write_attempted=true
fi

# Nothing to say. On `clear`, this is the ordinary case: nobody handed off, nobody cleared
# mid-work. On `compact`, it means the write trigger never even asked for a handoff this
# session AND none exists for this branch -- also nothing new to report. An in-flight or
# abandoned write (D23) is always something to report, regardless of source_kind.
if [ "$handoff_present" = false ] && [ "$marker_present" = false ] && [ "$write_attempted" = false ] \
   && [ "$writing_active" = false ] && [ "$writing_abandoned" = false ]; then
    exit 0
fi

# ── The gate ───────────────────────────────────────────────────────────────────────────────
#
# Probed beside this hook first -- one path that holds in-repo, installed and as a plugin -- then
# the in-repo path for a session already standing in the bundle's host monorepo. That second probe
# is the ONLY line in this file tied to a host layout, and it is the line that goes when the bundle
# is extracted to its own repository. It used to lead with $HOME/.claude/lib, which a plugin install
# never creates. Never through a sibling path like `<project>/../<other-repo>/tools/`, which is
# layout config of exactly the kind this bundle refuses to make configurable.
verdicts=""
status_line=""
if [ "$handoff_present" = true ]; then
    gate="${VERIFY_HANDOFF_GATE:-}"
    if [ -z "$gate" ]; then
        for g in "$hook_dir/../lib/verify-handoff.sh" "$here/plugins/context-economy/lib/verify-handoff.sh"; do
            [ -f "$g" ] && gate=$g && break
        done
    fi

    # -f, not -x: the gate always runs through `bash`, so an exec bit lost in git must not
    # make every handoff read as unverified.
    if [ -n "$gate" ] && [ -f "$gate" ]; then
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
    # 2>/dev/null on the whole substitution: handoff_store_mtime is only defined when the lib was
    # readable (handoff_present can be true via the pre-store fallback path too), and an
    # undefined-function error would otherwise leak to this hook's own stderr.
    mtime=$(handoff_store_mtime "$handoff" 2>/dev/null)
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
    printf '# Context reset (SessionStart, source: %s)\n\n' "$source_kind"

    if [ "$source_kind" = compact ]; then
        printf -- '## This session just auto-compacted\n\n'

        if [ "$write_attempted" = false ]; then
            printf 'No automatic write was attempted for this session before this compaction —\n`hooks/handoff-fork-write.sh` either never fired or exited before reaching its own dedup\nlock (no `claude` on PATH, no handoff-store.sh found, or similar). If a handoff exists\nbelow, treat it as predating this compaction rather than covering it.\n\n'
        elif [ "$handoff_present" = true ]; then
            printf 'An automatic write was attempted for this session. The handoff below was written\n%s — weigh that against how much happened since to judge whether it still covers\nthis compaction.\n\n' "$age_phrase"
        elif [ "$writing_active" = true ] || [ "$writing_abandoned" = true ]; then
            printf 'An automatic write was attempted for this session; see below for its status.\n\n'
        else
            printf 'An automatic write was attempted for this session, but no handoff and no in-progress\nwrite are visible for this branch — the attempt may have failed silently. Run\n`/handoff` yourself if you need one.\n\n'
        fi

        if [ "$handoff_present" = false ]; then
            printf -- '**No handoff exists for `%s`.**\n\n' "$ref"
        fi
        printf -- '---\n\n'
    fi

    if [ "$marker_present" = true ]; then
        printf -- '## The session you just cleared\n\n'
        printf 'It ended at %s by `/clear`' "${m_ended:-an unrecorded time}"
        if [ -n "${m_resident:-}" ]; then
            printf ', with **%sk of resident context**' "$(( m_resident / 1000 ))"
        fi
        printf '.\n\n'

        if [ "${m_write_attempted:-false}" = "true" ]; then
            printf 'An automatic write WAS attempted for that session before the `/clear` — compaction\nreached this branch at some point during it.\n'
        else
            printf 'No automatic write was attempted for that session — no compaction reached this branch\nbefore the `/clear`, so nothing asked for a handoff.\n'
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

    # ── D23: an in-flight or abandoned write, instead of a handoff body ────────────────────
    #
    # Neither branch below reads the placeholder's own (deliberately near-empty) content — it is
    # a signal, not a document. `writing_since` is empty when the mtime could not be read, which
    # `human_gap` cannot render, so that case gets a plain "an unknown time" rather than arithmetic
    # on an empty string.
    if [ "$writing_active" = true ] || [ "$writing_abandoned" = true ]; then
        if [ -n "$writing_since" ]; then
            since_phrase="$(human_gap $(( $(date +%s) - writing_since ))) ago"
        else
            since_phrase="an unknown time ago (mtime unreadable)"
        fi
        if [ "$writing_active" = true ]; then
            # How much of CTX_FORK_TIMEOUT_SECONDS is left, not the whole budget again -- the
            # skeleton was written some time before this hook ran, and the poll bound below has
            # to cover only what actually remains of the fork's own kill point, not re-grant the
            # full window on top of time already spent. Floored at 10s rather than left able to
            # reach 0/negative (guaranteed >0 here since writing_active already required elapsed
            # <= CTX_FORK_TIMEOUT_SECONDS above, but a 1-2s window is not a usable poll bound for a
            # model to act on) -- the cost of the floor is waiting a few seconds past the real
            # deadline in the rare case it is hit, never less. `writing_slow` is already PAST that
            # nominal budget (only kept `writing_active` by the transcript's own liveness, D28), so
            # its own poll bound is the shorter liveness window instead -- re-granting the full
            # nominal budget on top of a budget already spent would make a slow-but-alive run wait
            # far longer than a fresh one ever would for the same signal.
            if [ "$writing_slow" = true ]; then
                remaining="${CTX_FORK_LIVENESS_WINDOW_SECONDS:-90}"
            else
                remaining="${CTX_FORK_TIMEOUT_SECONDS:-600}"
                if [ -n "$writing_since" ]; then
                    remaining=$(( ${CTX_FORK_TIMEOUT_SECONDS:-600} - ( $(date +%s) - writing_since ) ))
                    [ "$remaining" -lt 10 ] && remaining=10
                fi
            fi
            printf -- '## A fresh handoff is being authored — wait for it before doing anything else\n\n'
            printf 'A handoff for `%s` in `%s` is being written right now — started %s, not yet\n' \
                "$ref" "$here" "$since_phrase"
            printf 'finished. Continuing with other work before it lands risks re-deriving exactly\n'
            printf 'what it exists to preserve, so wait for it rather than starting anything else.\n\n'
            if [ "$writing_slow" = true ]; then
                printf 'This has already run past its nominal budget (`CTX_FORK_TIMEOUT_SECONDS`), but its\n'
                printf 'transcript is still being written to as of this check — genuine evidence it is\n'
                printf 'still working, not dead, just slower than usual (a large or messy session can\n'
                printf 'take longer to read). Treated as still active on that basis.\n\n'
            fi
            if [ -n "$writing_transcript" ]; then
                printf -- '**Its transcript, if you want to check on it directly** (what it is doing right\n'
                printf 'now — tail the last few lines for its most recent tool call): `%s`\n\n' "$writing_transcript"
            fi
            printf 'Run this now, as your first tool call, with the Bash tool'"'"'s own `timeout`\n'
            printf 'parameter set to at least %s000ms (it must cover the wait below, not just the\n' "$remaining"
            printf 'command'"'"'s own overhead):\n\n'
            cat <<SNIPPET
\`\`\`bash
until grep -qm1 "^progress: complete" "$handoff" 2>/dev/null; do
  m=\$(stat -c %Y "$handoff" 2>/dev/null || stat -f %m "$handoff" 2>/dev/null)
  [ -z "\$m" ] && break
  if [ \$(( \$(date +%s) - m )) -ge $remaining ]; then
SNIPPET
            if [ -n "$writing_transcript" ]; then
                cat <<SNIPPET
    # Nominal budget elapsed on the skeleton's own (frozen) mtime -- but that alone cannot tell
    # "slow" from "dead" (D28). Check the writer's own transcript before giving up: still
    # advancing recently is real evidence it is alive, just slower than usual.
    tm=\$(stat -c %Y "$writing_transcript" 2>/dev/null || stat -f %m "$writing_transcript" 2>/dev/null)
    [ -z "\$tm" ] && break
    [ \$(( \$(date +%s) - tm )) -ge ${CTX_FORK_LIVENESS_WINDOW_SECONDS:-90} ] && break
SNIPPET
            else
                cat <<SNIPPET
    break
SNIPPET
            fi
            cat <<SNIPPET
  fi
  sleep 10
done
grep -m1 "^progress:" "$handoff"
\`\`\`

SNIPPET
            printf 'If that printed `progress: complete`, re-run `/handoff --read` (or read\n'
            printf '`%s` directly) and proceed from the real document. If it still says\n' "$handoff"
            printf '`progress: writing` once the loop exits, the authoring run most likely died\n'
            printf 'before finishing — treat it as abandoned, proceed without a handoff for this\n'
            printf 'branch, and run `/handoff` yourself if you want a fresh one.\n\n'
        else
            printf -- '## A handoff write appears to have failed\n\n'
            printf 'A handoff for `%s` in `%s` started being written %s and never completed — past\n' \
                "$ref" "$here" "$since_phrase"
            printf 'the %ss it should have taken (`CTX_FORK_TIMEOUT_SECONDS`)' \
                "${CTX_FORK_TIMEOUT_SECONDS:-600}"
            if [ -n "$writing_transcript" ]; then
                printf ', and its transcript has\nbeen quiet for at least %ss too (`CTX_FORK_LIVENESS_WINDOW_SECONDS`) — not just slow,\ngenuinely idle. Its last activity is at `%s` if you want to see what it was doing when\nit stopped.\n' \
                    "${CTX_FORK_LIVENESS_WINDOW_SECONDS:-90}" "$writing_transcript"
            else
                printf '.\n'
            fi
            printf 'Treat it as abandoned: there is no fresh handoff to read for this branch. Run\n'
            printf '`/handoff` yourself if you need one.\n\n'
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
                if [ "$handoff_progress" = consumed ]; then
                    printf '(`progress: consumed` — this is the same document already delivered at an earlier\n'
                    printf 'reset; nothing new has been written for this branch since.)\n\n'
                fi
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
        printf 'pointers, or unverified. Run `/handoff --read` for the full contract.\n\n'

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

# D23: flip `complete` (or absent, a pre-D23 handoff) to `consumed` now that the document has
# actually been shown to a reader -- never on a `writing` placeholder (handoff_present is false
# for that case, so this block never runs for it) and never on a `recent` pick, which is a guess
# about someone else's branch and not this reader's to mutate. Best-effort: failure here loses
# nothing but the "already seen" framing on the next reset, not the handoff itself.
if [ "$handoff_present" = true ] && [ "$handoff_pick" = exact ] && [ "$handoff_progress" != consumed ] \
   && [ -r "$hook_dir/../lib/handoff-store.sh" ]; then
    handoff_store_set_progress "$handoff" consumed 2>/dev/null
fi

exit 0
