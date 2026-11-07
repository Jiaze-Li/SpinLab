import Foundation

extension RulesBootstrapper {

    /// Called after `migrateRulesBookIfNeeded` at every startup and rules-book configure.
    ///
    /// - Missing file: seeds from bundled `library_import_rules.json`.
    /// - Incomplete file (any field empty): backs up existing file then merges defaults.
    /// - Corrupt/empty file: logs and skips — UI surfaces a "Repair" action instead.
    static func seedLibraryImportRulesIfNeeded(paths: RulesConfigPaths) {
        let fm = FileManager.default
        let url = paths.libraryImportRulesURL
        let encoder = jsonEncoder()
        let decoder = JSONDecoder()

        if !fm.fileExists(atPath: url.path) {
            guard let draft = loadDraftFromBundle() else {
                AppLogger.shared.error(.import,
                    "RulesBootstrapper: bundled library_import_rules.json not found — cannot seed")
                return
            }
            do {
                let data = try encoder.encode(draft)
                try data.write(to: url)
                AppLogger.shared.info(.import, "RulesBootstrapper: seeded library_import_rules.json from bundle")
            } catch {
                AppLogger.shared.error(.import, "RulesBootstrapper: failed to seed library_import_rules.json",
                                       metadata: ["error": error.localizedDescription])
            }
            return
        }

        let existingData: Data
        let bundleDraft: LibraryRegistryFileDraft
        let existingPartial: PartialLibraryRegistryFileDraft
        do {
            existingData = try Data(contentsOf: url)
            existingPartial = try decoder.decode(PartialLibraryRegistryFileDraft.self, from: existingData)
            guard let loadedBundleDraft = loadDraftFromBundle() else {
                AppLogger.shared.error(.import,
                    "RulesBootstrapper: bundled library_import_rules.json not found — cannot fill missing fields")
                return
            }
            bundleDraft = loadedBundleDraft
        } catch {
            AppLogger.shared.warning(.import,
                "RulesBootstrapper: library_import_rules.json exists but is corrupt; skipping auto-seed",
                metadata: ["error": error.localizedDescription])
            return
        }

        let mergedExisting = existingPartial.materialized(using: bundleDraft)
        let needsFieldFill = existingPartial.hasMissingFields || LegacyRegistryImportRulesDefaults.hasEmptyFields(mergedExisting)
        guard needsFieldFill else { return }

        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("library_import_rules_backup_\(migrationTimestamp()).json")
        do {
            try existingData.write(to: backupURL)
        } catch {
            AppLogger.shared.error(.import,
                "RulesBootstrapper: failed to back up library_import_rules.json before merge",
                metadata: ["error": error.localizedDescription])
            return
        }

        do {
            let merged = LegacyRegistryImportRulesDefaults.fillMissing(from: bundleDraft, into: mergedExisting)
            let newData = try encoder.encode(merged)
            try newData.write(to: url)
            AppLogger.shared.info(.import,
                "RulesBootstrapper: merged missing fields into library_import_rules.json",
                metadata: ["backup": backupURL.lastPathComponent])
        } catch {
            AppLogger.shared.error(.import,
                "RulesBootstrapper: failed to merge library_import_rules.json",
                metadata: ["error": error.localizedDescription])
        }
    }

    // MARK: - Helpers

    private static func loadDraftFromBundle() -> LibraryRegistryFileDraft? {
        guard let bundleURL = Bundle.spinLabConfig.url(forResource: "library_import_rules", withExtension: "json") else {
            return nil
        }
        return try? JSONDecoder().decode(LibraryRegistryFileDraft.self, from: Data(contentsOf: bundleURL))
    }

    private struct PartialLibraryRegistryFileDraft: Decodable {
        var version: Int?
        var registry: RegistryDraft?

        struct RegistryDraft: Decodable {
            var sampleHeaderAliases: [String]?
            var batchHeaderAliases: [String]?
            var substrateHeaderAliases: [String]?
            var excludedSheetNames: [String]?
            var sampleCellSeparators: String?
            var numericKeyAliases: [String: [String]]?
            var metadataLookupAliases: [String: [String]]?
        }

        var hasMissingFields: Bool {
            guard let registry else { return true }
            return version == nil
                || registry.sampleHeaderAliases == nil
                || registry.batchHeaderAliases == nil
                || registry.substrateHeaderAliases == nil
                || registry.excludedSheetNames == nil
                || registry.sampleCellSeparators == nil
                || registry.numericKeyAliases == nil
                || registry.metadataLookupAliases == nil
        }

        func materialized(using defaults: LibraryRegistryFileDraft) -> LibraryRegistryFileDraft {
            let registry = registry ?? RegistryDraft()
            return LibraryRegistryFileDraft(
                version: version ?? defaults.version,
                registry: LibraryRegistryFileDraft.RegistryDraft(
                    sampleHeaderAliases: registry.sampleHeaderAliases ?? defaults.registry.sampleHeaderAliases,
                    batchHeaderAliases: registry.batchHeaderAliases ?? defaults.registry.batchHeaderAliases,
                    substrateHeaderAliases: registry.substrateHeaderAliases ?? defaults.registry.substrateHeaderAliases,
                    excludedSheetNames: registry.excludedSheetNames ?? defaults.registry.excludedSheetNames,
                    sampleCellSeparators: registry.sampleCellSeparators ?? defaults.registry.sampleCellSeparators,
                    numericKeyAliases: registry.numericKeyAliases ?? defaults.registry.numericKeyAliases,
                    metadataLookupAliases: registry.metadataLookupAliases ?? defaults.registry.metadataLookupAliases
                )
            )
        }
    }

    private static func jsonEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}
