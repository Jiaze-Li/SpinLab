import Testing
import Foundation
@testable import SpinLabApp

// MARK: - Fakes

private final class MockRuleLoader: @unchecked Sendable, RuleProviding {
    enum Call: Equatable { case reloadCached, bumpRuleSetVersion }
    private(set) var calls: [Call] = []

    @discardableResult func reloadCached() -> RuleLoader.LoadResult {
        calls.append(.reloadCached)
        return RuleLoader().loadFromBundleOnly()
    }

    @discardableResult func bumpRuleSetVersion() -> Result<Int, Error> {
        calls.append(.bumpRuleSetVersion)
        return .success(1)
    }
}

private final class FakeAuditLogger: @unchecked Sendable, AuditLogging {
    private(set) var logImportCallCount = 0

    func logImportEvent(_ event: AuditEvent, libraryRootURL: URL) {
        logImportCallCount += 1
    }

    func logRuleWriteEvent(action: String, result: String, sourceFilePath: String, metadata: [String: String]) {}
}

private struct FakeRuleProvider: SpinLabRuleProviding {
    func loadResult() -> RuleLoader.LoadResult { RuleLoader().loadFromBundleOnly() }
    func reloadResult() -> RuleLoader.LoadResult { RuleLoader().loadFromBundleOnly() }
    func ruleSet() -> FilenameRuleSet { loadResult().ruleSet }
    func registryRules() -> FilenameRuleSet.RegistryRules { ruleSet().registry ?? FilenameRuleSet.fallback().registry! }
    func importRules() -> FilenameRuleSet.ImportRules { ruleSet().importRules ?? FilenameRuleSet.fallback().importRules! }
    func substrateConfig() -> FilenameRuleSet.SubstrateConfig? { nil }
}

// MARK: - Helpers

private func writeMinimalRulesConfig() throws -> (paths: RulesConfigPaths, cleanup: () -> Void) {
    let paths = RulesConfigPaths()
    let fm = FileManager.default
    var backup: URL?
    if fm.fileExists(atPath: paths.configDirectoryURL.path) {
        let b = paths.configDirectoryURL.appendingPathExtension("inv16-backup.\(UUID().uuidString)")
        try fm.moveItem(at: paths.configDirectoryURL, to: b)
        backup = b
    }
    try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
    try """
    {"version":1,"import":{"supportedFileExtensions":["dat"],"ignoredFileExtensions":[]}}
    """.data(using: .utf8)!.write(to: paths.importFiltersURL)
    try """
    {"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}
    """.data(using: .utf8)!.write(to: paths.filenameTokenizationURL)
    try """
    {"version":4,"sampleId":{"batchPrefixes":["S"]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}
    """.data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
    try """
    {"version":1,"workflows":[],"measurementTagRules":[]}
    """.data(using: .utf8)!.write(to: paths.workflowURL)
    try """
    {"version":2,"conditionDefinitions":[]}
    """.data(using: .utf8)!.write(to: paths.measuringConditionURL)
    let cleanup: () -> Void = {
        try? fm.removeItem(at: paths.configDirectoryURL)
        if let backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: paths.configDirectoryURL)
        }
        _ = RuleLoader.shared.reloadCached()
    }
    return (paths, cleanup)
}

// MARK: - Tests

@Suite("V5.1.14 Shared Singleton Absence (INV-16)", .serialized)
@MainActor
struct V5114SharedSingletonAbsenceTests {

    // INV-16a: RulesManagementStore save chain routes through injected RuleProviding
    @Test("INV-16a: RulesManagementStore persist calls injected ruleLoader, not RuleLoader.shared directly")
    func rulesSaveChainUsesInjectedLoader() throws {
        let (_, cleanup) = try writeMinimalRulesConfig()
        defer { cleanup() }

        let mockLoader = MockRuleLoader()
        let store = RulesManagementStore(ruleLoader: mockLoader)
        store.present()

        let outcome = store.saveCurrent()
        guard case .saved = outcome else { return }

        #expect(mockLoader.calls.contains(.reloadCached),
                "injected ruleLoader must receive reloadCached() after save")
        #expect(mockLoader.calls.contains(.bumpRuleSetVersion),
                "injected ruleLoader must receive bumpRuleSetVersion() after save")
    }

    // INV-16b: InboxArchiveApplyService routes audit through injected AuditLogging
    @Test("INV-16b: InboxArchiveApplyService routes audit log through injected AuditLogging")
    func applyAuditUsesInjectedLogger() throws {
        let fakeAudit = FakeAuditLogger()
        let service = InboxArchiveApplyService(auditLogger: fakeAudit)

        let pending = SpinLabDomain.PendingImport(
            fileName: "test.dat",
            sourceFilePath: "/nonexistent/\(UUID().uuidString)/test.dat",
            parsedHints: SpinLabDomain.ParsedFilenameHints()
        )
        let libraryIndex = LibraryIndex(
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            registryInternalPath: nil,
            registrySourcePath: nil,
            batches: [],
            samples: []
        )

        do {
            _ = try service.apply(
                pending: pending,
                targets: [],
                libraryIndex: libraryIndex,
                libraryStore: LibraryStore(),
                libraryRootURL: URL(fileURLWithPath: "/tmp/inv16-library")
            )
        } catch {
            // Expected: sourceFileNotFound; audit event was logged before throwing
        }

        #expect(fakeAudit.logImportCallCount >= 1,
                "injected AuditLogging must receive logImportEvent() instead of AuditLogger.shared")
    }

    // INV-16c: InboxArchiveApplyService init accepts SpinLabRuleProviding substitute (compile-time)
    @Test("INV-16c: InboxArchiveApplyService init accepts SpinLabRuleProviding substitute")
    func applyServiceAcceptsRuleProviderSubstitute() {
        let fakeProvider = FakeRuleProvider()
        let service = InboxArchiveApplyService(ruleProvider: fakeProvider)
        _ = service
    }
}
