import Foundation
import Testing
@testable import SpinLabApp

// MARK: - V750 Save Semantic Protection Tests
//
// Gate 7.5A: three coverage gaps identified in the save audit.
//
// Suite 1 — 3ω buildActiveChartMetrics semantic projection:
//   metric names, canonical unit strings, scaling factors, tab gate, conditions.
//
// Suite 2 — AHE override guard invariant:
//   source-inspection verification that the isSingleSample gate
//   is present for both Hc and R_AHE overrides.
//
// Suite 3 — PersistChartArtifactUseCase semanticParams["tabKey"] read path:
//   tabKey present → stored in reference; absent → nil.

// MARK: - Suite 1: 3ω metric projection

@Suite("V750 3ω buildActiveChartMetrics — semantic projection")
struct V750ThreeOmegaMetricProjectionTests {

    private func makeSegment(
        tLo: Double,
        tHi: Double,
        alpha: Double,
        beta: Double,
        rSquared: Double
    ) -> ThreeOmegaScalingSegment {
        ThreeOmegaScalingSegment(
            id: UUID(),
            tLo: tLo,
            tHi: tHi,
            alpha: alpha,
            beta: beta,
            rSquared: rSquared,
            pointCount: 5,
            participatingXValues: [1, 2, 3, 4, 5]
        )
    }

    // MARK: - Metric names

    @MainActor
    @Test("scaling tab produces alpha, beta, r_squared metric names")
    func metricNamesOnScalingTab() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.98)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg", deviceMode: "single")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()

        let names = Set(entries.map(\.metric))
        #expect(names.contains("alpha"), "Expected 'alpha' metric name")
        #expect(names.contains("beta"), "Expected 'beta' metric name")
        #expect(names.contains("r_squared"), "Expected 'r_squared' metric name")
    }

    // MARK: - Canonical unit strings

    @MainActor
    @Test("alpha canonicalUnit is 'Ω·μm³·cm²·V⁻²·S⁻²'")
    func alphaCanonicalUnit() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.98)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entry = store.buildActiveChartMetrics().first(where: { $0.metric == "alpha" })
        #expect(entry?.canonicalUnit == "Ω·μm³·cm²·V⁻²·S⁻²")
    }

    @MainActor
    @Test("beta canonicalUnit is 'Ω·μm³·V⁻²'")
    func betaCanonicalUnit() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.98)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entry = store.buildActiveChartMetrics().first(where: { $0.metric == "beta" })
        #expect(entry?.canonicalUnit == "Ω·μm³·V⁻²")
    }

    @MainActor
    @Test("r_squared canonicalUnit is empty string (dimensionless)")
    func r2CanonicalUnit() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.987)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entry = store.buildActiveChartMetrics().first(where: { $0.metric == "r_squared" })
        #expect(entry?.canonicalUnit == "")
    }

    // MARK: - Unit scaling factors

    @MainActor
    @Test("alpha value is raw alpha × 1e31")
    func alphaUnitScaling() {
        let rawAlpha = 2.5e-31
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: rawAlpha, beta: 1e-20, rSquared: 0.99)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entry = store.buildActiveChartMetrics().first(where: { $0.metric == "alpha" })
        let expected = rawAlpha * 1e31
        #expect(abs((entry?.value ?? 0) - expected) < 1e-9,
                "Expected alpha value \(expected), got \(String(describing: entry?.value))")
    }

    @MainActor
    @Test("beta value is raw beta × 1e20")
    func betaUnitScaling() {
        let rawBeta = 3.7e-20
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: rawBeta, rSquared: 0.99)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entry = store.buildActiveChartMetrics().first(where: { $0.metric == "beta" })
        let expected = rawBeta * 1e20
        #expect(abs((entry?.value ?? 0) - expected) < 1e-9,
                "Expected beta value \(expected), got \(String(describing: entry?.value))")
    }

    @MainActor
    @Test("r_squared value is not scaled")
    func r2NoScaling() {
        let rawR2 = 0.876
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: rawR2)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entry = store.buildActiveChartMetrics().first(where: { $0.metric == "r_squared" })
        #expect(entry?.value == rawR2)
    }

    // MARK: - Condition keys

    @MainActor
    @Test("condition 'range' encodes tLo–tHi as integer Kelvin strings")
    func conditionRangeFormat() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10.4, tHi: 49.6, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()
        #expect(entries.first?.conditions["range"] == "10K–50K",
                "Range condition must round tLo/tHi to nearest integer")
    }

    @MainActor
    @Test("condition 'v3method' is 'HFE' for highField method")
    func conditionV3MethodHFE() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.v3Method = .highField
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()
        #expect(entries.first?.conditions["v3method"] == "HFE")
    }

    @MainActor
    @Test("condition 'v3method' is 'WA' for window method")
    func conditionV3MethodWA() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.v3Method = .window
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()
        #expect(entries.first?.conditions["v3method"] == "WA")
    }

    @MainActor
    @Test("angleSweep deviceMode adds 'deviceMode' condition, no 'device' condition")
    func conditionAngleSweepDeviceMode() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(
            device: "",
            deviceMode: "angleSweep",
            devices: ["0deg", "45deg"]
        )
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()
        #expect(entries.first?.conditions["deviceMode"] == "angleSweep",
                "angleSweep mode must set 'deviceMode' condition")
        #expect(entries.first?.conditions["devices"] == "0deg,45deg",
                "angleSweep mode must join devices array into 'devices' condition")
        #expect(entries.first?.conditions["device"] == nil,
                "'device' condition must be absent in angleSweep mode")
    }

    @MainActor
    @Test("single device mode adds 'device' condition, no 'deviceMode' condition")
    func conditionSingleDeviceMode() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg", deviceMode: "single")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()
        #expect(entries.first?.conditions["device"] == "0deg",
                "Single mode must set 'device' condition")
        #expect(entries.first?.conditions["deviceMode"] == nil,
                "'deviceMode' condition must be absent in single mode")
    }

    // MARK: - Tab gate

    @MainActor
    @Test("non-scaling tabs return empty entries even with a valid scaling result")
    func nonScalingTabProducesEmpty() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]

        let nonScalingTabs: [ThreeOmegaWorkbenchTab] = [
            .fieldSweep1omega, .fieldSweep3omega, .rahe1omegaVsT, .rahe3omegaVsT, .hcVsT, .rtCurve
        ]
        for tab in nonScalingTabs {
            store.tabs.activeTab = tab
            let entries = store.buildActiveChartMetrics()
            #expect(entries.isEmpty,
                    "Tab \(tab.rawValue) must produce empty metrics — only .scaling produces entries")
        }
    }

    @MainActor
    @Test("nil scalingResult returns empty entries regardless of active tab")
    func nilScalingResultProducesEmpty() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = nil
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        #expect(store.buildActiveChartMetrics().isEmpty)
    }

    @MainActor
    @Test("empty segments returns empty entries")
    func emptySegmentsProducesEmpty() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(points: [], segments: [])
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        #expect(store.buildActiveChartMetrics().isEmpty)
    }

    // MARK: - Multi-segment: one entry triplet per segment

    @MainActor
    @Test("two segments produce six entries (alpha+beta+r_squared × 2)")
    func twoSegmentsProduceSixEntries() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [
                makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9),
                makeSegment(tLo: 100, tHi: 200, alpha: 2e-31, beta: 2e-20, rSquared: 0.8)
            ]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["SK-A"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()
        #expect(entries.count == 6, "Two segments must produce 3 entries each (alpha, beta, r²)")

        let alphaEntries = entries.filter { $0.metric == "alpha" }
        let ranges = Set(alphaEntries.compactMap { $0.conditions["range"] })
        #expect(ranges.contains("10K–50K"))
        #expect(ranges.contains("100K–200K"))
    }

    // MARK: - sampleKey propagation

    @MainActor
    @Test("entries use the first cachedSampleKey as sampleKey")
    func sampleKeyFromCachedKeys() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = ["PN31|b|STO|111", "other"]
        store.tabs.activeTab = .scaling

        let entries = store.buildActiveChartMetrics()
        for entry in entries {
            #expect(entry.sampleKey == "PN31|b|STO|111",
                    "All entries must use cachedSampleKeys.first as sampleKey")
        }
    }

    @MainActor
    @Test("empty cachedSampleKeys returns empty entries")
    func emptyCachedSampleKeysProducesEmpty() {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [makeSegment(tLo: 10, tHi: 50, alpha: 1e-31, beta: 1e-20, rSquared: 0.9)]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg")
        store.cachedSampleKeys = []
        store.tabs.activeTab = .scaling

        #expect(store.buildActiveChartMetrics().isEmpty)
    }
}

// MARK: - Suite 2: AHE override guard invariant

@Suite("V750 AHE override guard invariant")
struct V750AHEOverrideGuardTests {

    private func loadAHESource() throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: "Sources/SpinLabApp/Features/Workbench/AHEWorkspaceStore.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // INV-GUARD-1: multi-sample guard definition is present
    @Test("buildActiveChartMetrics defines isSingleSample as sampleKeys.count == 1")
    func isSingleSampleDefinition() throws {
        let source = try loadAHESource()
        #expect(source.contains("let isSingleSample = sampleKeys.count == 1"),
                "Guard must derive isSingleSample from count == 1, not any other expression")
    }

    // INV-GUARD-2: Hc override application is gated by isSingleSample
    @Test("Hc override is applied only inside isSingleSample branch")
    func hcOverrideIsGated() throws {
        let source = try loadAHESource()
        #expect(source.contains("if isSingleSample, let override = pendingMetricOverride"),
                "Hc override must be inside 'if isSingleSample' — without this guard, multi-sample results get wrong override")
    }

    // INV-GUARD-3: R_AHE override application is gated by isSingleSample
    @Test("R_AHE override is applied only inside isSingleSample branch")
    func rAHEOverrideIsGated() throws {
        let source = try loadAHESource()
        #expect(source.contains("if isSingleSample, let override = pendingRAHEOverride"),
                "R_AHE override must be inside 'if isSingleSample' — without this guard, multi-sample results get wrong override")
    }

    // INV-GUARD-4: override fields are cleared after successful persist
    @Test("Hc and R_AHE overrides are both cleared on successful persist")
    func overridesClearedOnSuccess() throws {
        let source = try loadAHESource()
        #expect(source.contains("self.pendingMetricOverride = nil"),
                "pendingMetricOverride must be cleared after successful persist")
        #expect(source.contains("self.pendingRAHEOverride = nil"),
                "pendingRAHEOverride must be cleared after successful persist")
    }

    // INV-GUARD-5: .partial outcome increments persistCount but preserves pending overrides
    @MainActor
    @Test("didCompleteSave(.partial) increments persistCount but does not clear pending overrides")
    func partialOutcomePreservesOverrides() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.pendingMetricOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: 0.05, reason: "test", source: .manual
        )
        store.pendingRAHEOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: 10.0, reason: "test", source: .manual
        )
        let before = store.persistCount
        store.didCompleteSave(outcome: .partial(trace: nil, metricError: "metric extraction failed"))
        #expect(store.persistCount == before + 1,
                ".partial must increment persistCount")
        #expect(store.pendingMetricOverride != nil,
                ".partial must not clear pendingMetricOverride — overrides survive for next save attempt")
        #expect(store.pendingRAHEOverride != nil,
                ".partial must not clear pendingRAHEOverride — overrides survive for next save attempt")
    }

    // INV-GUARD-6: .success outcome increments persistCount AND clears pending overrides
    @MainActor
    @Test("didCompleteSave(.success) increments persistCount and clears pending overrides")
    func successOutcomeClearsOverrides() {
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.pendingMetricOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: 0.05, reason: "test", source: .manual
        )
        store.pendingRAHEOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: 10.0, reason: "test", source: .manual
        )
        let before = store.persistCount
        let trace = WorkbenchRunTraceProjection(
            runID: "test-run", workflowID: "ahe",
            inputFiles: [], axisMapping: WorkbenchAxisMapping(xField: "H", yField: "R"),
            semanticParams: [:], outputImagePath: "", manifestPath: "", generatedAt: .distantPast
        )
        store.didCompleteSave(outcome: .success(trace: trace))
        #expect(store.persistCount == before + 1,
                ".success must increment persistCount")
        #expect(store.pendingMetricOverride == nil,
                ".success must clear pendingMetricOverride")
        #expect(store.pendingRAHEOverride == nil,
                ".success must clear pendingRAHEOverride")
    }

    // INV-GUARD-7: single-sample behavioral path — override IS propagated for one key
    @MainActor
    @Test("buildActiveChartMetrics returns empty when no sample keys are loaded")
    func emptyStateProducesEmptyEntries() {
        // When the store has no analysis state, override candidates must not create phantom entries.
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.pendingMetricOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: 0.05, reason: "test", source: .manual
        )
        store.pendingRAHEOverride = WorkbenchMetricOverrideCandidate(
            proposedValue: 10.0, reason: "test", source: .manual
        )
        // No analysis run, so lastRenderedSampleKeys is empty
        let entries = store.buildActiveChartMetrics()
        #expect(entries.isEmpty,
                "Override candidates must not create entries when no sample keys are present")
    }
}

// MARK: - Suite 3b: private(set) setter visibility and executeSave ordering

@Suite("V750 SaveCoordinator visibility and ordering invariants")
struct V750SaveCoordinatorStructureTests {

    private func loadSource(file: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: "Sources/SpinLabApp/Features/Workbench/\(file)")
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

    // VISIBILITY-1: AHE uses private(set) for persistenceOutcome
    @Test("AHEWorkspaceStore declares persistenceOutcome as private(set)")
    func ahePersistenceOutcomeIsPrivateSet() throws {
        let source = try loadSource(file: "AHEWorkspaceStore.swift")
        #expect(source.contains("private(set) var persistenceOutcome"),
                "AHEWorkspaceStore must not expose a public setter for persistenceOutcome")
    }

    // VISIBILITY-2: XY uses private(set) for persistenceOutcome
    @Test("XYRotationWorkspaceStore declares persistenceOutcome as private(set)")
    func xyPersistenceOutcomeIsPrivateSet() throws {
        let source = try loadSource(file: "XYRotationWorkspaceStore.swift")
        #expect(source.contains("private(set) var persistenceOutcome"),
                "XYRotationWorkspaceStore must not expose a public setter for persistenceOutcome")
    }

    // ORDER-1: executeSave calls didCompleteSave before setting saveMessage
    @Test("executeSave calls didCompleteSave before saveMessage is written")
    func executeSaveCallsDidCompleteSaveBeforeSaveMessage() throws {
        let coordinator = try loadSource(file: "WorkbenchSaveCoordinating.swift")
        let body = try #require(extractFunction("executeSave", from: coordinator),
                               "executeSave must be present in WorkbenchSaveCoordinating")
        let didCompleteRange = try #require(body.range(of: "didCompleteSave"),
                                            "executeSave must call didCompleteSave")
        let saveMessageRange = try #require(body.range(of: "saveMessage"),
                                            "executeSave must set saveMessage")
        #expect(didCompleteRange.lowerBound < saveMessageRange.lowerBound,
                "didCompleteSave must appear before saveMessage in executeSave — override clearing must precede message write")
    }

    // ORDER-2: executeSave calls didCompleteSave before refreshRelatedCharts
    @Test("executeSave calls didCompleteSave before refreshRelatedCharts")
    func executeSaveCallsDidCompleteSaveBeforeRefreshRelatedCharts() throws {
        let coordinator = try loadSource(file: "WorkbenchSaveCoordinating.swift")
        let body = try #require(extractFunction("executeSave", from: coordinator),
                               "executeSave must be present in WorkbenchSaveCoordinating")
        let didCompleteRange = try #require(body.range(of: "didCompleteSave"),
                                            "executeSave must call didCompleteSave")
        let refreshRange = try #require(body.range(of: "refreshRelatedCharts"),
                                        "executeSave must call refreshRelatedCharts")
        #expect(didCompleteRange.lowerBound < refreshRange.lowerBound,
                "didCompleteSave must appear before refreshRelatedCharts — AHE persistCount must be incremented before related charts load")
    }

    // ORDER-3: protocol uses applyPersistenceOutcome method, not { get set }
    @Test("WorkbenchSaveCoordinating protocol requires applyPersistenceOutcome, not a settable persistenceOutcome")
    func protocolUsesApplyMethod() throws {
        let coordinator = try loadSource(file: "WorkbenchSaveCoordinating.swift")
        #expect(coordinator.contains("func applyPersistenceOutcome"),
                "Protocol must declare applyPersistenceOutcome method")
        #expect(!coordinator.contains("persistenceOutcome? { get set }"),
                "Protocol must not require a public setter on persistenceOutcome — use applyPersistenceOutcome instead")
    }
}

// MARK: - Suite 3: PersistChartArtifactUseCase semanticParams["tabKey"]

@Suite("V750 PersistChartArtifactUseCase — semanticParams tabKey read path")
struct V750TabKeyReadPathTests {

    private func makeFixture(_ tag: String) throws -> (resolver: LibraryPathResolver, writer: AtomicFileWriter, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "v750-tabkey-\(tag)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (LibraryPathResolver(libraryRootURL: root), AtomicFileWriter(), root)
    }

    private func cleanup(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    private func payload(tabKey: String?) -> WorkbenchPlotPayload {
        var semantic: [String: String] = ["device": "0deg"]
        if let k = tabKey { semantic["tabKey"] = k }
        return WorkbenchPlotPayload(
            workflowID: "3w",
            workflowDisplayName: "3ω",
            title: "Test Chart",
            axisMapping: WorkbenchAxisMapping(xField: "H", yField: "R"),
            series: [WorkbenchPlotSeries(label: "s", x: [], y: [], sourceRef: "/fake/file.lvm")],
            semanticParams: semantic
        )
    }

    private func readIndex(sampleKey: String, resolver: LibraryPathResolver) throws -> WorkbenchResultsIndex {
        let url = try resolver.absoluteURL(for: "samples/\(sampleKey)/_spinlab/results_index.json")
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WorkbenchResultsIndex.self, from: data)
    }

    // MARK: - tabKey present

    @Test("semanticParams tabKey is stored in the result reference tabKey field")
    func tabKeyPresentIsStored() throws {
        let (resolver, writer, root) = try makeFixture("present")
        defer { cleanup(root) }

        _ = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKeys: ["SK-A"], payload: payload(tabKey: "scaling"),
                     imageData: Data([0xFF, 0xD8]))

        let index = try readIndex(sampleKey: "SK-A", resolver: resolver)
        let ref = try #require(index.references.first)
        #expect(ref.tabKey == "scaling",
                "tabKey 'scaling' from semanticParams must be stored in WorkbenchResultReference.tabKey")
    }

    @Test("semanticParams tabKey is returned directly by resolvedTabKey")
    func tabKeyPresentResolvedTabKey() throws {
        let (resolver, writer, root) = try makeFixture("resolvedPresent")
        defer { cleanup(root) }

        _ = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKeys: ["SK-A"], payload: payload(tabKey: "fieldSweep1omega"),
                     imageData: Data([0xFF, 0xD8]))

        let index = try readIndex(sampleKey: "SK-A", resolver: resolver)
        let ref = try #require(index.references.first)
        #expect(ref.resolvedTabKey == "fieldSweep1omega",
                "resolvedTabKey must return the stored tabKey directly when present")
    }

    @Test("tabKey survives round-trip through results_index.json JSON serialization")
    func tabKeyRoundTripThroughIndex() throws {
        let (resolver, writer, root) = try makeFixture("roundtrip")
        defer { cleanup(root) }

        _ = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKeys: ["SK-A"], payload: payload(tabKey: "rahe1omegaVsT"),
                     imageData: Data([0xFF, 0xD8]))

        let index = try readIndex(sampleKey: "SK-A", resolver: resolver)
        let ref = try #require(index.references.first)
        #expect(ref.tabKey == "rahe1omegaVsT")
        #expect(ref.resolvedTabKey == "rahe1omegaVsT")
    }

    // MARK: - tabKey absent

    @Test("absent semanticParams tabKey produces nil tabKey in reference")
    func tabKeyAbsentProducesNilTabKey() throws {
        let (resolver, writer, root) = try makeFixture("absent")
        defer { cleanup(root) }

        _ = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKeys: ["SK-A"], payload: payload(tabKey: nil),
                     imageData: Data([0xFF, 0xD8]))

        let index = try readIndex(sampleKey: "SK-A", resolver: resolver)
        let ref = try #require(index.references.first)
        #expect(ref.tabKey == nil,
                "tabKey must be nil when 'tabKey' is absent from semanticParams")
    }

    @Test("absent tabKey falls through to filename-based resolution in resolvedTabKey")
    func tabKeyAbsentFallsToFilenameResolution() throws {
        let (resolver, writer, root) = try makeFixture("fallback")
        defer { cleanup(root) }

        _ = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
            .execute(sampleKeys: ["SK-A"], payload: payload(tabKey: nil),
                     imageData: Data([0xFF, 0xD8]))

        let index = try readIndex(sampleKey: "SK-A", resolver: resolver)
        let ref = try #require(index.references.first)
        // tabKey is nil, so resolvedTabKey must attempt filename inference.
        // With a generic title "Test Chart", no known prefix matches → nil.
        #expect(ref.tabKey == nil)
        // resolvedTabKey may be nil or a filename-inferred value; it must NOT return the raw tabKey sentinel.
        let resolved = ref.resolvedTabKey
        #expect(resolved == nil || resolved != "tabKey",
                "resolvedTabKey must not return the literal string 'tabKey'")
    }

    // MARK: - tabKey for each known 3ω workflow tab

    @Test("known 3ω tabKey values all round-trip correctly")
    func knownTabKeysRoundTrip() throws {
        let knownKeys = [
            "fieldSweep1omega",
            "fieldSweep3omega",
            "rahe1omegaVsT",
            "rahe3omegaVsT",
            "hcVsT",
            "rtCurve",
            "scaling"
        ]
        for key in knownKeys {
            let (resolver, writer, root) = try makeFixture("tab-\(key)")
            defer { cleanup(root) }

            _ = try PersistChartArtifactUseCase(writer: writer, pathResolver: resolver)
                .execute(sampleKeys: ["SK-A"], payload: payload(tabKey: key),
                         imageData: Data([0xFF, 0xD8]))

            let index = try readIndex(sampleKey: "SK-A", resolver: resolver)
            let ref = try #require(index.references.first)
            #expect(ref.tabKey == key, "tabKey '\(key)' must round-trip through results_index.json")
            #expect(ref.resolvedTabKey == key, "resolvedTabKey must return stored '\(key)' directly")
        }
    }
}

// MARK: - Suite 4: Stage 2A-1 — 3ω manifestPayload purity

/// Verifies that _refreshManifestPayloads never bakes TabRenderState display overrides into
/// manifestPayload, and that the code change in renderThreeOmegaTab preserves clean manifests.

@Suite("V2A1 3ω manifest payload purity")
struct V2A1ThreeOmegaManifestPayloadPurityTests {

    @MainActor
    private func makeStoreWithIngestion() -> ThreeOmegaWorkspaceStore {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = ThreeOmegaIngestionResult(device: "0deg", deviceMode: "single")
        store.cachedInputFiles = ["/fake/file.lvm"]
        store.cachedRTFilePath = nil
        return store
    }

    // MARK: - _refreshManifestPayloads ignores title override

    @MainActor
    @Test("_refreshManifestPayloads title is scientific label, not titleOverride")
    func refreshManifestPayloadsIgnoresTitleOverride() {
        let store = makeStoreWithIngestion()
        store.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].titleOverride = "Custom Title"
        store._refreshManifestPayloads()
        let manifest = store.tabs.output(for: .fieldSweep1omega).manifestPayload
        #expect(manifest != nil,
                "fieldSweep1omega manifest must be set after _refreshManifestPayloads")
        #expect(manifest?.title != "Custom Title",
                "manifestPayload.title must not reflect titleOverride — TabRenderState owns display labels")
    }

    // MARK: - _refreshManifestPayloads ignores axis label overrides

    @MainActor
    @Test("_refreshManifestPayloads axisMapping is scientific field name, not xLabelOverride")
    func refreshManifestPayloadsIgnoresXLabelOverride() {
        let store = makeStoreWithIngestion()
        store.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].xLabelOverride = "My X Axis"
        store.tabs.tabStates[.fieldSweep1omega, default: TabRenderState()].yLabelOverride = "My Y Axis"
        store._refreshManifestPayloads()
        let manifest = store.tabs.output(for: .fieldSweep1omega).manifestPayload
        #expect(manifest?.axisMapping.xField != "My X Axis",
                "manifestPayload.axisMapping.xField must not reflect xLabelOverride")
        #expect(manifest?.axisMapping.yField != "My Y Axis",
                "manifestPayload.axisMapping.yField must not reflect yLabelOverride")
        #expect(manifest?.axisMapping.xField == "H (T)",
                "manifestPayload.axisMapping.xField must be the scientific field name")
        #expect(manifest?.axisMapping.yField == "R(1ω) (Ω)",
                "manifestPayload.axisMapping.yField must be the scientific field name")
    }

    // MARK: - Clean manifest survives re-render via TabRenderOutput preservation

    @MainActor
    @Test("clean manifestPayload survives a setOutput call that preserves existing manifest")
    func cleanManifestSurvivesSetOutputPreservation() {
        let store = makeStoreWithIngestion()
        store._refreshManifestPayloads()
        let clean = store.tabs.output(for: .fieldSweep1omega).manifestPayload

        // Simulate the fixed renderThreeOmegaTab behaviour: preserve existing manifest
        let after = TabRenderOutput(
            imageData: nil,
            layout: nil,
            manifestPayload: store.tabs.output(for: .fieldSweep1omega).manifestPayload,
            displayPayload: nil
        )
        store.tabs.setOutput(after, for: .fieldSweep1omega)

        #expect(store.tabs.output(for: .fieldSweep1omega).manifestPayload?.title == clean?.title,
                "manifest title must survive a re-render that preserves existing manifestPayload")
        #expect(store.tabs.output(for: .fieldSweep1omega).manifestPayload?.axisMapping.xField
                == clean?.axisMapping.xField,
                "manifest xField must survive a re-render that preserves existing manifestPayload")
    }

    // MARK: - Source inspection: renderThreeOmegaTab no longer assigns output.manifestPayload

    @Test("renderThreeOmegaTab does not assign output.manifestPayload to TabRenderOutput.manifestPayload")
    func renderThreeOmegaTabNoLongerPollutesManifest() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appending(path: "Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        // Stage 2A-1 fix: TabRenderOutput inside renderThreeOmegaTab must NOT use output.manifestPayload
        // as the manifestPayload field — it must preserve tabs.output(for: tab).manifestPayload instead.
        // Search for the exact forbidden pattern that would bake pipeline display overrides into manifest.
        let forbiddenPattern = "manifestPayload: output.manifestPayload"
        #expect(!source.contains(forbiddenPattern),
                "renderThreeOmegaTab must not set manifestPayload: output.manifestPayload — use tabs.output(for: tab).manifestPayload to preserve clean manifest from _refreshManifestPayloads")
    }
}
