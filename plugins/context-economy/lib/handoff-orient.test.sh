#!/usr/bin/env bash
#
# Tests for handoff-orient.sh.
#
#   t1  inside a checkout: every key is printed, and `handoff=` is the store path
#       handoff_store_path computes for the same (main, branch) -- the one contract this file exists
#       to keep, since the skill's Step 1 finds the same file by that function.
#   t2  an existing handoff reports exists=1, its mtime and its `progress:` header.
#   t3  a detached HEAD falls back to the short SHA for `branch=`.
#   t4  outside a checkout: exit 1, nothing printed, so the module lets core compact.
#
# Run it as:
#
#   bash lib/handoff-orient.test.sh

set -uo pipefail

# Arrange
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/handoff-orient.sh"

if [ ! -r "$subject" ]; then
    echo "handoff-orient.sh not found at $subject" >&2
    exit 2
fi

passed=0
failed=0

pass() { passed=$((passed + 1)); echo "ok   $1"; }
fail() { failed=$((failed + 1)); echo "FAIL $1 — $2"; }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export HANDOFF_STORE_DIR="$scratch/store"

repo="$scratch/repo"
git init -q -b feature/x "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

get() { printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2-; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# --- t1 — every key, and the store path the store library computes ----------

# Act
out=$(bash "$subject" "$repo")
rc=$?
main=$(git -C "$repo" worktree list | head -1 | cut -d' ' -f1)
expected=$(bash -c '. "$1"; handoff_store_path "$2" "$3"' _ "$script_dir/handoff-store.sh" "$main" feature-x)

# Assert
[ "$rc" -eq 0 ] && pass 't1 exits 0 inside a checkout' || fail 't1 exits 0 inside a checkout' "rc=$rc"
for key in main checkout branch handoff exists mtime progress gate; do
    printf '%s\n' "$out" | grep -q "^$key=" && pass "t1 prints $key=" || fail "t1 prints $key=" "absent"
done
[ "$(get "$out" branch)" = feature/x ] && pass 't1 branch is the ref' || fail 't1 branch is the ref' "$(get "$out" branch)"
[ "$(get "$out" handoff)" = "$(native "$expected")" ] && pass 't1 handoff is handoff_store_path' \
    || fail 't1 handoff is handoff_store_path' "$(get "$out" handoff) vs $(native "$expected")"
[ "$(get "$out" exists)" = 0 ] && pass 't1 no handoff yet reads exists=0' || fail 't1 no handoff yet reads exists=0' "$(get "$out" exists)"
[ -f "$(get "$out" gate)" ] && pass 't1 gate names a real file' || fail 't1 gate names a real file' "$(get "$out" gate)"

# --- t2 — an existing handoff ------------------------------------------------

# Arrange
mkdir -p "$HANDOFF_STORE_DIR"
printf '# Handoff — t\nbranch: feature/x\ncheckout: %s\nstatus: s\nprogress: complete\n' "$repo" > "$expected"

# Act
out=$(bash "$subject" "$repo")

# Assert
[ "$(get "$out" exists)" = 1 ] && pass 't2 exists=1' || fail 't2 exists=1' "$(get "$out" exists)"
[ -n "$(get "$out" mtime)" ] && pass 't2 mtime is set' || fail 't2 mtime is set' "empty"
[ "$(get "$out" progress)" = complete ] && pass 't2 progress is read' || fail 't2 progress is read' "$(get "$out" progress)"

# --- t3 — detached HEAD ------------------------------------------------------

# Arrange
git -C "$repo" checkout -q --detach
sha=$(git -C "$repo" rev-parse --short HEAD)

# Act
out=$(bash "$subject" "$repo")

# Assert
[ "$(get "$out" branch)" = "$sha" ] && pass 't3 detached HEAD reads the short SHA' \
    || fail 't3 detached HEAD reads the short SHA' "$(get "$out" branch)"

# --- t4 — outside a checkout -------------------------------------------------

# Arrange
mkdir -p "$scratch/plain"

# Act
out=$(bash "$subject" "$scratch/plain")
rc=$?

# Assert
[ "$rc" -eq 1 ] && pass 't4 exits 1 outside a checkout' || fail 't4 exits 1 outside a checkout' "rc=$rc"
[ -z "$out" ] && pass 't4 prints nothing' || fail 't4 prints nothing' "$out"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
