import Testing
import Foundation
@testable import SpinLabApp

// PR #148 corrective pass round 3: after the shared ZurichLVMLoader began preserving
// malformed rows as NaN instead of dropping them, ThreeOmegaLVMParser/XYRotationLVMParser's
// I_rms averaging window and IVLVMParser's channel arrays could be starved or corrupted by
// malformed required-column rows occupying the historical fixed physical-row slice. These
// tests pin the restored historical semantics: a *valid-ratio* window for 3ω/XY, and
// required-column row filtering (with preserved cross-array alignment) for IV.

@Suite("PR #148 ThreeOmega/XY I_rms valid-row window")
struct PR148ThreeOmegaXYValidRowWindowTests {

    private func writeLVM(rows: [String]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr148_lvm_\(UUID().uuidString).lvm")
        let content = "double header\n\nTableau:\n" + rows.joined(separator: "\n") + "\n"
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    /// 10-column row (3ω/XY width). col1 and col9 are the ratio's numerator/denominator.
    private func row(col0: Double = 0.001, col1: String, col9: String) -> String {
        "\(col0)\t\(col1)\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t\(col9)"
    }

    private func validRow(col1: Double, col9: Double) -> String {
        row(col1: "\(col1)", col9: "\(col9)")
    }

    private func malformedRow() -> String {
        // Blank col1 — the shared loader keeps the row (row alignment preserved) but col1
        // becomes NaN, matching real Zurich instrument dropouts.
        row(col1: "", col9: "100")
    }

    // MARK: ThreeOmega

    @Test("ThreeOmega: first 20 physical rows invalid, later valid rows exist -> succeeds")
    func threeOmegaFirst20InvalidLaterValidSucceeds() throws {
        var rows = Array(repeating: malformedRow(), count: 20)
        rows += (0..<20).map { validRow(col1: 0.001 + Double($0) * 1e-6, col9: 100) }
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try ThreeOmegaLVMParser().parse(fileURL: url, temperatureOverride: 4.999, kindOverride: .fieldSweep)
        #expect(file.iRms > 0)
        #expect(file.iRms.isFinite)
    }

    @Test("ThreeOmega: mixture of valid/invalid rows uses first 20 valid ratios")
    func threeOmegaMixtureUsesFirst20ValidRatios() throws {
        var rows: [String] = []
        var expectedRatios: [Double] = []
        for i in 0..<50 {
            if i % 3 == 0 {
                rows.append(malformedRow())
            } else {
                let col1 = 0.001 + Double(i) * 1e-6
                let col9 = 100.0
                rows.append(validRow(col1: col1, col9: col9))
                if expectedRatios.count < 20 {
                    expectedRatios.append(col1 / col9)
                }
            }
        }
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try ThreeOmegaLVMParser().parse(fileURL: url, temperatureOverride: 4.999, kindOverride: .fieldSweep)
        let expected = expectedRatios.reduce(0, +) / Double(expectedRatios.count)
        #expect(abs(file.iRms - expected) < 1e-12)
    }

    @Test("ThreeOmega: no valid ratios anywhere in the file still fails")
    func threeOmegaNoValidRatiosStillFails() throws {
        let rows = Array(repeating: malformedRow(), count: 25)
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ThreeOmegaLVMParser.ParseError.self) {
            try ThreeOmegaLVMParser().parse(fileURL: url, temperatureOverride: 4.999, kindOverride: .fieldSweep)
        }
    }

    // MARK: XY Rotation

    @Test("XY Rotation: first 20 physical rows invalid, later valid rows exist -> succeeds")
    func xyFirst20InvalidLaterValidSucceeds() throws {
        var rows = Array(repeating: malformedRow(), count: 20)
        rows += (0..<20).map { validRow(col1: 0.001 + Double($0) * 1e-6, col9: 100) }
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80.0)
        #expect(sweep.resistanceXY?.allSatisfy { $0.isFinite } == true)
    }

    @Test("XY Rotation: mixture of valid/invalid rows uses first 20 valid ratios")
    func xyMixtureUsesFirst20ValidRatios() throws {
        var rows: [String] = []
        var expectedRatios: [Double] = []
        for i in 0..<50 {
            if i % 3 == 0 {
                rows.append(malformedRow())
            } else {
                let col1 = 0.001 + Double(i) * 1e-6
                let col9 = 100.0
                rows.append(validRow(col1: col1, col9: col9))
                if expectedRatios.count < 20 {
                    expectedRatios.append(col1 / col9)
                }
            }
        }
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        // Rxy = col5 / I_rms; recover I_rms indirectly by comparing against the independently
        // computed expected average, matching the exact-precision style already used for 3ω.
        let expectedIRms = expectedRatios.reduce(0, +) / Double(expectedRatios.count)
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80.0)
        // col5 (the 6th tab field) is fixed at 0.02 in every row (see `row(col0:col1:col9:)`);
        // Rxy = col5 / I_rms.
        let rxy = try #require(sweep.resistanceXY?.first)
        #expect(abs(rxy - 0.02 / expectedIRms) < 1e-9)
    }

    @Test("XY Rotation: no valid ratios anywhere in the file still fails")
    func xyNoValidRatiosStillFails() throws {
        let rows = Array(repeating: malformedRow(), count: 25)
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: XYRotationLVMParser.ParseError.self) {
            try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80.0)
        }
    }
}

@Suite("PR #148 IVLVMParser required-column row filtering")
struct PR148IVLVMParserRequiredColumnFilteringTests {

    private func writeLVM(rows: [String]) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr148_iv_lvm_\(UUID().uuidString).lvm")
        let content = "double header\n\nTableau:\n" + rows.joined(separator: "\n") + "\n"
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    /// 11-column row (IV width). `current`=col0, ch1X=col1, ch1Y=col2, ch2X=col5, ch2Y=col6.
    private func validRow(current: Double, ch1X: Double, ch1Y: Double, ch2X: Double, ch2Y: Double) -> String {
        "\(current)\t\(ch1X)\t\(ch1Y)\t0.01\t5.7\t\(ch2X)\t\(ch2Y)\t0.02\t5.7\t100\t317"
    }

    /// A malformed row: blank `ch1X`, IV's own required column.
    private func malformedRow() -> String {
        "0.001\t\t0.01\t0.01\t5.7\t0.002\t0.02\t0.02\t5.7\t100\t317"
    }

    @Test("one malformed row among valid rows is skipped")
    func oneMalformedRowAmongValidRowsIsSkipped() throws {
        let rows = [
            validRow(current: 0.001, ch1X: 0.01, ch1Y: 0.02, ch2X: 0.03, ch2Y: 0.04),
            malformedRow(),
            validRow(current: 0.003, ch1X: 0.05, ch1Y: 0.06, ch2X: 0.07, ch2Y: 0.08)
        ]
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 5.0)
        #expect(sweep.current.count == 2)
        #expect(sweep.current == [0.001, 0.003])
        #expect(sweep.ch1X == [0.01, 0.05])
    }

    @Test("malformed first row + valid later rows succeeds")
    func malformedFirstRowPlusValidLaterRowsSucceeds() throws {
        let rows = [
            malformedRow(),
            validRow(current: 0.001, ch1X: 0.01, ch1Y: 0.02, ch2X: 0.03, ch2Y: 0.04),
            validRow(current: 0.002, ch1X: 0.011, ch1Y: 0.021, ch2X: 0.031, ch2Y: 0.041)
        ]
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 5.0)
        #expect(sweep.current.count == 2)
        #expect(sweep.current == [0.001, 0.002])
    }

    @Test("all malformed required rows fails")
    func allMalformedRequiredRowsFails() throws {
        let rows = [malformedRow(), malformedRow(), malformedRow()]
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: IVLVMParser.ParseError.self) {
            try IVLVMParser().parse(fileURL: url, temperatureOverride: 5.0)
        }
    }

    @Test("retained arrays remain aligned across all IV fields")
    func retainedArraysRemainAligned() throws {
        let rows = [
            validRow(current: 0.001, ch1X: 0.01, ch1Y: 0.02, ch2X: 0.03, ch2Y: 0.04),
            malformedRow(),
            validRow(current: 0.003, ch1X: 0.05, ch1Y: 0.06, ch2X: 0.07, ch2Y: 0.08),
            malformedRow(),
            validRow(current: 0.009, ch1X: 0.09, ch1Y: 0.10, ch2X: 0.11, ch2Y: 0.12)
        ]
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 5.0)
        #expect(sweep.current == [0.001, 0.003, 0.009])
        #expect(sweep.ch1X == [0.01, 0.05, 0.09])
        #expect(sweep.ch1Y == [0.02, 0.06, 0.10])
        #expect(sweep.ch2X == [0.03, 0.07, 0.11])
        #expect(sweep.ch2Y == [0.04, 0.08, 0.12])
        // Raw audit/reference arrays stay aligned to the same retained rows too.
        #expect(sweep.firstRH?.count == 3)
        #expect(sweep.frequencyAfter?.count == 3)
    }

    @Test("no NaN reaches the retained channel arrays used for classification/fitting")
    func noNaNReachesRetainedChannelArrays() throws {
        let rows = [
            malformedRow(),
            validRow(current: 0.001, ch1X: 0.01, ch1Y: 0.02, ch2X: 0.03, ch2Y: 0.04),
            malformedRow(),
            validRow(current: 0.002, ch1X: 0.011, ch1Y: 0.021, ch2X: 0.031, ch2Y: 0.041)
        ]
        let url = try writeLVM(rows: rows)
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 5.0)
        #expect(sweep.current.allSatisfy { $0.isFinite })
        #expect(sweep.ch1X.allSatisfy { $0.isFinite })
        #expect(sweep.ch1Y.allSatisfy { $0.isFinite })
        #expect(sweep.ch2X.allSatisfy { $0.isFinite })
        #expect(sweep.ch2Y.allSatisfy { $0.isFinite })

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: "iv-1",
            measurementFilePath: url.path,
            sourceFilePath: url.path,
            workflowID: "iv",
            workflowDisplayName: "IV",
            workflowCanonicalID: "iv",
            batchID: "batch",
            sampleKey: "S1",
            sampleSubstrate: "STO",
            conditions: ["temperature": "5K"],
            channels: [],
            appliedAt: .distantPast
        )
        let ingestion = IngestIVSelectionsUseCase().execute(hits: [hit])
        #expect(ingestion.ch1State.confidence.isFinite)
        #expect(ingestion.ch2State.confidence.isFinite)
    }
}
