import Foundation
import Testing
@testable import SpinLabApp

@MainActor
@Suite("V5.1.12 RulesPersistence FailSoft", .serialized)
struct V5112RulesPersistenceFailSoftTests {

    // MARK: - Isolation

    private struct IsolationContext {
        let dir: URL
        let paths: RulesConfigPaths
    }

    private func acquireIsolation() throws -> IsolationContext {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-persist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return IsolationContext(dir: dir, paths: RulesConfigPaths(configDirectoryURL: dir))
    }

    private func releaseIsolation(_ ctx: IsolationContext) {
        try? FileManager.default.removeItem(at: ctx.dir)
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
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        try Data("{ bad json garbage".utf8).write(to: ctx.paths.measuringConditionURL)

        let startCount = logLineCount()
        let store = RulesManagementStore(rulesBookPaths: ctx.paths)
        store.present()
        let newLines = newLogLines(since: startCount)

        #expect(store.measuringConditionDraft == nil)
        let hasError = newLines.contains { $0.contains("rules decode failed") || $0.contains("rules read failed") }
        #expect(hasError, "Expected AppLogger to record a decode error; new log lines: \(newLines)")
    }

    @Test("corrupt import_filters.json returns nil draft and logs decode error")
    func corruptImportFiltersReturnsNilAndLogs() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        // Valid JSON but missing required fields — triggers DecodingError
        try Data(#"{"unexpected_key": 1}"#.utf8).write(to: ctx.paths.importFiltersURL)

        let startCount = logLineCount()
        let store = RulesManagementStore(rulesBookPaths: ctx.paths)
        store.present()
        let newLines = newLogLines(since: startCount)

        #expect(store.importFiltersDraft == nil)
        let hasError = newLines.contains { $0.contains("rules decode failed") || $0.contains("rules read failed") }
        #expect(hasError, "Expected AppLogger to record a decode error; new log lines: \(newLines)")
    }

    @Test("missing config files return nil drafts without logging any error")
    func missingFilesReturnSilently() throws {
        let ctx = try acquireIsolation()
        defer { releaseIsolation(ctx) }

        // Config directory present but files absent — all files are absent
        let startCount = logLineCount()
        let store = RulesManagementStore(rulesBookPaths: ctx.paths)
        store.present()
        let newLines = newLogLines(since: startCount)

        #expect(store.importFiltersDraft == nil)
        #expect(store.measuringConditionDraft == nil)
        let hasError = newLines.contains { $0.contains("rules decode failed") || $0.contains("rules read failed") }
        #expect(!hasError, "File-not-found path must produce no error log; new log lines: \(newLines)")
    }
}
