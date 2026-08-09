import Testing
import Foundation
@testable import SpinLabApp

// Phase 3c: LoadedMeasurement foundation + IV vertical slice.
// Focused tests for the shared ZurichLVMLoader itself — independent of any workflow.

@Suite("Phase 3c ZurichLVMLoader")
struct V3cZurichLVMLoaderTests {

    private func ivXFixtureURL() -> URL? {
        Bundle.module.url(forResource: "iv_x_dominant_293K", withExtension: "lvm", subdirectory: "TestData/IV")
    }

    // MARK: A — returns 11 columns

    @Test("A: generic LVM loader returns 11 columns")
    func returnsElevenColumns() throws {
        guard let url = ivXFixtureURL() else {
            Issue.record("IV fixture not found at TestData/IV/iv_x_dominant_293K.lvm")
            return
        }
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        #expect(loaded.signals.count == ZurichLVMLoader.maximumColumnCount)
        #expect(loaded.signals.count == 11)
        #expect(loaded.format == .zurichLVM)
        #expect(loaded.rowCount == 5)
        for column in loaded.signals {
            #expect(column.values.count == loaded.rowCount)
        }
    }

    // MARK: B — positional sourceColumnIndex is stable

    @Test("B: sourceColumnIndex matches array position 0...10, rawLabel is nil")
    func sourceColumnIndexIsStable() throws {
        guard let url = ivXFixtureURL() else { return }
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        for (i, column) in loaded.signals.enumerated() {
            #expect(column.sourceColumnIndex == i)
            #expect(column.rawLabel == nil)
            #expect(column.stableSourceKey == "col\(i)")
        }
    }

    // MARK: C — loader assigns no IV physical meaning

    @Test("C: generic loader assigns no physicalQuantityID to any column")
    func loaderAssignsNoPhysicalMeaning() throws {
        guard let url = ivXFixtureURL() else { return }
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        for column in loaded.signals {
            #expect(column.physicalQuantityID == nil)
        }
    }

    // MARK: D — loader performs no current conversion / unit claim

    @Test("D: generic loader makes no unit claim — sourceUnit is undeclared everywhere")
    func loaderPerformsNoCurrentConversion() throws {
        guard let url = ivXFixtureURL() else { return }
        let loaded = try ZurichLVMLoader().load(fileURL: url)
        for column in loaded.signals {
            #expect(column.sourceUnit == .undeclared)
        }
        // col0 raw values are exactly what's in the file — no A→mA or any other scaling applied.
        #expect(abs(loaded.signals[0].values[0] - 0.001) < 1e-9)
    }

    // MARK: I — malformed / no-Tableau behavior remains acceptable

    @Test("I: no-marker file with valid numeric data still parses via positional fallback")
    func noMarkerFallsBackToPositionalScan() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("no_marker_\(Int.random(in: 100_000...999_999)).lvm")
        try "0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try ZurichLVMLoader().load(fileURL: tmp)
        #expect(loaded.rowCount == 1)
        #expect(loaded.signals[0].values.count == 1)
    }

    @Test("I: file with no marker and no numeric-looking rows throws markerNotFound")
    func noMarkerNoDataThrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty_\(Int.random(in: 100_000...999_999)).lvm")
        try "not\tnumeric\tdata\tat\tall\n".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        #expect(throws: ZurichLVMLoader.LoadError.self) {
            try ZurichLVMLoader().load(fileURL: tmp)
        }
    }

    @Test("I: rows with fewer than 11 fields are silently skipped, not fatal")
    func shortRowsAreSkipped() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("short_row_\(Int.random(in: 100_000...999_999)).lvm")
        // First row is short (malformed), second is a full valid 11-field row.
        try "double header\n\nTableau:\n0.001\t0.01\n0.002\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try ZurichLVMLoader().load(fileURL: tmp)
        #expect(loaded.rowCount == 1)
        #expect(abs(loaded.signals[0].values[0] - 0.002) < 1e-9)
    }

    // MARK: Corrective pass — width inference must not lock onto a malformed leading row

    @Test("corrective: a malformed 10-column leading row does not shrink an 11-column IV file")
    func malformedShortLeadingRowDoesNotShrinkWidth() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("iv_short_leader_\(Int.random(in: 100_000...999_999)).lvm")
        // Row 1: malformed, only 10 fields (missing Frequency_after). Rows 2-3: valid 11 fields.
        let malformedRow = "0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100"
        let validRow = "0.002\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317"
        try "double header\n\nTableau:\n\(malformedRow)\n\(validRow)\n\(validRow)\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try ZurichLVMLoader().load(fileURL: tmp)
        #expect(loaded.signals.count == 11)
        #expect(loaded.rowCount == 2)
    }

    @Test("corrective: 3ω/XY 10-column files still resolve to width 10")
    func tenColumnFilesStillResolveToWidthTen() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("threeomega_\(Int.random(in: 100_000...999_999)).lvm")
        let row = "0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100"
        try "double header\n\nTableau:\n\(row)\n\(row)\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try ZurichLVMLoader().load(fileURL: tmp)
        #expect(loaded.signals.count == 10)
        #expect(loaded.rowCount == 2)
    }

    // MARK: Corrective pass — an unused, blank/non-numeric column must not discard the row

    @Test("corrective: a blank unused column does not discard the row (3ω-shaped columns)")
    func blankUnusedColumnDoesNotDiscardRowFor3Omega() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("threeomega_blank_\(Int.random(in: 100_000...999_999)).lvm")
        // Column index 3 (unused by 3ω, which only reads 0,1,5,9) is blank.
        let row = "0.001\t0.01\t0.001\t\t5.7\t0.02\t0.002\t0.02\t5.7\t100"
        try "double header\n\nTableau:\n\(row)\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try ZurichLVMLoader().load(fileURL: tmp)
        #expect(loaded.signals.count == 10)
        #expect(loaded.rowCount == 1)
        #expect(loaded.signals[3].values[0].isNaN)
        #expect(abs(loaded.signals[0].values[0] - 0.001) < 1e-9)
        #expect(abs(loaded.signals[1].values[0] - 0.01) < 1e-9)
        #expect(abs(loaded.signals[5].values[0] - 0.02) < 1e-9)
        #expect(abs(loaded.signals[9].values[0] - 100) < 1e-9)
    }

    @Test("corrective: a blank unused column does not discard the row (XY-shaped columns)")
    func blankUnusedColumnDoesNotDiscardRowForXY() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xy_blank_\(Int.random(in: 100_000...999_999)).lvm")
        let row = "0.001\t0.01\t0.001\t\t5.7\t0.02\t0.002\t0.02\t5.7\t100"
        try "double header\n\nTableau:\n\(row)\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try ZurichLVMLoader().load(fileURL: tmp)
        #expect(loaded.signals.count == 10)
        #expect(loaded.rowCount == 1)
        #expect(loaded.signals[3].values[0].isNaN)
    }

    @Test("corrective: IV's own required 11th column still carries a real value through the shared loader")
    func ivRequiredColumnStillCarriesValue() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("iv_blank_unused_\(Int.random(in: 100_000...999_999)).lvm")
        // Column index 3 blank (unused elsewhere); column 10 (Frequency_after, IV's own
        // requirement) is present and numeric — the shared loader must preserve it untouched.
        let row = "0.001\t0.01\t0.001\t\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317"
        try "double header\n\nTableau:\n\(row)\n"
            .write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let loaded = try ZurichLVMLoader().load(fileURL: tmp)
        #expect(loaded.signals.count == 11)
        #expect(loaded.rowCount == 1)
        #expect(loaded.signals[3].values[0].isNaN)
        #expect(abs(loaded.signals[10].values[0] - 317) < 1e-9)
    }
}
