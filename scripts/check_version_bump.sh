#!/usr/bin/env bash
# Version Guard. Rules live in AGENTS.md, section "Versioning" (single source).
# Usage: check_version_bump.sh <base-ref>   (e.g. origin/main)
# Environment (set by CI from the pull request):
#   PR_LABELS  newline- or comma-separated label names
#   PR_BODY    pull request description
set -euo pipefail
BASE_REF="${1:?usage: check_version_bump.sh <base-ref>}"
FILE="Sources/SpinLabApp/App/AppVersion.swift"
RULES="AGENTS.md section 'Versioning'"
LABELS="${PR_LABELS:-}"
BODY="${PR_BODY:-}"

extract() { sed -n 's/^[[:space:]]*static let library = "v\([0-9]*\.[0-9]*\.[0-9]*\)".*/\1/p' | head -n 1; }

NEW="$(extract < "$FILE")"
OLD="$(git show "${BASE_REF}:${FILE}" | extract)"
[[ -n "$NEW" && -n "$OLD" ]] || { echo "Could not read version (new='$NEW' old='$OLD')"; exit 2; }

has_label() { printf '%s\n' "$LABELS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -Fxq "$1"; }

IFS=. read -r NMAJ NMIN NPAT <<<"$NEW"
IFS=. read -r OMAJ OMIN OPAT <<<"$OLD"

higher() { [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" && "$1" != "$2" ]]; }

# 1. A first-digit change always needs the major-approved label, even for no-release PRs.
if [[ "$NMAJ" != "$OMAJ" ]]; then
  if ! has_label "major-approved"; then
    echo "Major version change v${OLD} -> v${NEW} needs the 'major-approved' label."
    echo "Only add it after Jack explicitly approved this major version. See ${RULES}."
    exit 1
  fi
fi

# 2. Never go backwards, and lower digits reset when a higher digit moves (all PRs, including no-release).
if [[ "$NEW" != "$OLD" ]] && ! higher "$NEW" "$OLD"; then
  echo "Version went backwards: v${OLD} -> v${NEW}. See ${RULES}."
  exit 1
fi
if [[ "$NMAJ" != "$OMAJ" && ( "$NMIN" != "0" || "$NPAT" != "0" ) ]]; then
  echo "A major bump must reset minor and patch: expected v${NMAJ}.0.0, got v${NEW}. See ${RULES}."
  exit 1
fi
if [[ "$NMAJ" == "$OMAJ" && "$NMIN" != "$OMIN" && "$NPAT" != "0" ]]; then
  echo "A minor bump must reset patch: expected v${NMAJ}.${NMIN}.0, got v${NEW}. See ${RULES}."
  exit 1
fi

# no-release PRs (docs/CI only) skip the bump-required and reason checks.
if has_label "no-release"; then
  echo "OK: no-release PR (v${OLD} -> v${NEW})"
  exit 0
fi

# 3. The version must go up.
if ! higher "$NEW" "$OLD"; then
  echo "Version not bumped: still v${NEW} (main is v${OLD})."
  echo "Bump the version per ${RULES}, or add the 'no-release' label for docs/CI-only changes."
  exit 1
fi

# 4. The PR description must state the new version and why.
VLINE="$(printf '%s\n' "$BODY" | grep -E '^[[:space:]]*Version:[[:space:]]*' | head -n 1 || true)"
REASON="$(printf '%s' "$VLINE" | sed -E 's/^[[:space:]]*Version:[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*[-—:,.]*[[:space:]]*//')"
if [[ -z "$VLINE" || ! "$VLINE" =~ ^[[:space:]]*Version:[[:space:]]*v?${NEW//./\.}([^0-9.]|$) || -z "$REASON" || "$REASON" == "$VLINE" ]]; then
  echo "PR description must contain a line: 'Version: v${NEW} - <why this digit moved>'. See ${RULES}."
  exit 1
fi

echo "OK: version bumped v${OLD} -> v${NEW} (${REASON})"
