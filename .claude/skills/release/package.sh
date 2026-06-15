#!/usr/bin/env bash
# Build the distributable MythicLoot.zip: just the addon folder, nothing else.
#
# The dev docs (CONTEXT.md, docs/, CHANGELOG.md, .github, .claude) all live
# OUTSIDE MythicLoot/, so zipping just that folder already leaves them out. This
# also strips macOS metadata and editor cruft so the archive is clean on any OS.
# The zip's top-level entry is `MythicLoot/`, so it extracts straight into
# Interface/AddOns/.
#
# Safe to run from anywhere inside the repo.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ADDON="MythicLoot"
OUT="$ADDON.zip"

if [[ ! -f "$ADDON/$ADDON.toc" ]]; then
  echo "error: $ADDON/$ADDON.toc not found — are you in the MythicLoot repo?" >&2
  exit 1
fi

rm -f "$OUT"

zip -r -X "$OUT" "$ADDON" \
  -x '*/.DS_Store' -x '.DS_Store' \
  -x '*/__MACOSX/*' \
  -x '*.swp' -x '*~' >/dev/null

echo "Built $OUT ($(du -h "$OUT" | cut -f1)):"
unzip -l "$OUT"
