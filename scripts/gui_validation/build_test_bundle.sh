#!/bin/zsh
# Build an independent GUI-test copy of SpinLab from the CURRENT checkout.
# Bundle id com.spinlab.guitest, never touches /Applications/SpinLab.app.
# Usage: build_test_bundle.sh <out-dir>   -> prints <out-dir>/SpinLabGUITest.app
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: $0 <out-dir>" >&2; exit 2; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$1/SpinLabGUITest.app"
cd "$ROOT"
REV="$(git rev-parse --short=12 HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then REV="${REV}-dirty"; echo "warn: tracked changes present; bundle labelled ${REV}" >&2; fi
swift build -c debug 2>&1 | tail -2
BIN_DIR=$(swift build -c debug --show-bin-path)
rm -rf "$OUT"; mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN_DIR/SpinLabApp" "$OUT/Contents/MacOS/SpinLabGUITest"
for b in "$BIN_DIR"/*.bundle; do [[ -d $b && $b != *Tests* ]] && cp -R "$b" "$OUT/Contents/Resources/"; done
cat > "$OUT/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SpinLabGUITest</string>
<key>CFBundleIdentifier</key><string>com.spinlab.guitest</string>
<key>CFBundleVersion</key><string>${REV}</string>
<key>CFBundleShortVersionString</key><string>${REV}</string>
<key>CFBundleExecutable</key><string>SpinLabGUITest</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
P
codesign --force --sign - "$OUT"
echo "$OUT"
