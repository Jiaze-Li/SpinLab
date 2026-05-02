import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.12 RulesPersistence FailSoft", .serialized)
struct V5112RulesPersistenceFailSoftTests {

    // MARK: - Isolation

    private static let backupExtension = "v5112-persist-backup"

    private func acquireIsolation() throws -> (dir: URL, backup: URL?) {
        purgeStaleBackups()
        let dir = RulesConfigPaths().configDirectoryURL
        let fm = FileManager.default
        var backup: URL? = nil
        if fm.fileExists(atPath: dir.path) {
            let candidate = dir.appendingPathExtension("\(Self.backupExtension).\(UUID().uuidString)")
            try fm.moveItem(at: dir, to: candidate)
            backup = candidate
        }
        return (dir, backup)
    }

    private func releaseIsolation(dir: URL, backup: URL?) {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try? fm.removeItem(at: dir)
        }
        if let backup, fm.fileExists(atPath: backup.path) {
            try? fm.moveItem(at: backup, to: dir)
        }
        _ = RuleLoader.shared.reloadCached()
    }

    private func purgeStaleBackups() {
        let dir = RulesConfigPaths().configDirectoryURL
        let parent = dir.deletingLastPathComponent()
        let prefix = dir.lastPathComponent + "." + Self.backupExtension
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return }
        for entry in entries where entry.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(entry, isDirectory: true))
        }
    }

    // MARK: - Logger helper

    private func logFileURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appending(path: "SpinLab/logs/app_events.log")
    }

    private func logLineCount() -> Int {
        guard let data = try? Data(contentsOf: logFileURL()),
              let text = String(data: data, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }

    private func newLogLines(since startCount: Int) -> [String] {
        guard let data = try? Data(contentsOf: logFileURL()),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let all = text.split(whereSeparator: \.isNewline).map(String.init)
        guard all.count > startCount else { return [] }
        return Array(all[startCount...])
    }

    // MARK: - Tests

    @Test("corrupt measuring_condition.json returns nil draft and logs decode error")
    func corruptMeasuringConditionReturnsNilAndLogs() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = RulesConfigPaths()
        try Data("{ bad json garbage".utf8).write(to: paths.measuringConditionURL)

        let startCount = logLineCount()
        let store = RulesManagementStore()
        store.present()
        let newLines = newLogLines(since: startCount)

        #expect(store.measuringConditionDraft == nil)
        let hasError = newLines.contains { $0.contains("rules decode failed") || $0.contains("rules read failed") }
        #expect(hasError, "Expected AppLogger to record a decode error; new log lines: \(newLines)")
    }

    @Test("corrupt import_filters.json returns nil draft and logs decode error")
    func corruptImportFiltersReturnsNilAndLogs() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let paths = RulesConfigPaths()
        // Valid JSON but missing required fields — triggers DecodingError
        try Data(#"{"unexpected_key": 1}"#.utf8).write(to: paths.importFiltersURL)

        let startCount = logLineCount()
        let store = RulesManagementStore()
        store.present()
        let newLines = newLogLines(since: startCount)

        #expect(store.importFiltersDraft == nil)
        let hasError = newLines.contains { $0.contains("rules decode failed") || $0.contains("rules read failed") }
        #expect(hasError, "Expected AppLogger to record a decode error; new log lines: \(newLines)")
    }

    @Test("missing config files return nil drafts without logging any error")
    func missingFilesReturnSilently() throws {
        let (dir, backup) = try acquireIsolation()
        defer { releaseIsolation(dir: dir, backup: backup) }

        // Config directory absent entirely — all files are absent
        let startCount = logLineCount()
        let store = RulesManagementStore()
        store.present()
        let newLines = newLogLines(since: startCount)

        #expect(store.importFiltersDraft == nil)
        #expect(store.measuringConditionDraft == nil)
        let hasError = newLines.contains { $0.contains("rules decode failed") || $0.contains("rules read failed") }
        #expect(!hasError, "File-not-found path must produce no error log; new log lines: \(newLines)")
    }
}
