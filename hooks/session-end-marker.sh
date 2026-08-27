#!/bin/bash
#
# SessionEnd hook: record that a /clear happened (build-order item 4, piece 4).
#
# This closes the one hole in the write leg. `handoff-urge.sh` fires on `Stop`, at a turn boundary,
# once resident context reaches the threshold. But `/clear` does NOT fire `Stop` (F9 -- the
# binary's own hook table says otherwise and is wrong), so a clear typed at 180k, below the
# threshold, or before the trigger's turn boundary arrives, discards the session with no handoff
# and nothing anywhere saying so. The next session simply begins, blank, as though nothing had
# been lost. That silence is the defect: an undocumented reset and a properly handed-off one look
# exactly alike.
#
# ── WHAT THIS CAN AND CANNOT DO ────────────────────────────────────────────────────────────
#
# `SessionEnd` cannot inject and cannot make the model do anything -- it is absent from the
# `additionalContext` set, and by the time it runs there is no turn to continue. So it does not
# attempt a rescue. It RECORDS, and `handoff-inject.sh` surfaces the record into the next session.
#
# Two properties from F9 make the record worth having:
#
#   - It is AWAITED, and it runs BEFORE the clear (the call is the clear handler's first
#     statement; messages are emptied several statements later). So this hook sees the transcript
#     at FULL DEPTH and the resident figure it writes down is the real one.
#   - THE TRANSCRIPT SURVIVES THE CLEAR. That is the whole reason this is worth recording rather
#     than merely lamenting: the lost session is recoverable from disk, and the only thing standing
#     between the next session and that file is knowing the path. So the path is the payload.
#
# ── SCOPE: `clear` ONLY ────────────────────────────────────────────────────────────────────
#
# The reason enum is clear / resume / logout / prompt_input_exit / other, and the matcher matches
# the reason, so the settings entry is selective already; the check below is belt-and-braces for a
# hook invoked by hand or through a broader matcher.
#
# The others are excluded on purpose. `resume` keeps its context. `logout` and `prompt_input_exit`
# end the session rather than resetting it -- the next one is a `startup`, where nothing is
# surfaced anyway, and where a report about a session the human deliberately walked away from
# hours ago would be noise rather than news.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)

reason=$(printf '%s' "$input" | jq -r '.reason // empty' | tr -d '\r')
case "$reason" in
    clear) ;;
    *) exit 0 ;;
esac

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty' | tr -d '\r')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' | tr -d '\r')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' | tr -d '\r')

[ -n "$cwd" ] || cwd=$PWD

# TWO FORMS OF THE TRANSCRIPT PATH, KEPT SEPARATE ON PURPOSE.
#
# `transcript` is recorded verbatim as the harness supplied it, because that value is surfaced TO
# THE MODEL, which will hand it to a file-reading tool expecting a native Windows path. Passing it
# through `cygpath -u` first produced `/c/Users/...`, which reads fine to bash and not at all to
# anything else -- so the marker's most valuable field would have named a file its only consumer
# could not open.
#
# `transcript_fs` is the converted form, used solely for this script's own read below. Measured
# while writing the test: MSYS resolves `/tmp` onto the Windows temp directory, so `cygpath -u` is
# not a no-op even on an already-POSIX path, and the two forms genuinely differ in both directions.
transcript_fs="$transcript"
if command -v cygpath >/dev/null 2>&1; then
    cwd=$(cygpath -u "$cwd" 2>/dev/null || printf '%s' "$cwd")
    [ -n "$transcript_fs" ] && transcript_fs=$(cygpath -u "$transcript_fs" 2>/dev/null || printf '%s' "$transcript_fs")
fi
[ -d "$cwd" ] || exit 0

main=$(git -C "$cwd" worktree list 2>/dev/null | head -1 | awk '{print $1}')
here=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
ref=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$ref" = HEAD ] && ref=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

# No repo means no key to file this under, and the surface that reads it is repo-scoped. A clear
# in a scratch directory is not something the next session in some other project needs told.
[ -n "$main" ] || exit 0
[ -n "$ref" ] || exit 0

slug=$(printf '%s' "$ref" | tr '/' '-')

# ── Resident depth at the moment of the clear ──────────────────────────────────────────────
#
# Readable here precisely because SessionEnd runs before the messages are emptied. This number is
# what separates "cleared a shallow session, nothing lost" from "discarded 300k of work" -- and
# the surface needs the distinction to decide whether to say anything urgent at all.
resident=null
if [ -n "$transcript_fs" ] && [ -r "$transcript_fs" ]; then
    r=$(jq -r 'select(.message.usage != null)
               | .message.usage
               | (.input_tokens // 0)
                 + (.cache_creation_input_tokens // 0)
                 + (.cache_read_input_tokens // 0)' "$transcript_fs" 2>/dev/null | tail -1)
    case "${r:-}" in ''|*[!0-9]*) resident=null ;; *) resident=$r ;; esac
fi

# ── Was the work covered? ──────────────────────────────────────────────────────────────────
#
# The handoff's MTIME, captured now, is what lets the next session answer the only question that
# matters: does the handoff on disk describe the session that was just thrown away, or an older
# one? A stale handoff injected with no such note is worse than none -- it reads as coverage.
#
# RESOLVED THROUGH THE SHARED STORE, not derived here, and that is a correctness requirement
# rather than tidiness. This hook measures one file's mtime; handoff-inject.sh injects one file.
# If the two pick DIFFERENT files, the coverage sentence is attached to a document it was never
# computed from -- "written 2 minutes before that clear" printed above an unrelated handoff. The
# only way they cannot disagree is for one function to answer for both.
#
# Falls back to the pre-store path when the lib is missing, matching handoff-inject.sh: the two
# have to degrade the same way, or the fallback reintroduces exactly the mismatch above.
hook_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -r "$hook_dir/../lib/handoff-store.sh" ]; then
    # shellcheck source=../lib/handoff-store.sh
    . "$hook_dir/../lib/handoff-store.sh"
    handoff_store_resolve "$main" "$slug"
    handoff_path=$HANDOFF_FILE
else
    handoff_path="$main/.claude/handoff/$slug.md"
fi
[ -n "$handoff_path" ] || handoff_path="$main/.claude/handoff/$slug.md"
handoff_present=false
handoff_mtime=null
if [ -r "$handoff_path" ] && [ -s "$handoff_path" ]; then
    handoff_present=true
    m=$(stat -c %Y "$handoff_path" 2>/dev/null)
    case "${m:-}" in ''|*[!0-9]*) handoff_mtime=null ;; *) handoff_mtime=$m ;; esac
fi

# Did the write trigger ever arm for this session? The latch is the only evidence, and its absence
# is informative in its own right: it means the clear beat the threshold rather than overrode a
# demand for a handoff. Those are different mistakes and deserve different wording downstream.
urge_fired=false
[ -n "$session_id" ] && [ -e "$HOME/.claude/state/handoff-trigger/$session_id" ] && urge_fired=true

# ── Write ──────────────────────────────────────────────────────────────────────────────────
#
# Keyed by the MAIN worktree and the branch, so a clear in one project cannot surface in another,
# and two same-named checkouts cannot collide. Hashed for the same reason session-start.sh hashes
# its lock path: a repo path is not a safe filename.
state_dir="${LAST_CLEAR_STATE_DIR:-$HOME/.claude/state/last-clear}"
mkdir -p "$state_dir" 2>/dev/null || exit 0

key=$(printf '%s' "$main" | md5sum 2>/dev/null | cut -c1-32)
[ -n "$key" ] || exit 0
marker="$state_dir/$key-$slug.json"

now=$(date +%s)

jq -n \
    --arg ended_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson ended_at_epoch "$now" \
    --arg reason "$reason" \
    --arg session_id "$session_id" \
    --arg transcript_path "$transcript" \
    --arg repo "$here" \
    --arg main_worktree "$main" \
    --arg branch "$ref" \
    --argjson resident_tokens "$resident" \
    --arg handoff_path "$handoff_path" \
    --argjson handoff_present "$handoff_present" \
    --argjson handoff_mtime "$handoff_mtime" \
    --argjson urge_fired "$urge_fired" \
    '{
        ended_at: $ended_at,
        ended_at_epoch: $ended_at_epoch,
        reason: $reason,
        session_id: (if $session_id == "" then null else $session_id end),
        transcript_path: (if $transcript_path == "" then null else $transcript_path end),
        repo: (if $repo == "" then null else $repo end),
        main_worktree: $main_worktree,
        branch: $branch,
        resident_tokens: $resident_tokens,
        handoff: {
            present: $handoff_present,
            path: $handoff_path,
            mtime: $handoff_mtime
        },
        urge_fired: $urge_fired
    }' > "$marker" 2>/dev/null

# Nothing on stdout: SessionEnd cannot inject, the UI is being torn down, and hook failures here go
# to stderr rather than the interface. Anything printed would be noise nobody is positioned to read.
exit 0
