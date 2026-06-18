import Foundation

extension RulesBootstrapper {

    /// Called after `migrateRulesBookIfNeeded` at every startup and rules-book configure.
    ///
    /// - Missing file: seeds from bundled `library_import_rules.json`, falling back
    ///   to hardcoded `LegacyRegistryImportRulesDefaults`.
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
        let existing: LibraryRegistryFileDraft
        do {
            existingData = try Data(contentsOf: url)
            existing = try decoder.decode(LibraryRegistryFileDraft.self, from: existingData)
        } catch {
            // Corrupt — do not touch, let the UI offer a repair flow
            AppLogger.shared.warning(.import,
                "RulesBootstrapper: library_import_rules.json exists but is corrupt; skipping auto-seed",
                metadata: ["error": error.localizedDescription])
            return
        }

        guard LegacyRegistryImportRulesDefaults.hasEmptyFields(existing) else { return }

        guard let bundleDraft = loadDraftFromBundle() else {
            AppLogger.shared.error(.import,
                "RulesBootstrapper: bundled library_import_rules.json not found — cannot fill missing fields")
            return
        }

        // Backup then merge missing fields from bundle
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("library_import_rules_backup_\(migrationTimestamp()).json")
        do {
            try existingData.write(to: backupURL)
            let merged = LegacyRegistryImportRulesDefaults.fillMissing(from: bundleDraft, into: existing)
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
        guard let bundleURL = Bundle.module.url(forResource: "library_import_rules", withExtension: "json") else {
            return nil
        }
        return try? JSONDecoder().decode(LibraryRegistryFileDraft.self, from: Data(contentsOf: bundleURL))
    }

    private static func jsonEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}
