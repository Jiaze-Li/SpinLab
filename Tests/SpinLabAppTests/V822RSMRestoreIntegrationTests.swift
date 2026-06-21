import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixtures

private let rsmRestoreHL3x3 = """
# RSM scan — HL plane, K=0 fixed
H        K        L        Detector
-1.0     0.0      1.0      100.0
 0.0     0.0      1.0      200.0
 1.0     0.0      1.0      150.0
-1.0     0.0      1.5      110.0
 0.0     0.0      1.5      250.0
 1.0     0.0      1.5      180.0
-1.0     0.0      2.0       90.0
 0.0     0.0      2.0      300.0
 1.0     0.0      2.0      120.0
"""

private let rsmRestoreKL2x2 = """
H     K     L     Detector
0.0   0.0   1.0   10.0
0.0   0.5   1.0   20.0
0.0   0.0   2.0   30.0
0.0   0.5   2.0   40.0
"""

private let rsmRestoreHK2x2 = """
H     K     L     Intensity
-1.0  0.0   1.0   11.0
 1.0  0.0   1.0   22.0
-1.0  1.0   1.0   33.0
 1.0  1.0   1.0   44.0
"""

private let rsmRestoreIrregularGrid = """
H     K     L     Detector
0.0   0.0   1.0   10.0
1.0   0.0   1.0   20.0
0.0   0.0   2.0   30.0
"""

// MARK: - Restore harness

private struct RSMRestoreEnvelope: Codable, Hashable, Sendable {
    var packState: RSMPackState
    var displayState: HeatmapTabRenderState
}

private struct RSMRestoreResult {
    let envelope: RSMRestoreEnvelope
    let dataset: CanonicalRSMDataset
    let payload: HeatmapPlotPayload
    let output: HeatmapRenderPipeline.Output
}

private enum RSMRestoreHarnessError: Error, Equatable {
    case missingSourceFileIdentity
}

private func restoreHeatmap(
    from envelope: RSMRestoreEnvelope,
    sourceResolver: (String) throws -> String,
    title: String = "Recovered RSM"
) throws -> RSMRestoreResult {
    guard let sourceIdentity = envelope.packState.sourceFileIdentity, !sourceIdentity.isEmpty else {
        throw RSMRestoreHarnessError.missingSourceFileIdentity
    }

    let sourceText = try sourceResolver(sourceIdentity)
    let dataset = try RSMDataParser.parse(
        text: sourceText,
        title: title,
        sourceRef: sourceIdentity
    )

    var payload = try RSMHeatmapPayloadBuilder.build(
        from: dataset,
        options: .init(
            view: envelope.packState.activeView,
            title: envelope.displayState.titleOverride.isEmpty ? dataset.title : envelope.displayState.titleOverride,
            zLabel: envelope.displayState.zLabelOverride.isEmpty ? dataset.detectorColumnName : envelope.displayState.zLabelOverride
        )
    )

    if !envelope.displayState.titleOverride.isEmpty {
        payload.title = envelope.displayState.titleOverride
    }
    if !envelope.displayState.xLabelOverride.isEmpty {
        payload.xLabel = envelope.displayState.xLabelOverride
    }
    if !envelope.displayState.yLabelOverride.isEmpty {
        payload.yLabel = envelope.displayState.yLabelOverride
    }
    if !envelope.displayState.zLabelOverride.isEmpty {
        payload.zLabel = envelope.displayState.zLabelOverride
    }
    if !envelope.displayState.colormapKey.isEmpty {
        payload.colormapKey = envelope.displayState.colormapKey
    }

    let output = try HeatmapRenderPipeline.render(
        .init(
            payload: payload,
            colorScaleMode: envelope.displayState.colorScaleMode,
            zDomainState: envelope.displayState.zDomainState,
            showColorbar: envelope.displayState.showColorbar
        )
    )

    return RSMRestoreResult(
        envelope: envelope,
        dataset: dataset,
        payload: payload,
        output: output
    )
}

private func makeEnvelope(
    sourceIdentity: String,
    detectorColumnName: String,
    activeView: RSMView = .hl,
    displayState: HeatmapTabRenderState = .init()
) -> RSMRestoreEnvelope {
    RSMRestoreEnvelope(
        packState: RSMPackState(
            sourceFileIdentity: sourceIdentity,
            detectorColumnName: detectorColumnName,
            activeView: activeView
        ),
        displayState: displayState
    )
}

private func pngHeaderMatches(_ data: Data) -> Bool {
    let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    return [UInt8](data.prefix(4)) == pngHeader
}

// MARK: - RSM restore integration tests

@Suite("RSM restore integration")
struct V822RSMRestoreIntegrationTests {

    @Test("Restore default HL view from RSMPackState")
    @MainActor
    func restoreDefaultHLViewFromPackState() throws {
        let store = RSMWorkspaceStore()
        #expect(store.activeLayout == nil)

        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-hl.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )

        let result = try restoreHeatmap(
            from: envelope,
            sourceResolver: { _ in rsmRestoreHL3x3 }
        )

        #expect(result.payload.xLabel == "H (r.l.u.)")
        #expect(result.payload.yLabel == "L (r.l.u.)")
        #expect(result.payload.zLabel == "Detector")
        #expect(!result.output.imageData.isEmpty)
        #expect(pngHeaderMatches(result.output.imageData))
        #expect(result.output.layout.zMin == 90.0)
        #expect(result.output.layout.zMax == 300.0)
        #expect(store.activeLayout == nil)
    }

    @Test("Restore KL and HK active views")
    func restoreKLHKActiveViews() throws {
        let cases: [(view: RSMView, source: String, expectedX: String, expectedY: String)] = [
            (.kl, rsmRestoreKL2x2, "K (r.l.u.)", "L (r.l.u.)"),
            (.hk, rsmRestoreHK2x2, "H (r.l.u.)", "K (r.l.u.)")
        ]

        for item in cases {
            let envelope = makeEnvelope(
                sourceIdentity: "/tmp/rsm-restore-\(item.view.rawValue).dat",
                detectorColumnName: item.source.contains("Intensity") ? "Intensity" : "Detector",
                activeView: item.view
            )

            let result = try restoreHeatmap(
                from: envelope,
                sourceResolver: { _ in item.source }
            )

            #expect(result.payload.xLabel == item.expectedX)
            #expect(result.payload.yLabel == item.expectedY)
            #expect(!result.output.imageData.isEmpty)
            #expect(pngHeaderMatches(result.output.imageData))
        }
    }

    @Test("Restore detectorColumnName into zLabel")
    func restoreDetectorColumnNameIntoZLabel() throws {
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-intensity.dat",
            detectorColumnName: "Intensity",
            activeView: .hk
        )

        let result = try restoreHeatmap(
            from: envelope,
            sourceResolver: { _ in rsmRestoreHK2x2 }
        )

        #expect(result.payload.zLabel == "Intensity")
        #expect(result.output.layout.zMin == 11.0)
        #expect(result.output.layout.zMax == 44.0)
    }

    @Test("Restore title/x/y/z label overrides")
    func restoreTitleXYZLabelOverrides() throws {
        let displayState = HeatmapTabRenderState(
            titleOverride: "Restored RSM Title",
            xLabelOverride: "Restored X",
            yLabelOverride: "Restored Y",
            zLabelOverride: "Restored Z",
            colorScaleMode: .linear
        )
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-overrides.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )

        let result = try restoreHeatmap(
            from: envelope,
            sourceResolver: { _ in rsmRestoreHL3x3 }
        )

        #expect(result.payload.title == "Restored RSM Title")
        #expect(result.payload.xLabel == "Restored X")
        #expect(result.payload.yLabel == "Restored Y")
        #expect(result.payload.zLabel == "Restored Z")
        #expect(!result.output.imageData.isEmpty)
    }

    @Test("Restore colorScaleMode log10")
    func restoreColorScaleModeLog10() throws {
        let displayState = HeatmapTabRenderState(colorScaleMode: .log10)
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-log.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )

        let result = try restoreHeatmap(
            from: envelope,
            sourceResolver: { _ in rsmRestoreHL3x3 }
        )

        let logLayout = HeatmapPlotLayout.compute(
            payload: result.payload,
            colorScaleMode: .log10
        )
        let linearLayout = HeatmapPlotLayout.compute(
            payload: result.payload,
            colorScaleMode: .linear
        )

        let renderedTicks = result.output.layout.colorbarTicks.map { (Double($0.y), $0.label) }
        let expectedLogTicks = logLayout.colorbarTicks.map { (Double($0.y), $0.label) }
        let expectedLinearTicks = linearLayout.colorbarTicks.map { (Double($0.y), $0.label) }

        #expect(renderedTicks.count == expectedLogTicks.count)
        #expect(renderedTicks.count == expectedLinearTicks.count)
        #expect(zip(renderedTicks, expectedLogTicks).allSatisfy { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1
        })
        #expect(!zip(renderedTicks, expectedLinearTicks).allSatisfy { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1
        })
    }

    @Test("Restore colormapKey")
    func restoreColormapKey() throws {
        let displayState = HeatmapTabRenderState(colormapKey: "magma")
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-magma.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )

        let result = try restoreHeatmap(
            from: envelope,
            sourceResolver: { _ in rsmRestoreHL3x3 }
        )

        #expect(result.payload.colormapKey == "magma")
        #expect(!result.output.imageData.isEmpty)
    }

    @Test("Restore manual z domain")
    func restoreManualZDomain() throws {
        let displayState = HeatmapTabRenderState(
            zDomainState: HeatmapZDomainState(
                mode: .manual,
                manualRange: HeatmapZRangeDraft(minText: "110.0", maxText: "180.0")
            )
        )
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-zrange.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )

        let result = try restoreHeatmap(
            from: envelope,
            sourceResolver: { _ in rsmRestoreHL3x3 }
        )

        #expect(result.output.layout.zMin == 110.0)
        #expect(result.output.layout.zMax == 180.0)
    }

    @Test("Missing source file / dataset recovery failure path")
    func missingSourceFileRecoveryFails() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rsm-missing-\(UUID().uuidString).dat")
        let envelope = makeEnvelope(
            sourceIdentity: tempURL.path,
            detectorColumnName: "Detector",
            activeView: .hl
        )

        #expect(throws: CocoaError.self) {
            try restoreHeatmap(
                from: envelope,
                sourceResolver: { path in try String(contentsOfFile: path, encoding: .utf8) }
            )
        }
    }

    @Test("Irregular grid failure path")
    func irregularGridFailurePath() throws {
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-irregular.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )

        #expect(throws: RSMHeatmapPayloadBuilderError.self) {
            try restoreHeatmap(
                from: envelope,
                sourceResolver: { _ in rsmRestoreIrregularGrid }
            )
        }
    }

    @Test("Invalid saved manual z domain falls back")
    func invalidSavedManualZDomainFallsBack() throws {
        let displayState = HeatmapTabRenderState(
            zDomainState: HeatmapZDomainState(
                mode: .manual,
                manualRange: HeatmapZRangeDraft(minText: "5.0", maxText: "3.0")
            )
        )
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-invalid-zrange.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )

        let result = try restoreHeatmap(
            from: envelope,
            sourceResolver: { _ in rsmRestoreHL3x3 }
        )
        #expect(result.output.layout.zMin == 90.0)
        #expect(result.output.layout.zMax == 300.0)
    }

    @Test("Encoded restore does not require rendered PNG")
    func encodedRestoreDoesNotRequireRenderedPNG() throws {
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-codable.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )

        let data = try JSONEncoder().encode(envelope)
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("imageData"))
        #expect(!json.contains("renderedPNG"))
        #expect(!json.contains("png"))
    }

    @Test("Encoded restore does not require HeatmapPlotLayout")
    func encodedRestoreDoesNotRequireHeatmapPlotLayout() throws {
        let envelope = makeEnvelope(
            sourceIdentity: "/tmp/rsm-restore-no-heatmap.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: HeatmapTabRenderState(
                titleOverride: "Layout-free restore",
                colorScaleMode: .linear
            )
        )

        let data = try JSONEncoder().encode(envelope)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Encoded restore envelope should be a JSON object.")
            return
        }
        let keys = Set(object.keys)

        #expect(!keys.contains("layout"))
        #expect(!keys.contains("HeatmapPlotLayout"))
        #expect(!keys.contains("activeLayout"))
    }

    @Test("Cartesian XY render path remains untouched")
    func cartesianXYRenderPathRemainsUntouched() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            title: "XY Restore Smoke",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(
                    label: "Series 1",
                    x: [0.0, 1.0, 2.0],
                    y: [1.0, 2.0, 3.0]
                )
            ]
        )

        let output = try WorkbenchRenderPipeline.render(.init(payload: payload))

        #expect(!output.imageData.isEmpty)
        #expect(output.layout.chartTitle == "XY Restore Smoke")
        #expect(output.layout.xAxisLabel == "X")
        #expect(output.layout.yAxisLabel == "Y")
    }
}
