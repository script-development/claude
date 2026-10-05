#!/usr/bin/env bash
# Sync secondary git worktrees with the primary one.
# See ../SKILL.md for the design rationale and safety contract.

PULL=false
BASE=""

# A branch name is neither empty nor option-shaped. Refusing here rather than
# letting detection cover for it keeps "I named a base" and "detect one for me"
# as two distinct requests.
require_base() { # $1 = value, $2 = the spelling the caller used
  case "$1" in
    "")  echo "Error: $2 needs a branch name." >&2; exit 1 ;;
    -*)  echo "Error: $2 got the option '$1', not a branch name." >&2; exit 1 ;;
  esac
}

while [ $# -gt 0 ]; do
  case $1 in
    --pull) PULL=true ;;
    # `shift; BASE=$1` alone accepts two malformed forms, and both run to
    # completion against a base the caller did not ask for. `--base` as the last
    # argument leaves $1 unset, so BASE stays empty and the auto-detection below
    # picks origin/HEAD or main — the caller asked for an EXPLICIT base and
    # silently got a detected one. `--base --pull` swallows the next option as
    # the branch name AND consumes it, so --pull never takes effect either.
    # Measured: `--base` alone reported `Base branch: main`, and `--base --pull`
    # reported `Base branch: --pull` with `pull: skipped (--pull not set)`, both
    # exit 0. Validated in both spellings on purpose: fixing only the space form
    # leaves `--base=` doing the same thing one line down.
    --base) shift; BASE=${1-}; require_base "$BASE" "--base" ;;
    --base=*) BASE=${1#--base=}; require_base "$BASE" "--base=" ;;
    -h|--help)
      echo "Usage: sync.sh [--pull] [--base <branch>]"
      echo "  --pull           Fast-forward worktrees on the base branch/detached HEAD to origin/<base>"
      echo "  --base <branch>  Integration branch (default: origin/HEAD, then main, then master)"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
  shift
done

# Primary worktree is always the first entry in git worktree list. The path is everything
# after "worktree ", not awk's $2: a path with a space in it (common on macOS) was cut short.
PRIMARY=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
if [ -z "$PRIMARY" ]; then
  echo "Error: could not locate primary worktree. Run this from inside a git repo." >&2
  exit 1
fi

# Integration branch: explicit flag, else origin/HEAD, else main, else master
if [ -z "$BASE" ]; then
  BASE=$(git -C "$PRIMARY" symbolic-ref refs/remotes/origin/HEAD --short 2>/dev/null | sed 's|^origin/||')
fi
if [ -z "$BASE" ]; then
  for candidate in main master; do
    if git -C "$PRIMARY" show-ref --verify --quiet "refs/remotes/origin/$candidate"; then
      BASE=$candidate; break
    fi
  done
fi
if [ -z "$BASE" ]; then
  echo "Error: could not detect the integration branch. Pass --base <branch>." >&2
  exit 1
fi

# Collect secondary worktrees (everything except the primary). Computed here,
# BEFORE the env-file scan below, because that scan must exclude them: a
# secondary registered at a path primary's own .gitignore covers — the common
# layout, since a worktree directory inside the repo has to be ignored to keep
# it out of `git status` — otherwise gets walked as though it were part of
# primary.
#
# A read loop, not mapfile: mapfile is bash 4, and on the bash 3.2 of stock macOS it failed, left
# this list empty and reported "No secondary worktrees to sync." — a sync that did nothing and
# said all was well.
SECONDARIES=()
while IFS= read -r wt; do
  SECONDARIES+=("$wt")
done < <(git -C "$PRIMARY" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}' | tail -n +2)

if [ ${#SECONDARIES[@]} -eq 0 ]; then
  echo "No secondary worktrees to sync."
  exit 0
fi

# Env files: every gitignored .env* file in the primary, at any depth, skipping
# dependency dirs and every registered secondary worktree. Paths are kept
# relative to the worktree root.
#
# `.before-sync-*` is excluded for leftovers only: this script no longer creates
# backups (see the env block below), but a worktree synced by the version that
# did still has them on disk, and picking one up as an env file to propagate
# would copy a stale secret into every other worktree.
#
# Excluding secondaries is the primary fix: without it, a secondary
# nested inside primary (the common layout) is walked too, and its own
# TRACKED files matching `.env*` get classified as primary's — because
# `check-ignore` answers about the PATH (the secondary's directory is
# ignored), never about tracking state. The `ls-files --error-unmatch` guard
# below is a second, independent line of defence for the same class inside
# primary's own tree: an ignored directory can contain a tracked exception
# (a negated `.gitignore` pattern), and `check-ignore` alone cannot see that.
#
# The exclusion is a LITERAL path comparison via a quoted `case` pattern, not
# `find -path`: `find -path` matches its operand as a shell glob, so a
# secondary whose directory name contains `*`, `?` or `[` would not actually
# be excluded — the tool explicitly supports any worktree naming convention
# (SKILL.md), so that is a real name, not a hypothetical one. Quoting `$sec`
# inside a `case` pattern disables glob interpretation of its content,
# matching it byte-for-byte; only the unquoted `/*` suffix stays a wildcard.
ENV_FILES=()
while IFS= read -r abs; do
  under_secondary=false
  for sec in "${SECONDARIES[@]}"; do
    case "$abs" in
      "$sec"|"$sec"/*) under_secondary=true; break ;;
    esac
  done
  [ "$under_secondary" = true ] && continue

  rel=${abs#"$PRIMARY"/}
  if ! git -C "$PRIMARY" check-ignore -q -- "$rel"; then
    continue
  fi
  if git -C "$PRIMARY" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    # Tracked despite sitting under an ignored path — never a primary env
    # file to propagate.
    continue
  fi
  ENV_FILES+=("$rel")
done < <(find "$PRIMARY" -type f -name '.env*' \
           -not -name '*.before-sync-*' \
           -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | sort)

# Diverged env files, worktree-qualified, for the closing report.
DIVERGED_FILES=()
# A composer/npm/pull FAILED line was, until now, text only — the script's own
# exit status stayed 0 regardless, so a caller checking `$?` (a wrapper, a CI
# step) read a worktree left on missing or stale dependencies as a clean run.
HAD_FAILURE=0
# Registered worktrees that are not on disk. A third state beside success and
# HAD_FAILURE, for the same reason the diverged-env branch below is one: a
# worktree deleted with `rm -rf` instead of `git worktree remove` stays
# registered forever, so failing on it would make every future sync of that repo
# exit non-zero and teach the caller to stop reading the exit status at all.
# What was wrong was not the exit code but the closing line, which said every
# worktree's env files matched primary while the .env had reached none of them.
SKIPPED_WORKTREES=()

# Dependency manifests are looked up per worktree (they are tracked files).
find_manifests() { # $1 = worktree, $2 = manifest name
  find "$1" -maxdepth 3 -type f -name "$2" \
    -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | sort
}

echo "Primary: $PRIMARY"
echo "Base branch: $BASE"
echo "Env files: ${#ENV_FILES[@]} gitignored .env* file(s) found in primary"
echo "Syncing ${#SECONDARIES[@]} secondary worktree(s)..."

for wt in "${SECONDARIES[@]}"; do
  if [ ! -d "$wt" ]; then
    echo ""
    echo "=== $(basename "$wt") ==="
    echo "  directory missing on disk, skipping"
    # `prunable` is git's own word for "registered, gone from disk, safe to
    # deregister". Carrying it through means the report can name the fix instead
    # of leaving the reader to work out why a worktree they deleted is listed.
    if git -C "$PRIMARY" worktree list --porcelain | grep -qxF "worktree $wt" &&
       git -C "$PRIMARY" worktree list --porcelain |
         awk -v w="worktree $wt" '$0==w {f=1; next} /^worktree /{f=0} f && /^prunable/{found=1} END{exit !found}'; then
      SKIPPED_WORKTREES+=("$wt  (prunable)")
    else
      SKIPPED_WORKTREES+=("$wt")
    fi
    continue
  fi

  branch=$(git -C "$wt" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    head_short=$(git -C "$wt" rev-parse --short HEAD 2>/dev/null)
    branch_label="detached HEAD $head_short"
  else
    ahead=$(git -C "$wt" rev-list --count "origin/$BASE..HEAD" 2>/dev/null || echo "?")
    branch_label="$branch, $ahead commits ahead of $BASE"
  fi

  echo ""
  echo "=== $(basename "$wt") ($branch_label) ==="

  # Resolved once here, and every env write below is checked against it. A
  # worktree that cannot be resolved cannot be synced at all — the installs
  # would fail too — so it is reported and skipped rather than written into
  # on an unverified path.
  wt_real=$(cd "$wt" && pwd -P)
  if [ -z "$wt_real" ]; then
    echo "  skipped:  cannot resolve $wt — nothing synced here" >&2
    HAD_FAILURE=1
    continue
  fi

  # --- Env sync: copy where absent or identical, refuse where diverged ---
  # A secondary env file that differs from primary's is a deliberate local
  # override far more often than it is drift, so it is reported and left alone.
  # This used to overwrite it and keep a `.before-sync-<timestamp>` copy, which
  # made the backup load-bearing: it could fail, it could be raced by a
  # same-minute rerun, and it left a second copy of the secret in the worktree
  # for `git add -A` to stage. Refusing the write needs none of that.
  env_copied=0
  env_diverged=()
  env_written=()
  for f in "${ENV_FILES[@]}"; do
    src="$PRIMARY/$f"
    dst="$wt/$f"
    if [ ! -f "$src" ]; then
      continue
    fi
    if [ -L "$dst" ]; then
      # `[ -f "$dst" ]` below follows a symlink to a regular file, and so does
      # `cp` writing to it — a secondary worktree whose env path is a symlink
      # would have this write primary's secrets through it to wherever it
      # resolves, worktree boundary or not. Refuse rather than resolve it.
      echo "  env:      $f is a symlink at $wt — refusing to write through it" >&2
      HAD_FAILURE=1
      continue
    fi
    if [ -e "$dst" ] && [ ! -f "$dst" ]; then
      # A DIRECTORY named .env passes every other check here: -L is false, its
      # OWN dirname is the worktree root so the containment test below passes,
      # and -f is false so the divergence compare is skipped as though nothing
      # were there. `cp file dir` then writes $dst/.env — through a nested
      # symlink, if the directory holds one, straight out of the worktree.
      # Anything that exists and is not a regular file is refused rather than
      # reasoned about; the symlink case above is the one exception, and it is
      # refused too.
      echo "  env:      $f at $wt exists and is not a regular file — refusing" >&2
      HAD_FAILURE=1
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    # The symlink guard above covers the leaf name only. A parent directory
    # that is itself a symlink stays traversable through both `mkdir -p` and
    # `cp`, which puts the write outside the worktree just as effectively — so
    # what must be inside $wt is the RESOLVED parent, not the spelled one. An
    # unreadable parent leaves $dst_dir empty and fails the test below, which
    # is the safe direction. `mkdir -p` above can still create an empty
    # directory outside $wt before that refusal fires — a stray directory, not
    # a leaked secret, which is the half that matters here.
    #
    # This runs BEFORE the divergence check below, not after, and the order is
    # the whole point: `[ -f "$dst" ]` and `cmp` follow a symlinked parent just
    # as happily as `cp` does. Comparing first reported an out-of-worktree file
    # as a deliberate local override — exit 0, and a report telling the
    # developer to hand-copy into a path that is not in the worktree at all.
    dst_dir=$(cd "$(dirname "$dst")" && pwd -P)
    case "${dst_dir:-}/" in
      "$wt_real"/*) ;;
      *)
        echo "  env:      $f resolves to ${dst_dir:-an unreadable path}, outside $wt — refusing" >&2
        HAD_FAILURE=1
        continue
        ;;
    esac
    if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
      # Not a failure, a reported skip — like the pull's own "on feature
      # branch". A deliberate override that made the exit status non-zero on
      # every future sync of that worktree would teach a caller to stop
      # reading the exit status at all.
      env_diverged+=("$f")
      DIVERGED_FILES+=("$wt/$f")
      continue
    fi
    if ! cp "$src" "$dst"; then
      # Every other leg here sets HAD_FAILURE. This one used to increment
      # env_copied straight after an unchecked `cp`, so an unwritable
      # destination was reported — and exited — as a clean sync.
      echo "  env:      FAILED to copy $f into $wt" >&2
      HAD_FAILURE=1
      continue
    fi
    env_written+=("$f")
    env_copied=$((env_copied + 1))
  done
  if [ ${#env_diverged[@]} -gt 0 ]; then
    echo "  env:      $env_copied copied, ${#env_diverged[@]} left untouched (differs: ${env_diverged[*]})"
  else
    echo "  env:      $env_copied files copied (no differences)"
  fi

  # --- Optional pull ---
  # Runs BEFORE the installs below (though its line prints after them, matching
  # the output format documented in SKILL.md): a fast-forward can change
  # composer.lock or package-lock.json, and an install that already ran
  # against the pre-pull lockfile leaves the worktree on stale dependencies
  # with no signal that anything is wrong.
  if [ "$PULL" = true ]; then
    # An env file this same iteration just copied in is not necessarily
    # gitignored on $wt's OWN checked-out commit — a worktree stale enough to
    # need --pull is exactly one whose ignore rules may predate primary's. So
    # sync.sh's own writes are excluded here, by exact path rather than by a
    # wildcard, and any other uncommitted change still blocks the pull.
    status_pathspec=(':/')
    for f in "${env_written[@]}"; do
      status_pathspec+=(":(exclude,top)$f")
    done
    dirty=$(git -C "$wt" status --porcelain -- "${status_pathspec[@]}")
    if [ -n "$dirty" ]; then
      pull_msg="skipped (uncommitted changes)"
    elif [ -z "$branch" ]; then
      # Detached HEAD: fetch only, no checkout dance. The fetch's own exit
      # status is checked — an unchecked failure (auth, network) previously
      # still reported "fetched", leaving a stale worktree reporting itself
      # as current.
      if git -C "$wt" fetch origin "$BASE" --quiet 2>&1; then
        pull_msg="fetched origin/$BASE (detached, no checkout change)"
      else
        pull_msg="FAILED (could not fetch origin/$BASE)"
        HAD_FAILURE=1
      fi
    elif [ "$branch" = "$BASE" ]; then
      before=$(git -C "$wt" rev-parse HEAD)
      if git -C "$wt" fetch origin "$BASE" --quiet 2>&1; then
        if git -C "$wt" merge --ff-only "origin/$BASE" --quiet 2>&1; then
          after=$(git -C "$wt" rev-parse HEAD)
          if [ "$before" = "$after" ]; then
            pull_msg="already up to date"
          else
            new_commits=$(git -C "$wt" rev-list --count "$before..$after")
            pull_msg="fast-forwarded to origin/$BASE ($new_commits new commits)"
          fi
        else
          pull_msg="FAILED (could not fast-forward; manual resolution needed)"
          HAD_FAILURE=1
        fi
      else
        pull_msg="FAILED (could not fetch origin/$BASE)"
        HAD_FAILURE=1
      fi
    else
      pull_msg="skipped (on feature branch '$branch')"
    fi
  else
    pull_msg="skipped (--pull not set)"
  fi

  # --- Composer install (every composer.json, depth <= 3) ---
  found=0
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    found=1
    dir=$(dirname "$manifest")
    label=${dir#"$wt"}; label=${label#/}; label=${label:-.}
    if (cd "$dir" && composer install --no-interaction --quiet 2>&1); then
      echo "  composer: $label ok"
    else
      echo "  composer: $label FAILED"
      HAD_FAILURE=1
    fi
  done < <(find_manifests "$wt" composer.json)
  [ $found -eq 1 ] || echo "  composer: skipped (no composer.json)"

  # --- NPM install (every package.json, depth <= 3) ---
  found=0
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    found=1
    dir=$(dirname "$manifest")
    label=${dir#"$wt"}; label=${label#/}; label=${label:-.}
    # The order is deliberate: stderr joins the report on stdout, only npm's stdout is dropped.
    # shellcheck disable=SC2069
    if (cd "$dir" && npm install --silent 2>&1 >/dev/null); then
      echo "  npm:      $label ok"
    else
      echo "  npm:      $label FAILED"
      HAD_FAILURE=1
    fi
  done < <(find_manifests "$wt" package.json)
  [ $found -eq 1 ] || echo "  npm:      skipped (no package.json)"

  echo "  pull:     $pull_msg"
done

echo ""
if [ ${#SKIPPED_WORKTREES[@]} -gt 0 ]; then
  echo "⚠️  ${#SKIPPED_WORKTREES[@]} worktree(s) skipped — registered but not on disk:"
  for s in "${SKIPPED_WORKTREES[@]}"; do
    echo "    $s"
  done
  echo "    Run \`git worktree prune\` to deregister them. Nothing was synced into"
  echo "    them, so do not read the line below as covering them."
  echo ""
fi
if [ ${#DIVERGED_FILES[@]} -gt 0 ]; then
  echo "⚠️  ${#DIVERGED_FILES[@]} env file(s) left untouched because they differ from primary:"
  for d in "${DIVERGED_FILES[@]}"; do
    echo "    $d"
  done
  echo "    Copy one over by hand if that difference was drift rather than a"
  echo "    deliberate local override — nothing here overwrites it for you."
elif [ ${#SKIPPED_WORKTREES[@]} -gt 0 ]; then
  synced=$(( ${#SECONDARIES[@]} - ${#SKIPPED_WORKTREES[@]} ))
  echo "✓ Done. $synced of ${#SECONDARIES[@]} worktree(s) synced."
else
  echo "✓ Done. Every worktree's env files match primary."
fi

if [ "$HAD_FAILURE" -eq 1 ]; then
  echo "✗ One or more worktrees had a FAILED step above — see detail per worktree." >&2
  exit 1
fi
