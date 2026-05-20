import Foundation

extension RulesBootstrapper {

    static func seedMissingRuntimeFilesFromBundleIfNeeded() {
        migrateRuntimeRulesIfNeeded()
        let paths = RulesConfigPaths()
        let fm = FileManager.default
        let locator = BundleFileLocator()

        let files: [(url: URL, name: String)] = [
            (paths.importFiltersURL, "import_filters"),
            (paths.filenameTokenizationURL, "filename_tokenization"),
            (paths.sampleIdentificationURL, "sample_identification"),
            (paths.workflowURL, "workflow"),
            (paths.measuringConditionURL, "measuring_condition")
        ]

        for (url, name) in files {
            guard !fm.fileExists(atPath: url.path) else { continue }
            let data: Data?
            do {
                data = try locator.data(for: name)
            } catch {
                AppLogger.shared.warning(.import, "RulesBootstrapper: bundle file read failed — \(name).json (\(error.localizedDescription))")
                continue
            }
            guard let data else {
                AppLogger.shared.warning(.import, "RulesBootstrapper: bundle file missing — \(name).json")
                continue
            }
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                AppLogger.shared.error(.import, "RulesBootstrapper: failed to seed \(name).json", metadata: [
                    "reason": error.localizedDescription
                ])
            }
        }
    }
}
