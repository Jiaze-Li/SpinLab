#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="$ROOT_DIR/Sources/SpinLabApp/config"
RUNTIME_DIR="${SYNC_RUNTIME_DIR:-$HOME/Library/Application Support/SpinLab/config}"

if [[ ! -d "$RUNTIME_DIR" ]]; then
  echo "[sync-rules] Runtime config dir not found: $RUNTIME_DIR"
  exit 1
fi

RUNTIME_FILE="$RUNTIME_DIR/filename_rules.json"
BUNDLE_FILE="$BUNDLE_DIR/filename_rules.json"

if [[ ! -f "$RUNTIME_FILE" ]]; then
  echo "[sync-rules] Runtime filename_rules.json not found. Nothing to sync."
  exit 0
fi

if [[ ! -f "$BUNDLE_FILE" ]]; then
  echo "[sync-rules] Bundle filename_rules.json not found at: $BUNDLE_FILE"
  exit 1
fi

RUNTIME_HASH="$(shasum -a 256 "$RUNTIME_FILE" | awk '{print $1}')"
BUNDLE_HASH="$(shasum -a 256 "$BUNDLE_FILE" | awk '{print $1}')"

if [[ "$RUNTIME_HASH" == "$BUNDLE_HASH" ]]; then
  echo "[sync-rules] Already in sync. Hash: ${BUNDLE_HASH:0:12}"
  exit 0
fi

cp "$RUNTIME_FILE" "$BUNDLE_FILE"
echo "[sync-rules] Synced filename_rules.json"
echo "  runtime: ${RUNTIME_HASH:0:12}"
echo "  bundle:  ${BUNDLE_HASH:0:12} → ${RUNTIME_HASH:0:12}"
