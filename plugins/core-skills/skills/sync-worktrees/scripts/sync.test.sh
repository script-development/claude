#!/usr/bin/env bash
#
# Tests for sync.sh.
#
# Regressions found in review rounds on a consumer's copy of this script, each
# confirmed against the code before its case was written:
#
#   - A diverged secondary env file was overwritten behind a
#     `.before-sync-<timestamp>` backup. That backup was what made the
#     overwrite safe, and it could fail, could be raced by a same-minute
#     rerun, and left a second copy of the secret in the worktree for
#     `git add -A`. The write is now refused instead, and no backup exists —
#     so those three legs are asserted as ABSENT, not as handled.
#   - `cp` to a destination that is a symlink follows it, so a secondary
#     worktree's env path being a symlink let this script write primary's
#     secrets through it to wherever it resolved, worktree boundary or not.
#   - The symlink guard tested the leaf name only. A parent directory that is
#     itself a symlink stays traversable through `mkdir -p` and `cp`, which
#     puts the same write outside the worktree by a different spelling.
#   - A DIRECTORY at the destination passed every check for the same reason in
#     reverse: -L false, its own dirname inside the worktree, and -f false so
#     the divergence compare skipped it. `cp file dir` writes $dst/.env, and a
#     symlink nested in that directory carries the secret outside anyway.
#   - The final `cp` of an env file was unchecked, and `env_copied` was
#     incremented straight after it — so an unwritable destination reported,
#     and exited, as a clean sync.
#   - Dependency installs ran BEFORE --pull, so a fast-forward that changed
#     composer.lock/package-lock.json left the worktree on stale deps with
#     no signal anything was wrong.
#   - The detached-HEAD fetch's exit status was never checked, so a failed
#     fetch (auth, network) still printed "fetched" — a stale worktree
#     reporting itself as current.
#   - An env file this script writes is not necessarily gitignored on the
#     SECONDARY's own checked-out commit — a worktree stale enough to need
#     --pull is exactly one whose ignore rules may predate primary's — so
#     --pull skipped itself as "uncommitted changes" on exactly the worktree
#     it exists to catch up. Excluded by exact path, which is why the case
#     below is paired with one proving a REAL uncommitted change still blocks.
#   - A composer/npm install FAILED line never affected the script's own exit
#     status, so a caller checking `$?` read a worktree left on missing or
#     stale dependencies as a clean run.
#   - `awk '{print $2}'` field-split `git worktree list --porcelain`'s output,
#     truncating any worktree path containing a space.
#
# Real git throughout — a bare origin, a primary and secondary worktree. Only
# `composer`/`npm` are faked (record-only, no real installs), so ordering can
# be asserted without a real dependency tree.
#
# No framework by design, matching the other *.test.sh suites. Run it the same
# way:
#
#   bash <skill dir>/scripts/sync.test.sh

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/sync.sh"

if [ ! -x "$subject" ]; then
    echo "sync.sh not found or not executable at $subject" >&2
    exit 2
fi

passed=0
failed=0

check() {  # check <description> <expected-substring> <actual-output>
    local description=$1 expected=$2 actual=$3
    if printf '%s' "$actual" | grep -qF -- "$expected"; then
        passed=$((passed + 1))
        printf '  ok    %s\n' "$description"
    else
        failed=$((failed + 1))
        printf '  FAIL  %s\n        expected output containing: %s\n        got:\n%s\n' \
            "$description" "$expected" "$(printf '%s' "$actual" | sed 's/^/          | /')"
    fi
}

check_absent() {  # check_absent <description> <forbidden-substring> <actual-output>
    local description=$1 forbidden=$2 actual=$3
    if printf '%s' "$actual" | grep -qF -- "$forbidden"; then
        failed=$((failed + 1))
        printf '  FAIL  %s\n        should not contain: %s\n' "$description" "$forbidden"
    else
        passed=$((passed + 1))
        printf '  ok    %s\n' "$description"
    fi
}

# Resolved with `pwd -P`: on macOS $TMPDIR sits under /var, a symlink to
# /private/var, and sync.sh reports the resolved form.
tmp=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/sync-worktrees.XXXXXX")" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"

# --- Fakes -------------------------------------------------------------------

# `composer`/`npm` never really install anything — they record the manifest's
# content at invocation time, which is how the ordering test proves whether
# --pull's fast-forward already landed before the install ran.
cat > "$bin/composer" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == "install" ]] || exit 0
cat composer.json > "$STATE/composer_saw" 2>/dev/null
[[ -f "$STATE/composer_should_fail" ]] && exit 1
exit 0
FAKE
cat > "$bin/npm" <<'FAKE'
#!/usr/bin/env bash
[[ "$1" == "install" ]] || exit 0
exit 0
FAKE
chmod +x "$bin/composer" "$bin/npm"

# --- Fixture -----------------------------------------------------------------
# A bare origin, a primary worktree (where sync.sh runs from), and secondary
# worktrees it syncs into.

root="$tmp/repo"
mkdir -p "$root"
git -c init.defaultBranch=main init -q --bare "$root/origin.git"
git -c init.defaultBranch=main clone -q "$root/origin.git" "$root/primary"

primary="$root/primary"
cd "$primary" || exit 2
git config user.email t@sync.test
git config user.name "sync test"
echo old > composer.json
printf '.env\n.env.*\n!.env.example\n' > .gitignore
git add composer.json .gitignore
git commit -qm init
git push -q origin HEAD:main
git remote set-head origin main 2>/dev/null || true

# Detached, not on `main` itself — frees the `main` branch for a secondary
# worktree to check out directly, which the pull-ordering case below needs
# (git refuses to check out one branch into two worktrees at once).
git checkout -q --detach HEAD

echo "SECRET=primary" > .env

# --------------------------------------------------------------------- cases

echo "sync.sh"

# --- Case: a diverged env file is refused, not overwritten -------------------
# The whole backup construct is gone with it, so its three failure legs are
# asserted absent rather than handled: nothing to fail, nothing to race, and
# no second copy of the secret sitting in the worktree.

git worktree add -q -b feat-diverged "$root/wt-diverged" main >/dev/null
echo "SECRET=deliberate-override" > "$root/wt-diverged/.env"

export PATH="$bin:$PATH"
mkdir -p "$tmp/state"
export STATE="$tmp/state"
out=$(cd "$primary" && bash "$subject" 2>&1); rc=$?

check "a diverged env file is named as left untouched" "left untouched (differs: .env)" "$out"
check "the closing report lists the worktree still on its own env" \
  "env file(s) left untouched because they differ from primary" "$out"
if grep -q 'SECRET=deliberate-override' "$root/wt-diverged/.env" 2>/dev/null; then
    passed=$((passed + 1)); printf '  ok    %s\n' "the diverged .env keeps its own content"
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        .env now: %s\n' \
        "the diverged .env keeps its own content" \
        "$(cat "$root/wt-diverged/.env" 2>/dev/null)"
fi

backup_count=$(find "$root/wt-diverged" -maxdepth 1 -name '.env.before-sync-*' | wc -l)
if [ "$backup_count" -eq 0 ]; then
    passed=$((passed + 1)); printf '  ok    %s\n' 'no .before-sync-* copy of the secret is created'
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        found %s backup file(s)\n' \
        'no .before-sync-* copy of the secret is created' "$backup_count"
fi

# A refusal is a reported skip, not a failed step: a deliberate override that
# failed the exit status would do so on every future sync of that worktree.
if [ "$rc" -eq 0 ]; then
    passed=$((passed + 1)); printf '  ok    %s\n' 'a diverged env file alone is still exit 0'
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        exit was %s\n' \
        'a diverged env file alone is still exit 0' "$rc"
fi

# An ABSENT destination is still copied — refusing divergence must not turn
# into refusing to sync at all.
rm -f "$root/wt-diverged/.env"
out=$(cd "$primary" && bash "$subject" 2>&1)
if grep -q 'SECRET=primary' "$root/wt-diverged/.env" 2>/dev/null; then
    passed=$((passed + 1)); printf '  ok    %s\n' 'an absent env destination is still copied'
else
    failed=$((failed + 1)); printf '  FAIL  %s\n' 'an absent env destination is still copied'
fi

git worktree remove --force "$root/wt-diverged" >/dev/null 2>&1 || rm -rf "$root/wt-diverged"

# --- Case: --pull runs before composer install, not after --------------------

git worktree add -q "$root/wt-order" main >/dev/null

# Move origin/main forward with a composer.json change the worktree hasn't
# seen yet — the worktree is clean and sits exactly on main, so --pull
# fast-forwards it.
echo new > composer.json
git add composer.json && git commit -qm "bump composer.json"
git push -q origin HEAD:main

mkdir -p "$tmp/state"
STATE="$tmp/state" bash "$subject" --pull >/dev/null 2>&1

if [ -f "$tmp/state/composer_saw" ] && grep -q '^new$' "$tmp/state/composer_saw"; then
    passed=$((passed + 1)); printf '  ok    %s\n' 'composer install sees the post-pull composer.json, not the pre-pull one'
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        composer_saw: %s\n' \
        'composer install sees the post-pull composer.json, not the pre-pull one' \
        "$(cat "$tmp/state/composer_saw" 2>/dev/null || echo '<missing>')"
fi

git worktree remove --force "$root/wt-order" >/dev/null 2>&1 || rm -rf "$root/wt-order"

# --- Case: sync.sh's own env write does not block the --pull it precedes ----
# A worktree stale enough to need --pull may be checked out at a commit whose
# .gitignore is narrower than primary's — so a file sync.sh copies in can land
# as untracked AND unignored there, dirtying `git status` with sync.sh's own
# side effect. This fixture builds exactly that: primary ignores `.env.*`, the
# secondary's own checked-out gitignore covers only `.env`.

git worktree add -q "$root/wt-pull-blocked" main >/dev/null
printf '.env\n' > "$root/wt-pull-blocked/.gitignore"
git -C "$root/wt-pull-blocked" add .gitignore
git -C "$root/wt-pull-blocked" commit -qm "narrow gitignore, no wildcard"
git -C "$root/wt-pull-blocked" push -q origin main
# Left checked out at the narrow-gitignore commit — its own local `main`
# never learns about the wider one primary pushes next.

# Primary (still detached) takes origin/main's new tip, widens the gitignore
# back, and pushes a further commit — advancing origin/main one more step
# that wt-pull-blocked has not fetched, so it is now behind and needs --pull.
git fetch -q origin main
git checkout -q --detach origin/main
printf '.env\n.env.*\n!.env.example\n' > .gitignore
git add .gitignore && git commit -qm "widen gitignore"
git push -q origin HEAD:main
# `.env.local` is ignored in primary by `.env.*` and NOT ignored on the
# secondary's own commit, so copying it in is what would dirty that worktree.
echo "LOCAL=primary" > "$primary/.env.local"

out=$(cd "$primary" && bash "$subject" --pull 2>&1)
check "sync's own env write does not block the pull that follows it" \
  "fast-forwarded to origin/main" "$out"
check_absent "the pull is not skipped as uncommitted" "skipped (uncommitted changes)" "$out"

# The other half: the exclusion is by exact path, so a real uncommitted change
# still blocks the fast-forward. Without this, a filter wide enough to hide
# sync.sh's own writes would fast-forward over in-flight work.
git worktree remove --force "$root/wt-pull-blocked" >/dev/null 2>&1 || rm -rf "$root/wt-pull-blocked"
git worktree add -q "$root/wt-pull-dirty" main >/dev/null
git -C "$root/wt-pull-dirty" reset -q --hard HEAD~1
echo "developer was here" >> "$root/wt-pull-dirty/composer.json"

out=$(cd "$primary" && bash "$subject" --pull 2>&1)
check "a real uncommitted change still blocks the pull" \
  "skipped (uncommitted changes)" "$out"

rm -f "$primary/.env.local"
git worktree remove --force "$root/wt-pull-dirty" >/dev/null 2>&1 || rm -rf "$root/wt-pull-dirty"

# --- Case: a composer/npm failure is not a clean exit ------------------------

git worktree add -q "$root/wt-installfail" main >/dev/null
: > "$tmp/state/composer_should_fail"

bash "$subject" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    passed=$((passed + 1)); printf '  ok    %s\n' 'a composer install failure makes sync.sh exit non-zero'
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        exit was 0\n' \
        'a composer install failure makes sync.sh exit non-zero'
fi

rm -f "$tmp/state/composer_should_fail"
git worktree remove --force "$root/wt-installfail" >/dev/null 2>&1 || rm -rf "$root/wt-installfail"

# --- Case: a failed env copy is a FAILED line and a non-zero exit -----------
# The destination is absent (so the copy is attempted) inside a read-only
# directory (so it cannot succeed). This is the leg that used to increment
# env_copied straight after an unchecked `cp`.

git worktree add -q "$root/wt-copyfail" main >/dev/null
rm -f "$root/wt-copyfail/.env"
chmod 555 "$root/wt-copyfail"

out=$(cd "$primary" && bash "$subject" 2>&1); rc=$?
chmod 755 "$root/wt-copyfail"
check "a failed env copy says FAILED" "FAILED to copy .env" "$out"
check_absent "a failed env copy is not counted as copied" "1 files copied" "$out"
[ "$rc" -ne 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' 'a failed env copy makes sync.sh exit non-zero'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' 'a failed env copy makes sync.sh exit non-zero (exit was 0)'; }

git worktree remove --force "$root/wt-copyfail" >/dev/null 2>&1 || rm -rf "$root/wt-copyfail"

# --- Case: a worktree path containing a space is not truncated ---------------

git worktree add -q "$root/wt with space" main >/dev/null

out=$(cd "$primary" && bash "$subject" 2>&1)
check "a worktree path with a space is recognised, not truncated" "wt with space" "$out"

git worktree remove --force "$root/wt with space" >/dev/null 2>&1 || rm -rf "$root/wt with space"

# --- Case: sync.sh refuses to write primary's env through a dest symlink ----

git worktree add -q "$root/wt-symlink" main >/dev/null
sentinel="$tmp/external-sentinel"
echo "untouched" > "$sentinel"
rm -f "$root/wt-symlink/.env"
ln -s "$sentinel" "$root/wt-symlink/.env"
echo "SECRET=primary-v5" > "$primary/.env"

out=$(cd "$primary" && bash "$subject" 2>&1)
check "a symlinked .env destination is refused, not written through" \
  "refusing to write through it" "$out"
if grep -q '^untouched$' "$sentinel" 2>/dev/null; then
    passed=$((passed + 1)); printf '  ok    %s\n' "the symlink's external target is unchanged"
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        sentinel now: %s\n' \
        "the symlink's external target is unchanged" "$(cat "$sentinel" 2>/dev/null)"
fi

git worktree remove --force "$root/wt-symlink" >/dev/null 2>&1 || rm -rf "$root/wt-symlink"

# --- Case: a SYMLINKED PARENT directory is refused too ----------------------
# The leaf-name guard above cannot see this one: `$wt/backend` is a symlink to
# somewhere else entirely, so `mkdir -p` traverses it and `cp` writes
# `backend/.env` outside the worktree under a perfectly ordinary-looking path.

git worktree add -q "$root/wt-parent-symlink" main >/dev/null
external_dir="$tmp/external-dir"
mkdir -p "$external_dir"
echo "untouched" > "$external_dir/.env"
ln -s "$external_dir" "$root/wt-parent-symlink/backend"
mkdir -p "$primary/backend"
echo "SECRET=primary-nested" > "$primary/backend/.env"

out=$(cd "$primary" && bash "$subject" 2>&1); rc=$?
check "a symlinked parent directory is refused" "outside $root/wt-parent-symlink" "$out"
if grep -q '^untouched$' "$external_dir/.env" 2>/dev/null; then
    passed=$((passed + 1)); printf '  ok    %s\n' "the symlinked parent's external target is unchanged"
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        external .env now: %s\n' \
        "the symlinked parent's external target is unchanged" \
        "$(cat "$external_dir/.env" 2>/dev/null)"
fi
[ "$rc" -ne 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' 'an out-of-bounds destination makes sync.sh exit non-zero'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' 'an out-of-bounds destination makes sync.sh exit non-zero (exit was 0)'; }

rm -rf "$primary/backend"
git worktree remove --force "$root/wt-parent-symlink" >/dev/null 2>&1 || rm -rf "$root/wt-parent-symlink"

# --- Case: a DIRECTORY at the destination is refused -------------------------
# It passes every other check: -L is false, its own dirname is the worktree
# root so containment passes, and -f is false so the divergence compare is
# skipped. `cp file dir` would then write $dst/.env — and a symlink nested
# inside that directory carries it out of the worktree entirely.

git worktree add -q "$root/wt-dir-dest" main >/dev/null
nested_target="$tmp/nested-sentinel"
echo "untouched" > "$nested_target"
rm -f "$root/wt-dir-dest/.env"
mkdir -p "$root/wt-dir-dest/.env"
ln -s "$nested_target" "$root/wt-dir-dest/.env/.env"
echo "SECRET=primary-v6" > "$primary/.env"

out=$(cd "$primary" && bash "$subject" 2>&1); rc=$?
check "a directory at the env destination is refused" \
  "exists and is not a regular file" "$out"
if grep -q '^untouched$' "$nested_target" 2>/dev/null; then
    passed=$((passed + 1)); printf '  ok    %s\n' "the symlink nested in that directory is not written through"
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        nested sentinel now: %s\n' \
        "the symlink nested in that directory is not written through" \
        "$(cat "$nested_target" 2>/dev/null)"
fi
[ "$rc" -ne 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' 'a non-regular-file destination makes sync.sh exit non-zero'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' 'a non-regular-file destination makes sync.sh exit non-zero (exit was 0)'; }

rm -rf "$root/wt-dir-dest/.env"
git worktree remove --force "$root/wt-dir-dest" >/dev/null 2>&1 || rm -rf "$root/wt-dir-dest"

# --- Case: a failed fetch is reported as FAILED, never as a false success ----

git worktree add -q --detach "$root/wt-fetchfail" main >/dev/null
git remote set-url origin "$root/does-not-exist.git"

out=$(cd "$primary" && bash "$subject" --pull 2>&1)

check "a failed detached-HEAD fetch says FAILED" "FAILED (could not fetch" "$out"
check_absent "a failed detached-HEAD fetch never claims it fetched" "fetched origin/main (detached" "$out"

git worktree remove --force "$root/wt-fetchfail" >/dev/null 2>&1 || rm -rf "$root/wt-fetchfail"

# --- Case: --base must carry a real branch name ------------------------------
# Every earlier case removes the worktree it created, so the script would exit
# at "No secondary worktrees to sync." before reaching anything below. These
# cases need one present to reach the base line and the closing report.
git worktree add -q "$root/wt-args" main >/dev/null

# `shift; BASE=$1` accepted two malformed forms and ran to completion against a
# base the caller never asked for. Measured before the fix, in a repo with an
# origin/main to fall back to: `--base` alone reported `Base branch: main`, and
# `--base --pull` reported `Base branch: --pull` with `pull: skipped (--pull not
# set)` — the flag swallowed as the value AND consumed. Both exited 0. Both
# spellings are covered, because fixing only the space form leaves `--base=`
# doing the same thing one line down.

out=$(cd "$primary" && bash "$subject" --base 2>&1); rc=$?
check "--base with its value omitted is refused" "--base needs a branch name" "$out"
check_absent "--base with its value omitted never falls through to detection" "Base branch:" "$out"
[ "$rc" -ne 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' '--base with no value exits non-zero'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' '--base with no value exits non-zero (exit was 0)'; }

out=$(cd "$primary" && bash "$subject" --base --pull 2>&1); rc=$?
check "--base given an option is refused" "not a branch name" "$out"
check_absent "--base given an option never syncs against it" "Base branch: --pull" "$out"
[ "$rc" -ne 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' '--base given an option exits non-zero'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' '--base given an option exits non-zero (exit was 0)'; }

out=$(cd "$primary" && bash "$subject" --base= 2>&1); rc=$?
check "the --base= spelling is validated too" "--base= needs a branch name" "$out"
[ "$rc" -ne 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' '--base= with no value exits non-zero'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' '--base= with no value exits non-zero (exit was 0)'; }

out=$(cd "$primary" && bash "$subject" --base main 2>&1); rc=$?
check "a well-formed --base still works" "Base branch: main" "$out"
[ "$rc" -eq 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' 'a well-formed --base exits zero'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' 'a well-formed --base exits zero (exit was non-zero)'; }

# --- Case: a registered worktree missing from disk is a REPORTED skip --------
# It was skipped silently and the closing line still read "Every worktree's env
# files match primary" at exit 0 — while the .env had reached none of them. The
# exit code deliberately stays 0: a worktree deleted with `rm -rf` instead of
# `git worktree remove` stays registered forever, so failing on it would make
# every later sync of that repo exit non-zero, which is the habit sync.sh's
# diverged-env branch already refuses to build. What was wrong was the claim.

# --detach, not `main`: wt-args above already has that branch checked out and
# git refuses the same branch in two worktrees. The skip fires before any
# branch logic, so a detached head exercises it identically.
git worktree add -q --detach "$root/wt-gone" main >/dev/null
rm -rf "$root/wt-gone"

out=$(cd "$primary" && bash "$subject" 2>&1); rc=$?
check "a missing worktree is named in the closing report" \
  "worktree(s) skipped — registered but not on disk" "$out"
check "the report names git's own word for the state" "(prunable)" "$out"
check "the report names the fix" "git worktree prune" "$out"
check_absent "the report no longer claims every worktree matches primary" \
  "Every worktree's env files match primary" "$out"
check "the closing line counts what was actually synced" "worktree(s) synced." "$out"
[ "$rc" -eq 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' 'a missing worktree does not fail the run'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' 'a missing worktree does not fail the run (exit was non-zero)'; }

git worktree prune

# --- Case: with every worktree present, the clean message is unchanged -------
# The count line replaces the clean one only when something was skipped or
# diverged. A run with nothing to report must still say what it always said.

out=$(cd "$primary" && bash "$subject" 2>&1); rc=$?
check "a fully clean run keeps its original closing line" \
  "Every worktree's env files match primary" "$out"
check_absent "a fully clean run reports no skipped worktrees" \
  "worktree(s) skipped" "$out"

# --- Case: a gitignored secondary worktree living INSIDE primary is pruned ---
# The env-file scan was not pruned to the primary, so a secondary
# worktree registered at a path primary's own .gitignore covers (the common
# layout — a worktree directory inside the repo has to be ignored to keep it
# out of `git status`) was walked too. `check-ignore` answers about the path,
# not tracking state, so the secondary's own TRACKED files matching `.env*`
# were classified as primary's and propagated into every other worktree — and
# because the write landed back inside $PRIMARY, the next run picked the copy
# up again, compounding a level deeper each time.

printf '.worktrees/\n' >> "$primary/.gitignore"
git -C "$primary" add .gitignore
git -C "$primary" commit -qm "ignore a nested worktree slot"

git worktree add -q -b nested-slot "$primary/.worktrees/wt-nested" main >/dev/null
echo "TRACKED=1" > "$primary/.worktrees/wt-nested/.env.example"
git -C "$primary/.worktrees/wt-nested" add .env.example
git -C "$primary/.worktrees/wt-nested" commit -qm "a tracked env file inside the nested worktree"

# Let the first sync settle: a newly added worktree legitimately receives
# primary's real env files once, same as any other secondary. The idempotency
# claim below is about REPEATED runs, not this initial catch-up.
(cd "$primary" && bash "$subject" >/dev/null 2>&1)

out1=$(cd "$primary" && bash "$subject" 2>&1); rc1=$?
out2=$(cd "$primary" && bash "$subject" 2>&1)

check_absent "the nested worktree's own tracked env file is never read as primary's" \
  ".worktrees/wt-nested/.env.example" "$out1"

if [ -e "$root/wt-args/.env.example" ]; then
    failed=$((failed + 1)); printf '  FAIL  %s\n' \
        'a tracked file from the nested worktree is not propagated to other secondaries'
else
    passed=$((passed + 1)); printf '  ok    %s\n' \
        'a tracked file from the nested worktree is not propagated to other secondaries'
fi

doubled=$(find "$root" -path '*wt-nested*wt-nested*' 2>/dev/null)
if [ -z "$doubled" ]; then
    passed=$((passed + 1)); printf '  ok    %s\n' 'no path nests the worktree directory name inside itself'
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        found: %s\n' \
        'no path nests the worktree directory name inside itself' "$doubled"
fi

[ "$rc1" -eq 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' 'a gitignored nested worktree alone is still exit 0'; } \
                 || { failed=$((failed + 1)); printf '  FAIL  %s\n' 'a gitignored nested worktree alone is still exit 0 (exit was non-zero)'; }

if [ "$out1" = "$out2" ]; then
    passed=$((passed + 1)); printf '  ok    %s\n' 'two consecutive runs produce byte-identical output'
else
    failed=$((failed + 1)); printf '  FAIL  %s\n        run 1:\n%s\n        run 2:\n%s\n' \
        'two consecutive runs produce byte-identical output' \
        "$(printf '%s' "$out1" | sed 's/^/          | /')" \
        "$(printf '%s' "$out2" | sed 's/^/          | /')"
fi

git worktree remove --force "$primary/.worktrees/wt-nested" >/dev/null 2>&1 || rm -rf "$primary/.worktrees/wt-nested"

# --- Case: a secondary worktree NAME with glob metacharacters is still
# excluded ---------------------------------------------------------------------
# `find -path` matches its operand as a shell glob, so the first version of
# this fix — pruning secondaries via `find -not -path "$sec"` — failed to
# exclude a worktree named with `*`, `?` or `[`: a bracket expression does not
# match its own literal characters. The fix now excludes by a quoted `case`
# pattern, a literal comparison; this pins the exact shape a reviewer found,
# including the self-nesting destination its trace names.

git worktree add -q -b glob-name-slot "$primary/.worktrees/wt[abc]" main >/dev/null
echo "TRACKED=1" > "$primary/.worktrees/wt[abc]/.env.example"
git -C "$primary/.worktrees/wt[abc]" add .env.example
git -C "$primary/.worktrees/wt[abc]" commit -qm "a tracked env file inside a glob-named worktree"

# Let this new worktree receive its first, legitimate catch-up sync before
# asserting on the scan itself.
(cd "$primary" && bash "$subject" >/dev/null 2>&1)

out=$(cd "$primary" && bash "$subject" 2>&1); rc=$?

check_absent "a glob-named worktree's own tracked env file is never read as primary's" \
  "wt[abc]/.env.example" "$out"

if [ -e "$root/wt-args/.env.example" ]; then
    failed=$((failed + 1)); printf '  FAIL  %s\n' \
        'a tracked file from a glob-named worktree is not propagated to other secondaries'
else
    passed=$((passed + 1)); printf '  ok    %s\n' \
        'a tracked file from a glob-named worktree is not propagated to other secondaries'
fi

if [ -e "$primary/.worktrees/wt[abc]/.worktrees/wt[abc]/.env.example" ]; then
    failed=$((failed + 1)); printf '  FAIL  %s\n' \
        'a glob-named worktree does not nest a copy of itself inside itself'
else
    passed=$((passed + 1)); printf '  ok    %s\n' \
        'a glob-named worktree does not nest a copy of itself inside itself'
fi

[ "$rc" -eq 0 ] && { passed=$((passed + 1)); printf '  ok    %s\n' 'a glob-named worktree alone is still exit 0'; } \
               || { failed=$((failed + 1)); printf '  FAIL  %s\n' 'a glob-named worktree alone is still exit 0 (exit was non-zero)'; }

git worktree remove --force "$primary/.worktrees/wt[abc]" >/dev/null 2>&1 || rm -rf "$primary/.worktrees/wt[abc]"

git worktree remove --force "$root/wt-args" >/dev/null 2>&1 || rm -rf "$root/wt-args"


echo
if [ "$failed" -gt 0 ]; then
    echo "FAILED: $failed of $((passed + failed)) assertions"
    exit 1
fi

echo "OK: all $passed assertions passed"
