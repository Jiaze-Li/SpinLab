import Foundation
import Testing
@testable import SpinLabApp

/// V7.6.0 Pack / Restore — Protection Tests (Gate 7.6A)
///
/// Baseline tests for the Gate 7.6 pack/restore audit. These tests pin the
/// current behavioral contract before any extraction or refactor begins.
///
/// Groups:
///   1. RT round-trip canonical path — selectedRTHit is the effective restore source
///   2. cachedRTFilePath overwrite guard — source inspection pins the derived-output contract
///   3. Required field decode failures — 3ω and XY required fields throw on missing input
///   4. Optional field backward-compat — AHE and XY optional fields default correctly
///   5. Overlay runtime cleared on restore — wired WorkbenchAnalysisOverlayRuntime is cleared

// MARK: - Group 1: RT Round-Trip Canonical Path

@Suite("V760 RT round-trip canonical path")
struct V760RTRoundTripTests {

    private func makeRTHit(
        measurementFilePath: String = "/tmp/rt-measurement.lvm"
    ) -> WorkflowMeasurementSearchHit {
        let sidecarPath = measurementFilePath + ".spinlab.json"
        return WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: measurementFilePath,
            sourceFilePath: measurementFilePath,
            workflowID: "3w",
            workflowDisplayName: "3ω",
            workflowCanonicalID: "3w",
            batchID: "PN31",
            sampleKey: "PN31|b|STO|111",
            sampleSubstrate: "STO111",
            conditions: ["temperature": "5K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }

    private func makePackConfig(
        selectedRTHit: WorkflowMeasurementSearchHit?,
        rtFilePath: String?
    ) -> ThreeOmegaPackConfig {
        ThreeOmegaPackConfig(
            device: "",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: rtFilePath,
            sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega",
            titleTemplate: "",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: false,
            plotLegendAnchor: "",
            selectedRTHit: selectedRTHit
        )
    }

    private func makePackResult() -> ThreeOmegaPackResult {
        ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
    }

    private func makePack(config: ThreeOmegaPackConfig) throws -> AnalysisPack {
        try AnalysisPack(
            label: "RT Round-Trip Fixture",
            workflowID: "3w",
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: makePackResult()
        )
    }

    /// PRIMARY contract: when a pack encodes a selectedRTHit, restoreFromPack sets
    /// cachedRTFilePath to selectedRTHit.measurementFilePath — not to config.rtFilePath.
    /// This test documents that selectedRTHit is the canonical RT restore source.
    @MainActor
    @Test("cachedRTFilePath after restore equals selectedRTHit.measurementFilePath")
    func cachedRTFilePathMatchesSelectedRTHitMeasurementPath() throws {
        let store = ThreeOmegaWorkspaceStore()
        let rtHit = makeRTHit(measurementFilePath: "/tmp/actual-rt.lvm")
        // config.rtFilePath is intentionally set to a DIFFERENT path from the hit,
        // so that if restore were to read config.rtFilePath directly the test would fail.
        let config = makePackConfig(selectedRTHit: rtHit, rtFilePath: "/tmp/stale-path.lvm")
        let pack = try makePack(config: config)

        store.restoreFromPack(
            config: config,
            result: makePackResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.selectedRTHit?.id == rtHit.id,
                "selectedRTHit must be applied directly from pack config")
        #expect(store.cachedRTFilePath == rtHit.measurementFilePath,
                "cachedRTFilePath must derive from selectedRTHit.measurementFilePath — not from config.rtFilePath")
        #expect(store.cachedRTFilePath != "/tmp/stale-path.lvm",
                "cachedRTFilePath must NOT be the stale config.rtFilePath value")
    }

    /// When selectedRTHit.measurementFilePath equals config.rtFilePath (the normal save case),
    /// cachedRTFilePath is still derived from selectedRTHit — it just happens to be the same value.
    @MainActor
    @Test("cachedRTFilePath consistent when selectedRTHit.measurementFilePath matches config.rtFilePath")
    func cachedRTFilePathConsistentWhenPathsMatch() throws {
        let store = ThreeOmegaWorkspaceStore()
        let measurementPath = "/tmp/consistent-rt.lvm"
        let rtHit = makeRTHit(measurementFilePath: measurementPath)
        let config = makePackConfig(selectedRTHit: rtHit, rtFilePath: measurementPath)
        let pack = try makePack(config: config)

        store.restoreFromPack(
            config: config,
            result: makePackResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.cachedRTFilePath == measurementPath,
                "cachedRTFilePath must equal the measurement path when both sources agree")
    }

    /// When selectedRTHit is nil, cachedRTFilePath is nil after restore —
    /// even if config.rtFilePath is non-nil. config.rtFilePath is NOT a standalone restore input.
    /// This test documents the derivation-only contract (see audit §3b, priority 3).
    @MainActor
    @Test("cachedRTFilePath is nil when selectedRTHit is nil — config.rtFilePath is not a restore input")
    func cachedRTFilePathNilWhenNoSelectedRTHit() throws {
        let store = ThreeOmegaWorkspaceStore()
        // Pack encodes a non-nil rtFilePath but no selectedRTHit.
        let config = makePackConfig(selectedRTHit: nil, rtFilePath: "/tmp/orphan-rt.lvm")
        let pack = try makePack(config: config)

        store.restoreFromPack(
            config: config,
            result: makePackResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.selectedRTHit == nil,
                "selectedRTHit must remain nil when pack encodes none")
        #expect(store.cachedRTFilePath == nil,
                "cachedRTFilePath must be nil when selectedRTHit is nil — config.rtFilePath is not promoted to cachedRTFilePath when selectedRTHit is absent")
    }
}

// MARK: - Group 2: cachedRTFilePath Overwrite Guard (Source Inspection)

@Suite("V760 cachedRTFilePath overwrite guard — source inspection")
struct V760CachedRTFilePathOverwriteGuardTests {

    private func loadManifestCacheSource() throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path:
            "Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func loadPackSource() throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path:
            "Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractFunction(_ name: String, from source: String) -> String? {
        guard let sig = source.range(of: "func \(name)") else { return nil }
        guard let open = source[sig.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let c = source[index]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return String(source[sig.lowerBound...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    /// _snapshotAndCacheManifestPayloads(from:) derives cachedRTFilePath from
    /// selectedRTHit?.measurementFilePath. This pins the derivation so that future
    /// refactors cannot silently promote config.rtFilePath to the canonical source.
    @Test("_snapshotAndCacheManifestPayloads derives cachedRTFilePath from selectedRTHit?.measurementFilePath")
    func snapshotCacheDerivesCachedRTFromSelectedHit() throws {
        let source = try loadManifestCacheSource()
        let body = try #require(
            extractFunction("_snapshotAndCacheManifestPayloads(from selectedHits", from: source)
                ?? extractFunction("_snapshotAndCacheManifestPayloads(from", from: source),
            "_snapshotAndCacheManifestPayloads(from:) must exist in ManifestCache"
        )
        #expect(
            body.contains("cachedRTFilePath = selectedRTHit?.measurementFilePath"),
            "_snapshotAndCacheManifestPayloads(from:) must assign cachedRTFilePath = selectedRTHit?.measurementFilePath"
        )
        #expect(
            !body.contains("config.rtFilePath"),
            "_snapshotAndCacheManifestPayloads(from:) must not reference config.rtFilePath — derivation is from selectedRTHit only"
        )
    }

    /// Gate 7.6B cleanup: the intermediate assignment `cachedRTFilePath = config.rtFilePath`
    /// has been removed from restoreFromPack. config.rtFilePath is a fingerprint-context field
    /// only; cachedRTFilePath is derived exclusively from selectedRTHit?.measurementFilePath
    /// by _snapshotAndCacheManifestPayloads(). This test pins the absence so the intermediate
    /// write cannot be re-introduced without failing here.
    @Test("restoreFromPack does not assign cachedRTFilePath from config.rtFilePath (Gate 7.6B cleanup)")
    func restoreFromPackDoesNotAssignConfigRTFilePath() throws {
        let source = try loadPackSource()
        let body = try #require(
            extractFunction("restoreFromPack", from: source),
            "restoreFromPack must exist in ThreeOmegaWorkspaceStore+Pack.swift"
        )
        #expect(
            !body.contains("cachedRTFilePath = config.rtFilePath"),
            "restoreFromPack must NOT assign cachedRTFilePath from config.rtFilePath — config.rtFilePath is fingerprint context only; cachedRTFilePath is derived by _snapshotAndCacheManifestPayloads()"
        )
    }

    /// restoreFromPack must NOT assign cachedRTFilePath after _snapshotAndCacheManifestPayloads.
    /// A second assignment after the snapshot call would create a competing restore path.
    @Test("restoreFromPack does not re-assign cachedRTFilePath after _snapshotAndCacheManifestPayloads call")
    func restoreFromPackNoPostSnapshotRTPathAssignment() throws {
        let source = try loadPackSource()
        let body = try #require(
            extractFunction("restoreFromPack", from: source),
            "restoreFromPack must exist in ThreeOmegaWorkspaceStore+Pack.swift"
        )
        guard let snapshotCall = body.range(of: "_snapshotAndCacheManifestPayloads()") else {
            Issue.record("restoreFromPack must call _snapshotAndCacheManifestPayloads()")
            return
        }
        let afterSnapshot = String(body[snapshotCall.upperBound...])
        #expect(
            !afterSnapshot.contains("cachedRTFilePath ="),
            "restoreFromPack must not assign cachedRTFilePath after _snapshotAndCacheManifestPayloads() — any post-snapshot assignment would create a competing restore path that bypasses the derivation"
        )
    }
}

// MARK: - Group 3: Required Field Decode Failures

@Suite("V760 required field decode failures")
struct V760RequiredFieldDecodeFailureTests {

    // MARK: - ThreeOmegaPackConfig required fields

    private var minimalValid3wConfigJSON: String {
        """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
    }

    private func decode3w(_ json: String) throws -> ThreeOmegaPackConfig {
        try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: Data(json.utf8))
    }

    private func decodeXY(_ json: String) throws -> XYRotationPackConfig {
        try JSONDecoder().decode(XYRotationPackConfig.self, from: Data(json.utf8))
    }

    @Test("ThreeOmegaPackConfig decodes successfully from minimal valid JSON")
    func threeOmegaMinimalValidDecodes() throws {
        // Baseline: confirm the minimal fixture itself is valid.
        #expect(throws: Never.self) {
            try decode3w(minimalValid3wConfigJSON)
        }
    }

    @Test("ThreeOmegaPackConfig missing 'geometry' throws decode error")
    func threeOmegaMissingGeometryThrows() {
        let json = """
        {
          "device": "0deg",
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
        #expect(throws: (any Error).self, "missing 'geometry' must throw") {
            try decode3w(json)
        }
    }

    @Test("ThreeOmegaPackConfig missing 'v3Method' throws decode error")
    func threeOmegaMissingV3MethodThrows() {
        let json = """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
        #expect(throws: (any Error).self, "missing 'v3Method' must throw") {
            try decode3w(json)
        }
    }

    @Test("ThreeOmegaPackConfig missing 'stackOffsetMultiplier' throws decode error")
    func threeOmegaMissingStackOffsetMultiplierThrows() {
        let json = """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "showPlotGrid": false
        }
        """
        #expect(throws: (any Error).self, "missing 'stackOffsetMultiplier' must throw") {
            try decode3w(json)
        }
    }

    @Test("ThreeOmegaPackConfig missing 'showPlotGrid' throws decode error")
    func threeOmegaMissingShowPlotGridThrows() {
        let json = """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2
        }
        """
        #expect(throws: (any Error).self, "missing 'showPlotGrid' must throw") {
            try decode3w(json)
        }
    }

    // MARK: - XYRotationPackConfig required fields

    private var minimalValidXYConfigJSON: String {
        """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": false,
          "activeTab": "rxxVsPhi"
        }
        """
    }

    @Test("XYRotationPackConfig decodes successfully from minimal valid JSON")
    func xyMinimalValidDecodes() throws {
        #expect(throws: Never.self) {
            try decodeXY(minimalValidXYConfigJSON)
        }
    }

    @Test("XYRotationPackConfig missing 'phiOffsetOverrides' throws decode error")
    func xyMissingPhiOffsetOverridesThrows() {
        let json = """
        {
          "centerBaseline": false,
          "activeTab": "rxxVsPhi"
        }
        """
        #expect(throws: (any Error).self, "missing 'phiOffsetOverrides' must throw") {
            try decodeXY(json)
        }
    }

    @Test("XYRotationPackConfig missing 'centerBaseline' throws decode error")
    func xyMissingCenterBaselineThrows() {
        let json = """
        {
          "phiOffsetOverrides": {},
          "activeTab": "rxxVsPhi"
        }
        """
        #expect(throws: (any Error).self, "missing 'centerBaseline' must throw") {
            try decodeXY(json)
        }
    }

    @Test("XYRotationPackConfig missing 'activeTab' throws decode error")
    func xyMissingActiveTabThrows() {
        let json = """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": false
        }
        """
        #expect(throws: (any Error).self, "missing 'activeTab' must throw") {
            try decodeXY(json)
        }
    }

    // MARK: - loadPack decode failure path

    /// When a pack's config blob is malformed (required field missing), loadPack()
    /// sets analysisMessage and returns without mutating workflow state.
    @MainActor
    @Test("loadPack with corrupt 3ω config sets analysisMessage, does not crash")
    func loadPackCorrupt3wConfigSetsAnalysisMessage() throws {
        let store = ThreeOmegaWorkspaceStore()
        let vault = AnalysisVault()
        store.vault = vault

        // Build a pack with invalid config (missing required 'geometry').
        let badConfigJSON = """
        {
          "device": "0deg",
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
        let result = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
        let resultData = try JSONEncoder().encode(result)
        let pack = AnalysisPack(
            label: "Corrupt Config Pack",
            workflowID: "3w",
            filePaths: [],
            sampleKeys: [],
            config: Data(badConfigJSON.utf8),
            result: resultData
        )
        vault.add(pack)

        let priorIngestionResult = store.ingestionResult

        store.loadPack(id: pack.id) { _, _ in }

        #expect(store.analysisMessage != nil,
                "loadPack with corrupt config must set analysisMessage")
        #expect(store.analysisMessage?.contains("decode") == true || store.analysisMessage?.contains("Failed") == true,
                "analysisMessage must describe the decode failure")
        #expect(store.ingestionResult == priorIngestionResult,
                "loadPack with corrupt config must not mutate workflow analysis state")
        #expect(store.activePackID == nil,
                "loadPack with corrupt config must not set activePackID")
    }
}

// MARK: - Group 4: Optional Field Backward-Compat

@Suite("V760 optional field backward-compat")
struct V760OptionalFieldBackwardCompatTests {

    // MARK: - AHEPackConfig optional fields

    private func decodeAHE(_ json: String) throws -> AHEPackConfig {
        try JSONDecoder().decode(AHEPackConfig.self, from: Data(json.utf8))
    }

    private func decodeXY(_ json: String) throws -> XYRotationPackConfig {
        try JSONDecoder().decode(XYRotationPackConfig.self, from: Data(json.utf8))
    }

    private func decode3w(_ json: String) throws -> ThreeOmegaPackConfig {
        try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: Data(json.utf8))
    }

    @Test("AHEPackConfig missing 'showPlotGrid' defaults to true")
    func aheMissingShowPlotGridDefaultsToTrue() throws {
        let json = "{}"
        let config = try decodeAHE(json)
        #expect(config.showPlotGrid == true,
                "showPlotGrid must default to true when absent from pack")
    }

    @Test("AHEPackConfig missing 'titleTemplate' defaults to empty string")
    func aheMissingTitleTemplateDefaultsToEmpty() throws {
        let json = "{}"
        let config = try decodeAHE(json)
        #expect(config.titleTemplate == "",
                "titleTemplate must default to empty string when absent from pack")
    }

    @Test("AHEPackConfig missing 'tabStates' defaults to empty dictionary")
    func aheMissingTabStatesDefaultsToEmpty() throws {
        let json = "{}"
        let config = try decodeAHE(json)
        #expect(config.tabStates.isEmpty,
                "tabStates must default to [:] when absent from pack")
    }

    @Test("AHEPackConfig missing 'cachedSearchResults' defaults to empty array")
    func aheMissingCachedSearchResultsDefaultsToEmpty() throws {
        let json = "{}"
        let config = try decodeAHE(json)
        #expect(config.cachedSearchResults.isEmpty,
                "cachedSearchResults must default to [] when absent from pack")
    }

    @Test("AHEPackConfig missing 'searchQueryText' defaults to empty string")
    func aheMissingSearchQueryTextDefaultsToEmpty() throws {
        let json = "{}"
        let config = try decodeAHE(json)
        #expect(config.searchQueryText == "",
                "searchQueryText must default to empty string when absent from pack")
    }

    @Test("AHEPackConfig empty JSON object decodes without error — all optional fields use defaults")
    func aheEmptyJSONObjectDecodes() throws {
        #expect(throws: Never.self) {
            try decodeAHE("{}")
        }
    }

    // MARK: - XYRotationPackConfig optional fields

    @Test("XYRotationPackConfig missing 'linearDetrend' defaults to false")
    func xyMissingLinearDetrendDefaultsToFalse() throws {
        // This is the key backward-compat case: old packs written before linearDetrend
        // was introduced must decode as false, not crash or produce an uninitialized value.
        let json = """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": true,
          "activeTab": "rxxVsPhi"
        }
        """
        let config = try decodeXY(json)
        #expect(config.linearDetrend == false,
                "linearDetrend must default to false when absent from old pack")
    }

    @Test("XYRotationPackConfig missing 'stackOffsetMultiplier' defaults to 0.0")
    func xyMissingStackOffsetMultiplierDefaultsToZero() throws {
        let json = """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": false,
          "activeTab": "rxxVsPhi"
        }
        """
        let config = try decodeXY(json)
        #expect(config.stackOffsetMultiplier == 0.0,
                "stackOffsetMultiplier must default to 0.0 when absent from pack")
    }

    @Test("XYRotationPackConfig missing 'titleTemplate' defaults to empty string")
    func xyMissingTitleTemplateDefaultsToEmpty() throws {
        let json = """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": false,
          "activeTab": "rxxVsPhi"
        }
        """
        let config = try decodeXY(json)
        #expect(config.titleTemplate == "",
                "titleTemplate must default to empty string when absent from pack")
    }

    @Test("XYRotationPackConfig missing 'showPlotGrid' defaults to true")
    func xyMissingShowPlotGridDefaultsToTrue() throws {
        let json = """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": false,
          "activeTab": "rxxVsPhi"
        }
        """
        let config = try decodeXY(json)
        #expect(config.showPlotGrid == true,
                "showPlotGrid must default to true when absent from pack")
    }

    @Test("XYRotationPackConfig missing 'tabStates' defaults to empty dictionary")
    func xyMissingTabStatesDefaultsToEmpty() throws {
        let json = """
        {
          "phiOffsetOverrides": {},
          "centerBaseline": false,
          "activeTab": "rxxVsPhi"
        }
        """
        let config = try decodeXY(json)
        #expect(config.tabStates.isEmpty,
                "tabStates must default to [:] when absent from pack")
    }

    // MARK: - ThreeOmegaPackConfig optional fields

    @Test("ThreeOmegaPackConfig missing 'rahe1Method' defaults to v3Method")
    func threeOmegaMissingRahe1MethodFallsBackToV3Method() throws {
        // Old packs written before the RAHE method split did not have rahe1Method.
        // It must fall back to v3Method to preserve the original behavior.
        let json = """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
        let config = try decode3w(json)
        #expect(config.rahe1Method == config.v3Method,
                "rahe1Method must fall back to v3Method when absent from old pack")
        #expect(config.rahe3Method == config.v3Method,
                "rahe3Method must fall back to v3Method when absent from old pack")
    }

    @Test("ThreeOmegaPackConfig missing 'tabStates' defaults to empty dictionary")
    func threeOmegaMissingTabStatesDefaultsToEmpty() throws {
        let json = """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
        let config = try decode3w(json)
        #expect(config.tabStates.isEmpty,
                "tabStates must default to [:] when absent from pre-v5.3.3 pack")
    }

    @Test("ThreeOmegaPackConfig missing 'chartStyleOverrides' defaults to empty dictionary")
    func threeOmegaMissingChartStyleOverridesDefaultsToEmpty() throws {
        let json = """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
        let config = try decode3w(json)
        #expect(config.chartStyleOverrides.isEmpty,
                "chartStyleOverrides must default to [:] when absent from pre-v5.3.5 pack")
    }

    @Test("ThreeOmegaPackConfig missing 'selectedRTHit' defaults to nil")
    func threeOmegaMissingSelectedRTHitDefaultsToNil() throws {
        let json = """
        {
          "device": "0deg",
          "geometry": {"lxx": 0, "lxy": 0, "dNm": 0},
          "fitRanges": [],
          "v3Method": "highField",
          "sampleBatchAndSubstrate": "",
          "activeTab": "fieldSweep1omega",
          "stackOffsetMultiplier": 1.2,
          "showPlotGrid": false
        }
        """
        let config = try decode3w(json)
        #expect(config.selectedRTHit == nil,
                "selectedRTHit must default to nil when absent from pre-v5.3.4 pack")
        #expect(config.rtFilePath == nil,
                "rtFilePath must default to nil when absent from old pack")
        #expect(config.rtQuery == "",
                "rtQuery must default to empty string when absent from old pack")
    }
}

// MARK: - Group 5: Overlay Runtime Cleared on Restore (Wired Runtime Case)

@Suite("V760 overlay runtime cleared on restore — wired runtime")
struct V760OverlayRuntimeClearedOnRestoreTests {

    private func makeMinimalConfig() -> ThreeOmegaPackConfig {
        ThreeOmegaPackConfig(
            device: "",
            geometry: ThreeOmegaGeometry(),
            fitRanges: [ThreeOmegaFitRange()],
            v3Method: ThreeOmegaV3Method.highField.rawValue,
            rahe1Method: ThreeOmegaV3Method.highField.rawValue,
            rahe3Method: ThreeOmegaV3Method.highField.rawValue,
            rtFilePath: nil,
            sampleBatchAndSubstrate: "",
            activeTab: "fieldSweep1omega",
            titleTemplate: "",
            stackOffsetMultiplier: 1.2,
            minGapFraction: 0.15,
            showPlotGrid: false,
            plotLegendAnchor: ""
        )
    }

    private func makeMinimalResult() -> ThreeOmegaPackResult {
        ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: ""),
            scalingResult: nil
        )
    }

    private func makePack() throws -> AnalysisPack {
        try AnalysisPack(
            label: "Overlay Runtime Fixture",
            workflowID: "3w",
            filePaths: [],
            sampleKeys: [],
            config: makeMinimalConfig(),
            result: makeMinimalResult()
        )
    }

    /// When a WorkbenchAnalysisOverlayRuntime is wired to the store, restoreFromPack
    /// must call runtime.clear() — clearing overlayIDs and displayLabels.
    /// V740 tests cover the _overlayPackIDs standalone fallback; this test covers
    /// the wired-runtime path.
    @MainActor
    @Test("restoreFromPack clears wired WorkbenchAnalysisOverlayRuntime overlayIDs")
    func restoreFromPackClearsWiredRuntimeOverlayIDs() throws {
        let store = ThreeOmegaWorkspaceStore()
        let runtime = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = runtime

        let idA = AnalysisPack.ID()
        let idB = AnalysisPack.ID()
        runtime.addEntry(id: idA, label: "Overlay A")
        runtime.addEntry(id: idB, label: "Overlay B")
        #expect(runtime.overlayIDs.count == 2, "Precondition: runtime must have 2 overlay entries before restore")

        let pack = try makePack()
        store.restoreFromPack(
            config: makeMinimalConfig(),
            result: makeMinimalResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(runtime.overlayIDs.isEmpty,
                "restoreFromPack must call runtime.clear(), leaving overlayIDs empty")
    }

    /// restoreFromPack must also clear the runtime's displayLabels.
    @MainActor
    @Test("restoreFromPack clears wired WorkbenchAnalysisOverlayRuntime displayLabels")
    func restoreFromPackClearsWiredRuntimeDisplayLabels() throws {
        let store = ThreeOmegaWorkspaceStore()
        let runtime = WorkbenchAnalysisOverlayRuntime()
        store.overlayRuntime = runtime

        let id = AnalysisPack.ID()
        runtime.addEntry(id: id, label: "Chip Label")
        #expect(runtime.displayLabels[id] == "Chip Label", "Precondition: display label must be set before restore")

        let pack = try makePack()
        store.restoreFromPack(
            config: makeMinimalConfig(),
            result: makeMinimalResult(),
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(runtime.displayLabels.isEmpty,
                "restoreFromPack must call runtime.clear(), leaving displayLabels empty")
    }

}
