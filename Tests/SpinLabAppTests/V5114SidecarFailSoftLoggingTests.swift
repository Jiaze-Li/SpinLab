import Testing
import Foundation
@testable import SpinLabApp

// MARK: - Mock

private final class RecordingLogger: @unchecked Sendable, AppLogging {
    struct Entry: Equatable { let level: String; let message: String }
    private(set) var entries: [Entry] = []

    func info(_ c: AppLogCategory, _ m: String, metadata: [String: String] = [:]) {
        entries.append(Entry(level: "info", message: m))
    }
    func warning(_ c: AppLogCategory, _ m: String, metadata: [String: String] = [:]) {
        entries.append(Entry(level: "warning", message: m))
    }
    func error(_ c: AppLogCategory, _ m: String, metadata: [String: String] = [:]) {
        entries.append(Entry(level: "error", message: m))
    }

    var errorCount: Int { entries.filter { $0.level == "error" }.count }
}

// MARK: - Fixture helpers

private func makeMeasurementsDir() throws -> URL {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("spinlab-sidecar-test-\(UUID().uuidString)", isDirectory: true)
    let measurementsDir = tmp.appendingPathComponent("measurements", isDirectory: true)
    try FileManager.default.createDirectory(at: measurementsDir, withIntermediateDirectories: true)
    return measurementsDir
}

private func writeMeasurementFile(in dir: URL, name: String = "test.dat") throws -> URL {
    let url = dir.appendingPathComponent(name)
    try Data("measurement".utf8).write(to: url)
    return url
}

private func writeSidecar(_ content: Data, for measurementURL: URL) throws -> URL {
    let sidecarURL = measurementURL.deletingPathExtension()
        .appendingPathExtension(measurementURL.pathExtension + ".spinlab.json")
    try content.write(to: sidecarURL)
    return sidecarURL
}

private func makeService(logger: any AppLogging) -> LibrarySidecarService {
    LibrarySidecarService(libraryStore: LibraryStore(), logger: logger)
}

private func bundleLoadResult() -> RuleLoader.LoadResult {
    RuleLoader().loadFromBundleOnly()
}

// MARK: - Tests

@Suite("V5.1.14 Sidecar Fail-Soft Logging")
struct V5114SidecarFailSoftLoggingTests {

    // INV-3 failure type A: corrupt sidecar JSON — must log logger.error
    @Test("INV-3a: corrupt sidecar read/decode triggers logger.error")
    func corruptSidecarLogsError() throws {
        let log = RecordingLogger()
        let svc = makeService(logger: log)
        let measurementsDir = try makeMeasurementsDir()
        defer { try? FileManager.default.removeItem(at: measurementsDir.deletingLastPathComponent()) }

        let measurementURL = try writeMeasurementFile(in: measurementsDir)
        _ = try writeSidecar(Data("not-valid-json!!!".utf8), for: measurementURL)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        _ = svc.recomputeSidecars(
            in: measurementsDir.deletingLastPathComponent(),
            encoder: encoder,
            loadResult: bundleLoadResult()
        )

        #expect(log.errorCount >= 1, "corrupt sidecar must produce at least one error log entry")
    }

    // INV-3 failure type B: update write failure — must log logger.error
    @Test("INV-3b: sidecar update write failure triggers logger.error")
    func updateWriteFailureLogsError() throws {
        let log = RecordingLogger()
        let svc = makeService(logger: log)
        let measurementsDir = try makeMeasurementsDir()
        defer {
            // Restore permissions before cleanup
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: measurementsDir.path)
            try? FileManager.default.removeItem(at: measurementsDir.deletingLastPathComponent())
        }

        let measurementURL = try writeMeasurementFile(in: measurementsDir)
        let sidecarURL = try writeSidecar(Data("{}".utf8), for: measurementURL)
        // Make sidecar read-only so the write back fails
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: sidecarURL.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        _ = svc.recomputeSidecars(
            in: measurementsDir.deletingLastPathComponent(),
            encoder: encoder,
            loadResult: bundleLoadResult()
        )

        #expect(log.errorCount >= 1, "update write failure must produce at least one error log entry")
    }

    // INV-3 failure type C: create write failure — must log logger.error
    @Test("INV-3c: sidecar create write failure triggers logger.error")
    func createWriteFailureLogsError() throws {
        let log = RecordingLogger()
        let svc = makeService(logger: log)
        let measurementsDir = try makeMeasurementsDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: measurementsDir.path)
            try? FileManager.default.removeItem(at: measurementsDir.deletingLastPathComponent())
        }

        _ = try writeMeasurementFile(in: measurementsDir)
        // Make measurements dir read-only so sidecar creation fails
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: measurementsDir.path)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        _ = svc.recomputeSidecars(
            in: measurementsDir.deletingLastPathComponent(),
            encoder: encoder,
            loadResult: bundleLoadResult()
        )

        #expect(log.errorCount >= 1, "sidecar create write failure must produce at least one error log entry")
    }
}
