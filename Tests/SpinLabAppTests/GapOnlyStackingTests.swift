import Foundation
import Testing
@testable import SpinLabApp

/// Gap-only stacking: net gap between adjacent vertical envelopes = max peak-to-peak × Gap,
/// Gap = 0 leaves curves in place. There is one algorithm; Stack never takes part.
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
}

/// Old Packs and sessions load directly: the saved Gap becomes the Gap, the saved Stack and the
/// old mode flag are ignored, nothing is asked, and saving again writes only the Gap.
@MainActor
@Suite("Gap-only stacking — old Pack and session compatibility")
struct GapOnlyPackCompatibilityTests {

    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    /// (old Stack, old Gap, expected Gap)
    private let table: [(stack: Double, gap: Double, expected: Double)] = [
        (0, 0.4, 0.4), (0.5, 0.4, 0.4), (1.2, 0.4, 0.4), (1.6, 0.11, 0.11), (0, 0, 0), (0.5, 0, 0), (1.6, 0, 0), (9, 0, 0),
    ]

    /// A Pack config JSON as an old version wrote it: current config plus the retired keys.
    private func oldJSON<T: Encodable>(_ config: T, stack: Double, gap: Double?) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        object["stackOffsetMultiplier"] = stack
        object["uniformGapSpacing"] = false
        if let gap { object["minGapFraction"] = gap } else { object.removeValue(forKey: "minGapFraction") }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func keys(_ data: Data) throws -> Set<String> {
        Set(try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
    }

    private func noRetiredKeys<T: Encodable>(_ config: T) throws -> Bool {
        let k = try keys(JSONEncoder().encode(config))
        return !k.contains("stackOffsetMultiplier") && !k.contains("uniformGapSpacing")
    }

    private let noSearch: ([WorkflowMeasurementSearchHit], String) -> Void = { _, _ in }
    private let noSeed: (Set<String>, [WorkflowMeasurementSearchHit]) -> Void = { _, _ in }

    // MARK: Packs — one run per workflow: decode old → restore → re-save → reopen

    @Test("AHE: old Pack Stack/Gap table restores Gap only, re-saves without Stack or mode flag, reopens the same")
    func aheOldPack() throws {
        for row in table {
            let store = makeWorkbenchStore().aheWorkspace
            let old = try JSONDecoder().decode(AHEPackConfig.self, from: oldJSON(
                AHEPackConfig(titleTemplate: "", showPlotGrid: true), stack: row.stack, gap: row.gap))
            let result = AHEPackResult(ingestionResult: nil)
            store.restoreFromPack(config: old, result: result,
                                  pack: try AnalysisPack(label: "o", workflowID: "AHE", filePaths: [], sampleKeys: [], config: old, result: result),
                                  restoreSearchState: noSearch, seedSelection: noSeed)
            #expect(store.minGapFraction == row.expected, "stack \(row.stack) gap \(row.gap)")
            let saved = store.buildPackConfig()
            #expect(try noRetiredKeys(saved) && saved.minGapFraction == row.expected)
            let reopened = try JSONDecoder().decode(AHEPackConfig.self, from: JSONEncoder().encode(saved))
            #expect(reopened.minGapFraction == row.expected)
        }
    }

    @Test("IV: old Pack Stack/Gap table restores Gap only, re-saves without Stack or mode flag, reopens the same")
    func ivOldPack() throws {
        for row in table {
            let store = makeWorkbenchStore().ivWorkspace
            let old = try JSONDecoder().decode(IVPackConfig.self, from: oldJSON(
                IVPackConfig(titleTemplate: "", activeTab: IVWorkbenchTab.voltage.rawValue, showPlotGrid: true), stack: row.stack, gap: row.gap))
            let result = IVPackResult(ingestionResult: IVIngestionResult())
            store.restoreFromPack(config: old, result: result,
                                  pack: try AnalysisPack(label: "o", workflowID: "IV", filePaths: [], sampleKeys: [], config: old, result: result),
                                  restoreSearchState: noSearch, seedSelection: noSeed)
            #expect(store.minGapFraction == row.expected, "stack \(row.stack) gap \(row.gap)")
            let saved = store.buildPackConfig()
            #expect(try noRetiredKeys(saved) && saved.minGapFraction == row.expected)
            #expect(try JSONDecoder().decode(IVPackConfig.self, from: JSONEncoder().encode(saved)).minGapFraction == row.expected)
        }
    }

    @Test("RT: old Pack Stack/Gap table restores Gap only, re-saves without Stack or mode flag, reopens the same")
    func rtOldPack() throws {
        for row in table {
            let store = makeWorkbenchStore().rtWorkspace
            let old = try JSONDecoder().decode(RTPackConfig.self, from: oldJSON(
                RTPackConfig(titleTemplate: "", showPlotGrid: true), stack: row.stack, gap: row.gap))
            let result = RTPackResult()
            store.restoreFromPack(config: old, result: result,
                                  pack: try AnalysisPack(label: "o", workflowID: "RT", filePaths: [], sampleKeys: [], config: old, result: result),
                                  restoreSearchState: noSearch, seedSelection: noSeed)
            #expect(store.minGapFraction == row.expected, "stack \(row.stack) gap \(row.gap)")
            let saved = store.buildPackConfig()
            #expect(try noRetiredKeys(saved) && saved.minGapFraction == row.expected)
            #expect(try JSONDecoder().decode(RTPackConfig.self, from: JSONEncoder().encode(saved)).minGapFraction == row.expected)
        }
    }

    @Test("XY Rotation: old Pack Stack/Gap table restores Gap only, re-saves without Stack or mode flag, reopens the same")
    func xyOldPack() throws {
        for row in table {
            let store = makeWorkbenchStore().xyRotationWorkspace
            let old = try JSONDecoder().decode(XYRotationPackConfig.self, from: oldJSON(
                XYRotationPackConfig(phiOffsetOverrides: [:], centerBaseline: false, activeTab: "", titleTemplate: "", minGapFraction: 0, showPlotGrid: true),
                stack: row.stack, gap: row.gap))
            let result = XYRotationPackResult(ingestionResult: XYRotationIngestionResult())
            store.restoreFromPack(config: old, result: result,
                                  pack: try AnalysisPack(label: "o", workflowID: "XYRotation", filePaths: [], sampleKeys: [], config: old, result: result),
                                  restoreSearchState: noSearch, seedSelection: noSeed)
            #expect(store.minGapFraction == row.expected, "stack \(row.stack) gap \(row.gap)")
            let saved = store.buildPackConfig()
            #expect(try noRetiredKeys(saved) && saved.minGapFraction == row.expected)
            #expect(try JSONDecoder().decode(XYRotationPackConfig.self, from: JSONEncoder().encode(saved)).minGapFraction == row.expected)
        }
    }

    @Test("3ω: old Pack Stack/Gap table restores Gap only, re-saves without Stack or mode flag, reopens the same")
    func threeOmegaOldPack() throws {
        for row in table {
            let store = makeWorkbenchStore().threeOmegaWorkspace
            let base = ThreeOmegaPackConfig(
                device: "D", geometry: ThreeOmegaGeometry(), fitRanges: [], v3Method: "", rahe1Method: "", rahe3Method: "",
                rtFilePath: nil, sampleBatchAndSubstrate: "", activeTab: "", titleTemplate: "",
                minGapFraction: 0, showPlotGrid: true, plotLegendAnchor: "")
            let old = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: oldJSON(base, stack: row.stack, gap: row.gap))
            let result = ThreeOmegaPackResult(ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], device: "D"), scalingResult: nil)
            store.restoreFromPack(config: old, result: result,
                                  pack: try AnalysisPack(label: "o", workflowID: "3Omega", filePaths: [], sampleKeys: [], config: old, result: result),
                                  restoreSearchState: noSearch, seedSelection: noSeed)
            #expect(store.minGapFraction == row.expected, "stack \(row.stack) gap \(row.gap)")
            let saved = store.buildPackConfig()
            #expect(try noRetiredKeys(saved) && saved.minGapFraction == row.expected)
            #expect(try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: JSONEncoder().encode(saved)).minGapFraction == row.expected)
        }
    }

    @Test("A Pack with no Gap key restores the historical default 0.15, not zero; the old 3ω Stack key is no longer required")
    func missingGapUsesHistoricalDefault() throws {
        let ahe = try JSONDecoder().decode(AHEPackConfig.self, from: oldJSON(AHEPackConfig(titleTemplate: "", showPlotGrid: true), stack: 1.2, gap: nil))
        #expect(ahe.minGapFraction == 0.15)
        let xy = try JSONDecoder().decode(XYRotationPackConfig.self, from: oldJSON(
            XYRotationPackConfig(phiOffsetOverrides: [:], centerBaseline: false, activeTab: "", titleTemplate: "", minGapFraction: 0, showPlotGrid: true), stack: 0, gap: nil))
        #expect(xy.minGapFraction == 0.15)
        // 3ω Packs used to fail without a Stack key; Stack is gone, so that requirement is too.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(ThreeOmegaPackConfig(
            device: "D", geometry: ThreeOmegaGeometry(), fitRanges: [], v3Method: "", rahe1Method: "", rahe3Method: "",
            rtFilePath: nil, sampleBatchAndSubstrate: "", activeTab: "", titleTemplate: "",
            minGapFraction: 0, showPlotGrid: true, plotLegendAnchor: ""))) as? [String: Any])
        object.removeValue(forKey: "minGapFraction")
        let three = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(three.minGapFraction == 0.15)
    }

    // MARK: Sessions

    private func oldSnapshotJSON(stack: Double, gap: Double?) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(SpinLabInteractionSnapshot())) as? [String: Any])
        for prefix in ["threeOmega", "ahe", "iv", "rt"] {
            object["\(prefix)StackOffsetMultiplier"] = stack
            object["\(prefix)UniformGapSpacing"] = false
            if let gap { object["\(prefix)MinGapFraction"] = gap }
        }
        object["xyRotationStackOffset"] = stack
        object["xyRotationUniformGapSpacing"] = false
        if let gap { object["xyRotationMinGapFraction"] = gap }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test("Old sessions: Stack/Gap table restores Gap only for all five workflows; no prompt; re-save and reopen keep the Gap")
    func oldSessionsRestoreGapOnly() throws {
        for row in table {
            let old = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: oldSnapshotJSON(stack: row.stack, gap: row.gap))
            let store = makeWorkbenchStore()
            store.restoreInteraction(
                selectedArchivedRecordID: nil, workbenchResultDraft: "",
                threeOmegaMinGapFraction: old.threeOmegaMinGapFraction,
                aheMinGapFraction: old.aheMinGapFraction,
                xyRotationStackOffset: old.xyRotationStackOffset, xyRotationMinGapFraction: old.xyRotationMinGapFraction,
                ivMinGapFraction: old.ivMinGapFraction,
                rtMinGapFraction: old.rtMinGapFraction)
            let gaps = [store.threeOmegaWorkspace.minGapFraction, store.aheWorkspace.minGapFraction,
                        store.xyRotationWorkspace.minGapFraction, store.ivWorkspace.minGapFraction, store.rtWorkspace.minGapFraction]
            #expect(gaps.allSatisfy { $0 == row.expected }, "stack \(row.stack) gap \(row.gap): \(gaps)")

            var snapshot = SpinLabInteractionSnapshot()
            store.captureInteraction(into: &snapshot)
            let data = try JSONEncoder().encode(snapshot)
            let written = try keys(data)
            #expect(!written.contains { $0.contains("StackOffset") || $0.contains("UniformGap") }, "new sessions carry no Stack or mode flag")
            let again = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: data)
            let reopened = makeWorkbenchStore()
            reopened.restoreInteraction(
                selectedArchivedRecordID: nil, workbenchResultDraft: "",
                threeOmegaMinGapFraction: again.threeOmegaMinGapFraction, aheMinGapFraction: again.aheMinGapFraction,
                xyRotationStackOffset: again.xyRotationStackOffset, xyRotationMinGapFraction: again.xyRotationMinGapFraction,
                ivMinGapFraction: again.ivMinGapFraction, rtMinGapFraction: again.rtMinGapFraction)
            #expect(reopened.aheWorkspace.minGapFraction == row.expected && reopened.rtWorkspace.minGapFraction == row.expected
                    && reopened.xyRotationWorkspace.minGapFraction == row.expected && reopened.ivWorkspace.minGapFraction == row.expected
                    && reopened.threeOmegaWorkspace.minGapFraction == row.expected)
        }
    }

    @Test("Old XY Rotation session written before its Gap was saved restores the historical 0.15; fresh sessions keep today's defaults")
    func xyHistoricalDefaultAndFreshDefaults() throws {
        let oldXY = makeWorkbenchStore()
        oldXY.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "", xyRotationStackOffset: 1.0)
        #expect(oldXY.xyRotationWorkspace.minGapFraction == 0.15)

        let fresh = makeWorkbenchStore()
        fresh.restoreInteraction(selectedArchivedRecordID: nil, workbenchResultDraft: "")
        #expect(fresh.aheWorkspace.minGapFraction == 0 && fresh.ivWorkspace.minGapFraction == 0
                && fresh.rtWorkspace.minGapFraction == 0 && fresh.xyRotationWorkspace.minGapFraction == 0)
        #expect(fresh.threeOmegaWorkspace.minGapFraction == 0.15)
    }

    @Test("Loaded old state draws with the Gap rule only: Stack never re-enables stacking")
    func stackNeverReEnablesStacking() throws {
        let curves = (0..<3).map { WorkbenchPlotSeries(label: "c\($0)", x: [0, 1], y: [0, 4]) }
        for row in table {
            let plan = SeriesVisualPlanner.plan(SeriesVisualPlanningInput(
                series: curves, visualSeriesOrder: nil, hiddenSeriesKeys: [], stackingPolicy: .uniformGapVertical(gapFraction: row.expected)))
            if row.expected == 0 {
                #expect(plan.displaySeries.map(\.y) == curves.map(\.y), "Gap 0 is not stacked whatever the old Stack was (\(row.stack))")
            } else {
                #expect(plan.displaySeries.map(\.y) != curves.map(\.y))
            }
        }
    }

    @Test("Gap 0.11 and 0 through the renderers' stacking path give identical results for old and new states")
    func oldAndNewStateRenderTheSame() {
        // Old state (Stack 1.6, Gap 0.11) and a new state (Gap 0.11) reduce to the same Gap value.
        let curves = [WorkbenchPlotSeries(label: "a", x: [0, 1], y: [0, 10]), WorkbenchPlotSeries(label: "b", x: [0, 1], y: [0, 1]),
                      WorkbenchPlotSeries(label: "c", x: [0, 1], y: [0, 1])]
        for gap in [0.0, 0.11] {
            let plan = SeriesVisualPlanner.plan(SeriesVisualPlanningInput(
                series: curves, visualSeriesOrder: nil, hiddenSeriesKeys: [], stackingPolicy: .uniformGapVertical(gapFraction: gap)))
            if gap == 0 {
                #expect(plan.displayOffsetsByIdentityKey.values.allSatisfy { $0 == 0 })
            } else {
                let envelopes = plan.displaySeries.reversed().map { ($0.y.min()!, $0.y.max()!) }
                let gaps = zip(envelopes, envelopes.dropFirst()).map { $1.0 - $0.1 }
                #expect(gaps.allSatisfy { abs($0 - 1.1) < 1e-9 })
            }
        }
    }
}
