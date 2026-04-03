import Foundation
import Testing
@testable import SpinLabApp

@Suite("V2.7.0 Audit Logger")
struct V270AuditLoggerTests {
    @Test("import apply event is written to app support and library sinks")
    func writesDualSinksWithSameEventPayload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spinlab-audit-\(UUID().uuidString)", isDirectory: true)
        let appSupport = root.appendingPathComponent("app_support", isDirectory: true)
        let libraryRoot = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let logger = AuditLogger(
            fileManager: .default,
            appSupportBaseURL: appSupport,
            maxLogFileBytes: 4096
        )
        let event = AuditEvent(
            eventID: UUID().uuidString,
            timestamp: "2026-04-03T00:00:00.000Z",
            action: "apply_import",
            sourceFileName: "PN20_RT.dat",
            sourceFilePath: "/tmp/PN20_RT.dat",
            targetDrawers: ["batches/PN20/sample/measurements/RT"],
            result: "applied",
            metadata: ["copiedTargetCount": "1"]
        )

        logger.logImportEvent(event, libraryRootURL: libraryRoot)

        let appSupportLog = appSupport
            .appendingPathComponent("SpinLab", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("import_audit.log")
        let libraryLog = libraryRoot
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("import_audit.log")

        let appSupportLines = logger.readLines(at: appSupportLog)
        let libraryLines = logger.readLines(at: libraryLog)
        #expect(appSupportLines.count == 1)
        #expect(libraryLines.count == 1)

        let decoder = JSONDecoder()
        let appSupportEvent = try decoder.decode(AuditEvent.self, from: Data(appSupportLines[0].utf8))
        let libraryEvent = try decoder.decode(AuditEvent.self, from: Data(libraryLines[0].utf8))
        #expect(appSupportEvent == event)
        #expect(libraryEvent == event)
    }
}
