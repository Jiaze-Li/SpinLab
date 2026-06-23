import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.4.1 Library Registry Bootstrapper", .serialized)
struct V541LibraryRegistryBootstrapperTests {

    private func seedPartialRegistry(at url: URL) throws {
        try """
        {
          "version": 1,
          "registry": {
            "sampleHeaderAliases": ["user-sample"],
            "batchHeaderAliases": ["user-batch"],
            "substrateHeaderAliases": ["user-substrate"],
            "excludedSheetNames": ["user-sheet"],
            "sampleCellSeparators": "|",
            "numericKeyAliases": {
              "user-key": ["custom"]
            }
          }
        }
        """.data(using: .utf8)!.write(to: url)
    }

    @Test("partial library_import_rules.json fills missing registry fields without replacing user aliases")
    func partialRegistryFileIsMergedBeforeStrictDecode() throws {
        try withTempRulesBook(prefix: "SL-library-registry-partial") { paths, _ in
            try seedPartialRegistry(at: paths.libraryImportRulesURL)

            let bundleMetadataLookupAliases = try withBundledRules { provider in
                try #require(provider.registryRules()).metadataLookupAliases
            }

            RulesBootstrapper.seedLibraryImportRulesIfNeeded(paths: paths)

            let onDisk = try JSONDecoder().decode(
                LibraryRegistryFileDraft.self,
                from: Data(contentsOf: paths.libraryImportRulesURL)
            )
            #expect(onDisk.registry.sampleHeaderAliases == ["user-sample"])
            #expect(onDisk.registry.batchHeaderAliases == ["user-batch"])
            #expect(onDisk.registry.substrateHeaderAliases == ["user-substrate"])
            #expect(onDisk.registry.excludedSheetNames == ["user-sheet"])
            #expect(onDisk.registry.sampleCellSeparators == "|")
            #expect(onDisk.registry.numericKeyAliases["user-key"] == ["custom"])
            #expect(onDisk.registry.metadataLookupAliases == bundleMetadataLookupAliases)

            let backupFiles = try FileManager.default.contentsOfDirectory(
                atPath: paths.configDirectoryURL.path
            ).filter { $0.hasPrefix("library_import_rules_backup_") }
            #expect(!backupFiles.isEmpty)
        }
    }

    @Test("corrupt library_import_rules.json is left untouched")
    func corruptRegistryFileSkipsAutoRepair() throws {
        try withTempRulesBook(prefix: "SL-library-registry-corrupt") { paths, _ in
            try "not-json".data(using: .utf8)!.write(to: paths.libraryImportRulesURL)

            RulesBootstrapper.seedLibraryImportRulesIfNeeded(paths: paths)

            let onDisk = try Data(contentsOf: paths.libraryImportRulesURL)
            #expect(String(data: onDisk, encoding: .utf8) == "not-json")

            let backupFiles = try FileManager.default.contentsOfDirectory(
                atPath: paths.configDirectoryURL.path
            ).filter { $0.hasPrefix("library_import_rules_backup_") }
            #expect(backupFiles.isEmpty)
        }
    }
}
