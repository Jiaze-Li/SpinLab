import Foundation

/// Application Support paths for app-internal state (NOT user-editable rule files).
/// Rule JSON files live in the user-configured Rules Book directory (see RulesBookSettings).
struct AppInternalPaths {
    let appSupportDirectoryURL: URL

    var ruleSetStateURL: URL {
        appSupportDirectoryURL.appendingPathComponent("rule_set_state.json")
    }

    var rulesBookSettingsURL: URL {
        appSupportDirectoryURL.appendingPathComponent("rules_book.json")
    }

    var migrationStateURL: URL {
        appSupportDirectoryURL.appendingPathComponent(".migration_state.json")
    }

    var migrationFailedURL: URL {
        appSupportDirectoryURL.appendingPathComponent(".migration_failed.json")
    }

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)

        let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMainApp = bundleID?.caseInsensitiveCompare("com.spinlab.app") == .orderedSame
        let appFolder: String
        if !RulesConfigPaths.isRunningTests() && isMainApp {
            appFolder = "SpinLab"
        } else if let bundleID, !bundleID.isEmpty {
            appFolder = bundleID
        } else {
            appFolder = "com.spinlab.tests.\(ProcessInfo.processInfo.processIdentifier)"
        }
        appSupportDirectoryURL = base.appendingPathComponent(appFolder, isDirectory: true)
    }

    init(appSupportDirectoryURL: URL) {
        self.appSupportDirectoryURL = appSupportDirectoryURL
    }
}
