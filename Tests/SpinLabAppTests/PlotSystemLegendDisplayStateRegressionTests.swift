import Foundation
import Testing
@testable import SpinLabApp

@Suite("PlotSystem Legend Display-State Regression")
struct PlotSystemLegendDisplayStateRegressionTests {

    private func makeThreeOmegaIngestion() -> ThreeOmegaIngestionResult {
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample-a",
            sourceFilePath: "/tmp/sample-a.csv",
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 0.0,
            hc3omega: 0.0,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
        return ThreeOmegaIngestionResult(
            fieldSweeps: [sweep],
            rtResult: nil,
            device: "0deg",
            deviceMode: "single",
            devices: ["0deg"],
            iRmsValues: [100: 1e-3],
            warnings: []
        )
    }

    @MainActor
    private func makeGlobalSettings(
        store: ThreeOmegaWorkspaceStore
    ) -> ThreeOmegaRendererGlobalSettings {
        ThreeOmegaRendererGlobalSettings(
            workflowID: store.workflowID,
            showGrid: store.tabs.showPlotGrid,
            seriesRenderMode: store.tabs.seriesRenderMode,
            chartStyleOverrides: store.tabs.chartStyleOverrides,
            globalPlotDefaults: store.globalPlotDefaults,
            legendAnchor: store.tabs.legendAnchor,
            stackOffsetMultiplier: store.stackOffsetMultiplier,
            minGapFraction: store.minGapFraction,
            titleTemplate: store.titleTemplate,
            titleTokens: [:]
        )
    }

    private func assertLegendPointConsumed(
        _ layout: WorkbenchPlotLayout,
        point: CGPoint
    ) {
        guard let row = layout.legendRows.first else {
            Issue.record("legendRows should not be empty")
            return
        }
        let expectedOriginX = layout.plotRect.minX + point.x * layout.plotRect.width
        let expectedOriginY = layout.plotRect.minY + point.y * layout.plotRect.height
        #expect(abs(row.cgOriginX - expectedOriginX) < 0.5)
        #expect(abs((row.cgRowY + row.style.rowHeight * 0.4) - expectedOriginY) < 0.5)
    }

    @MainActor
    @Test("fieldSweep1omega rerender consumes legendPoint and preserves state")
    func fieldSweep1omegaRerenderConsumesLegendPoint() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeThreeOmegaIngestion()
        store.tabs.activeTab = .fieldSweep1omega

        let legendPoint = CGPoint(x: 0.2, y: 0.7)
        store.tabs.tabStates[.fieldSweep1omega] = TabRenderState(
            legendPoint: CGPointCodable(legendPoint),
            titleOverride: "Custom 1ω Title",
            axisRangeOverride: AxisRangeOverride(xMin: -1, xMax: 1, yMin: -4, yMax: 4)
        )
        let snapshot = store.tabs.displayStateSnapshot(for: .fieldSweep1omega)

        #expect(snapshot.legendPoint == legendPoint)
        #expect(store.tabs.state(for: .fieldSweep1omega).legendPoint?.cgPoint == legendPoint)

        let result = await store.renderThreeOmegaTab(
            .fieldSweep1omega,
            ingestion: try #require(store.ingestionResult),
            scalingResult: nil,
            fieldSweepSeriesOrder: nil,
            globalSettings: makeGlobalSettings(store: store),
            tabSnapshot: snapshot,
            policy: .preserveDisplayOverrides
        )

        guard let layout = result.layout else {
            Issue.record("fieldSweep1omega layout should not be nil")
            return
        }

        #expect(result.imageData != nil)
        #expect(result.displayPayload != nil)
        #expect(layout.chartTitle == "Custom 1ω Title")
        #expect(layout.axisXMin == -1)
        #expect(layout.axisXMax == 1)
        #expect(store.tabs.state(for: .fieldSweep1omega).legendPoint?.cgPoint == legendPoint)
        #expect(store.tabs.output(for: .fieldSweep1omega).layout != nil)
        assertLegendPointConsumed(layout, point: legendPoint)
    }

    @MainActor
    @Test("fieldSweep3omega rerender consumes legendPoint and preserves state")
    func fieldSweep3omegaRerenderConsumesLegendPoint() async throws {
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.ingestionResult = makeThreeOmegaIngestion()
        store.tabs.activeTab = .fieldSweep3omega

        let legendPoint = CGPoint(x: 0.65, y: 0.35)
        store.tabs.tabStates[.fieldSweep3omega] = TabRenderState(
            legendPoint: CGPointCodable(legendPoint),
            titleOverride: "Custom 3ω Title",
            axisRangeOverride: AxisRangeOverride(xMin: -2, xMax: 2, yMin: -8, yMax: 8)
        )
        let snapshot = store.tabs.displayStateSnapshot(for: .fieldSweep3omega)

        #expect(snapshot.legendPoint == legendPoint)
        #expect(store.tabs.state(for: .fieldSweep3omega).legendPoint?.cgPoint == legendPoint)

        let result = await store.renderThreeOmegaTab(
            .fieldSweep3omega,
            ingestion: try #require(store.ingestionResult),
            scalingResult: nil,
            fieldSweepSeriesOrder: nil,
            globalSettings: makeGlobalSettings(store: store),
            tabSnapshot: snapshot,
            policy: .preserveDisplayOverrides
        )

        guard let layout = result.layout else {
            Issue.record("fieldSweep3omega layout should not be nil")
            return
        }

        #expect(result.imageData != nil)
        #expect(result.displayPayload != nil)
        #expect(layout.chartTitle == "Custom 3ω Title")
        #expect(layout.axisXMin == -2)
        #expect(layout.axisXMax == 2)
        #expect(store.tabs.state(for: .fieldSweep3omega).legendPoint?.cgPoint == legendPoint)
        #expect(store.tabs.output(for: .fieldSweep3omega).layout != nil)
        assertLegendPointConsumed(layout, point: legendPoint)
    }
}
