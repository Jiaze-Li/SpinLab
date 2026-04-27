import Foundation

struct RulesConfigPaths {
    let configDirectoryURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMainAppBundle = bundleID?.caseInsensitiveCompare("com.spinlab.app") == .orderedSame
        let appFolder: String
        if !Self.isRunningTests() && isMainAppBundle {
            appFolder = "SpinLab"
        } else if let bundleID, !bundleID.isEmpty {
            appFolder = bundleID
        } else {
            appFolder = "com.spinlab.tests.\(ProcessInfo.processInfo.processIdentifier)"
        }

        configDirectoryURL = base
            .appendingPathComponent(appFolder, isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
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

    /// NOT included in allSchemaFileURLs; must not enter compositeHash (§1.4 [HARD]).
    var ruleSetStateURL: URL {
        configDirectoryURL.appendingPathComponent("rule_set_state.json")
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
