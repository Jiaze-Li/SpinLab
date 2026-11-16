#!/usr/bin/env bash
# Tests for scripts/check_version_bump.sh using a throwaway git repository.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/check_version_bump.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FILE="Sources/SpinLabApp/App/AppVersion.swift"

cd "$TMP"
git init -q -b main .
git config user.email t@example.com
git config user.name t
mkdir -p "$(dirname "$FILE")"
setv() { printf 'enum AppVersion {\n    static let library = "v%s"\n}\n' "$1" > "$FILE"; }
setv 5.19.1
git add -A && git commit -q -m base

fail=0
# expect <name> <0|1> <version> <labels> <body>
expect() {
  local name="$1" want="$2" ver="$3" labels="$4" body="$5" got
  setv "$ver"
  PR_LABELS="$labels" PR_BODY="$body" bash "$SCRIPT" main >/dev/null 2>&1
  got=$?
  if [[ "$got" == "$want" ]]; then echo "ok   - $name"; else echo "FAIL - $name (want exit $want, got $got)"; fail=1; fi
}

expect "no bump rejected"                     1 5.19.1 "" "Version: v5.19.1 - nothing"
expect "patch with reason ok"                 0 5.19.2 "" "Version: v5.19.2 - fixes a crash"
expect "minor with reset patch ok"            0 5.20.0 "" "Version: v5.20.0 - new capability"
expect "minor with nonzero patch rejected"    1 5.20.1 "" "Version: v5.20.1 - new capability"
expect "missing Version line rejected"        1 5.19.2 "" "Fixes a crash"
expect "Version line without reason rejected" 1 5.19.2 "" "Version: v5.19.2"
expect "Version line with wrong number rejected" 1 5.19.2 "" "Version: v5.19.3 - fixes a crash"
expect "Version line with longer number rejected" 1 5.19.2 "" "Version: v5.19.20 - fixes a crash"
expect "major without label rejected"         1 6.0.0  "" "Version: v6.0.0 - publish done"
expect "major with label ok"                  0 6.0.0  "major-approved" "Version: v6.0.0 - publish done"
expect "major with nonzero minor rejected"    1 6.1.0  "major-approved" "Version: v6.1.0 - publish done"
expect "no-release docs only ok"              0 5.19.1 "no-release" "docs only"
expect "no-release with unlabeled major rejected" 1 6.0.0 "no-release" "docs only"
expect "no-release with approved major ok"    0 6.0.0  "no-release,major-approved" "docs only"
expect "no-release downgrade rejected"        1 5.18.0 "no-release" "docs only"
expect "no-release minor with nonzero patch rejected" 1 5.20.1 "no-release" "docs only"
expect "no-release major with nonzero minor rejected" 1 6.1.0 "no-release,major-approved" "docs only"
expect "downgrade rejected"                   1 5.18.0 "" "Version: v5.18.0 - oops"

exit "$fail"
