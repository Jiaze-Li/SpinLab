#!/usr/bin/env bash
set -euo pipefail

app_bundle="/Applications/SpinLab.app"
desktop_bundle="$HOME/Desktop/SpinLab.app"
macos_bin="$app_bundle/Contents/MacOS/SpinLab"
resources_dir="$app_bundle/Contents/Resources"

if [[ ! -d "$app_bundle" ]]; then
  echo "Error: missing app bundle: $app_bundle"
  exit 1
fi

if [[ -e "$desktop_bundle" ]]; then
  echo "Error: forbidden Desktop app bundle exists: $desktop_bundle"
  exit 1
fi

if [[ ! -f "$macos_bin" ]]; then
  echo "Error: missing executable: $macos_bin"
  exit 1
fi

if [[ ! -x "$macos_bin" ]]; then
  echo "Error: executable is not marked executable: $macos_bin"
  exit 1
fi

if [[ ! -d "$resources_dir" ]]; then
  echo "Error: missing resources directory: $resources_dir"
  exit 1
fi

if find "$app_bundle" -type d \( -name '*Tests*.bundle' -o -name '*.xctest' \) | grep -q .; then
  echo "Error: test bundle content found inside app bundle"
  find "$app_bundle" -type d \( -name '*Tests*.bundle' -o -name '*.xctest' \)
  exit 1
fi

codesign_output="$(codesign --verify --deep --strict --verbose=2 "$app_bundle" 2>&1)" || {
  echo "$codesign_output"
  echo "Error: codesign verification failed"
  exit 1
}
echo "$codesign_output"
if echo "$codesign_output" | grep -Eiq 'malformed|resource.*(modified|missing|invalid)|code object is not signed'; then
  echo "Error: malformed resource sealing or signature issue detected"
  exit 1
fi

if ! command -v mdls >/dev/null 2>&1; then
  echo "Warning: mdls unavailable; skipping Spotlight content-type check"
else
  mdls_tree_output=""
  mdls_type_output=""
  mdls_ok=true

  if ! mdls_tree_output="$(mdls -name kMDItemContentTypeTree "$app_bundle" 2>/dev/null)"; then
    mdls_ok=false
  fi
  if ! mdls_type_output="$(mdls -name kMDItemContentType "$app_bundle" 2>/dev/null)"; then
    mdls_ok=false
  fi

  if [[ "$mdls_ok" == false ]]; then
    echo "Warning: mdls metadata unavailable; skipping Spotlight content-type check"
  else
    mdls_combined="$mdls_tree_output"$'\n'"$mdls_type_output"
    if echo "$mdls_combined" | grep -q 'com.apple.application-bundle'; then
      :
    elif echo "$mdls_combined" | grep -q '(null)'; then
      echo "Warning: mdls returned null metadata; Spotlight has not classified this bundle yet"
    else
      echo "Error: bundle is not identified as com.apple.application-bundle"
      echo "$mdls_tree_output"
      echo "$mdls_type_output"
      exit 1
    fi
  fi
fi

echo "App bundle verification passed: $app_bundle"
