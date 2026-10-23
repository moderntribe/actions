#!/usr/bin/env bash
#
# Runs ON THE SERVER. Finalizes a freshly-rsynced release. The build is synced
# into releases/<id>.tmp, so a failed or interrupted deploy never leaves a
# half-built folder that looks like a release:
#   1. ensures base dirs exist (first-deploy setup) and drops stale *.tmp folders
#   2. symlinks persistent shared items into the release
#   3. renames releases/<id>.tmp to releases/<id>
#   4. atomically flips `current` to the new release (rename(2))
#   5. rotates old releases, keeping the newest N
#
# Usage: finalize-release.sh <deploy-path> <release-id> <keep-releases> [revision]
#   shared items ("src:dest" pairs, newline separated) are read from stdin.
#
# Requires GNU coreutils on the server (mv -T for the atomic flip, ln -sr for
# relative symlinks).
set -euo pipefail

DEPLOY_PATH=${1:?deploy-path required}
RELEASE_ID=${2:?release-id required}
KEEP=${3:-2}
REVISION=${4:-}

RELEASES="$DEPLOY_PATH/releases"
SHARED="$DEPLOY_PATH/shared"
NEW="$RELEASES/$RELEASE_ID.tmp"
FINAL="$RELEASES/$RELEASE_ID"

[ -d "$NEW" ] || { echo "ERROR: release $NEW not found (rsync did not run?)"; exit 1; }
[ ! -e "$FINAL" ] || { echo "ERROR: release $FINAL already exists"; exit 1; }
mkdir -p "$RELEASES" "$SHARED"

# Leftovers from deploys that failed before this point. Deploys are serialized
# per environment, so none of these can be in use.
find "$RELEASES" -mindepth 1 -maxdepth 1 -type d -name '*.tmp' ! -path "$NEW" \
  -exec rm -rf {} + -exec echo "removed stale {}" \;

# --- 2. symlink shared items into the new release --------------------------
# Each line is "src:dest". `src` is under $SHARED; `dest` is under the release.
# `|| [ -n ... ]` keeps a final line that has no trailing newline.
while IFS=: read -r src dest || [ -n "${src:-}" ]; do
  [ -z "${src:-}" ] && continue
  s="$SHARED/$src"
  t="$NEW/$dest"

  # Auto-create only the uploads dir on first deploy. Every other shared source
  # must already exist (seeded via shared-seeds, or set up during server setup);
  # abort rather than symlink to a missing source and flip to a broken release.
  if [ "$src" = "uploads" ] && [ ! -e "$s" ]; then
    mkdir -p "$s"
  elif [ ! -e "$s" ]; then
    echo "ERROR: shared source $s missing (seed it or set it up first)"; exit 1
  fi

  mkdir -p "$(dirname "$t")"
  rm -rf "$t"
  # -r makes the link relative to its own location, so the tree keeps working
  # if <deploy-path> is moved or mounted under a different absolute path.
  ln -srfn "$s" "$t"
  echo "linked $dest -> shared/$src"
done

# Record which commit this release was built from (shown by rollback.sh).
[ -z "$REVISION" ] || printf '%s\n' "$REVISION" > "$NEW/REVISION"

# --- 3. promote the finished release ---------------------------------------
# The relative shared links keep working: the folder moves within releases/, so
# the link depth is unchanged.
mv -T "$NEW" "$FINAL"
NEW="$FINAL"

# --- 4. atomic flip --------------------------------------------------------
# ln into a temp name then rename over `current`: readers never see a
# half-built release, and the swap cannot leave `current` dangling.
# -r keeps `current` a relative link (-> releases/<id>) so the tree is relocatable.
ln -srfn "$NEW" "$DEPLOY_PATH/current.tmp"
mv -Tf "$DEPLOY_PATH/current.tmp" "$DEPLOY_PATH/current"
echo "current -> releases/$RELEASE_ID"

# --- 5. rotate old releases ------------------------------------------------
# Release ids are UTC timestamps, so name order is age order. Modified time is
# not: anything writing into a release changes it. Never prune the live release.
cd "$RELEASES"
LIVE=$(basename "$(readlink "$DEPLOY_PATH/current")")
ls -1 | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$' | sort -r \
  | tail -n "+$((KEEP + 1))" | while read -r old; do
  [ "$old" = "$LIVE" ] && continue
  echo "pruning old release $old"
  rm -rf "$old"
done
