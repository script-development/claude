#!/bin/bash
# Sync secondary git worktrees with the primary one.
# See ../SKILL.md for the design rationale and safety contract.

PULL=false
BASE=""
while [ $# -gt 0 ]; do
  case $1 in
    --pull) PULL=true ;;
    --base) shift; BASE=$1 ;;
    --base=*) BASE=${1#--base=} ;;
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

# Primary worktree is always the first entry in git worktree list
PRIMARY=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2; exit}')
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

# Env files: every gitignored .env* file in the primary, at any depth, skipping
# dependency dirs and our own backups. Paths are kept relative to the worktree root.
ENV_FILES=()
while IFS= read -r abs; do
  rel=${abs#"$PRIMARY"/}
  if git -C "$PRIMARY" check-ignore -q -- "$rel"; then
    ENV_FILES+=("$rel")
  fi
done < <(find "$PRIMARY" -type f -name '.env*' \
           -not -name '*.before-sync-*' \
           -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | sort)

TIMESTAMP=$(date +%Y-%m-%d-%H%M)
BACKUPS_CREATED=()

# Dependency manifests are looked up per worktree (they are tracked files).
find_manifests() { # $1 = worktree, $2 = manifest name
  find "$1" -maxdepth 3 -type f -name "$2" \
    -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' | sort
}

# Collect secondary worktrees (everything except the primary)
mapfile -t SECONDARIES < <(git -C "$PRIMARY" worktree list --porcelain | awk '/^worktree / {print $2}' | tail -n +2)

if [ ${#SECONDARIES[@]} -eq 0 ]; then
  echo "No secondary worktrees to sync."
  exit 0
fi

echo "Primary: $PRIMARY"
echo "Base branch: $BASE"
echo "Env files: ${#ENV_FILES[@]} gitignored .env* file(s) found in primary"
echo "Syncing ${#SECONDARIES[@]} secondary worktree(s)..."

for wt in "${SECONDARIES[@]}"; do
  if [ ! -d "$wt" ]; then
    echo ""
    echo "=== $(basename "$wt") ==="
    echo "  directory missing on disk, skipping"
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

  # --- Env sync with backup on divergence ---
  env_copied=0
  env_backed_up=()
  for f in "${ENV_FILES[@]}"; do
    src="$PRIMARY/$f"
    dst="$wt/$f"
    if [ ! -f "$src" ]; then
      continue
    fi
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
      backup="$dst.before-sync-$TIMESTAMP"
      cp "$dst" "$backup"
      env_backed_up+=("$f")
      BACKUPS_CREATED+=("$backup")
    fi
    cp "$src" "$dst"
    env_copied=$((env_copied + 1))
  done
  if [ ${#env_backed_up[@]} -gt 0 ]; then
    echo "  env:      $env_copied files copied (${#env_backed_up[@]} backed up: ${env_backed_up[*]})"
  else
    echo "  env:      $env_copied files copied (no differences)"
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
    if (cd "$dir" && npm install --silent 2>&1 >/dev/null); then
      echo "  npm:      $label ok"
    else
      echo "  npm:      $label FAILED"
    fi
  done < <(find_manifests "$wt" package.json)
  [ $found -eq 1 ] || echo "  npm:      skipped (no package.json)"

  # --- Optional pull ---
  if [ "$PULL" = true ]; then
    if [ -n "$(git -C "$wt" status --porcelain)" ]; then
      echo "  pull:     skipped (uncommitted changes)"
    elif [ -z "$branch" ]; then
      # Detached HEAD: fetch only, no checkout dance
      git -C "$wt" fetch origin "$BASE" --quiet 2>&1
      echo "  pull:     fetched origin/$BASE (detached, no checkout change)"
    elif [ "$branch" = "$BASE" ]; then
      before=$(git -C "$wt" rev-parse HEAD)
      git -C "$wt" fetch origin "$BASE" --quiet 2>&1
      if git -C "$wt" merge --ff-only "origin/$BASE" --quiet 2>&1; then
        after=$(git -C "$wt" rev-parse HEAD)
        if [ "$before" = "$after" ]; then
          echo "  pull:     already up to date"
        else
          new_commits=$(git -C "$wt" rev-list --count "$before..$after")
          echo "  pull:     fast-forwarded to origin/$BASE ($new_commits new commits)"
        fi
      else
        echo "  pull:     FAILED (could not fast-forward; manual resolution needed)"
      fi
    else
      echo "  pull:     skipped (on feature branch '$branch')"
    fi
  else
    echo "  pull:     skipped (--pull not set)"
  fi
done

echo ""
if [ ${#BACKUPS_CREATED[@]} -gt 0 ]; then
  echo "⚠️  ${#BACKUPS_CREATED[@]} env backup(s) created. Review before deleting:"
  for b in "${BACKUPS_CREATED[@]}"; do
    echo "    $b"
  done
else
  echo "✓ Done. No env backups needed — all worktrees were in sync."
fi
