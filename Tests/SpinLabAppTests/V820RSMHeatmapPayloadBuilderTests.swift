import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Representative file text (H K L Detector, 3×3 HL scan, K=0 fixed)

private let rsmText3x3HL = """
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

// 2×2 KL scan (H=0 fixed) for KL view tests
private let rsmText2x2KL = """
H     K     L     Detector
0.0   0.0   1.0   10.0
0.0   0.5   1.0   20.0
0.0   0.0   2.0   30.0
0.0   0.5   2.0   40.0
"""

// 2×2 HK scan (L=1 fixed) for HK view tests
private let rsmText2x2HK = """
H     K     L     Intensity
-1.0  0.0   1.0   11.0
 1.0  0.0   1.0   22.0
-1.0  1.0   1.0   33.0
 1.0  1.0   1.0   44.0
"""

// Irregular: 3 H × 3 L axis values but only 8 points
private let rsmTextIrregular = """
H     K     L     Detector
-1.0  0.0   1.0   100.0
 0.0  0.0   1.0   200.0
 1.0  0.0   1.0   150.0
-1.0  0.0   1.5   110.0
 0.0  0.0   1.5   250.0
 1.0  0.0   1.5   180.0
-1.0  0.0   2.0    90.0
 0.0  0.0   2.0   300.0
"""

// MARK: - Parser tests

@Suite("RSMDataParser")
struct RSMDataParserTests {

    @Test func parsesHKLDetectorColumns() throws {
        let dataset = try RSMDataParser.parse(text: rsmText3x3HL, title: "Test")
        #expect(dataset.points.count == 9)
        #expect(dataset.title == "Test")
        #expect(dataset.detectorColumnName == "Detector")
    }

    @Test func parsesIntensityColumnName() throws {
        let dataset = try RSMDataParser.parse(text: rsmText2x2HK)
        #expect(dataset.points.count == 4)
        #expect(dataset.detectorColumnName == "Intensity")
    }

    @Test func correctValuesForFirstPoint() throws {
        let dataset = try RSMDataParser.parse(text: rsmText3x3HL)
        let p = try #require(dataset.points.first)
        #expect(p.h == -1.0)
        #expect(p.k ==  0.0)
        #expect(p.l ==  1.0)
        #expect(p.detector == 100.0)
    }

    @Test func skipsCommentLines() throws {
        // Comment line starting with # must not appear in points
        let dataset = try RSMDataParser.parse(text: rsmText3x3HL)
        // All 9 data rows parsed; none from the comment line
        #expect(dataset.points.count == 9)
    }

    @Test func emptyTextThrows() {
        #expect(throws: RSMDataParser.ParseError.empty) {
            try RSMDataParser.parse(text: "")
        }
    }

    @Test func missingHKLThrows() {
        let noHKL = "X Y Z Value\n1.0 2.0 3.0 4.0"
        #expect(throws: (any Error).self) {
            try RSMDataParser.parse(text: noHKL)
        }
    }
}

// MARK: - CanonicalRSMDataset helpers

private func makeDataset(from text: String) throws -> CanonicalRSMDataset {
    try RSMDataParser.parse(text: text, title: "Parsed")
}

// MARK: - RSMHeatmapPayloadBuilder tests

@Suite("RSMHeatmapPayloadBuilder")
struct RSMHeatmapPayloadBuilderTests {

    // HL default: x=H, y=L, z=Detector
    @Test func hlDefaultMapsHToXAndLToY() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)

        #expect(payload.xLabel == "H (r.l.u.)")
        #expect(payload.yLabel == "L (r.l.u.)")
        #expect(payload.zLabel == "Detector")
        #expect(payload.workflowID == "rsm")
    }

    @Test func hlGridDimensions() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)

        #expect(payload.grid.nX == 3)   // H: -1.0, 0.0, 1.0
        #expect(payload.grid.nY == 3)   // L:  1.0, 1.5, 2.0
        #expect(payload.grid.isValid)
    }

    @Test func hlXValuesAreH() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)

        #expect(payload.grid.xValues == [-1.0, 0.0, 1.0])
    }

    @Test func hlYValuesAreL() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)

        #expect(payload.grid.yValues == [1.0, 1.5, 2.0])
    }

    @Test func hlZMatrixCellValues() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)

        // zMatrix[row=yIndex][col=xIndex]
        // Row 0 → L=1.0: H=-1→100, H=0→200, H=1→150
        #expect(payload.grid.zMatrix[0] == [100.0, 200.0, 150.0])
        // Row 1 → L=1.5: H=-1→110, H=0→250, H=1→180
        #expect(payload.grid.zMatrix[1] == [110.0, 250.0, 180.0])
        // Row 2 → L=2.0: H=-1→90,  H=0→300, H=1→120
        #expect(payload.grid.zMatrix[2] == [90.0, 300.0, 120.0])
    }

    // KL view: x=K, y=L
    @Test func klViewMapsKToXAndLToY() throws {
        let dataset = try makeDataset(from: rsmText2x2KL)
        let payload = try RSMHeatmapPayloadBuilder.build(
            from: dataset,
            options: .init(view: .kl)
        )

        #expect(payload.xLabel == "K (r.l.u.)")
        #expect(payload.yLabel == "L (r.l.u.)")
        #expect(payload.grid.nX == 2)   // K: 0.0, 0.5
        #expect(payload.grid.nY == 2)   // L: 1.0, 2.0
        #expect(payload.grid.isValid)
    }

    // HK view: x=H, y=K
    @Test func hkViewMapsHToXAndKToY() throws {
        let dataset = try makeDataset(from: rsmText2x2HK)
        let payload = try RSMHeatmapPayloadBuilder.build(
            from: dataset,
            options: .init(view: .hk)
        )

        #expect(payload.xLabel == "H (r.l.u.)")
        #expect(payload.yLabel == "K (r.l.u.)")
        #expect(payload.grid.nX == 2)   // H: -1.0, 1.0
        #expect(payload.grid.nY == 2)   // K:  0.0, 1.0
        #expect(payload.grid.isValid)
    }

    // zLabel inherits intensity column name from parser
    @Test func zLabelInheritsDetectorColumnName() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)
        #expect(payload.zLabel == "Detector")
    }

    @Test func zLabelIsIntensityWhenColumnIsIntensity() throws {
        let dataset = try makeDataset(from: rsmText2x2HK)  // uses "Intensity" column
        let payload = try RSMHeatmapPayloadBuilder.build(
            from: dataset,
            options: .init(view: .hk)
        )
        #expect(payload.zLabel == "Intensity")
    }

    @Test func zLabelOverrideRespected() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(
            from: dataset,
            options: .init(zLabel: "Counts (a.u.)")
        )
        #expect(payload.zLabel == "Counts (a.u.)")
    }

    @Test func titleFallsBackToDatasetTitle() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)  // title = "Parsed"
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)
        #expect(payload.title == "Parsed")
    }

    @Test func titleOverrideRespected() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(
            from: dataset,
            options: .init(title: "Override Title")
        )
        #expect(payload.title == "Override Title")
    }

    // Grid policy: irregular grid must be rejected
    @Test func irregularGridThrows() throws {
        let dataset = try makeDataset(from: rsmTextIrregular)   // 8 points, 3×3 axes
        #expect(throws: (any Error).self) {
            try RSMHeatmapPayloadBuilder.build(from: dataset)
        }
    }

    @Test func irregularGridErrorDescribesView() throws {
        let dataset = try makeDataset(from: rsmTextIrregular)
        do {
            _ = try RSMHeatmapPayloadBuilder.build(from: dataset)
            Issue.record("Expected error not thrown")
        } catch let err as RSMHeatmapPayloadBuilderError {
            if case .irregularGrid(let view, _, _, _) = err {
                #expect(view == .hl)
            } else {
                Issue.record("Unexpected error case: \(err)")
            }
        }
    }

    @Test func emptyDatasetThrows() {
        let empty = CanonicalRSMDataset(points: [], title: "", sourceRef: "", detectorColumnName: "Detector")
        #expect(throws: RSMHeatmapPayloadBuilderError.emptyDataset) {
            try RSMHeatmapPayloadBuilder.build(from: empty)
        }
    }

    // Output passes into HeatmapRenderPipeline (smoke path from Gate D)
    @Test func payloadRendersViaHeatmapPipeline() throws {
        let dataset = try makeDataset(from: rsmText3x3HL)
        let payload = try RSMHeatmapPayloadBuilder.build(from: dataset)
        let output  = try HeatmapRenderPipeline.render(.init(payload: payload))
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(output.imageData.prefix(8) == png)
    }
}
