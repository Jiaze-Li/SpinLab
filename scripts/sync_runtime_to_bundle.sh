#!/usr/bin/env bash
# Sync runtime config (what Jack sees in Rules panel) to bundled defaults (what
# fresh installs and tests see). Philosophy: the UI is the single source of truth.
#
# Run after editing rules in the desktop app, before committing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$HOME/Library/Application Support/SpinLab/config"
BUNDLE_DIR="$ROOT_DIR/Sources/SpinLabApp/config"

if [[ ! -d "$RUNTIME_DIR" ]]; then
  echo "[sync] Runtime dir not found: $RUNTIME_DIR" >&2
  exit 1
fi

FILES=(
  filename_tokenization.json
  import_filters.json
  measuring_condition.json
  sample_identification.json
  workflow.json
)

changed=0
for f in "${FILES[@]}"; do
  src="$RUNTIME_DIR/$f"
  dst="$BUNDLE_DIR/$f"
  if [[ ! -f "$src" ]]; then
    echo "[sync][skip] $f missing in runtime"
    continue
  fi
  if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
    continue
  fi
  cp "$src" "$dst"
  echo "[sync] $f → bundle"
  changed=$((changed + 1))
done

echo "[sync] done ($changed file(s) updated)"
