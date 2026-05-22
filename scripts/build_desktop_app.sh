#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME_DEFAULT="SpinLab"
APP_NAME="${SPINLAB_APP_NAME:-${APP_NAME_DEFAULT}}"
PRODUCT_NAME="SpinLabApp"
APP_BUNDLE_NAME="${APP_NAME}.app"
APP_BUNDLE_PATH="/Applications/${APP_BUNDLE_NAME}"
BUILD_CONFIGURATION="${1:-debug}"
APP_VERSION_SOURCE="${ROOT_DIR}/Sources/SpinLabApp/App/AppVersion.swift"
APP_ICON_SOURCE="${ROOT_DIR}/Resources/AppIcon.icns"

if [[ "${BUILD_CONFIGURATION}" != "debug" && "${BUILD_CONFIGURATION}" != "release" ]]; then
  echo "Usage: $0 [debug|release]"
  exit 1
fi

cd "${ROOT_DIR}"

APP_VERSION_RAW=""
if [[ -f "${APP_VERSION_SOURCE}" ]]; then
  APP_VERSION_RAW="$(sed -n 's/^[[:space:]]*static let library = "\([^"]*\)".*/\1/p' "${APP_VERSION_SOURCE}" | head -n 1)"
fi
APP_VERSION="${SPINLAB_APP_VERSION:-${APP_VERSION_RAW:-0.1.0}}"
APP_BUILD_VERSION="${SPINLAB_APP_BUILD_VERSION:-$(date +%Y%m%d%H%M)}"

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
if [[ -d "${APP_BUNDLE_PATH}" ]]; then
  rm -rf "${APP_BUNDLE_PATH}"
fi
mkdir -p "${APP_BUNDLE_PATH}/Contents/MacOS"

cp "${BIN_PATH}" "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"

if [[ -f "${APP_ICON_SOURCE}" ]]; then
  mkdir -p "${APP_BUNDLE_PATH}/Contents/Resources"
  cp "${APP_ICON_SOURCE}" "${APP_BUNDLE_PATH}/Contents/Resources/AppIcon.icns"
fi

BIN_DIR="$(dirname "${BIN_PATH}")"
for bundle in "${BIN_DIR}"/*.bundle; do
  [[ -e "${bundle}" ]] || continue
  cp -R "${bundle}" "${APP_BUNDLE_PATH}/Contents/MacOS/"
done

cat > "${APP_BUNDLE_PATH}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.spinlab.app</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD_VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
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

echo "Version: ${APP_VERSION} (${APP_BUILD_VERSION})"
echo "Done: ${APP_BUNDLE_PATH}"
