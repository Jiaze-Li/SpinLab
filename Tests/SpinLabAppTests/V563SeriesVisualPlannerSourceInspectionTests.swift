import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.6.3 SeriesVisualPlanner source inspection")
struct V563SeriesVisualPlannerSourceInspectionTests {

    private func loadSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractFunction(_ name: String, from source: String) -> String? {
        guard let sig = source.range(of: "func \(name)") else { return nil }
        guard let open = source[sig.lowerBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(source[sig.lowerBound...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private func assertActivePlannerFunction(_ function: String, context: String) {
        #expect(function.contains("SeriesVisualPlanner.plan("), "\(context) must route reorderable payloads through SeriesVisualPlanner")
        #expect(!function.contains("_legacyApplyRawSweepOrder("), "\(context) must not call the raw-sweep legacy bridge")
        #expect(!function.contains("legacyRendererBottomToTopOrder("), "\(context) must not reintroduce legacy bottom-to-top order conversion")
        #expect(!function.contains("func _applySeriesOrder"), "\(context) must not define a local _applySeriesOrder helper")
        #expect(!function.contains("reverseSeriesForLegend: true"), "\(context) must not opt into reverseSeriesForLegend for active payloads")
        #expect(!function.contains("filterHiddenStackSeries("), "\(context) must not manually filter hidden series outside SeriesVisualPlanner")
    }

    @Test("active payload builders route through SeriesVisualPlanner")
    func activePayloadBuildersRouteThroughPlanner() throws {
        let aheSource = try loadSource("Sources/SpinLabApp/UseCases/BuildAHEPlotPayloadUseCase.swift")
        let xySource = try loadSource("Sources/SpinLabApp/UseCases/XYRotationPlotRenderer.swift")
        let ivSource = try loadSource("Sources/SpinLabApp/UseCases/IVPlotRenderer.swift")
        let threeOmegaSource = try loadSource("Sources/SpinLabApp/UseCases/ThreeOmegaPlotRenderer.swift")

        let ahe = try #require(extractFunction("executePayloads", from: aheSource))
        let xy = try #require(extractFunction("makePlannedStackedRotationPayloads", from: xySource))
        let iv = try #require(extractFunction("makeStackedPayloads", from: ivSource))
        let threeOmegaStacked = try #require(extractFunction("makeStackedFieldSweepPayloads", from: threeOmegaSource))
        let threeOmegaRahe = try #require(extractFunction("makeCombinedRAHEVsTPayloads", from: threeOmegaSource))

        assertActivePlannerFunction(ahe, context: "AHE executePayloads")
        assertActivePlannerFunction(xy, context: "XY makePlannedStackedRotationPayloads")
        assertActivePlannerFunction(iv, context: "IV makeStackedPayloads")
        assertActivePlannerFunction(threeOmegaStacked, context: "3ω makeStackedFieldSweepPayloads")
        assertActivePlannerFunction(threeOmegaRahe, context: "3ω makeCombinedRAHEVsTPayloads")
    }

    @Test("XY label-order bridge derives mapping from planner output")
    func xyLabelOrderBridgeDerivesMappingFromPlannerOutput() throws {
        let storeSource = try loadSource("Sources/SpinLabApp/Features/Workbench/XYRotationWorkspaceStore.swift")
        let snapshotRenderer = try #require(extractFunction("_snapshotRenderer", from: storeSource))
        let helper = try #require(extractFunction("_plannerDerivedXYLabelSeries", from: storeSource))

        #expect(snapshotRenderer.contains("_plannerDerivedXYLabelSeries("))
        #expect(!snapshotRenderer.contains("_orderedXYLabelSeries("))
        #expect(!snapshotRenderer.contains("AlignXYSeriesOrderUseCase.applySeriesOrder("))
        #expect(!snapshotRenderer.contains("hiddenSeriesKeys:"))
        #expect(!snapshotRenderer.contains("stackingPolicy:"))
        #expect(helper.contains("SeriesVisualPlanner.plan("))
        #expect(helper.contains("stackingPolicy: .none"))
        #expect(helper.contains("hiddenSeriesKeys: []"))
        #expect(!helper.contains("resolveOrderKeys("))
        #expect(!helper.contains("resolveIdentities(for: rawSeries)"))
    }

    @Test("3ω manifest cache ordering derives from planner output")
    func threeOmegaManifestCacheOrderingDerivesFromPlannerOutput() throws {
        let cacheSource = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+ManifestCache.swift")
        let buildPayload = try #require(extractFunction("_buildManifestPayload", from: cacheSource))
        let helper = try #require(extractFunction("_plannedFieldSweepManifestSeries", from: cacheSource))

        #expect(buildPayload.contains("_plannedFieldSweepManifestSeries("))
        #expect(!buildPayload.contains("manifestOrderedFieldSweeps("))
        #expect(!buildPayload.contains("_legacyApplyRawSweepOrder("))
        #expect(!buildPayload.contains("filterHiddenStackSeries("))
        #expect(!buildPayload.contains("stackingPolicy: .orderEnforcingVertical"))
        #expect(helper.contains("SeriesVisualPlanner.plan("))
        #expect(helper.contains("hiddenSeriesKeys: []"))
        #expect(helper.contains("stackingPolicy: .none"))
        #expect(!helper.contains("_legacyApplyRawSweepOrder("))
    }

    @Test("3ω legacy bridge is removed from production sources")
    func threeOmegaLegacyBridgeRemovedFromProductionSources() throws {
        let plottingSource = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Plotting.swift")
        let renderingSource = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Rendering.swift")
        let packSource = try loadSource("Sources/SpinLabApp/Features/Workbench/ThreeOmegaWorkspaceStore+Pack.swift")

        #expect(!plottingSource.contains("legacyRendererBottomToTopOrder"))
        #expect(!plottingSource.contains("_legacyApplyRawSweepOrder"))

        let rendering = try #require(extractFunction("_buildRenderer", from: renderingSource))
        let restoreFromPack = try #require(extractFunction("restoreFromPack", from: packSource))

        #expect(!rendering.contains("legacyRendererBottomToTopOrder"))
        #expect(!rendering.contains("_legacyApplyRawSweepOrder"))
        #expect(rendering.contains("manifestOrderedFieldSweeps("))
        #expect(!restoreFromPack.contains("legacyRendererBottomToTopOrder"))
        #expect(!restoreFromPack.contains("_legacyApplyRawSweepOrder"))
        #expect(restoreFromPack.contains("manifestOrderedFieldSweeps("))
    }
}
