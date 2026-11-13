#!/usr/bin/env bash
# Self-test for the UI rules guard: it must reject new violations and accept clean/shrinking code.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK=(python3 -I "$ROOT_DIR/scripts/ui_rules_check.py")
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/src"
fail() { echo "SELF-TEST FAILED: $1"; exit 1; }

cat > "$TMP/src/Clean.swift" <<'SW'
// .padding(12) in a comment is ignored
struct Clean { var body: some View { VStack(spacing: AppSpacing.md) { Text("x").padding(AppSpacing.lg).padding(.horizontal, AppSpacing.xxl).padding(0) } } }
SW
echo '{}' > "$TMP/baseline.json"
"${CHECK[@]}" --root "$TMP/src" --baseline "$TMP/baseline.json" >/dev/null || fail "clean file rejected"

cat > "$TMP/src/Bad.swift" <<'SW'
struct Bad { var body: some View { VStack(spacing: 10) { Text("x").padding(20).padding(.top, 18).font(.caption) } } }
SW
if "${CHECK[@]}" --root "$TMP/src" --baseline "$TMP/baseline.json" >/dev/null; then fail "new violations accepted"; fi

"${CHECK[@]}" --root "$TMP/src" --baseline "$TMP/baseline.json" --update-baseline >/dev/null
"${CHECK[@]}" --root "$TMP/src" --baseline "$TMP/baseline.json" >/dev/null || fail "baselined violations rejected"

echo 'struct Bad { var body: some View { Text("x").padding(20).font(.caption) } }' > "$TMP/src/Bad.swift"
"${CHECK[@]}" --root "$TMP/src" --baseline "$TMP/baseline.json" >/dev/null || fail "shrinking violations rejected"

echo 'struct Bad { var body: some View { Text("x").padding(20).padding(8).padding(6).padding(4).font(.caption) } }' > "$TMP/src/Bad.swift"
if "${CHECK[@]}" --root "$TMP/src" --baseline "$TMP/baseline.json" >/dev/null; then fail "growing violations accepted"; fi
# "//" inside a string literal must not hide a later violation on the same line
printf '%s\n' 'struct S { var body: some View { Text("https://x.y").padding(20) } }' > "$TMP/src/Bad.swift"
echo '{}' > "$TMP/empty.json"
if "${CHECK[@]}" --root "$TMP/src" --baseline "$TMP/empty.json" >/dev/null; then fail "violation after // in a string missed"; fi

# the baseline may not be raised relative to the target branch
echo '{"A.swift":{"numeric-spacing":2}}' > "$TMP/base.json"
echo '{"B.swift":{"numeric-spacing":2}}' > "$TMP/moved.json"
echo '{"A.swift":{"numeric-spacing":3}}' > "$TMP/raised.json"
mkdir -p "$TMP/none"
"${CHECK[@]}" --root "$TMP/none" --baseline "$TMP/moved.json" --base-baseline "$TMP/base.json" >/dev/null || fail "rename-only baseline rejected"
if "${CHECK[@]}" --root "$TMP/none" --baseline "$TMP/raised.json" --base-baseline "$TMP/base.json" >/dev/null; then fail "raised baseline accepted"; fi
echo "ui-rules self-test: OK"
