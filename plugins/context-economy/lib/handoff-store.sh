#!/bin/bash
#
# The handoff store: where handoffs live, and how a hook finds the right one.
# SOURCED, never executed.
#
# ── WHY THERE IS A STORE AT ALL ────────────────────────────────────────────────────────────
#
# Handoffs used to live at `<main-worktree>/.claude/handoff/<branch>.md`, derived from the
# session's own cwd. That worked only while the session's repository and the repository the
# work is in were the same thing, and in this setup they routinely are not: an orchestrating
# session drives a sibling checkout with `git -C`, and its cwd never moves. So the document
# was written to the ORCHESTRATOR, keyed to the ORCHESTRATOR's branch, while its citations
# described someone else's tree -- two branches of work driven from the same session branch
# overwrote each other's handoff, and the gate was aimed at the wrong repository by default.
#
# Moving the file INTO the target repo fixes the keying and breaks something worse: a
# SessionStart hook has only `cwd`, so it can derive exactly one candidate path and would
# never find a handoff belonging to a sibling checkout. The fix is not a pointer file --
# it is centralisation. One machine-local root can be ENUMERATED, and enumeration is the
# only discovery mechanism that works when the thing you are looking for is somewhere the
# caller cannot derive.
#
# So: keyed by the TARGET (the tree the citations describe), found by listing.
#
# ── WHY MACHINE-LOCAL, AND NOT IN A REPOSITORY ─────────────────────────────────────────────
#
# Same argument that put the compaction corpus outside every checkout, and it sits beside it
# for that reason. A handoff holds Dead ends and Traps -- which is exactly where candid
# remarks about a project's tooling end up -- and committing that into a client repository
# puts it in `git log` permanently, long after the PR that carried it is closed.
#
# ── THE STORE ROOT IS A PUBLISHED CONTRACT ─────────────────────────────────────────────────
#
# `${XDG_DATA_HOME:-$HOME/.local/share}/context-economy/` is this bundle's data root, and it is
# depended on from OUTSIDE the bundle -- so it is DECLARED here rather than merely observed. One
# parameter expansion, not an OS branch: it is the same shape as HANDOFF_STORE_DIR's own override
# below, applied uniformly on every platform this runs on, including Windows.
#
# It used to be `~/.claude/context-economy/` -- moved because Claude Code's own permission layer
# refuses `Write` to any `.claude`-containing path for a headless/least-privilege turn (see
# `docs/measured.md` finding #28 and its correction), which blocked exactly the write this store
# exists to receive. `~/.local/share/` was checked directly and found clear of that guard (see
# `docs/measured.md`'s 2026-09-17 XDG addendum); see `docs/design.md`'s `D21` for the full account,
# including what this move does NOT do (it is not full per-OS-native pathing, and not the complete
# XDG Base Directory spec -- just the one env var, at zero cost over an arbitrary path).
#
# handoffs/     written and read by this bundle. Resolved below; HANDOFF_STORE_DIR overrides it
#               for tests.
# compactions/  NOT under this root any more. It was RESERVED space here for an external capture
#               hook (`compaction-capture.sh`, its own COMPACTION_CORPUS_DIR) that this bundle
#               never wrote to -- the move above only relocates what this bundle owns, so
#               compactions/ was left wherever that hook's own config already points it, `D21`
#               decouples the two rather than migrating something it does not own.
#
# Renaming the root is a MIGRATION, not a rename. Handoffs are found by ENUMERATING this
# directory, so a changed root resolves to an empty store and every lookup reports "no handoff"
# -- the failure is silent and reads exactly like "there was nothing to resume".
#
# ── WHAT THE FILENAME IS FOR ───────────────────────────────────────────────────────────────
#
# `<repo-basename>-<branch-slug>-<hash8>.md`. The hash is the correctness half: a repo path is
# not a safe filename, and two checkouts can share a basename (`emmie` and a second `emmie`
# under a different parent). The basename and slug are the READABILITY half, and they are not
# decoration -- when the resolver reports the candidates it did not pick, a reader has to be
# able to recognise one without opening it. A pure hash would make that listing useless.
#
# The filename is not authoritative about the checkout, though: it cannot hold an absolute
# path. `checkout:` inside the document is the authority, which is why the resolver reads each
# candidate's envelope rather than trusting its name.

# The root. Overridable for tests, like LAST_CLEAR_STATE_DIR before it, and for the same
# reason: a test that writes into the real store corrupts the thing under test.
handoff_store_dir() {
    printf '%s' "${HANDOFF_STORE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/context-economy/handoffs}"
}

# Anything outside this set becomes `_`. Repository directories and branch names are freer
# than filenames are: a branch can hold `/` (already slugged by callers) and a directory can
# hold a space, and either one silently splits a path or an argument downstream.
handoff_store_slugify() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# handoff_store_md5 [-> 32 hex chars of MD5(stdin)]
#
# Portable MD5 hex digest of stdin. `md5sum` is GNU coreutils, present on Linux and on Windows
# through Git Bash's own coreutils -- but NOT on stock macOS, which ships no md5sum at all (BSD's
# `md5` instead, different flags, different output shape: `md5 -q` prints the bare digest the same
# way `md5sum | cut -c1-32` does here). Every caller already treats an empty result as "hash
# unavailable, degrade" (`handoff_store_name` below, and the two `/clear`-marker keys in
# handoff-inject.sh / session-end-marker.sh that hash `$main` for an unrelated file), so this
# degrades the same way when NEITHER exists: no output, not a fabricated or zero hash.
#
# Not independently verified on a real BSD/macOS machine -- this repo runs on Windows. `md5 -q`'s
# behavior (bare stdin digest, no filename/dash suffix) is long-stable, well-documented BSD
# userland syntax, but treat this branch as implemented-not-measured until it is actually run
# there, the same distinction this bundle draws everywhere else between asserting and checking.
handoff_store_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum 2>/dev/null | cut -c1-32
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q 2>/dev/null
    fi
}

# handoff_store_mtime <file> [-> epoch seconds]
#
# Portable mtime. GNU `stat -c %Y` (Linux, Git Bash on Windows) first; BSD/macOS `stat -f %m`
# otherwise -- same flag divergence as handoff_store_md5, same "empty on failure, never a
# fabricated number" contract every caller already relies on (an unreadable mtime must render as
# "unknown", not as a confident but wrong age). Same not-independently-verified-on-macOS caveat.
handoff_store_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

# handoff_store_find_transcript <session-id> [-> path, or empty]
#
# Locates a `--session-id`-pinned run's own transcript (D28) WITHOUT reconstructing Claude Code's
# own `~/.claude/projects/<cwd-slug>/` naming scheme -- deliberately. That encoding is an
# unpublished internal detail, and measured directly to disagree with what this bundle's own hooks
# compute for the same checkout: `git rev-parse --show-toplevel` returns `C:/Users/...` (forward
# slashes) on this machine, while the real project directory for that identical checkout is
# `C--Users-...` (colon and BACKSLASH both mapped to `-`) -- see `docs/measured.md` Finding #36.
# Reconstructing that mapping here would be a second, unversioned copy of a detail this bundle does
# not own, liable to silently drift the moment the real implementation changes it.
#
# A pinned session id sidesteps the whole problem: the filename itself is the exact, unambiguous
# key, so a two-level search under the projects root cannot collide with an unrelated session
# regardless of which directory Claude Code decided to file it under. Empty on failure -- no
# `$HOME`, no projects directory yet, or the file has not been created (the run just started) --
# and a caller degrades to "no liveness signal available", never to a fabricated path.
handoff_store_find_transcript() {
    local session_id=$1 root
    [ -n "$session_id" ] || return 0
    root="${HOME:-}/.claude/projects"
    [ -d "$root" ] || return 0
    find "$root" -maxdepth 2 -name "$session_id.jsonl" 2>/dev/null | head -1
}

# handoff_store_name <target-main-worktree> <branch-slug>
# The canonical filename for one target. Empty on failure, never a partial name -- a name
# missing its hash would collide with a different repository of the same basename.
handoff_store_name() {
    local main=$1 slug=$2 hash base
    hash=$(printf '%s' "$main" | handoff_store_md5 | cut -c1-8)
    [ -n "$hash" ] || return 1
    base=$(handoff_store_slugify "$(basename "$main")")
    slug=$(handoff_store_slugify "$slug")
    printf '%s-%s-%s.md' "$base" "$slug" "$hash"
}

# handoff_store_path <target-main-worktree> <branch-slug>
handoff_store_path() {
    local name
    name=$(handoff_store_name "$1" "$2") || return 1
    printf '%s/%s' "$(handoff_store_dir)" "$name"
}

# handoff_store_field <file> <field>
# One envelope field, from the head of the document only. Bounded on purpose: the envelope is
# the first handful of lines by contract, and a `checkout:` further down is body text -- a
# quoted example, a field note about some other run -- not this document's own header.
handoff_store_field() {
    head -20 "$1" 2>/dev/null | tr -d '\r' \
        | grep -m1 -E "^$2:" | sed -E "s/^$2:[[:space:]]*//" | sed -E 's/[[:space:]]+$//'
}

# handoff_store_write_skeleton <path> <checkout> <branch> [write-session-id]
#
# The WRITE leg's half of D23's compaction-race fix (docs/design.md): overwrites <path> with a
# bare, mostly-empty document whose only load-bearing content is `progress: writing`. Called
# SYNCHRONOUSLY, before the detached authoring turn is even spawned (hooks/handoff-fork-write.sh),
# so the file a session's own compaction finds already says "a fresh one is coming" rather than
# either nothing (silently read as "nothing to resume") or a stale `complete` document from a
# previous cycle (read as if it covers work it never saw). Unconditional: called every time
# `PreCompact` fires, whether or not anything real was here before -- an unread `complete` handoff
# lost this way is an accepted casualty of reusing one file per target, not a new failure D23
# introduces (the store already worked this way before this field existed).
#
# Deliberately passes the FULL format contract (verify-handoff.sh): "None." in each required
# subsection, an empty Pointers fence. Nothing today runs the gate against a `writing` placeholder
# on purpose -- the read leg checks `progress:` before ever reaching the gate -- but a skeleton
# that would fail its own document's contract if someone opened `verify-handoff.sh` against it by
# hand is a worse failure mode than the few extra lines cost to avoid it.
#
# `write-session-id` (D28, docs/design.md) is optional and omitted from the header entirely when
# empty -- the caller could not generate one (no `uuidgen`, no `openssl`), and an empty
# `write_session:` line would read as a real, empty answer rather than "not available". When
# present, it is the `--session-id` the detached authoring turn was launched with, letting a reader
# (or the read leg itself, past the nominal timeout) find that turn's own transcript by exact
# filename instead of guessing -- see `handoff_store_find_transcript` below.
handoff_store_write_skeleton() {
    local path=$1 checkout=$2 branch=$3 write_session=${4:-} tmp
    tmp="$path.tmp.$$"
    {
        printf '# Handoff — (placeholder: a fresh write is in progress)\n'
        printf 'branch: %s\n' "$branch"
        printf 'checkout: %s\n' "$checkout"
        printf 'status: placeholder -- not yet authored\n'
        printf 'progress: writing\n'
        [ -n "$write_session" ] && printf 'write_session: %s\n' "$write_session"
        cat <<BODY

## Do not re-derive

### Decisions
None.

### Dead ends
None.

### Traps
This is a placeholder, not a handoff -- see \`## Next\` before acting on anything else here.

## Next
1. Wait for this file's \`progress:\` field to flip from \`writing\` to \`complete\` before treating
   it as a real handoff. If it still says \`writing\` more than ${CTX_FORK_TIMEOUT_SECONDS:-600}
   seconds after this file's own mtime, the detached authoring run most likely died before
   finishing -- treat it as abandoned rather than waiting on it forever, and run \`/handoff\`
   yourself instead.

## Pointers

\`\`\`
\`\`\`
BODY
    } > "$tmp" 2>/dev/null && mv -f "$tmp" "$path" 2>/dev/null
}

# handoff_store_set_progress <file> <value>
#
# The READ leg's half of D23: rewrites the ONE header field in place, after a `complete` (or
# missing/legacy) handoff has actually been shown to a reader -- never on a `writing` placeholder,
# which the read leg does not call this for at all (see hooks/handoff-inject.sh). Bounded to the
# envelope for the same reason handoff_store_field reads only the head: a `progress:`-shaped line
# appearing later is body text, not this document's own header, and must never be rewritten.
#
# Replaces an existing `progress:` line if the envelope already has one; inserts a new line right
# after `status:` if it does not -- the missing case is every handoff written before this field
# existed, and this is also how such a document acquires the field going forward, rather than
# staying permanently unreadable by anything that expects it.
#
# Atomic: composed into a sibling temp file, then renamed over the original, so a reader mid-`cat`
# of the file never sees a half-written header. Degrades silently on failure (unwritable file, no
# `status:` line to anchor an insert on a malformed document) -- callers already treat this as
# best-effort bookkeeping, not something to fail a hook over.
handoff_store_set_progress() {
    local file=$1 value=$2 tmp
    [ -w "$file" ] || return 1
    tmp="$file.tmp.$$"
    if head -20 "$file" 2>/dev/null | grep -qE '^progress:'; then
        awk -v n=20 -v val="progress: $value" \
            'NR <= n && /^progress:/ { print val; next } { print }' \
            "$file" > "$tmp" 2>/dev/null
    else
        awk -v n=20 -v val="progress: $value" \
            'NR <= n && /^status:/ { print; print val; next } { print }' \
            "$file" > "$tmp" 2>/dev/null
    fi
    mv -f "$tmp" "$file" 2>/dev/null
}

# handoff_store_resolve <session-main-worktree> <session-branch-slug>
#
# Picks the handoff to surface, and sets:
#
#   HANDOFF_FILE      absolute path, or empty when the store holds nothing readable
#   HANDOFF_CHECKOUT  the tree its citations describe, from its own `checkout:` header
#   HANDOFF_BRANCH    its `branch:` header
#   HANDOFF_MTIME     epoch seconds, or empty when unreadable
#   HANDOFF_PICK      why this one -- `exact` or `recent`
#   HANDOFF_OTHERS    one line per candidate not picked: `path | branch | checkout | mtime`
#
# RANKING, and the order is the whole design:
#
#   1. An exact match on the session's own (repo, branch). Nothing beats being asked about
#      the very thing you are standing in, and it keeps the pre-store behaviour byte-identical
#      for the ordinary same-repo session -- the common case must not change.
#   2. Otherwise the most recently written candidate.
#
# Recency is a GUESS, and it is deliberately a visible one. Two live candidates cannot be
# disambiguated from `cwd` alone by any rule, so the resolver picks the newest and hands the
# rest back in HANDOFF_OTHERS for the caller to display. That is the one thing a pointer file
# could not do: a pointer resolves the ambiguity by silently overwriting, which loses the
# other candidate without ever admitting there was one.
# shellcheck disable=SC2034  # the HANDOFF_* globals above are this function's output, read by callers
handoff_store_resolve() {
    local session_main=$1 session_slug=$2
    # Two variables for one fact, deliberately. `best_key` is the comparison key and treats an
    # unreadable mtime as 0; `best_mtime` is what gets REPORTED and stays empty in that case.
    # Collapsing them would make an unreadable timestamp render as epoch 0 -- a confident
    # "20000 day(s) ago" downstream, which is a fabricated fact in a document whose entire job
    # is telling a reader what to trust.
    local dir exact f branch checkout mtime best="" best_mtime="" best_key=-1

    HANDOFF_FILE=""; HANDOFF_CHECKOUT=""; HANDOFF_BRANCH=""
    HANDOFF_MTIME=""; HANDOFF_PICK=""; HANDOFF_OTHERS=""

    dir=$(handoff_store_dir)
    [ -d "$dir" ] || return 0

    exact=""
    if [ -n "$session_main" ] && [ -n "$session_slug" ]; then
        exact=$(handoff_store_path "$session_main" "$session_slug" 2>/dev/null) || exact=""
    fi

    # A single pass. Each candidate is measured once, and the winner is decided from the same
    # data the OTHERS lines are built from -- so the listing can never disagree with the pick.
    for f in "$dir"/*.md; do
        [ -r "$f" ] && [ -s "$f" ] || continue
        mtime=$(handoff_store_mtime "$f")
        case "${mtime:-}" in ''|*[!0-9]*) mtime="" ;; esac

        if [ -n "$exact" ] && [ "$f" = "$exact" ]; then
            best=$f; best_mtime=$mtime; best_key=${mtime:-0}; HANDOFF_PICK=exact
        elif [ "${HANDOFF_PICK:-}" != exact ] && [ "${mtime:-0}" -gt "$best_key" ]; then
            # The previous best is demoted, not dropped: it is still a candidate a reader may
            # have meant, so it has to reach OTHERS. Rebuilt below rather than tracked here.
            best=$f; best_mtime=$mtime; best_key=${mtime:-0}; HANDOFF_PICK=recent
        fi
    done

    [ -n "$best" ] || return 0

    HANDOFF_FILE=$best
    HANDOFF_MTIME=$best_mtime
    HANDOFF_BRANCH=$(handoff_store_field "$best" branch)
    HANDOFF_CHECKOUT=$(handoff_store_field "$best" checkout)

    for f in "$dir"/*.md; do
        [ -r "$f" ] && [ -s "$f" ] || continue
        [ "$f" = "$best" ] && continue
        mtime=$(handoff_store_mtime "$f")
        case "${mtime:-}" in ''|*[!0-9]*) mtime=0 ;; esac
        branch=$(handoff_store_field "$f" branch)
        checkout=$(handoff_store_field "$f" checkout)
        HANDOFF_OTHERS="${HANDOFF_OTHERS}${f} | ${branch:-?} | ${checkout:-?} | ${mtime}
"
    done

    return 0
}
