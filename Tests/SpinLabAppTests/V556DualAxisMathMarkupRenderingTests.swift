import CoreGraphics
import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.6 — DualAxisChartRenderer must consume the existing "math:" markup convention,
/// the same way WorkbenchChartRenderer and HeatmapRenderer already do (see
/// V820HeatmapRenderPathTests.heatmapRendererRoutesMathLabelsThroughMathMarkupRenderer for the
/// established test pattern this mirrors). Fixes the Temperature Dependence plot showing a
/// literal "math:E_{AHE}^{3ω} / ..." string instead of parsed subscripts/superscripts.
@Suite("v5.5.6 - DualAxis math-markup rendering")
struct V556DualAxisMathMarkupRenderingTests {

    private func makePayload(
        xLabel: String = "X",
        leftYLabel: String = "Left Y",
        rightYLabel: String = "Right Y",
        leftSeries: [DualAxisPlotSeries] = [],
        rightSeries: [DualAxisPlotSeries] = []
    ) -> DualAxisPlotPayload {
        DualAxisPlotPayload(
            workflowID: "test",
            workflowDisplayName: "Test",
            title: "Dual Axis Test",
            xLabel: xLabel,
            leftYLabel: leftYLabel,
            rightYLabel: rightYLabel,
            leftSeries: leftSeries,
            rightSeries: rightSeries
        )
    }

    private func makeLineSeries(label: String) -> DualAxisPlotSeries {
        DualAxisPlotSeries(label: label, x: [0, 1, 2], y: [0, 1, 2])
    }

    // MARK: - Source-scan proof (established pattern; no pixel/glyph introspection exists in this codebase)

    @Test("DualAxisChartRenderer routes math labels through MathMarkupRenderer")
    func dualAxisChartRendererRoutesMathLabelsThroughMathMarkupRenderer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisChartRenderer.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("MathMarkupRenderer.isMathLabel"))
        #expect(source.contains("MathMarkupRenderer.extractMathMarkup"))
        #expect(source.contains("MathMarkupRenderer.makeLine"))

        let forbidden = [
            "LatexAxisLabelRenderer",
            "LatexAxisLabelRendering",
            "LegacyAxisLabelRenderer",
            "LegacyAxisLabelRendering",
            "DeprecatedMathAxisShim",
            "latex:",
        ]
        for symbol in forbidden {
            #expect(!source.contains(symbol))
        }
    }

    // MARK: - Behavioral: rendering math-prefixed labels does not crash and produces a valid PNG

    @Test("renderPNG succeeds with math-prefixed left/right axis labels and legend")
    func renderPNGSucceedsWithMathLabels() throws {
        let payload = makePayload(
            xLabel: "Temperature (K)",
            leftYLabel: #"math:E_{AHE}^{3ω} / E_{xx}^{3} × 10^{2} (μm^{2} V^{-2})"#,
            rightYLabel: #"math:σ_{xx} × 10^{3} (S cm^{-1})"#,
            leftSeries: [makeLineSeries(label: #"math:E_{AHE}^{3ω} / E_{xx}^{3}"#)],
            rightSeries: [makeLineSeries(label: #"math:σ_{xx}"#)]
        )
        let data = try DualAxisChartRenderer().renderPNG(payload: payload)
        #expect(!data.isEmpty)
        #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    }

    // MARK: - Plain labels remain unaffected

    @Test("plain (non-math) dual-axis labels still render without going through MathMarkupRenderer's parser")
    func plainLabelsBypassMarkupParsing() {
        #expect(!MathMarkupRenderer.isMathLabel("Temperature (K)"))
        #expect(!MathMarkupRenderer.isMathLabel("μ₀H (T)"))
        #expect(!MathMarkupRenderer.isMathLabel("φ (deg)"))
    }

    @Test("renderPNG succeeds with plain dual-axis labels (regression guard)")
    func renderPNGSucceedsWithPlainLabels() throws {
        let payload = makePayload(
            xLabel: "Temperature (K)",
            leftYLabel: "μ₀H (T)",
            rightYLabel: "φ (deg)",
            leftSeries: [makeLineSeries(label: "Series A")],
            rightSeries: [makeLineSeries(label: "Series B")]
        )
        let data = try DualAxisChartRenderer().renderPNG(payload: payload)
        #expect(!data.isEmpty)
    }

    // MARK: - The math-prefixed payload/semantic labels are the established convention and must remain intact

    @Test("Temperature Dependence payload keeps math-prefixed semantic labels (convention unchanged)")
    func temperatureDependencePayloadKeepsMathPrefixedLabels() throws {
        let result = ThreeOmegaScalingResult(
            points: [
                ThreeOmegaScalingPoint(temperatureK: 10, sigma2xx: 4.0, scalingY: 3.0),
                ThreeOmegaScalingPoint(temperatureK: 20, sigma2xx: 9.0, scalingY: 1.0)
            ],
            segments: []
        )
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeTemperatureDependencePayload(result: result))

        #expect(MathMarkupRenderer.isMathLabel(payload.leftYLabel))
        #expect(MathMarkupRenderer.isMathLabel(payload.rightYLabel))
        #expect(MathMarkupRenderer.isMathLabel(payload.leftSeries.first?.label ?? ""))
        #expect(MathMarkupRenderer.isMathLabel(payload.rightSeries.first?.label ?? ""))
        #expect(!MathMarkupRenderer.isMathLabel(payload.xLabel))
    }

    // MARK: - Single-axis math label rendering must still work (no regression)

    @Test("WorkbenchChartRenderer still routes math labels through MathMarkupRenderer (single-axis unaffected)")
    func singleAxisMathLabelRenderingStillWorks() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent(
            "Sources/SpinLabApp/Workbench/V3/WorkbenchChartRenderer.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("MathMarkupRenderer.isMathLabel"))
        #expect(source.contains("MathMarkupRenderer.extractMathMarkup"))
    }
}
