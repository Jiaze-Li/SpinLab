#!/usr/bin/env bash
# Read-only: reports whether the Controls Contract check is a REQUIRED status check on `main`
# (AC9 / spec invariant I16). Never modifies repository settings.
# Exit 0 = required and enforced; 1 = not enforced (HUMAN REQUIRED to configure); 2 = cannot determine.
set -uo pipefail
REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)}"
CHECK_NAME="${CONTROLS_CONTRACT_CHECK_NAME:-Controls Contract}"
[[ -n "$REPO" ]] || { echo "[main-required-checks] cannot determine repository"; exit 2; }
rules="$(gh api "repos/$REPO/rules/branches/main" 2>&1)" || { echo "[main-required-checks] cannot read rules: $rules"; exit 2; }
if echo "$rules" | python3 -c '
import json,sys
name=sys.argv[1]
rules=json.load(sys.stdin)
for r in rules:
    if r.get("type")=="required_status_checks":
        for c in r.get("parameters",{}).get("required_status_checks",[]):
            if c.get("context")==name: sys.exit(0)
sys.exit(1)
' "$CHECK_NAME"; then
  echo "[main-required-checks] ENFORCED: '$CHECK_NAME' is a required status check on main"
  exit 0
fi
echo "[main-required-checks] NOT ENFORCED: '$CHECK_NAME' is not a required status check on main — HUMAN REQUIRED (repository ruleset change needs the owner's authorization)"
exit 1
