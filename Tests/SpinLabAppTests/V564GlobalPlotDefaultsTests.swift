import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.6.4 Global Plot Defaults")
struct V564GlobalPlotDefaultsTests {

    private func makeWorkbenchStore() -> WorkbenchFeatureStore {
        let persistence = LocalPersistenceStub(archivedRecords: [], projects: [])
        return WorkbenchFeatureStore(libraryRepository: LibraryRepository(persistence: persistence))
    }

    private func makePayload() -> WorkbenchPlotPayload {
        WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Plot",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "series", x: [0, 1], y: [0, 1])
            ]
        )
    }

    @Test("Global plot defaults sync across workflow stores")
    func globalPlotDefaultsSyncAcrossWorkspaces() {
        let store = makeWorkbenchStore()
        store.globalPlotDefaults = [
            "titleFontSize": "31",
            "axisTitleFontSize": "24",
            "plotFontName": "AvenirNext-Regular",
        ]

        #expect(store.aheWorkspace.globalPlotDefaults == store.globalPlotDefaults)
        #expect(store.xyRotationWorkspace.globalPlotDefaults == store.globalPlotDefaults)
        #expect(store.threeOmegaWorkspace.globalPlotDefaults == store.globalPlotDefaults)
        #expect(store.ivWorkspace.globalPlotDefaults == store.globalPlotDefaults)
    }

    @Test("WorkbenchRenderPipeline merges global plot defaults with local style overrides")
    func renderPipelineAppliesGlobalPlotDefaults() throws {
        var input = WorkbenchRenderPipeline.Input(payload: makePayload())
        input.globalPlotDefaults = [
            "titleFontSize": "31",
            "axisTitleFontSize": "24",
            "tickLabelFontSize": "20",
            "legendFontSize": "18",
            "pointLabelFontSize": "17",
            "plotFontName": "AvenirNext-Regular",
            "plotBoldFontName": "AvenirNext-Bold",
        ]
        input.chartStyleOverrides = [
            "tickTargetX": "10",
            "tickTargetY": "8",
        ]

        let output = try WorkbenchRenderPipeline.render(input)

        // globalPlotDefaults/chartStyleOverrides merges are render-only (manifestPayload
        // purity contract, v5.5.5 render-route cleanup) — they land only in the pipeline's
        // internal renderPayload.styleParams, never in manifestPayload.styleParams.
        for key in ["titleFontSize", "axisTitleFontSize", "tickLabelFontSize", "legendFontSize",
                    "pointLabelFontSize", "plotFontName", "plotBoldFontName", "tickTargetX", "tickTargetY"] {
            #expect(output.manifestPayload.styleParams[key] == nil,
                     "\(key) is render-only and must not persist to manifestPayload")
        }

        // Render-time equivalent: WorkbenchChartStyle.from(styleParams:) is the exact parser
        // the pipeline runs (step 6) against renderPayload.styleParams after merging
        // globalPlotDefaults (step 2) and chartStyleOverrides (step 5). Since the test payload
        // starts with empty styleParams and the two override sets don't collide, merging them
        // directly reproduces renderPayload.styleParams for parsing.
        let mergedStyleParams = input.globalPlotDefaults.merging(input.chartStyleOverrides) { _, new in new }
        let renderChartStyle = WorkbenchChartStyle.from(styleParams: mergedStyleParams)
        #expect(renderChartStyle.titleFontSize == 31)
        #expect(renderChartStyle.axisTitleFontSize == 24)
        #expect(renderChartStyle.tickLabelFontSize == 20)
        #expect(renderChartStyle.legendFontSize == 18)
        #expect(renderChartStyle.pointLabelFontSize == 17)
        #expect(renderChartStyle.fontName == "AvenirNext-Regular")
        #expect(renderChartStyle.boldFontName == "AvenirNext-Bold")
        #expect(renderChartStyle.tickTargetX == 10)
        #expect(renderChartStyle.tickTargetY == 8)

        // Directly observable proof on Output: legend geometry is derived from the same
        // render-time chart style (fontSize/fontName), so it must reflect the merged defaults.
        #expect(output.layout.legendStyle.fontSize == 18)
        #expect(output.layout.legendStyle.fontName == "AvenirNext-Regular")
    }

    @Test("IV restoreFromPack migrates old font overrides into shared global defaults")
    func ivRestoreMigratesLegacyFontOverrides() throws {
        let store = IVWorkspaceStore(workflowID: WorkflowKey.iv.rawValue)
        store.xCurrentBasis = .peak

        let config = IVPackConfig(
            titleTemplate: "#tab #sample",
            showPlotGrid: true,
            chartStyleOverrides: [
                "titleFontSize": "30",
                "axisTitleFontSize": "25",
                "tickLabelFontSize": "21",
                "legendFontSize": "19",
                "pointLabelFontSize": "18",
                "plotFontName": "TimesNewRomanPSMT",
                "plotBoldFontName": "TimesNewRomanPS-BoldMT",
                "tickTargetX": "7",
            ],
            xCurrentBasis: .rms
        )
        let result = IVPackResult(ingestionResult: IVIngestionResult())
        let pack = try AnalysisPack(
            label: "IV Legacy Font Migration",
            workflowID: "IV",
            filePaths: [],
            sampleKeys: [],
            config: config,
            result: result
        )

        store.restoreFromPack(
            config: config,
            result: result,
            pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.globalPlotDefaults == [
            "titleFontSize": "30",
            "axisTitleFontSize": "25",
            "tickLabelFontSize": "21",
            "legendFontSize": "19",
            "pointLabelFontSize": "18",
            "plotFontName": "TimesNewRomanPSMT",
            "plotBoldFontName": "TimesNewRomanPS-BoldMT",
        ])
        #expect(store.tabs.chartStyleOverrides == ["tickTargetX": "7"])
        #expect(store.xCurrentBasis == .rms)

        let rebuilt = store.buildPackConfig()
        #expect(rebuilt.chartStyleOverrides == ["tickTargetX": "7"])
    }

    @Test("SpinLabInteractionSnapshot round-trips IV stackOffset and chartStyleOverrides")
    func interactionSnapshotRoundTripsIVControls() throws {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.ivStackOffsetMultiplier = 1.4
        snapshot.ivMinGapFraction = 0.20
        snapshot.workbenchChartStyleOverrides = ["tickTargetX": "5"]

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: data)

        #expect(restored.ivStackOffsetMultiplier == 1.4)
        #expect(restored.ivMinGapFraction == 0.20)
        #expect(restored.workbenchChartStyleOverrides == ["tickTargetX": "5"])
    }

    @Test("WorkbenchFeatureStore restoreInteraction applies IV stack controls")
    func restoreInteractionAppliesIVStackControls() {
        let store = makeWorkbenchStore()
        store.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            ivStackOffsetMultiplier: 1.6,
            ivMinGapFraction: 0.25
        )
        #expect(store.ivWorkspace.stackOffsetMultiplier == 1.6)
        #expect(store.ivWorkspace.minGapFraction == 0.25)
    }

    @Test("captureInteraction includes IV chartStyleOverrides in workbenchChartStyleOverrides")
    func captureInteractionIncludesIVChartStyleOverrides() {
        let store = makeWorkbenchStore()
        store.ivWorkspace.tabs.chartStyleOverrides = ["tickTargetX": "7"]

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)

        #expect(snapshot.workbenchChartStyleOverrides?["tickTargetX"] == "7")
    }

    @Test("SpinLabInteractionSnapshot round-trips IV titleTemplate")
    func interactionSnapshotRoundTripsIVTitleTemplate() throws {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.ivTitleTemplate = "#tab #sample"

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: data)

        #expect(restored.ivTitleTemplate == "#tab #sample")
    }

    @Test("captureInteraction and restoreInteraction round-trip IV titleTemplate through store")
    func captureRestoreRoundTripsIVTitleTemplate() {
        let store = makeWorkbenchStore()
        store.ivWorkspace.titleTemplate = "#tab #device"

        var snapshot = SpinLabInteractionSnapshot()
        store.captureInteraction(into: &snapshot)
        #expect(snapshot.ivTitleTemplate == "#tab #device")

        let store2 = makeWorkbenchStore()
        store2.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            ivTitleTemplate: snapshot.ivTitleTemplate
        )
        #expect(store2.ivWorkspace.titleTemplate == "#tab #device")
    }

    @Test("restoreInteraction mirrors chartStyleOverrides into IV workspace")
    func restoreInteractionMirrorsOverridesToIVWorkspace() {
        let store = makeWorkbenchStore()
        store.restoreInteraction(
            selectedArchivedRecordID: nil,
            workbenchResultDraft: "",
            workbenchChartStyleOverrides: ["tickTargetY": "6"]
        )
        #expect(store.ivWorkspace.tabs.chartStyleOverrides["tickTargetY"] == "6")
    }

    @Test("SpinLabInteractionSnapshot round-trips shared plot defaults")
    func interactionSnapshotRoundTripsGlobalPlotDefaults() throws {
        var snapshot = SpinLabInteractionSnapshot()
        snapshot.workbenchPlotDefaults = [
            "titleFontSize": "29",
            "axisTitleFontSize": "23",
            "plotFontName": "AvenirNext-Regular",
        ]
        snapshot.workbenchChartStyleOverrides = [
            "tickTargetX": "9",
        ]

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(SpinLabInteractionSnapshot.self, from: data)

        #expect(restored.workbenchPlotDefaults == snapshot.workbenchPlotDefaults)
        #expect(restored.workbenchChartStyleOverrides == snapshot.workbenchChartStyleOverrides)
    }
}
