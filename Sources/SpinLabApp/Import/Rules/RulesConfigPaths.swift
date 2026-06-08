import Foundation

struct RulesConfigPaths {
    let configDirectoryURL: URL

    /// Caller provides the Rules Book directory directly.
    /// In production, pass the URL from RulesBookSettings.rulesBookURL.
    /// In tests, pass a tempDir to avoid touching real files.
    init(configDirectoryURL: URL) {
        self.configDirectoryURL = configDirectoryURL
    }

    // MARK: - New 5-book schema (v3)

    var importFiltersURL: URL {
        configDirectoryURL.appendingPathComponent("import_filters.json")
    }

    var filenameTokenizationURL: URL {
        configDirectoryURL.appendingPathComponent("filename_tokenization.json")
    }

    var sampleIdentificationURL: URL {
        configDirectoryURL.appendingPathComponent("sample_identification.json")
    }

    var workflowURL: URL {
        configDirectoryURL.appendingPathComponent("workflow.json")
    }

    var measuringConditionURL: URL {
        configDirectoryURL.appendingPathComponent("measuring_condition.json")
    }

    var libraryImportRulesURL: URL {
        configDirectoryURL.appendingPathComponent("library_import_rules.json")
    }

    var allSchemaFileURLs: [URL] {
        [
            importFiltersURL,
            filenameTokenizationURL,
            sampleIdentificationURL,
            workflowURL,
            measuringConditionURL
        ]
    }

    static func isRunningTests() -> Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("xctest") == .orderedSame
            || Bundle.main.bundlePath.localizedCaseInsensitiveContains(".xctest/")
    }
}
