#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

resolve_base_ref() {
  if [[ -n "${RULE_GUARD_BASE_REF:-}" ]]; then
    echo "$RULE_GUARD_BASE_REF"
    return 0
  fi

  if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    echo "origin/main"
    return 0
  fi

  if git rev-parse --verify --quiet HEAD~1 >/dev/null 2>&1; then
    echo "HEAD~1"
    return 0
  fi

  echo ""
}

runtime_rule_hash_report() {
  local runtime_dir="${RULE_GUARD_RUNTIME_RULES_DIR:-}"
  if [[ -z "$runtime_dir" ]]; then
    return 0
  fi
  if [[ ! -d "$runtime_dir" ]]; then
    echo "[rule-guard][warn] Runtime rules dir not found: $runtime_dir"
    return 0
  fi

  echo "[rule-guard] Runtime rules hash report: $runtime_dir"
  local files=(
    "workflow_match_rules.json"
    "sample_id_rules.json"
    "conditions_rules.json"
    "substrate_rules.json"
    "measurement_tag_rules.json"
  )

  for name in "${files[@]}"; do
    local runtime_file="$runtime_dir/$name"
    if [[ ! -f "$runtime_file" ]]; then
      echo "[rule-guard][warn] Runtime override missing: $name"
      continue
    fi

    local runtime_hash
    runtime_hash="$(shasum -a 256 "$runtime_file" | awk '{print $1}')"
    local repo_file="Sources/SpinLabApp/config/$name"
    if [[ -f "$repo_file" ]]; then
      local repo_hash
      repo_hash="$(shasum -a 256 "$repo_file" | awk '{print $1}')"
      if [[ "$runtime_hash" == "$repo_hash" ]]; then
        echo "[rule-guard] $name runtime=$runtime_hash repo=$repo_hash (match)"
      else
        echo "[rule-guard][warn] $name runtime=$runtime_hash repo=$repo_hash (diff)"
      fi
    else
      echo "[rule-guard][warn] $name runtime=$runtime_hash repo=<missing default>"
    fi
  done
}

is_guard_target() {
  case "$1" in
    Sources/SpinLabApp/config/filename_rules.json)
      return 0
      ;;
    Sources/SpinLabApp/Import/Rules/RuleLoader.swift)
      return 0
      ;;
    Sources/SpinLabApp/Import/Rules/ConditionRulesHandbookStore.swift)
      return 0
      ;;
    Sources/SpinLabApp/Import/Rules/RuleCanonicalizer.swift)
      return 0
      ;;
    Sources/SpinLabApp/Import/Parse/FilenameRuleParser.swift)
      return 0
      ;;
    Sources/SpinLabApp/Import/Route/RoutePlanner.swift)
      return 0
      ;;
    Sources/SpinLabApp/Import/Match/DrawerMatchEngine.swift)
      return 0
      ;;
    Sources/SpinLabApp/Import/Evaluate/PendingRoutingRuleBook.swift)
      return 0
      ;;
    Sources/SpinLabApp/Import/Evaluate/PendingRoutingSnapshotEvaluator.swift)
      return 0
      ;;
    Tests/SpinLabAppTests/V210ImportAndParseTests.swift)
      return 0
      ;;
    Tests/SpinLabAppTests/V213InboxClosedLoopTests.swift)
      return 0
      ;;
    Tests/SpinLabAppTests/V221RoutingExplanationTests.swift)
      return 0
      ;;
    Tests/SpinLabAppTests/V225RulesConfigContractTests.swift)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

BASE_REF="$(resolve_base_ref)"
runtime_rule_hash_report

if [[ -z "$BASE_REF" ]]; then
  echo "[rule-guard] Base ref not found. Running guard suites in safe mode."
  SHOULD_RUN=1
else
  echo "[rule-guard] Comparing changes against: $BASE_REF"
  CHANGED_FILES="$(git diff --name-only "$BASE_REF"...HEAD)"

  SHOULD_RUN=0
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if is_guard_target "$path"; then
      SHOULD_RUN=1
      break
    fi
  done <<< "$CHANGED_FILES"

  if [[ "$SHOULD_RUN" -eq 0 ]]; then
    echo "[rule-guard] No rule-critical files changed. Skipping guard suites."
    exit 0
  fi
fi

echo "[rule-guard] Rule-critical changes detected. Running golden suites..."
swift test \
  --filter V210ImportAndParseTests \
  --filter V213InboxClosedLoopTests \
  --filter V221RoutingExplanationTests \
  --filter V225RulesConfigContractTests

echo "[rule-guard] PASS"
