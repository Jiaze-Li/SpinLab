import Testing
import Foundation
@testable import SpinLabApp

// PR #148 corrective pass: ZurichLVMLoader must not impose IV's 11-column requirement on every
// workflow. 3ω and XY Rotation only need 10 columns; IV additionally needs an 11th and enforces
// that requirement itself. These tests pin the boundary at the loader and at each consumer.

@Suite("PR #148 ZurichLVMLoader column boundary")
struct PR148ZurichLVMColumnBoundaryTests {
    private func write(_ contents: String, name: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)_\(UUID().uuidString).lvm")
        try contents.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    private let tenColumnRow = "0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\n"
    private let elevenColumnRow = "0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\t317\n"

    // MARK: Loader itself

    @Test("ZurichLVMLoader accepts an exactly-10-column file and yields 10 signal columns")
    func loaderAcceptsExactlyTenColumns() throws {
        let url = try write("double header\n\nTableau:\n\(tenColumnRow)", name: "ten_col")
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try ZurichLVMLoader().load(fileURL: url)
        #expect(loaded.signals.count == 10)
        #expect(loaded.rowCount == 1)
    }

    @Test("ZurichLVMLoader accepts an 11-column file and yields 11 signal columns")
    func loaderAcceptsElevenColumns() throws {
        let url = try write("double header\n\nTableau:\n\(elevenColumnRow)", name: "eleven_col")
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try ZurichLVMLoader().load(fileURL: url)
        #expect(loaded.signals.count == 11)
    }

    @Test("ZurichLVMLoader rejects a file with fewer than 10 columns")
    func loaderRejectsFewerThanTenColumns() throws {
        let url = try write("double header\n\nTableau:\n0.001\t0.01\t0.001\n", name: "short_col")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ZurichLVMLoader.LoadError.self) {
            try ZurichLVMLoader().load(fileURL: url)
        }
    }

    // MARK: 3ω — exactly 10 columns remains valid

    @Test("ThreeOmegaLVMParser accepts an exactly-10-column row")
    func threeOmegaAcceptsTenColumnRow() throws {
        let url = try write("double header\n\nTableau:\n\(tenColumnRow)", name: "3w_ten_col")
        defer { try? FileManager.default.removeItem(at: url) }

        let file = try ThreeOmegaLVMParser().parse(fileURL: url, temperatureOverride: 4.0, kindOverride: .fieldSweep)
        #expect(file.col0.count == 1)
        #expect(file.col9.count == 1)
    }

    // MARK: XY Rotation — exactly 10 columns remains valid

    @Test("XYRotationLVMParser accepts an exactly-10-column row")
    func xyRotationAcceptsTenColumnRow() throws {
        let url = try write("double header\n\nTableau:\n\(tenColumnRow)", name: "xy_ten_col")
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 4.0)
        #expect(sweep.angleDeg.count == 1)
        #expect(sweep.resistanceXX.count == 1)
    }

    // MARK: IV — still requires its own 11th column

    @Test("IVLVMParser rejects a 10-column row: it needs the 11th column IV itself requires")
    func ivRejectsTenColumnRow() throws {
        let url = try write("double header\n\nTableau:\n\(tenColumnRow)", name: "iv_ten_col")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: IVLVMParser.ParseError.self) {
            try IVLVMParser().parse(fileURL: url, temperatureOverride: 4.0)
        }
    }

    @Test("IVLVMParser accepts an 11-column row")
    func ivAcceptsElevenColumnRow() throws {
        let url = try write("double header\n\nTableau:\n\(elevenColumnRow)", name: "iv_eleven_col")
        defer { try? FileManager.default.removeItem(at: url) }

        let sweep = try IVLVMParser().parse(fileURL: url, temperatureOverride: 4.0)
        #expect(sweep.current.count == 1)
        #expect(sweep.frequencyAfter?.count == 1)
    }
}
