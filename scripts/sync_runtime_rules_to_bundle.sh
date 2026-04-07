#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_DIR="$ROOT_DIR/Sources/SpinLabApp/config"
RUNTIME_DIR="${SYNC_RUNTIME_DIR:-$HOME/Library/Application Support/SpinLab/config}"

if [[ ! -d "$RUNTIME_DIR" ]]; then
  echo "[sync-rules] Runtime config dir not found: $RUNTIME_DIR"
  exit 1
fi

# Only sync separated override files.
# filename_rules.json is NOT synced because the bundle version is self-contained
# (includes registry, full measurementNameRules, etc.) while the runtime version
# is a base layer that relies on overrides to be complete.
RULE_FILES=(
  "workflow_match_rules.json"
  "sample_id_rules.json"
  "substrate_rules.json"
  "measurement_tag_rules.json"
)

synced=0
skipped=0

for name in "${RULE_FILES[@]}"; do
  runtime_file="$RUNTIME_DIR/$name"
  bundle_file="$BUNDLE_DIR/$name"

  if [[ ! -f "$runtime_file" ]]; then
    echo "[sync-rules] skip $name (not in runtime)"
    ((skipped++))
    continue
  fi

  runtime_hash="$(shasum -a 256 "$runtime_file" | awk '{print $1}')"

  if [[ -f "$bundle_file" ]]; then
    bundle_hash="$(shasum -a 256 "$bundle_file" | awk '{print $1}')"
    if [[ "$runtime_hash" == "$bundle_hash" ]]; then
      echo "[sync-rules] ok   $name (in sync)"
      continue
    fi
    echo "[sync-rules] sync $name  ${bundle_hash:0:12} → ${runtime_hash:0:12}"
  else
    echo "[sync-rules] new  $name"
  fi

  cp "$runtime_file" "$bundle_file"
  ((synced++))
done

echo "[sync-rules] Done: $synced synced, $skipped skipped"
