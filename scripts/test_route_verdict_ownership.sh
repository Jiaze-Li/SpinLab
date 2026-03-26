#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/spinlab_route_verdict_ownership.XXXXXX)"
TMP_SWIFT="$TMP_DIR/main.swift"
TMP_BIN="$TMP_DIR/spinlab_route_verdict_ownership"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat > "$TMP_SWIFT" <<'SWIFT'
import Foundation

func assertOrFail(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let parsed = SpinLabDomain.ParsedFilenameHints(
    defaultSampleKey: "PN41",
    channelHints: [
        SpinLabDomain.ParsedChannelHint(channel: "ch2", sampleID: nil, tags: ["STO001"])
    ],
    substrateTags: ["STO001"]
)

let planner = SpinLabRoutePlanner()
let plan = planner.makeRoutePlan(from: parsed)
assertOrFail(plan.planningStatus == .reviewRequired, "planner status should remain provisional")
assertOrFail(plan.targets.first?.sampleKey == "PN41 - STO(001)", "planner target mismatch")

let evaluator = PendingRoutingSnapshotEvaluator()
let snapshotMatched = evaluator.makeSnapshot(routePlan: plan) { sampleInput in
    sampleInput == "PN41 - STO(001)" ? "PN41 - o STO(001)" : nil
}
assertOrFail(snapshotMatched.verdict == .libraryMatched, "evaluator should produce matched verdict")

let snapshotUnmatched = evaluator.makeSnapshot(routePlan: plan) { _ in nil }
assertOrFail(snapshotUnmatched.verdict == .reviewRequired, "evaluator should produce review-required verdict")

print("PASS: route verdict ownership checks")
SWIFT

swiftc -O -o "$TMP_BIN" \
  "$TMP_SWIFT" \
  "$ROOT_DIR/Sources/SpinLabApp/Domain/Models.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/SampleTokenization.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/SampleSemanticDescriptor.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/FileRoutingSemanticRules.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/FilenameRuleSet.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/RuleLoader.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/FileRoutingRuleBook.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/RoutingExplanationBook.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/RoutePlanner.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/PendingRoutingRuleBook.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/PendingRoutingSnapshotEvaluator.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/App/AppLogger.swift"

"$TMP_BIN"
