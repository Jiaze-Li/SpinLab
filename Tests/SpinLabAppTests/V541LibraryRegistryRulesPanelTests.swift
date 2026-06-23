import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.4.1 Library Registry Rules Panel", .serialized)
struct V541LibraryRegistryRulesPanelTests {

    // MARK: - Isolation

    private struct IsolationContext {
        let dir: URL
        let paths: RulesConfigPaths
    }

    private func acquireIsolation() throws -> IsolationContext {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-registry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return IsolationContext(dir: dir, paths: RulesConfigPaths(configDirectoryURL: dir))
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        try? FileManager.default.removeItem(at: ctx.dir)
    }

    // MARK: - Seed helpers

    private func seedCoreBook(in iso: IsolationContext) throws {
        try writeMinimalRulesBook(to: iso.paths)
    }

    private func seedLibraryRegistry(at url: URL, extra: [String: Any] = [:]) throws {
        var dict: [String: Any] = [
            "version": 1,
            "registry": [
                "sampleHeaderAliases": ["sampleid", "编号"],
                "batchHeaderAliases": ["Batch", "BatchID"],
                "substrateHeaderAliases": ["substrate", "衬底"],
                "excludedSheetNames": ["实验大纲"],
                "sampleCellSeparators": "/,;",
                "numericKeyAliases": ["厚度": ["预打", "生长次数"]],
                "metadataLookupAliases": [
                    "batch": ["Batch", "BatchID"],
                    "sample": ["Sample", "SampleID"]
                ]
            ] as [String: Any]
        ]
        extra.forEach { dict[$0] = $1 }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: url)
    }

    // MARK: - Tests: load

    @Test("present() loads libraryRegistryDraft when file exists")
    func presentLoadsRegistryDraft() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        let d = try #require(store.libraryRegistryDraft)
        #expect(d.registry.sampleHeaderAliases.contains("编号"))
        #expect(d.registry.excludedSheetNames.contains("实验大纲"))
        #expect(d.registry.numericKeyAliases["厚度"] == ["预打", "生长次数"])
    }

    @Test("libraryRegistryDraft is nil when file is absent")
    func draftIsNilWhenFileMissing() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        #expect(store.libraryRegistryDraft == nil)
    }

    @Test("missing library_import_rules.json does not affect rulesBookState (optional file)")
    func missingRegistryFileDoesNotAffectBookState() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        guard case .ready = store.rulesBookState else {
            Issue.record("Expected .ready, got \(store.rulesBookState)")
            return
        }
    }

    // MARK: - Tests: update + dirty

    @Test("updateLibraryRegistry marks section dirty")
    func updateMarksDirty() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.sampleHeaderAliases.append("testAlias")
        store.updateLibraryRegistry(d)

        #expect(store.dirtySections.contains(.libraryRegistry))
    }

    @Test("discard clears dirty and restores disk content")
    func discardRestoresDiskContent() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.sampleHeaderAliases = ["ONLY_THIS"]
        store.updateLibraryRegistry(d)
        store.selectSection(.libraryRegistry)
        store.discardCurrent()

        #expect(!store.dirtySections.contains(.libraryRegistry))
        #expect(store.libraryRegistryDraft?.registry.sampleHeaderAliases.contains("编号") == true)
    }

    // MARK: - Tests: save round-trip

    @Test("save writes registry fields to library_import_rules.json and clears dirty")
    func saveRoundTrip() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.sampleHeaderAliases = ["myAlias"]
        d.registry.sampleCellSeparators = "/"
        store.updateLibraryRegistry(d)
        store.selectSection(.libraryRegistry)
        let outcome = store.saveCurrent()

        guard case .saved = outcome else {
            Issue.record("Expected .saved, got \(outcome)")
            return
        }
        #expect(!store.dirtySections.contains(.libraryRegistry))

        let onDisk = try JSONDecoder().decode(
            LibraryRegistryFileDraft.self,
            from: Data(contentsOf: iso.paths.libraryImportRulesURL)
        )
        #expect(onDisk.registry.sampleHeaderAliases == ["myAlias"])
        #expect(onDisk.registry.sampleCellSeparators == "/")
    }

    @Test("save reloads rules and bumps rule set version")
    func saveReloadsRules() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        var reloadCount = 0
        let store = RulesManagementStore(
            onRulesSaved: { reloadCount += 1 },
            rulesBookPaths: iso.paths
        )
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.excludedSheetNames = ["Sheet1"]
        store.updateLibraryRegistry(d)
        store.selectSection(.libraryRegistry)
        _ = store.saveCurrent()

        #expect(reloadCount == 1)
    }

    // MARK: - Tests: hash precondition

    @Test("external mutation triggers externalConflict")
    func hashConflict() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.batchHeaderAliases = ["mine"]
        store.updateLibraryRegistry(d)
        store.selectSection(.libraryRegistry)

        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL,
                                  extra: ["_externalMarker": "changed"])

        let outcome = store.saveCurrent()
        guard case .externalConflict = outcome else {
            Issue.record("Expected .externalConflict, got \(outcome)")
            return
        }
    }

    @Test("override after conflict writes draft and succeeds")
    func overrideAfterConflict() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.batchHeaderAliases = ["override"]
        store.updateLibraryRegistry(d)
        store.selectSection(.libraryRegistry)

        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)
        _ = store.saveCurrent()

        let outcome = store.overrideWithCurrentDraft(section: .libraryRegistry)
        guard case .saved = outcome else {
            Issue.record("Expected .saved on override, got \(outcome)")
            return
        }
        let onDisk = try JSONDecoder().decode(
            LibraryRegistryFileDraft.self,
            from: Data(contentsOf: iso.paths.libraryImportRulesURL)
        )
        #expect(onDisk.registry.batchHeaderAliases == ["override"])
    }

    // MARK: - Tests: validation

    @Test("validation rejects empty alias strings")
    func validationRejectsEmptyAlias() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.sampleHeaderAliases.append("")
        store.updateLibraryRegistry(d)
        store.selectSection(.libraryRegistry)

        let outcome = store.saveCurrent()
        guard case .validationFailed(let errors) = outcome else {
            Issue.record("Expected .validationFailed, got \(outcome)")
            return
        }
        #expect(errors.hasGroup("registry.sampleHeaderAliases"))
    }

    @Test("validation rejects empty numericKeyAlias key")
    func validationRejectsEmptyNumericKey() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)
        try seedLibraryRegistry(at: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()

        var d = try #require(store.libraryRegistryDraft)
        d.registry.numericKeyAliases[""] = ["something"]
        store.updateLibraryRegistry(d)
        store.selectSection(.libraryRegistry)

        let outcome = store.saveCurrent()
        guard case .validationFailed(let errors) = outcome else {
            Issue.record("Expected .validationFailed, got \(outcome)")
            return
        }
        #expect(errors.hasGroup("registry.numericKeyAliases"))
    }

    // MARK: - Tests: dead fields dropped on save

    @Test("dead JSON fields substrateMaterialTokens and substrateProcessingKeywords are not round-tripped")
    func deadFieldsNotRoundTripped() throws {
        let iso = try acquireIsolation()
        defer { releaseIsolation(iso) }
        try seedCoreBook(in: iso)

        let withDeadFields = """
        {
          "version": 1,
          "registry": {
            "sampleHeaderAliases": ["s"],
            "batchHeaderAliases": ["b"],
            "substrateHeaderAliases": ["sub"],
            "excludedSheetNames": [],
            "sampleCellSeparators": "/",
            "numericKeyAliases": {},
            "substrateMaterialTokens": ["STO","NGO"],
            "substrateProcessingKeywords": {"HF":["HF"]},
            "metadataLookupAliases": {}
          }
        }
        """
        try withDeadFields.data(using: .utf8)!.write(to: iso.paths.libraryImportRulesURL)

        let store = RulesManagementStore(rulesBookPaths: iso.paths)
        store.present()
        store.selectSection(.libraryRegistry)
        let outcome = store.saveCurrent()
        guard case .saved = outcome else {
            Issue.record("Expected .saved, got \(outcome)")
            return
        }

        let onDisk = try Data(contentsOf: iso.paths.libraryImportRulesURL)
        let json = try JSONSerialization.jsonObject(with: onDisk) as! [String: Any]
        let registry = json["registry"] as! [String: Any]
        #expect(registry["substrateMaterialTokens"] == nil)
        #expect(registry["substrateProcessingKeywords"] == nil)
    }
}
