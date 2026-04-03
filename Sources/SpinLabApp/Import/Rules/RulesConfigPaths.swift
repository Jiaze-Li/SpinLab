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

    var ruleURL: URL {
        configDirectoryURL.appendingPathComponent("filename_rules.json")
    }

    var workflowMatchRulesURL: URL {
        configDirectoryURL.appendingPathComponent("workflow_match_rules.json")
    }

    var sampleIDRulesURL: URL {
        configDirectoryURL.appendingPathComponent("sample_id_rules.json")
    }

    var conditionsRulesURL: URL {
        configDirectoryURL.appendingPathComponent("conditions_rules.json")
    }

    var substrateRulesURL: URL {
        configDirectoryURL.appendingPathComponent("substrate_rules.json")
    }

    var measurementTagRulesURL: URL {
        configDirectoryURL.appendingPathComponent("measurement_tag_rules.json")
    }

    static func isRunningTests() -> Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("xctest") == .orderedSame
            || Bundle.main.bundlePath.localizedCaseInsensitiveContains(".xctest/")
    }
}
