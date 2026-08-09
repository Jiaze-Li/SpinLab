import Foundation
import Testing
@testable import SpinLabApp

// Phase 2b: Library as the single Sidecar gateway.
// Covers: bulk-read skip+warning behavior, Search resilience to a corrupt
// sidecar, Import dedup resilience + logging, Workbench RT restore routing
// through the canonical single-sidecar reader, LibraryStore's internal
// enumeration reusing the canonical reader, and an architecture guard that
// no non-Library production code decodes *.spinlab.json directly.

@Suite("Phase 2b — Library Sidecar Gateway")
struct Phase2bLibrarySidecarGatewayTests {

    // MARK: - LibrarySidecarBulkReader: skip + warning

    @Test("Bulk reader returns good sidecars and skips corrupt ones with a diagnostic count")
    func bulkReaderSkipsCorruptAndReportsCount() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeGoodSidecar(batchID: "PN01", sampleKey: "PN01|b|STO|111", fileName: "AHE_PN01.dat")
        try fixture.writeGoodSidecar(batchID: "PN02", sampleKey: "PN02|b|STO|111", fileName: "AHE_PN02.dat")
        try fixture.writeCorruptSidecar(batchID: "PN03", sampleKey: "PN03|b|STO|111", fileName: "AHE_PN03.dat")

        let spyLogger = SpyLogger()
        let reader = LibrarySidecarBulkReader(logger: spyLogger)
        let result = reader.enumerateSidecars(rootURL: fixture.rootURL, fileManager: .default)

        #expect(result.records.count == 2)
        #expect(result.diagnostics.skippedCount == 1)
        #expect(result.diagnostics.skippedPaths.count == 1)
        #expect(result.diagnostics.skippedPaths.first?.hasSuffix("AHE_PN03.dat.spinlab.json") == true)
    }

    @Test("Bulk reader logs a warning for each skipped sidecar")
    func bulkReaderLogsWarningForCorruptSidecar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeCorruptSidecar(batchID: "PN04", sampleKey: "PN04|b|STO|111", fileName: "AHE_PN04.dat")

        let spyLogger = SpyLogger()
        let reader = LibrarySidecarBulkReader(logger: spyLogger)
        _ = reader.enumerateSidecars(rootURL: fixture.rootURL, fileManager: .default)

        #expect(spyLogger.warnings.count == 1)
        #expect(spyLogger.warnings.first?.category == .library)
    }

    // MARK: - Search: corrupt sidecar no longer aborts the whole search

    @Test("Search returns good hits when one sidecar is corrupt, instead of throwing")
    func searchReturnsGoodHitsWhenOneSidecarIsCorrupt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeGoodSidecar(batchID: "PN10", sampleKey: "PN10|b|STO|111", fileName: "AHE_PN10.dat")
        try fixture.writeCorruptSidecar(batchID: "PN11", sampleKey: "PN11|b|STO|111", fileName: "AHE_PN11.dat")

        let hits = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN1"),
            libraryRootURL: fixture.rootURL
        )

        #expect(hits.count == 1)
        #expect(hits[0].sampleKey == "PN10|b|STO|111")
    }

    @Test("Search surfaces a diagnostic count for a corrupt sidecar via the bulk reader")
    func searchProducesDiagnosticForCorruptSidecar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeGoodSidecar(batchID: "PN12", sampleKey: "PN12|b|STO|111", fileName: "AHE_PN12.dat")
        try fixture.writeCorruptSidecar(batchID: "PN13", sampleKey: "PN13|b|STO|111", fileName: "AHE_PN13.dat")

        let spyReader = SpyBulkReader(wrapped: LibrarySidecarBulkReader())
        _ = try SearchWorkflowMeasurementsUseCase().execute(
            query: WorkflowSearchQuery(rawText: "PN1"),
            libraryRootURL: fixture.rootURL,
            sidecarBulkReader: spyReader
        )

        #expect(spyReader.lastResult?.diagnostics.skippedCount == 1)
    }

    // MARK: - Import dedup: valid sidecars still work, bad ones are skipped (and logged by the shared reader)

    @Test("Import dedup collects sourceFilePath from valid sidecars and skips a corrupt one")
    func importDedupSkipsCorruptSidecarButKeepsValidOnes() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeGoodSidecar(batchID: "PN20", sampleKey: "PN20|b|STO|111", fileName: "AHE_PN20.dat", sourceFilePath: "/original/AHE_PN20.dat")
        try fixture.writeCorruptSidecar(batchID: "PN21", sampleKey: "PN21|b|STO|111", fileName: "AHE_PN21.dat")

        let reader = LibrarySidecarBulkReader()
        let result = reader.enumerateSidecars(rootURL: fixture.rootURL, fileManager: .default)
        let collected = Set(result.records.map { $0.sidecar.sourceFilePath })

        #expect(collected.contains("/original/AHE_PN20.dat"))
        #expect(result.diagnostics.skippedCount == 1)
    }

    // MARK: - Workbench RT restore: routes through the canonical single-sidecar reader

    @Test("RT restore returns nil for a corrupt sidecar via the canonical reader")
    func rtRestoreReturnsNilForCorruptSidecar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let corruptPath = try fixture.writeCorruptSidecar(batchID: "PN30", sampleKey: "PN30|b|STO|111", fileName: "AHE_PN30.dat")

        let hit = ThreeOmegaWorkspaceStore.rebuildRTHit(
            fromSidecarPath: corruptPath,
            workflowID: "ahe",
            relatedRTWorkflowID: nil
        )
        #expect(hit == nil)
    }

    @Test("RT restore routes through the injected LibrarySidecarReaderCapability")
    func rtRestoreUsesInjectedReader() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        let goodPath = try fixture.writeGoodSidecar(batchID: "PN31", sampleKey: "PN31|b|STO|111", fileName: "AHE_PN31.dat", workflow: "ahe")

        let spyReader = SpyReader(wrapped: LibrarySidecarReader())
        let hit = ThreeOmegaWorkspaceStore.rebuildRTHit(
            fromSidecarPath: goodPath,
            workflowID: "ahe",
            relatedRTWorkflowID: nil,
            sidecarReader: spyReader
        )

        #expect(hit != nil)
        #expect(spyReader.loadCallCount == 1)
    }

    // MARK: - LibraryStore internal enumeration reuses the canonical reader

    @Test("LibraryStore.scanAppliedMeasurements skips a corrupt sidecar and keeps valid ones")
    func scanAppliedMeasurementsSkipsCorruptSidecar() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try fixture.writeGoodSidecar(batchID: "PN40", sampleKey: "PN40|b|STO|111", fileName: "AHE_PN40.dat")
        try fixture.writeCorruptSidecar(batchID: "PN40", sampleKey: "PN40|b|STO|111", fileName: "AHE_PN40b.dat")

        let store = LibraryStore()
        let sampleDirectory = fixture.rootURL
            .appending(path: "batches/PN/PN40/samples/PN40|b|STO|111", directoryHint: .isDirectory)
        let results = store.scanAppliedMeasurements(in: sampleDirectory)

        #expect(results.count == 1)
    }

    // MARK: - Architecture guard: no non-Library production code decodes *.spinlab.json directly

    @Test("No production code outside Library/ decodes SpinLabFileSidecar directly")
    func noDirectSidecarDecodeOutsideLibrary() throws {
        let projectRoot = Self.projectRoot
        let sourcesDir = projectRoot.appendingPathComponent("Sources/SpinLabApp", isDirectory: true)
        let libraryDir = projectRoot.appendingPathComponent("Sources/SpinLabApp/Library", isDirectory: true)

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: sourcesDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            Issue.record("Could not enumerate Sources/SpinLabApp")
            return
        }

        var violations: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard !url.path.hasPrefix(libraryDir.path) else { continue }
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if contents.contains("decode(SpinLabFileSidecar.self") {
                violations.append(url.path.replacingOccurrences(of: sourcesDir.path + "/", with: ""))
            }
        }

        #expect(violations.isEmpty, "Direct SpinLabFileSidecar decode found outside Library/: \(violations)")
    }

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // SpinLabAppTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
    }()
}

// MARK: - Test doubles

private final class SpyLogger: AppLogging {
    struct Entry {
        let category: AppLogCategory
        let message: String
    }
    private(set) var warnings: [Entry] = []

    func info(_ category: AppLogCategory, _ message: String, metadata: [String: String]) {}
    func warning(_ category: AppLogCategory, _ message: String, metadata: [String: String]) {
        warnings.append(Entry(category: category, message: message))
    }
    func error(_ category: AppLogCategory, _ message: String, metadata: [String: String]) {}
}

private final class SpyReader: LibrarySidecarReaderCapability {
    private let wrapped: any LibrarySidecarReaderCapability
    private(set) var loadCallCount = 0

    init(wrapped: any LibrarySidecarReaderCapability) {
        self.wrapped = wrapped
    }

    func loadSidecar(atPath path: String) -> SpinLabFileSidecar? {
        loadCallCount += 1
        return wrapped.loadSidecar(atPath: path)
    }

    func loadSidecar(at url: URL) -> SpinLabFileSidecar? {
        loadCallCount += 1
        return wrapped.loadSidecar(at: url)
    }
}

private final class SpyBulkReader: LibrarySidecarBulkReaderCapability {
    private let wrapped: any LibrarySidecarBulkReaderCapability
    private(set) var lastResult: SidecarBulkReadResult?

    init(wrapped: any LibrarySidecarBulkReaderCapability) {
        self.wrapped = wrapped
    }

    func enumerateSidecars(rootURL: URL, fileManager: FileManager) -> SidecarBulkReadResult {
        let result = wrapped.enumerateSidecars(rootURL: rootURL, fileManager: fileManager)
        lastResult = result
        return result
    }
}

// MARK: - Fixture

private struct Fixture {
    let rootURL: URL
    private let fileManager = FileManager.default

    init() throws {
        rootURL = fileManager.temporaryDirectory.appending(path: "spinlab-phase2b-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }

    @discardableResult
    func writeGoodSidecar(
        batchID: String,
        sampleKey: String,
        fileName: String,
        workflow: String = "ahe",
        sourceFilePath: String? = nil
    ) throws -> String {
        let measurementDirectory = rootURL
            .appending(path: "batches/PN/\(batchID)/samples/\(sampleKey)/measurements/\(workflow)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: measurementDirectory, withIntermediateDirectories: true)

        let measurementURL = measurementDirectory.appending(path: fileName)
        try Data("x,y\n1,2\n".utf8).write(to: measurementURL)

        let sidecarURL = measurementDirectory.appending(path: "\(fileName).spinlab.json")
        let sidecar = SpinLabFileSidecar(
            workflow: workflow,
            workflowDisplayName: workflow,
            channels: ["ch1"],
            sourceFilePath: sourceFilePath ?? measurementURL.path,
            appliedAt: Date(timeIntervalSince1970: 1_712_146_400),
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 0,
                ruleSetFingerprint: "test:fixture",
                appliedAt: Date(timeIntervalSince1970: 1_712_146_400),
                fields: SidecarRuleFields(sampleID: nil, conditions: [:], substrateTags: [])
            ),
            userOverrides: SidecarUserOverrides(conditions: [:]),
            sampleKey: sampleKey,
            measurementTimestamp: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sidecar).write(to: sidecarURL)
        return sidecarURL.path
    }

    @discardableResult
    func writeCorruptSidecar(
        batchID: String,
        sampleKey: String,
        fileName: String,
        workflow: String = "ahe"
    ) throws -> String {
        let measurementDirectory = rootURL
            .appending(path: "batches/PN/\(batchID)/samples/\(sampleKey)/measurements/\(workflow)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: measurementDirectory, withIntermediateDirectories: true)

        let measurementURL = measurementDirectory.appending(path: fileName)
        try Data("x,y\n1,2\n".utf8).write(to: measurementURL)

        let sidecarURL = measurementDirectory.appending(path: "\(fileName).spinlab.json")
        try Data("{ this is not valid json".utf8).write(to: sidecarURL)
        return sidecarURL.path
    }
}
