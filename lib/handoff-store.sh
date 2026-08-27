#!/bin/bash
#
# The handoff store: where handoffs live, and how a hook finds the right one.
# SOURCED, never executed.
#
# ── WHY THERE IS A STORE AT ALL ────────────────────────────────────────────────────────────
#
# Handoffs used to live at `<main-worktree>/.claude/handoff/<branch>.md`, derived from the
# session's own cwd. That worked only while the session's repository and the repository the
# work is in were the same thing, and in this setup they routinely are not: a mission_control
# session drives a sibling checkout with `git -C`, and its cwd never moves. So the document
# was written to mission_control, keyed to mission_control's branch, while its citations
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
    printf '%s' "${HANDOFF_STORE_DIR:-$HOME/.claude/context-economy/handoffs}"
}

# Anything outside this set becomes `_`. Repository directories and branch names are freer
# than filenames are: a branch can hold `/` (already slugged by callers) and a directory can
# hold a space, and either one silently splits a path or an argument downstream.
handoff_store_slugify() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# handoff_store_name <target-main-worktree> <branch-slug>
# The canonical filename for one target. Empty on failure, never a partial name -- a name
# missing its hash would collide with a different repository of the same basename.
handoff_store_name() {
    local main=$1 slug=$2 hash base
    hash=$(printf '%s' "$main" | md5sum 2>/dev/null | cut -c1-8)
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
        mtime=$(stat -c %Y "$f" 2>/dev/null)
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
        mtime=$(stat -c %Y "$f" 2>/dev/null)
        case "${mtime:-}" in ''|*[!0-9]*) mtime=0 ;; esac
        branch=$(handoff_store_field "$f" branch)
        checkout=$(handoff_store_field "$f" checkout)
        HANDOFF_OTHERS="${HANDOFF_OTHERS}${f} | ${branch:-?} | ${checkout:-?} | ${mtime}
"
    done

    return 0
}
