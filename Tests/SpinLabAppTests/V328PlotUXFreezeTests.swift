import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.8 Plot UX Freeze")
struct V328PlotUXFreezeTests {

    // MARK: - Legend anchor: different positions produce different PNGs

    @Test("top-left anchor produces different PNG than top-right (default)")
    func topLeftDiffersFromDefault() throws {
        let base = try render(legendAnchor: "")
        let topLeft = try render(legendAnchor: "top-left")
        #expect(base != topLeft)
    }

    @Test("bottom-right anchor produces different PNG than top-right")
    func bottomRightDiffersFromDefault() throws {
        let base = try render(legendAnchor: "")
        let bottomRight = try render(legendAnchor: "bottom-right")
        #expect(base != bottomRight)
    }

    @Test("bottom-left anchor produces different PNG than top-right")
    func bottomLeftDiffersFromDefault() throws {
        let base = try render(legendAnchor: "")
        let bottomLeft = try render(legendAnchor: "bottom-left")
        #expect(base != bottomLeft)
    }

    @Test("missing legendAnchor styleParam renders same as empty string (top-right default)")
    func missingAnchorSameAsDefault() throws {
        let withEmpty = try render(legendAnchor: "")
        let withMissing = try renderPayload(styleParams: [:])   // no legendAnchor key at all
        #expect(withEmpty == withMissing)
    }

    // MARK: - Legend anchor maps to styleParams (workflow-agnostic)

    @Test("legendAnchor is stored in styleParams, not a separate payload field")
    func legendAnchorInStyleParams() {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [], styleParams: ["legendAnchor": "top-left"]
        )
        #expect(payload.styleParams["legendAnchor"] == "top-left")
    }

    @Test("all four anchor values are valid and produce distinct PNGs")
    func allFourAnchorsDistinct() throws {
        let anchors = ["", "top-left", "bottom-right", "bottom-left"]
        let renders = try anchors.map { try render(legendAnchor: $0) }

        // All four should be distinct
        for i in 0..<renders.count {
            for j in (i+1)..<renders.count {
                #expect(renders[i] != renders[j], "anchors[\(i)] and anchors[\(j)] should differ")
            }
        }
    }

    // MARK: - Legend anchor is style-only: does not affect identity key

    @Test("changing legendAnchor does not alter chart identity key")
    func legendAnchorDoesNotAffectIdentity() {
        let base = makePayload(legendAnchor: "")
        let topLeft = makePayload(legendAnchor: "top-left")
        let bottomRight = makePayload(legendAnchor: "bottom-right")

        let keyBase = WorkbenchChartIdentity.makeIdentityKey(from: base)
        let keyTopLeft = WorkbenchChartIdentity.makeIdentityKey(from: topLeft)
        let keyBottomRight = WorkbenchChartIdentity.makeIdentityKey(from: bottomRight)

        #expect(keyBase == keyTopLeft)
        #expect(keyBase == keyBottomRight)
    }

    // MARK: - Title: already workflow-agnostic, excluded from identity

    @Test("title change does not affect chart identity key")
    func titleDoesNotAffectIdentity() {
        let p1 = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "Original Title",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [1.0], sourceRef: "a.dat")]
        )
        let p2 = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "Edited Title",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [1.0], y: [1.0], sourceRef: "a.dat")]
        )
        #expect(WorkbenchChartIdentity.makeIdentityKey(from: p1) ==
                WorkbenchChartIdentity.makeIdentityKey(from: p2))
    }

    @Test("title change produces different rendered PNG")
    func titleChangeProducesDifferentPNG() throws {
        let p1 = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "Title A",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [-1.0, 0.0, 1.0], y: [1.0, 0.9, 0.8])]
        )
        let p2 = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "Title B",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [-1.0, 0.0, 1.0], y: [1.0, 0.9, 0.8])]
        )
        let png1 = try WorkbenchChartRenderer().renderPNG(payload: p1)
        let png2 = try WorkbenchChartRenderer().renderPNG(payload: p2)
        #expect(png1 != png2)
    }

    // MARK: - Interaction state contract: all UX controls map to styleParams

    @Test("showGrid and legendAnchor both live in styleParams (workflow-agnostic contract)")
    func uxControlsInStyleParams() {
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE", workflowDisplayName: "AHE", title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [],
            styleParams: ["showGrid": "true", "legendAnchor": "bottom-left"]
        )
        #expect(payload.styleParams["showGrid"] == "true")
        #expect(payload.styleParams["legendAnchor"] == "bottom-left")
    }
}

// MARK: - Helpers

private func makePayload(legendAnchor: String) -> WorkbenchPlotPayload {
    var style: [String: String] = [:]
    if !legendAnchor.isEmpty { style["legendAnchor"] = legendAnchor }
    return WorkbenchPlotPayload(
        workflowID: "AHE", workflowDisplayName: "AHE", title: "T",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: [WorkbenchPlotSeries(label: "S1", x: [-1.0, 0.0, 1.0],
                                     y: [1.0, 0.9, 0.8], sourceRef: "a.dat")],
        styleParams: style
    )
}

private func render(legendAnchor: String) throws -> Data {
    try WorkbenchChartRenderer().renderPNG(payload: makePayload(legendAnchor: legendAnchor))
}

private func renderPayload(styleParams: [String: String]) throws -> Data {
    let payload = WorkbenchPlotPayload(
        workflowID: "AHE", workflowDisplayName: "AHE", title: "T",
        axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
        series: [WorkbenchPlotSeries(label: "S1", x: [-1.0, 0.0, 1.0],
                                     y: [1.0, 0.9, 0.8])],
        styleParams: styleParams
    )
    return try WorkbenchChartRenderer().renderPNG(payload: payload)
}
