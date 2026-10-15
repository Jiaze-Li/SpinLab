#!/usr/bin/env bash
# Proves the Plot Style Guard passes the real tree and rejects deliberate violations.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT_DIR/scripts/check_plot_style.sh"
FIX="$ROOT_DIR/scripts/tests/plot_style_guard_fixtures"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "== real tree must pass =="
"$GUARD"

echo "== clean fixture must pass (curve/grid colors allowed) =="
mkdir -p "$TMP/clean"; cp "$FIX/clean.swift.txt" "$TMP/clean/Clean.swift"
"$GUARD" "$TMP/clean"

status=0
for v in "$FIX"/violation_*.swift.txt; do
  name="$(basename "$v" .swift.txt)"
  mkdir -p "$TMP/$name"; cp "$v" "$TMP/$name/Renderer.swift"
  if "$GUARD" "$TMP/$name" >"$TMP/$name.out" 2>&1; then
    echo "FAIL: guard did not reject $name"; status=1
  else
    echo "ok: guard rejected $name -> $(grep -m1 'violation' "$TMP/$name.out" | sed 's/.*\[violation\] //' | cut -c1-90)"
  fi
done
exit $status
