#!/usr/bin/env bash
#
# Orientation for the v2 hooks module (hooks/register.ts): one call that turns a directory into
# everything the module needs to write or find that directory's handoff, as `key=value` lines.
#
# Usage:
#   handoff-orient.sh <dir>
#
# Prints, one per line, every key always present (empty when unknown):
#
#   main=      the main worktree, exactly as `git worktree list` spells it -- the string the store
#              hashes, so it must stay byte-identical to skills/handoff/SKILL.md's Step 1
#   checkout=  git's own toplevel for <dir>: what goes in the `checkout:` header
#   branch=    the ref, or the short SHA on a detached HEAD: what goes in `branch:`
#   handoff=   the store path for (main, branch), in the host's native notation
#   exists=    1 when that file is there, else 0
#   mtime=     its mtime in epoch seconds, empty when absent or unreadable
#   progress=  its `progress:` header, empty when absent
#   gate=      verify-handoff.sh beside this script, native notation
#
# Exit 0 with the lines above; exit 1, printing nothing, when <dir> is not inside a git checkout or
# the store library is missing -- the module then writes no handoff and lets core compact.
#
# WHY SHELL, FROM A TYPESCRIPT MODULE. Two reasons, both about not having two copies of a contract.
# The filename is md5(main)-keyed and computed by lib/handoff-store.sh, which the skill's Step 1 also
# sources; a second implementation in TypeScript would be a second copy that drifts (and the module's
# environment has no MD5 anyway). And `main` must be git's own output, not a re-spelling of it.
#
# WHY NATIVE PATHS. The module hands `handoff=` to `$.fs`, which takes the host's notation. Under Git
# Bash, $HOME is `/c/Users/...`, which bash reads and Windows does not; `cygpath -m` turns it into
# `C:/Users/...`, which both read. Where cygpath does not exist (macOS, Linux) the path is already
# native and passes through unchanged.

set -uo pipefail

dir=${1:-}
[ -n "$dir" ] || exit 1

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
store_lib="$script_dir/handoff-store.sh"
[ -r "$store_lib" ] || exit 1
# shellcheck source=handoff-store.sh
. "$store_lib"

native() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -m "$1"
    else
        printf '%s' "$1"
    fi
}

# cut, not awk: the same spelling SKILL.md's Step 1 uses, so both hash the same string.
main=$(git -C "$dir" worktree list 2>/dev/null | head -1 | cut -d' ' -f1)
checkout=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
[ -n "$main" ] && [ -n "$checkout" ] || exit 1

branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ "$branch" = HEAD ] && branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
slug=$(printf '%s' "$branch" | tr '/' '-')

handoff=$(handoff_store_path "$main" "$slug") || exit 1
mkdir -p "$(handoff_store_dir)" 2>/dev/null

exists=0 mtime="" progress=""
if [ -f "$handoff" ]; then
    exists=1
    mtime=$(handoff_store_mtime "$handoff" 2>/dev/null)
    progress=$(handoff_store_field "$handoff" progress)
fi

printf 'main=%s\n' "$main"
printf 'checkout=%s\n' "$checkout"
printf 'branch=%s\n' "$branch"
printf 'handoff=%s\n' "$(native "$handoff")"
printf 'exists=%s\n' "$exists"
printf 'mtime=%s\n' "$mtime"
printf 'progress=%s\n' "$progress"
printf 'gate=%s\n' "$(native "$script_dir/verify-handoff.sh")"
