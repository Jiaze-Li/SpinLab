import Foundation
import Testing
@testable import SpinLabApp

/// Gap-only stacking: net gap between adjacent vertical envelopes = max peak-to-peak × Gap,
/// Gap = 0 leaves curves in place, and Packs saved with the old Stack × Gap meaning keep it.
@Suite("Gap-only stacking")
struct GapOnlyStackingTests {

    private func series(_ label: String, _ y: [Double]) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(label: label, x: y.indices.map(Double.init), y: y)
    }

    private func plan(_ curves: [WorkbenchPlotSeries], _ policy: SeriesStackingPolicy) -> SeriesVisualPlan {
        SeriesVisualPlanner.plan(SeriesVisualPlanningInput(
            series: curves, visualSeriesOrder: nil, hiddenSeriesKeys: [], stackingPolicy: policy))
    }

    /// Net gaps between neighbouring envelopes, bottom to top.
    private func netGaps(_ displayed: [WorkbenchPlotSeries]) -> [Double] {
        let envelopes = displayed.reversed().map { ($0.y.min()!, $0.y.max()!) }
        return zip(envelopes, envelopes.dropFirst()).map { lower, upper in upper.0 - lower.1 }
    }

    private let magnitudes = [[-5.0, 5.0], [-0.5, 0.5], [-0.5, 0.5]]   // peak-to-peak 10, 1, 1

    // MARK: Algorithm

    @Test("Different magnitudes (10, 1, 1): every net gap is max peak-to-peak × Gap")
    func uniformGapForDifferentMagnitudes() {
        let curves = [series("a", magnitudes[0]), series("b", magnitudes[1]), series("c", magnitudes[2])]
        let result = plan(curves, .uniformGapVertical(gapFraction: 0.11))
        let gaps = netGaps(result.displaySeries)
        #expect(gaps.count == 2)
        for gap in gaps { #expect(abs(gap - 1.1) < 1e-9, "gap \(gap)") }
    }

    @Test("Gap = 0 keeps every curve at its original position")
    func zeroGapDoesNotStack() {
        let curves = [series("a", [1, 2, 3]), series("b", [1, 2, 3]), series("c", [2, 4, 6])]
        let result = plan(curves, .uniformGapVertical(gapFraction: 0))
        #expect(result.displaySeries.map(\.y) == curves.map(\.y))
        #expect(result.displayOffsetsByIdentityKey.values.allSatisfy { $0 == 0 })
    }

    @Test("Gaps are not quantized: 0.01, 0.11 and 0.125 give exactly that fraction of the max peak-to-peak")
    func gapIsNotQuantized() {
        let curves = [series("a", [0, 8]), series("b", [0, 2])]
        for gap in [0.01, 0.11, 0.125, 0.333] {
            let gaps = netGaps(plan(curves, .uniformGapVertical(gapFraction: gap)).displaySeries)
            #expect(abs(gaps[0] - 8 * gap) < 1e-9, "Gap \(gap): \(gaps)")
        }
    }

    @Test("Flat curves: no peak-to-peak to scale, so nothing moves; a flat curve beside a real one keeps the gap")
    func flatCurves() {
        let allFlat = [series("a", [3, 3, 3]), series("b", [7, 7, 7])]
        #expect(plan(allFlat, .uniformGapVertical(gapFraction: 0.2)).displaySeries.map(\.y) == allFlat.map(\.y))

        let mixed = [series("flat", [4, 4, 4]), series("wave", [0, 10, 0])]
        let gaps = netGaps(plan(mixed, .uniformGapVertical(gapFraction: 0.2)).displaySeries)
        #expect(abs(gaps[0] - 2.0) < 1e-9, "\(gaps)")
    }

    @Test("Invalid Gap (negative, NaN, infinite) never stacks")
    func invalidGapDoesNotStack() {
        let curves = [series("a", [0, 1]), series("b", [0, 1])]
        for gap in [-0.5, Double.nan, Double.infinity] {
            #expect(plan(curves, .uniformGapVertical(gapFraction: gap)).displaySeries.map(\.y) == curves.map(\.y), "Gap \(gap)")
        }
    }

    @Test("Stacking shifts display copies only; the measured series are untouched")
    func rawDataIsNeverModified() {
        let curves = [series("a", magnitudes[0]), series("b", magnitudes[1])]
        let result = plan(curves, .uniformGapVertical(gapFraction: 0.5))
        #expect(result.visualSeries.map(\.y) == curves.map(\.y))
        #expect(result.displaySeries.map(\.y) != curves.map(\.y))
    }

    // MARK: Legacy

    @Test("Legacy policy keeps the old Stack × Gap result; Stack = 0 stays unstacked whatever Gap is")
    func legacyPolicyIsUnchanged() {
        let curves = [series("a", [0, 4]), series("b", [0, 4])]
        let legacy = SeriesStackingPolicy.spacing(uniformGap: false, multiplier: 0, minGapFraction: 0.3)
        #expect(plan(curves, legacy).displaySeries.map(\.y) == curves.map(\.y))

        let stacked = SeriesStackingPolicy.spacing(uniformGap: false, multiplier: 1.2, minGapFraction: 0.15)
        let expected = plan(curves, .orderEnforcingVertical(multiplier: 1.2, minGapFraction: 0.15)).displaySeries.map(\.y)
        #expect(plan(curves, stacked).displaySeries.map(\.y) == expected)
        #expect(expected != curves.map(\.y))
    }

    // MARK: Input

    @Test("Gap input accepts non-negative finite decimals exactly and rejects everything else")
    func gapInputParsing() {
        #expect(WorkbenchGapInput.parse("0.125") == 0.125)
        #expect(WorkbenchGapInput.parse(" 0.11 ") == 0.11)
        #expect(WorkbenchGapInput.parse("0") == 0)
        #expect(WorkbenchGapInput.parse("-0")?.sign == .plus)
        #expect(WorkbenchGapInput.parse("0.01") == 0.01)
        for bad in ["", " ", "-0.1", "abc", "nan", "inf", "-inf", "1.2.3"] {
            #expect(WorkbenchGapInput.parse(bad) == nil, "\(bad)")
        }
        for value in [0.01, 0.11, 0.125, 0.15, 1.0, 0.0] {
            #expect(WorkbenchGapInput.parse(WorkbenchGapInput.format(value)) == value, "\(value)")
        }
        #expect(WorkbenchGapInput.format(0.125) == "0.125")
    }

    @Test("Gap 0 and 0.11: new state is Gap-only; an unmigrated legacy state still renders as saved")
    func gapZeroAndPointOneOneInBothStates() {
        let curves = [series("a", [0, 10]), series("b", [0, 1]), series("c", [0, 1])]
        for gap in [0.0, 0.11] {
            let new = plan(curves, .spacing(uniformGap: true, multiplier: 1.4, minGapFraction: gap))
            let legacy = plan(curves, .spacing(uniformGap: false, multiplier: 1.4, minGapFraction: gap))
            let oldRule = plan(curves, .orderEnforcingVertical(multiplier: 1.4, minGapFraction: gap))
            #expect(legacy == oldRule)
            if gap == 0 {
                #expect(new.displayOffsetsByIdentityKey.values.allSatisfy { $0 == 0 })
            } else {
                #expect(netGaps(new.displaySeries).allSatisfy { abs($0 - 1.1) < 1e-9 })
            }
        }
    }
}

/// Old Packs and snapshots: Stack and Gap are kept as saved, the legacy meaning is kept until Gap
/// is edited, and saving again does not lose or rewrite either number.
@MainActor
@Suite("Gap-only stacking — Pack and snapshot compatibility")
struct GapOnlyPackCompatibilityTests {

    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    /// A config as written before the flag existed: the new key is stripped from the JSON.
    private func legacyJSON<T: Encodable>(_ config: T) throws -> Data {
        let data = try JSONEncoder().encode(config)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "uniformGapSpacing")
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("Every workflow's old Pack config decodes as legacy and keeps Stack and Gap")
    func oldPackConfigsDecodeAsLegacy() throws {
        let ahe = try JSONDecoder().decode(AHEPackConfig.self, from: legacyJSON(AHEPackConfig(
            titleTemplate: "", showPlotGrid: true, stackOffsetMultiplier: 1.4, minGapFraction: 0.2)))
        #expect(!ahe.uniformGapSpacing && ahe.stackOffsetMultiplier == 1.4 && ahe.minGapFraction == 0.2)

        let iv = try JSONDecoder().decode(IVPackConfig.self, from: legacyJSON(IVPackConfig(
            titleTemplate: "", activeTab: IVWorkbenchTab.voltage.rawValue, stackOffsetMultiplier: 0, minGapFraction: 0.3, showPlotGrid: true)))
        #expect(!iv.uniformGapSpacing && iv.stackOffsetMultiplier == 0 && iv.minGapFraction == 0.3)

        let rt = try JSONDecoder().decode(RTPackConfig.self, from: legacyJSON(RTPackConfig(
            titleTemplate: "", showPlotGrid: true, stackOffsetMultiplier: 0.8, minGapFraction: 0.1)))
        #expect(!rt.uniformGapSpacing && rt.stackOffsetMultiplier == 0.8 && rt.minGapFraction == 0.1)

        let xy = try JSONDecoder().decode(XYRotationPackConfig.self, from: legacyJSON(XYRotationPackConfig(
            phiOffsetOverrides: [:], centerBaseline: false, activeTab: "", titleTemplate: "",
            stackOffsetMultiplier: 1.0, minGapFraction: 0.12, showPlotGrid: true)))
        #expect(!xy.uniformGapSpacing && xy.stackOffsetMultiplier == 1.0 && xy.minGapFraction == 0.12)
    }

    @Test("An old 3ω Pack decodes as legacy, keeps Stack and Gap, and re-saves with the same numbers")
    func oldThreeOmegaPackKeepsNumbers() throws {
        let old = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: legacyJSON(ThreeOmegaPackConfig(
            device: "D", geometry: ThreeOmegaGeometry(), fitRanges: [], v3Method: "", rahe1Method: "", rahe3Method: "",
            rtFilePath: nil, sampleBatchAndSubstrate: "", activeTab: "", titleTemplate: "",
            stackOffsetMultiplier: 1.2, minGapFraction: 0.15, showPlotGrid: true, plotLegendAnchor: "")))
        #expect(!old.uniformGapSpacing && old.stackOffsetMultiplier == 1.2 && old.minGapFraction == 0.15)

        let again = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: JSONEncoder().encode(old))
        #expect(!again.uniformGapSpacing && again.stackOffsetMultiplier == 1.2 && again.minGapFraction == 0.15)

        // A fresh 3ω session is Gap-only at 0.15 and saves that.
        let store = makeWorkbenchStore().threeOmegaWorkspace
        let saved = store.buildPackConfig()
        #expect(saved.uniformGapSpacing && saved.minGapFraction == 0.15)
    }

    @Test("An old IV Pack restores as legacy, renders as saved, and re-saves with the same numbers")
    func oldIVPackRestoresAndResaves() throws {
        let store = makeWorkbenchStore().ivWorkspace
        let old = try JSONDecoder().decode(IVPackConfig.self, from: legacyJSON(IVPackConfig(
            titleTemplate: "", activeTab: IVWorkbenchTab.voltage.rawValue,
            stackOffsetMultiplier: 0, minGapFraction: 0.3, showPlotGrid: true)))
        let result = IVPackResult(ingestionResult: IVIngestionResult())
        let pack = try AnalysisPack(label: "old", workflowID: "IV", filePaths: [], sampleKeys: [], config: old, result: result)
        store.restoreFromPack(config: old, result: result, pack: pack,
                              restoreSearchState: { _, _ in }, seedSelection: { _, _ in })

        #expect(!store.uniformGapSpacing, "an old Pack must not be silently reinterpreted")
        #expect(store.legacySpacingDecisionPending, "loading an old Pack queues the migration prompt")
        // Stack = 0, Gap > 0 in the old meaning is not stacked, and still is.
        let curves = [WorkbenchPlotSeries(label: "a", x: [0, 1], y: [0, 4]), WorkbenchPlotSeries(label: "b", x: [0, 1], y: [0, 4])]
        let policy = SeriesStackingPolicy.spacing(uniformGap: store.uniformGapSpacing,
                                                  multiplier: store.stackOffsetMultiplier,
                                                  minGapFraction: store.minGapFraction)
        let shown = SeriesVisualPlanner.plan(SeriesVisualPlanningInput(
            series: curves, visualSeriesOrder: nil, hiddenSeriesKeys: [], stackingPolicy: policy))
        #expect(shown.displaySeries.map(\.y) == curves.map(\.y))

        let resaved = store.buildPackConfig()
        #expect(!resaved.uniformGapSpacing && resaved.stackOffsetMultiplier == 0 && resaved.minGapFraction == 0.3)
        let again = try JSONDecoder().decode(IVPackConfig.self, from: JSONEncoder().encode(resaved))
        #expect(!again.uniformGapSpacing && again.minGapFraction == 0.3)
    }

    @Test("A new Pack carries the Gap-only flag through save and restore")
    func newPackRoundTrips() throws {
        let store = makeWorkbenchStore().aheWorkspace
        store.minGapFraction = 0.11
        let config = store.buildPackConfig()
        #expect(config.uniformGapSpacing && config.minGapFraction == 0.11)
        let decoded = try JSONDecoder().decode(AHEPackConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.uniformGapSpacing && decoded.minGapFraction == 0.11)
    }

    private func plotModel(_ store: AHEWorkspaceStore, _ appState: SpinLabAppState) -> CartesianXYControlsModel? {
        guard case .cartesianXY(let plot) = store.controlsDescriptor(appState: appState, globalPlotDefaults: .constant([:])).plot else { return nil }
        return plot
    }

    @Test("A loaded legacy session asks once; Keep leaves it legacy and Gap read-only, Migrate switches without rewriting Stack")
    func legacyLoadAsksAndMigrates() throws {
        let appState = SpinLabAppState()
        let workbench = appState.workbench
        workbench.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "",
                                     aheStackOffsetMultiplier: 1.4, aheMinGapFraction: 0.11)
        let store = workbench.aheWorkspace
        workbench.currentRoute = .workflow(id: store.workflowID)
        #expect(!store.uniformGapSpacing && store.legacySpacingDecisionPending)
        #expect(workbench.legacySpacingPromptPending, "the prompt belongs to the workflow, not to the Plot controls")
        #expect(try #require(plotModel(store, appState)).gapIsLegacy, "an unmigrated legacy state is not the new Gap control")

        workbench.resolveLegacySpacing(migrate: false)
        #expect(!store.uniformGapSpacing && !workbench.legacySpacingPromptPending, "Keep legacy changes nothing")
        #expect(store.stackOffsetMultiplier == 1.4 && store.minGapFraction == 0.11)
        #expect(try #require(plotModel(store, appState)).gapIsLegacy)

        store.adoptSavedSpacing(uniform: false)
        workbench.resolveLegacySpacing(migrate: true)
        #expect(store.uniformGapSpacing && !workbench.legacySpacingPromptPending)
        #expect(store.stackOffsetMultiplier == 1.4, "the legacy Stack number is not rewritten")
        #expect(!(try #require(plotModel(store, appState))).gapIsLegacy)

        var snapshot = SpinLabInteractionSnapshot()
        workbench.captureInteraction(into: &snapshot)
        #expect(snapshot.aheUniformGapSpacing == true && snapshot.aheStackOffsetMultiplier == 1.4 && snapshot.aheMinGapFraction == 0.11)
        let again = makeWorkbenchStore()
        again.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "",
                                 aheStackOffsetMultiplier: snapshot.aheStackOffsetMultiplier,
                                 aheMinGapFraction: snapshot.aheMinGapFraction, aheUniformGapSpacing: snapshot.aheUniformGapSpacing)
        #expect(again.aheWorkspace.uniformGapSpacing && !again.aheWorkspace.legacySpacingDecisionPending)
    }

    @Test("Loading an old Pack queues the prompt; a new Pack and a new session never do")
    func packLoadQueuesPromptOnlyForLegacy() throws {
        let store = makeWorkbenchStore().aheWorkspace
        store.adoptSavedSpacing(uniform: false)
        #expect(store.legacySpacingDecisionPending)
        store.migrateToGapOnlySpacing()
        store.adoptSavedSpacing(uniform: true)
        #expect(!store.legacySpacingDecisionPending && store.uniformGapSpacing)
        #expect(!makeWorkbenchStore().aheWorkspace.legacySpacingDecisionPending)
    }

    @Test("Interaction snapshots: legacy values restore as legacy, new ones as Gap-only, fresh sessions stay Gap-only")
    func snapshotCompatibility() throws {
        let legacy = makeWorkbenchStore()
        legacy.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "",
                                  ivStackOffsetMultiplier: 1.2, ivMinGapFraction: 0.25)
        #expect(!legacy.ivWorkspace.uniformGapSpacing)
        #expect(legacy.ivWorkspace.stackOffsetMultiplier == 1.2 && legacy.ivWorkspace.minGapFraction == 0.25)

        let modern = makeWorkbenchStore()
        modern.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "",
                                  ivStackOffsetMultiplier: 0, ivMinGapFraction: 0.11, ivUniformGapSpacing: true)
        #expect(modern.ivWorkspace.uniformGapSpacing && modern.ivWorkspace.minGapFraction == 0.11)

        let fresh = makeWorkbenchStore()
        fresh.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "")
        #expect(fresh.ivWorkspace.uniformGapSpacing && fresh.ivWorkspace.minGapFraction == 0)

        // XY Rotation never persisted its Gap before: an old snapshot ran at the old 0.15 default.
        let oldXY = makeWorkbenchStore()
        oldXY.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "", xyRotationStackOffset: 1.0)
        #expect(!oldXY.xyRotationWorkspace.uniformGapSpacing && oldXY.xyRotationWorkspace.minGapFraction == 0.15)

        var snapshot = SpinLabInteractionSnapshot()
        modern.captureInteraction(into: &snapshot)
        let decoded = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.ivUniformGapSpacing == true && decoded.ivMinGapFraction == 0.11)
    }
}
