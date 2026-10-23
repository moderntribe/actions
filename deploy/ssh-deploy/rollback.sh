#!/usr/bin/env bash
#
# Runs ON THE SERVER. Repoints `current` at a previous release.
#
# Usage: rollback.sh <deploy-path> [release-id]
#   With no release-id, rolls back to the release just before `current`.
#   Release ids are UTC timestamps, so sorting by name sorts by age.
set -euo pipefail

DEPLOY_PATH=${1:?deploy-path required}
TARGET=${2:-}

RELEASES="$DEPLOY_PATH/releases"
ID_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$'

list_releases() {
  ls -1 "$RELEASES" 2>/dev/null | grep -E "$ID_PATTERN" | sort || true
}

CURRENT=""
if [ -L "$DEPLOY_PATH/current" ]; then
  CURRENT=$(basename "$(readlink "$DEPLOY_PATH/current")")
fi

echo "Releases (newest last):"
list_releases | while read -r id; do
  marker=" "
  [ "$id" = "$CURRENT" ] && marker="*"
  rev=$(head -c 7 "$RELEASES/$id/REVISION" 2>/dev/null || true)
  echo "  $marker $id ${rev:+($rev)}"
done

if [ -n "$TARGET" ]; then
  [[ "$TARGET" =~ $ID_PATTERN ]] || { echo "ERROR: release-id must look like 2026-10-02_18-58-31"; exit 1; }
  [ -d "$RELEASES/$TARGET" ] || { echo "ERROR: release $TARGET not found"; exit 1; }
  [ "$TARGET" != "$CURRENT" ] || { echo "ERROR: $TARGET is already current"; exit 1; }
else
  [ -n "$CURRENT" ] || { echo "ERROR: no current release to roll back from"; exit 1; }
  TARGET=$(list_releases | awk -v cur="$CURRENT" '$0 == cur { print prev; exit } { prev = $0 }')
  [ -n "$TARGET" ] || { echo "ERROR: no release older than $CURRENT"; exit 1; }
fi

# -r keeps `current` a relative link (-> releases/<id>) so the tree is relocatable.
ln -srfn "$RELEASES/$TARGET" "$DEPLOY_PATH/current.tmp"
mv -Tf "$DEPLOY_PATH/current.tmp" "$DEPLOY_PATH/current"
echo "rolled back: current -> releases/$TARGET"
