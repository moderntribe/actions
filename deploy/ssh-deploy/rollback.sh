#!/usr/bin/env bash
#
# Runs ON THE SERVER. Repoints `current` at a previous release.
#
# Usage: rollback.sh <deploy-path> [release-id]
#   With no release-id, rolls back to the previous release (2nd newest).
set -euo pipefail

DEPLOY_PATH=${1:?deploy-path required}
TARGET=${2:-}

RELEASES="$DEPLOY_PATH/releases"

if [ -n "$TARGET" ]; then
  DEST="$RELEASES/$TARGET"
else
  # Second-newest release directory = the one before current.
  DEST=$(ls -1dt "$RELEASES"/*/ 2>/dev/null | sed -n '2p')
fi

DEST=${DEST%/}
[ -n "$DEST" ] && [ -d "$DEST" ] || { echo "ERROR: rollback target not found ($DEST)"; exit 1; }

ln -sfn "$DEST" "$DEPLOY_PATH/current.tmp"
mv -Tf "$DEPLOY_PATH/current.tmp" "$DEPLOY_PATH/current"
echo "rolled back: current -> $DEST"
