#!/usr/bin/env bash
#
# Runs ON THE SERVER. Finalizes a freshly-rsynced release:
#   1. ensures base dirs exist (first-deploy setup)
#   2. symlinks persistent shared items into the release
#   3. atomically flips `current` to the new release (rename(2))
#   4. rotates old releases, keeping the newest N
#
# Usage: finalize-release.sh <deploy-path> <release-id> <keep-releases>
#   shared items ("src:dest" pairs, newline separated) are read from stdin.
set -euo pipefail

DEPLOY_PATH=${1:?deploy-path required}
RELEASE_ID=${2:?release-id required}
KEEP=${3:-2}

RELEASES="$DEPLOY_PATH/releases"
SHARED="$DEPLOY_PATH/shared"
NEW="$RELEASES/$RELEASE_ID"

[ -d "$NEW" ] || { echo "ERROR: release $NEW not found (rsync did not run?)"; exit 1; }
mkdir -p "$RELEASES" "$SHARED"

# --- 2. symlink shared items into the new release --------------------------
# Each line is "src:dest". `src` is under $SHARED; `dest` is under the release.
while IFS=: read -r src dest; do
  [ -z "${src:-}" ] && continue
  s="$SHARED/$src"
  t="$NEW/$dest"

  # Auto-create a missing shared source as a directory (e.g. uploads on first
  # deploy). A shared FILE (e.g. local-config.php) must be seeded beforehand;
  # if it is missing it is created here as an empty dir, which surfaces the
  # setup mistake loudly rather than silently shipping without config.
  [ -e "$s" ] || mkdir -p "$s"

  mkdir -p "$(dirname "$t")"
  rm -rf "$t"
  ln -sfn "$s" "$t"
  echo "linked $dest -> $s"
done

# --- 3. atomic flip --------------------------------------------------------
# ln into a temp name then rename over `current`: readers never see a
# half-built release, and the swap cannot leave `current` dangling.
ln -sfn "$NEW" "$DEPLOY_PATH/current.tmp"
mv -Tf "$DEPLOY_PATH/current.tmp" "$DEPLOY_PATH/current"
echo "current -> $NEW"

# --- 4. rotate old releases ------------------------------------------------
# Release dirs are machine timestamps (no spaces/newlines), so this is safe.
cd "$RELEASES"
ls -1dt */ 2>/dev/null | tail -n "+$((KEEP + 1))" | while read -r old; do
  echo "pruning old release $old"
  rm -rf "${old%/}"
done
