import Foundation
import Testing
@testable import SpinLabApp

// TestRecord architecture Phase 1: MeasurementTimestampResolver.
// Covers regression cases C, D, E from the Phase 1 implementation spec.

@Suite("TestRecord Phase 1 — MeasurementTimestampResolver")
struct TestRecordPhase1TimestampResolverTests {

    private func makeTmpFile(name: String, contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-timestamp-resolver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - C: DAT FILEOPENTIME parses correctly

    @Test("PPMS .dat FILEOPENTIME parses to instrumentHeader with rawText preserved")
    func datFileOpenTimeParses() throws {
        let content = """
        [Header]
        TITLE, default name
        FILEOPENTIME,38091212.03,3/18/2026,1:24 PM
        BYAPP, Resistivity, 2.1, 1.0
        [Data]
        Temperature (K),Bridge 1 Resistance (Ohms)
        170.0,100.0
        """
        let url = try makeTmpFile(name: "xy_rotation_sample.dat", contents: content)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = MeasurementTimestampResolver().resolve(fileURL: url)

        #expect(result.provenance == .instrumentHeader)
        #expect(result.rawText == "3/18/2026,1:24 PM")

        let expectedFormatter = DateFormatter()
        expectedFormatter.locale = Locale(identifier: "en_US_POSIX")
        expectedFormatter.calendar = Calendar(identifier: .gregorian)
        expectedFormatter.timeZone = TimeZone.current
        expectedFormatter.dateFormat = "M/d/yyyy,h:mm a"
        let expectedDate = expectedFormatter.date(from: "3/18/2026,1:24 PM")
        #expect(result.value == expectedDate)
    }

    @Test("DAT without FILEOPENTIME resolves to unknown")
    func datWithoutFileOpenTimeResolvesUnknown() throws {
        let content = """
        [Header]
        TITLE, default name
        [Data]
        Temperature (K),Bridge 1 Resistance (Ohms)
        170.0,100.0
        """
        let url = try makeTmpFile(name: "no_header_time.dat", contents: content)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = MeasurementTimestampResolver().resolve(fileURL: url)

        #expect(result.provenance == .unknown)
        #expect(result.value == nil)
    }

    // MARK: - D: LVM YYYYMMDDHHMMSS filename prefix parses correctly

    @Test("LVM filename prefix YYYYMMDDHHMMSS parses to filename provenance")
    func lvmFilenamePrefixParses() throws {
        let url = try makeTmpFile(name: "20260430211659_3w_0deg.lvm", contents: "Tableau:\n1\t2\t3")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = MeasurementTimestampResolver().resolve(fileURL: url)

        #expect(result.provenance == .filename)
        #expect(result.rawText == "20260430211659")

        var expectedComponents = DateComponents()
        expectedComponents.year = 2026
        expectedComponents.month = 4
        expectedComponents.day = 30
        expectedComponents.hour = 21
        expectedComponents.minute = 16
        expectedComponents.second = 59
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let expectedDate = calendar.date(from: expectedComponents)
        #expect(result.value == expectedDate)
    }

    // MARK: - E: LVM without filename timestamp falls back to source contentModificationDate

    @Test("LVM without filename timestamp falls back to source file's contentModificationDate")
    func lvmWithoutFilenameTimestampFallsBackToMtime() throws {
        let url = try makeTmpFile(name: "3w_0deg_T_4.999 K_Iac_0.001000 A.lvm", contents: "Tableau:\n1\t2\t3")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let expectedMtime = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let result = MeasurementTimestampResolver().resolve(fileURL: url)

        #expect(result.provenance == .filesystemFallback)
        #expect(result.rawText == nil)
        #expect(result.value == expectedMtime)
    }

    @Test("filename prefix takes precedence over filesystem fallback when both are available")
    func filenamePrefixPrecedesFilesystemFallback() throws {
        let url = try makeTmpFile(name: "20260430211659_should_win.lvm", contents: "Tableau:\n1\t2\t3")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let result = MeasurementTimestampResolver().resolve(fileURL: url)

        #expect(result.provenance == .filename)
    }
}
