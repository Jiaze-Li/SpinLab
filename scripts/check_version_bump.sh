#!/usr/bin/env bash
# Fails when the app version was not bumped relative to a base ref.
# Usage: check_version_bump.sh <base-ref>   (e.g. origin/main)
set -euo pipefail
BASE_REF="${1:?usage: check_version_bump.sh <base-ref>}"
FILE="Sources/SpinLabApp/App/AppVersion.swift"
extract() { sed -n 's/^[[:space:]]*static let library = "v\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/p' | head -n 1; }

NEW="$(extract < "$FILE")"
OLD="$(git show "${BASE_REF}:${FILE}" | extract)"
[[ -n "$NEW" && -n "$OLD" ]] || { echo "Could not read version (new='$NEW' old='$OLD')"; exit 2; }

higher() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" && "$1" != "$2" ]]; }
if higher "$NEW" "$OLD"; then
  echo "OK: version bumped v${OLD} -> v${NEW}"
else
  echo "Version not bumped: still v${NEW} (main is v${OLD})."
  echo "Bump the version per CLAUDE.md 'Versioning', or add the 'no-release' label for docs/CI-only changes."
  exit 1
fi
