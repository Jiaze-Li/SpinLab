#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/spinlab_drawer_match_engine_consistency.XXXXXX)"
TMP_SWIFT="$TMP_DIR/main.swift"
TMP_BIN="$TMP_DIR/spinlab_drawer_match_engine_consistency"

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

func makeSample(batch: String, treatment: String, material: String, orientation: String, display: String) -> LibrarySample {
    LibrarySample(
        id: "\(batch)|\(treatment)|\(material)|\(orientation)",
        displayName: display,
        batchId: batch,
        substrateRaw: "\(treatment) \(material)(\(orientation))",
        substrateDisplay: "\(treatment) \(material)(\(orientation))",
        substrateTokens: [treatment, material, orientation].filter { !$0.isEmpty && $0 != "UNKNOWN" },
        substrateTags: [],
        metadata: [:],
        numericTags: [:],
        numericDisplay: [:],
        updatedAt: .now
    )
}

let engine = DrawerMatchEngine()
let index = engine.makeIndex(from: [
    makeSample(batch: "PN32", treatment: "HF", material: "STO", orientation: "111", display: "PN32 - HF STO(111)"),
    makeSample(batch: "PN32", treatment: "baked", material: "STO", orientation: "111", display: "PN32 - baked STO(111)")
])

assertOrFail(
    engine.match(sampleInput: "PN32|baked|STO|111", index: index) == "PN32 - baked STO(111)",
    "exact canonical match did not resolve expected drawer"
)

let descriptor = SampleSemanticDescriptor(
    batch: "pn32",
    processingTokens: ["BAKED", "o", "HF"],
    material: "sto",
    orientation: "111"
)
assertOrFail(
    descriptor.canonicalKey == "PN32|HF+baked+o|STO|111",
    "shared semantic descriptor canonicalization mismatch"
)

assertOrFail(
    engine.match(sampleInput: "PN32 baked STO", index: index) == "PN32 - baked STO(111)",
    "fallback subset match did not resolve expected drawer"
)

assertOrFail(
    engine.match(sampleInput: "PN32 STO", index: index) == nil,
    "ambiguous fallback should not resolve"
)

let legacyIndex = engine.makeIndex(from: [
    LibrarySample(
        id: "legacy-pn50-hf-sto111",
        displayName: "PN50 - HF STO(111)",
        batchId: "PN50",
        substrateRaw: "HF STO(111)",
        substrateDisplay: "HF STO(111)",
        substrateTokens: ["HF", "STO", "111"],
        substrateTags: [],
        metadata: [:],
        numericTags: [:],
        numericDisplay: [:],
        updatedAt: .now
    )
])
assertOrFail(
    engine.match(sampleInput: "PN50 HF STO", index: legacyIndex) == "PN50 - HF STO(111)",
    "legacy non-canonical sample should still resolve via fallback"
)

print("PASS: drawer match engine consistency checks")
SWIFT

swiftc -O -o "$TMP_BIN" \
  "$TMP_SWIFT" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/Match/DrawerMatchEngine.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/Parse/SampleTokenization.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/Parse/SampleSemanticDescriptor.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/Rules/FileRoutingSemanticRules.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/Rules/RuleLoader.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/Rules/FilenameRuleSet.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Import/Route/FileRoutingRuleBook.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/Library/LibraryModels.swift" \
  "$ROOT_DIR/Sources/SpinLabApp/App/AppLogger.swift"

"$TMP_BIN"
