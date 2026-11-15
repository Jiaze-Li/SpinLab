import Foundation
import Testing
@testable import SpinLabApp

@Suite("Web Library Auto Publisher", .serialized)
struct WebLibraryAutoPublisherTests {
    /// Stand-in for the app: counts publishes, and lets the test decide when the wait ends.
    @MainActor
    final class Harness {
        var running = false
        var started = 0
        var waiters: [CheckedContinuation<Void, Error>] = []
        lazy var publisher = WebLibraryAutoPublisher(
            delay: .seconds(5),
            isPublishing: { [unowned self] in running },
            startPublish: { [unowned self] in started += 1; running = true },
            sleep: { [unowned self] _ in
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { waiters.append($0) }
                } onCancel: {
                    Task { @MainActor in self.cancelAll() }
                }
            }
        )

        /// Ends the wait that is still counting (the newest one).
        func endWait() { waiters.popLast()?.resume() }
        private func cancelAll() {
            let old = waiters.dropLast()
            waiters = Array(waiters.suffix(1))
            for w in old { w.resume(throwing: CancellationError()) }
        }
        func settle() async { for _ in 0..<20 { await Task.yield() } }
    }

    @Test("A save starts one publish after the wait, not before")
    @MainActor func saveStartsOnePublish() async {
        let h = Harness()
        h.publisher.requestPublish()
        await h.settle()
        #expect(h.started == 0)
        h.endWait()
        await h.settle()
        #expect(h.started == 1)
    }

    @Test("Saves in a row become one publish")
    @MainActor func savesInARowMakeOnePublish() async {
        let h = Harness()
        h.publisher.requestPublish()
        await h.settle()
        h.publisher.requestPublish()
        await h.settle()
        h.publisher.requestPublish()
        await h.settle()
        h.endWait()
        await h.settle()
        #expect(h.started == 1)
    }

    @Test("A save during a running publish gets one more publish when it ends")
    @MainActor func saveDuringPublishIsNotLost() async {
        let h = Harness()
        h.running = true
        h.publisher.requestPublish()
        await h.settle()
        h.endWait()
        await h.settle()
        #expect(h.started == 0)           // not started on top of the running one
        h.running = false
        h.publisher.publishFinished()
        await h.settle()
        #expect(h.started == 1)           // owed publish runs now
        h.running = false
        h.publisher.publishFinished()
        await h.settle()
        #expect(h.started == 1)           // nothing more owed
    }

    @Test("A publish ending with nothing owed starts nothing")
    @MainActor func nothingOwedStartsNothing() async {
        let h = Harness()
        h.publisher.publishFinished()
        await h.settle()
        #expect(h.started == 0)
    }

    @Test("A publish ending while the wait is still counting leaves it to the timer")
    @MainActor func finishedDuringWaitLeavesItToTheTimer() async {
        let h = Harness()
        h.publisher.requestPublish()
        await h.settle()
        h.publisher.publishFinished()
        await h.settle()
        #expect(h.started == 0)
        h.endWait()
        await h.settle()
        #expect(h.started == 1)
    }
}

/// The Rules Panel tells the app which section was saved, and only after the save really happened.
@MainActor
@Suite("Rules save reports the saved section", .serialized, .rulesGlobalState)
struct RulesSaveSectionCallbackTests {
    private func writeBook(to paths: RulesConfigPaths) throws {
        try FileManager.default.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
        try #"{"version":1,"import":{"supportedFileExtensions":["csv"],"ignoredFileExtensions":["gph"]}}"#
            .data(using: .utf8)!.write(to: paths.importFiltersURL)
        try #"{"version":1,"tokenization":{"separators":"_","caseFold":"preserve"},"sources":["file"],"channel":{"aliases":{}}}"#
            .data(using: .utf8)!.write(to: paths.filenameTokenizationURL)
        try #"{"version":4,"sampleId":{"batchPrefixes":["PN"]},"substrate":{"materials":[],"treatments":[],"orientations":[]}}"#
            .data(using: .utf8)!.write(to: paths.sampleIdentificationURL)
        try #"{"version":1,"workflows":[{"id":"MR","displayName":"MR","matchRules":[{"scope":"tokens","type":"equals","value":"MR"}],"conditionFieldIDs":["temperature"]}],"measurementTagRules":[]}"#
            .data(using: .utf8)!.write(to: paths.workflowURL)
        try #"{"version":2,"conditionDefinitions":[{"id":"temperature","label":"Temperature","kind":"unit_suffix","unitPattern":"^\\d+K$"}]}"#
            .data(using: .utf8)!.write(to: paths.measuringConditionURL)
    }

    @Test("A successful save reports its section once; a refused save reports nothing")
    func reportsOnlySuccessfulSaves() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL-save-callback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = RulesConfigPaths(configDirectoryURL: dir)
        try writeBook(to: paths)
        let savedPaths = RuleLoader.currentBookPaths
        RuleLoader.configure(bookPaths: paths, internalPaths: AppInternalPaths())
        defer { RuleLoader.configure(bookPaths: savedPaths, internalPaths: AppInternalPaths()) }

        var reported: [RulesPanelSection] = []
        let store = RulesManagementStore(onSectionSaved: { reported.append($0) }, rulesBookPaths: paths)
        store.present()
        store.selectSection(.importFilters)

        var draft = try #require(store.importFiltersDraft)
        draft.config.supportedFileExtensions = ["csv", "ibw"]
        store.updateImportFilters(draft)
        guard case .saved = store.saveCurrent() else { Issue.record("Expected .saved"); return }
        #expect(reported == [.importFilters])

        // The same extension in both lists is refused, so nothing is reported.
        draft.config.supportedFileExtensions = ["csv", "ibw"]
        draft.config.ignoredFileExtensions = ["ibw"]
        store.updateImportFilters(draft)
        if case .saved = store.saveCurrent() { Issue.record("Overlap should have been refused") }
        #expect(reported == [.importFilters])
    }
}
