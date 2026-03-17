#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SpinLab"
PRODUCT_NAME="SpinLabApp"
APP_BUNDLE_NAME="${APP_NAME}.app"
APP_BUNDLE_PATH="/Users/jack/Desktop/${APP_BUNDLE_NAME}"
BUILD_CONFIGURATION="${1:-debug}"

if [[ "${BUILD_CONFIGURATION}" != "debug" && "${BUILD_CONFIGURATION}" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

cd "${ROOT_DIR}"

echo "Building ${PRODUCT_NAME} (${BUILD_CONFIGURATION})..."
swift build -c "${BUILD_CONFIGURATION}"

if [[ "${BUILD_CONFIGURATION}" == "release" ]]; then
  BIN_PATH="${ROOT_DIR}/.build/arm64-apple-macosx/release/${PRODUCT_NAME}"
else
  BIN_PATH="${ROOT_DIR}/.build/arm64-apple-macosx/debug/${PRODUCT_NAME}"
fi

if [[ ! -f "${BIN_PATH}" ]]; then
  echo "Build output not found at ${BIN_PATH}"
  exit 1
fi

echo "Packaging app bundle at ${APP_BUNDLE_PATH}..."
rm -rf "${APP_BUNDLE_PATH}"
mkdir -p "${APP_BUNDLE_PATH}/Contents/MacOS"

cp "${BIN_PATH}" "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"

cat > "${APP_BUNDLE_PATH}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>SpinLab</string>
  <key>CFBundleDisplayName</key>
  <string>SpinLab</string>
  <key>CFBundleIdentifier</key>
  <string>com.spinlab.app</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleExecutable</key>
  <string>SpinLab</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign to avoid launch restrictions on manually bundled apps.
codesign --force --deep --sign - "${APP_BUNDLE_PATH}" >/dev/null 2>&1 || true

echo "Done: ${APP_BUNDLE_PATH}"
