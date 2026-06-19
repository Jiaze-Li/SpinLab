#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app_path="/Applications/SpinLab.app"
desktop_shadow="$HOME/Desktop/SpinLab.app"

cd "$repo_root"

check_output=""
check_status=0
if check_output="$(./scripts/check_required_actions.sh 2>&1)"; then
  check_status=0
else
  check_status=$?
fi

if [[ -n "$check_output" ]]; then
  printf '%s\n' "$check_output"
fi

if [[ $check_status -ne 0 ]]; then
  exit "$check_status"
fi

requires_build=false
if grep -Fq "Required: ./scripts/build_desktop_app.sh debug" <<<"$check_output"; then
  requires_build=true
fi

if [[ "$requires_build" == true ]]; then
  ./scripts/build_desktop_app.sh debug
fi

if [[ ! -d "$app_path" ]]; then
  echo "Error: $app_path does not exist"
  exit 1
fi

if [[ -e "$desktop_shadow" ]]; then
  echo "Error: remove $desktop_shadow; only $app_path should exist"
  exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"

echo "Version: $version"
echo "CFBundleVersion: $build_version"
echo "Desktop shadow: absent"
