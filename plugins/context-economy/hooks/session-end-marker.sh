#!/bin/bash
#
# SessionEnd hook: record that a /clear happened (build-order item 4, piece 4).
#
# This closes the one hole in the write leg. The automatic write leg (`hooks/handoff-fork-write.sh`)
# fires on `PreCompact`, which only fires ahead of a compaction. `/clear` triggers no compaction at
# all, so a clear typed before compaction ever reached this session discards the session with no
# handoff and nothing anywhere saying so. The next session simply begins, blank, as though nothing
# had been lost. That silence is the defect: an undocumented reset and a properly handed-off one
# look exactly alike.
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
#
# ── DEGRADE WITHOUT jq, DON'T JUST DISAPPEAR ───────────────────────────────────────────────
#
# This hook used to bail out entirely (`command -v jq || exit 0`) the moment jq was absent, on
# the theory that SessionEnd has no additionalContext channel anyway, so there is no one to tell.
# That reasoning covers "cannot report to the user this turn"; it does not cover "cannot record
# anything on disk either", and those are different claims. Silently writing NO marker made an
# undocumented clear indistinguishable from a session where nothing was lost -- exactly the
# failure this whole hook exists to close, just reintroduced by its own dependency check.
#
# So jq is now optional, not required: `have_jq` gates only the two things that genuinely need
# it (reading nested usage figures out of the transcript, and building the JSON marker with a
# guarantee of correct escaping). Everything else -- which field values are present, git's own
# `worktree list`/`rev-parse`, the handoff lookup via handoff-store.sh -- never touched jq and
# still runs. Field extraction and the marker write below both fork on `have_jq`; neither
# degraded branch is a smaller rewrite of the other, they cover the same fields.

set -uo pipefail

if command -v jq >/dev/null 2>&1; then have_jq=true; else have_jq=false; fi

input=$(cat)

# extract_field <name>: one flat string field from the SessionEnd payload. The grep/sed
# fallback assumes a simple `"name":"value"` pair with no escaped quote inside the value --
# true of every field this hook reads (reason, an id, two paths), and no worse an assumption
# than the rest of this bundle's hand-rolled JSON already makes elsewhere.
extract_field() {
    if [ "$have_jq" = true ]; then
        printf '%s' "$input" | jq -r --arg f "$1" '.[$f] // empty' | tr -d '\r'
    else
        printf '%s' "$input" \
            | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" \
            | tr -d '\r'
    fi
}

reason=$(extract_field reason)
case "$reason" in
    clear) ;;
    *) exit 0 ;;
esac

session_id=$(extract_field session_id)
transcript=$(extract_field transcript_path)
cwd=$(extract_field cwd)

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
#
# jq-only: this is a query over an NDJSON transcript (pick the usage fields off the LAST message
# that has them), not a flat single-object read like the fields above. Reimplementing that
# without jq is a real parser, not a grep -- so this one figure is genuinely unavailable when jq
# is missing, and stays `null` rather than attempting a fragile line-based approximation. `null`
# already renders correctly downstream (handoff-inject.sh only prints the resident line when set).
resident=null
if [ "$have_jq" = true ] && [ -n "$transcript_fs" ] && [ -r "$transcript_fs" ]; then
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
    # 2>/dev/null on the whole substitution: handoff_store_mtime is only defined when the lib was
    # readable (handoff_path can be set via the pre-store fallback too), and an undefined-function
    # error would otherwise leak to this hook's own stderr.
    m=$(handoff_store_mtime "$handoff_path" 2>/dev/null)
    case "${m:-}" in ''|*[!0-9]*) handoff_mtime=null ;; *) handoff_mtime=$m ;; esac
fi

# Was an automatic write ever attempted for this session? `hooks/handoff-fork-write.sh` (the
# current PreCompact write leg) drops a per-session dedup lock the first firing it reaches, win
# or lose, and never removes it -- the only evidence on disk that a write was attempted before
# this clear. Its absence means no compaction reached this session before the clear, not that a
# demand for a handoff was ignored; those are different mistakes and deserve different wording
# downstream.
#
# (Superseded 2026-09-18: the previous write leg, `handoff-write.sh`, armed a latch at
# `~/.claude/state/handoff-trigger/$session_id` instead. Removed along with that file, which no
# longer runs, so that latch is never written any more -- checking it here would always read
# false. `write_attempted` is a new name, not a rename, because the underlying question changed:
# "did a write get predicted and asked for" versus "did compaction actually reach this session".)
write_attempted=false
[ -n "$session_id" ] && [ -e "$HOME/.claude/state/handoff-fork/$session_id.lock" ] && write_attempted=true

# ── Write ──────────────────────────────────────────────────────────────────────────────────
#
# Keyed by the MAIN worktree and the branch, so a clear in one project cannot surface in another,
# and two same-named checkouts cannot collide. Hashed for the same reason session-start.sh hashes
# its lock path: a repo path is not a safe filename.
state_dir="${LAST_CLEAR_STATE_DIR:-$HOME/.claude/state/last-clear}"
mkdir -p "$state_dir" 2>/dev/null || exit 0

# 2>/dev/null on the whole substitution: handoff_store_md5 is only defined when the lib was
# readable, and an undefined-function error would otherwise leak to this hook's own stderr.
key=$(printf '%s' "$main" | handoff_store_md5 2>/dev/null)
[ -n "$key" ] || exit 0
marker="$state_dir/$key-$slug.json"

now=$(date +%s)
ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ "$have_jq" = true ]; then
    jq -n \
        --arg ended_at "$ended_at" \
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
        --argjson write_attempted "$write_attempted" \
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
            write_attempted: $write_attempted
        }' > "$marker" 2>/dev/null
else
    # No jq to build the object, so escape by hand: backslash first (a Windows path is the
    # common case here), then the double quote that would otherwise close the string early.
    # This is the same two-character class `handoff-inject.sh`'s own jq-missing branch avoids
    # needing, because that branch never embeds arbitrary paths -- this one has to.
    json_str() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
    session_id_json='null'; [ -n "$session_id" ] && session_id_json="\"$(json_str "$session_id")\""
    transcript_json='null'; [ -n "$transcript" ] && transcript_json="\"$(json_str "$transcript")\""
    repo_json='null'; [ -n "$here" ] && repo_json="\"$(json_str "$here")\""
    cat > "$marker" 2>/dev/null <<EOF
{
  "ended_at": "$ended_at",
  "ended_at_epoch": $now,
  "reason": "$(json_str "$reason")",
  "session_id": $session_id_json,
  "transcript_path": $transcript_json,
  "repo": $repo_json,
  "main_worktree": "$(json_str "$main")",
  "branch": "$(json_str "$ref")",
  "resident_tokens": $resident,
  "handoff": {
    "present": $handoff_present,
    "path": "$(json_str "$handoff_path")",
    "mtime": $handoff_mtime
  },
  "write_attempted": $write_attempted,
  "degraded_no_jq": true
}
EOF
fi

# Nothing on stdout: SessionEnd cannot inject, the UI is being torn down, and hook failures here go
# to stderr rather than the interface. Anything printed would be noise nobody is positioned to read.
# The marker file is the only report this hook can ever make -- see the note above the `have_jq`
# check for why that is still written, in whichever form is available, rather than skipped.
exit 0
