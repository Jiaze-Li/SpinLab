import Foundation
import os
import Testing
@testable import SpinLabApp

@MainActor
@Suite("Publish feature store and orchestration", .serialized, .rulesGlobalState)
struct PublishFeatureStoreTests {
    private func lines(_ items: [(WebLibraryPublishOutputKind, String)]) -> [PublishOutputLine] {
        items.map { PublishOutputLine(kind: $0.0, line: $0.1) }
    }

    @Test("exit 0 after pushing is pushedToRemote, never 'live'")
    func pushedToRemote() {
        let store = PublishFeatureStore()
        store.begin(trigger: .manual, libraryRootPath: "/lib")
        store.appendOutput(kind: .stdout, line: "[publish-web] Publishing changes from public/...")
        store.appendOutput(kind: .stdout, line: "[publish-web] Cloudflare Pages will redeploy automatically.")
        store.finish(exitCode: 0)
        #expect(store.outcome == .pushedToRemote)
        #expect(store.isRunning == false)
        #expect(store.completedAt != nil)
        #expect(PublishPresentation.detail(for: store.outcome)?.contains("not verified") == true)
        #expect(PublishPresentation.title(for: store.outcome).lowercased().contains("live") == false)
    }

    @Test("exit 0 with the no-changes marker is noChanges")
    func noChanges() {
        let store = PublishFeatureStore()
        store.begin(trigger: .automatic, libraryRootPath: "/lib")
        store.appendOutput(kind: .stdout, line: "No web snapshot changes to publish")
        store.finish(exitCode: 0)
        #expect(store.outcome == .noChanges)
        #expect(store.trigger == .automatic)
    }

    @Test("failures report the last script stage", arguments: [
        ("Exporting static library snapshot...", PublishFailureStage.export),
        ("Validating web library snapshot...", .validate),
        ("Checking web snapshot changes...", .check),
        ("Publishing changes from public/...", .publish),
    ])
    func failureStages(prefixLine: String, expected: PublishFailureStage) {
        let out = lines([(.stdout, "[publish-web] Exporting static library snapshot..."), (.stdout, "[publish-web] " + prefixLine), (.stderr, "boom")])
        let outcome = PublishOutcomeResolver.resolve(exitCode: 1, outputLines: out)
        #expect(outcome == .failed(stage: expected, summary: "boom"))
    }

    @Test("non-zero exit without a stage prefix is a process failure")
    func processFailure() {
        let outcome = PublishOutcomeResolver.resolve(exitCode: 2, outputLines: [])
        #expect(outcome == .failed(stage: .process, summary: "Publish script exited with code 2."))
    }

    @Test("launch errors are reported as launch failures")
    func launchFailure() {
        let store = PublishFeatureStore()
        store.begin(trigger: .manual, libraryRootPath: "/lib")
        store.fail(launchSummary: "no bash")
        #expect(store.outcome == .failed(stage: .launch, summary: "no bash"))
    }

    @Test("begin clears the previous run")
    func beginResets() {
        let store = PublishFeatureStore()
        store.begin(trigger: .manual, libraryRootPath: "/lib")
        store.appendOutput(kind: .stderr, line: "x")
        store.finish(exitCode: 1)
        store.begin(trigger: .manual, libraryRootPath: "/lib")
        #expect(store.outputLines.isEmpty)
        #expect(store.completedAt == nil)
        #expect(store.isRunning)
    }

    // MARK: Orchestration

    final class GatedPublisher: WebLibraryPublishingCapability, @unchecked Sendable {
        private let counter = OSAllocatedUnfairLock(initialState: 0)
        var calls: Int { counter.withLock { $0 } }
        let exitCode: Int32
        let linesToEmit: [String]
        init(exitCode: Int32, lines: [String]) { self.exitCode = exitCode; self.linesToEmit = lines }
        private let roots = OSAllocatedUnfairLock(initialState: [String]())
        var libraryRoots: [String] { roots.withLock { $0 } }
        private let webRepos = OSAllocatedUnfairLock(initialState: [String]())
        var webRepoRoots: [String] { webRepos.withLock { $0 } }
        func publishWebLibrary(
            publishRootURL: URL,
            libraryRootURL: URL,
            webRepoURL: URL,
            onOutput: @escaping @Sendable (WebLibraryPublishOutputKind, String) -> Void
        ) async throws -> Int32 {
            counter.withLock { $0 += 1 }
            roots.withLock { $0.append(libraryRootURL.path) }
            webRepos.withLock { $0.append(webRepoURL.path) }
            try await Task.sleep(nanoseconds: 200_000_000)
            for line in linesToEmit { onOutput(.stdout, line) }
            return exitCode
        }
    }

    private func makeState(_ publisher: GatedPublisher, validatePathsOnDisk: Bool = false) -> SpinLabAppState {
        var env = AppEnvironment.live()
        env.webLibraryPublisher = publisher
        let state = SpinLabAppState(environment: env)
        state.publish.validatePathsOnDisk = validatePathsOnDisk
        return state
    }

    @Test("a second trigger while running does not start another run")
    func reentrancyGuard() async {
        let publisher = GatedPublisher(exitCode: 0, lines: ["No web snapshot changes to publish"])
        let state = makeState(publisher)
        state.library.librarySettings.rootPath = "/chosen/library"
        state.library.librarySettings.webLibraryRepoPath = "/chosen/web-repo"
        state.publish.publishWebLibrary(trigger: .manual)
        state.publish.publishWebLibrary(trigger: .automatic)
        #expect(state.publish.isRunning)
        #expect(state.publish.trigger == .manual)
        for _ in 0..<100 where state.publish.isRunning { try? await Task.sleep(nanoseconds: 50_000_000) }
        #expect(publisher.calls == 1)
        #expect(publisher.libraryRoots == ["/chosen/library"])
        #expect(publisher.webRepoRoots == ["/chosen/web-repo"])
        #expect(state.publish.libraryRootPath == "/chosen/library")
        #expect(state.publish.webRepoPath == "/chosen/web-repo")
        #expect(state.publish.outcome == .noChanges)
    }

    @Test("publishing without a selected Library never starts the script and says why")
    func noLibrarySelected() {
        let publisher = GatedPublisher(exitCode: 0, lines: [])
        let state = makeState(publisher)
        state.library.librarySettings.rootPath = nil
        state.library.librarySettings.webLibraryRepoPath = "/chosen/web-repo"
        state.publish.publishWebLibrary(trigger: .manual)
        #expect(publisher.calls == 0)
        #expect(state.publish.isRunning == false)
        #expect(state.publish.outcome == .failed(stage: .launch, summary: PublishFeatureStore.noLibrarySelectedMessage))
        state.library.librarySettings.rootPath = "   "
        state.publish.publishWebLibrary(trigger: .automatic)
        #expect(publisher.calls == 0)
    }

    @Test("publishing without a valid Web Repository never starts the script and says why")
    func webRepositoryValidation() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("spinlab-publish-webrepo-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }
        let libraryDir = tempRoot.appendingPathComponent("library", isDirectory: true)
        let nonGitWebDir = tempRoot.appendingPathComponent("web-not-git", isDirectory: true)
        let validGitWebDir = tempRoot.appendingPathComponent("web-git", isDirectory: true)
        try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: nonGitWebDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: validGitWebDir.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)

        let publisher = GatedPublisher(exitCode: 0, lines: ["No web snapshot changes to publish"])
        let state = makeState(publisher, validatePathsOnDisk: true)
        state.library.librarySettings.rootPath = libraryDir.path

        // 1. Unset web repo
        state.library.librarySettings.webLibraryRepoPath = nil
        state.publish.publishWebLibrary(trigger: .manual)
        #expect(publisher.calls == 0)
        #expect(state.publish.outcome == .failed(stage: .launch, summary: PublishFeatureStore.noWebRepoSelectedMessage))

        // 2. Non-existent web repo folder
        let missingPath = tempRoot.appendingPathComponent("does-not-exist").path
        state.library.librarySettings.webLibraryRepoPath = missingPath
        state.publish.publishWebLibrary(trigger: .manual)
        #expect(publisher.calls == 0)
        #expect(state.publish.outcome == .failed(stage: .launch, summary: PublishFeatureStore.webRepoNotFoundMessage(missingPath)))

        // 3. Existing folder without .git
        state.library.librarySettings.webLibraryRepoPath = nonGitWebDir.path
        state.publish.publishWebLibrary(trigger: .manual)
        #expect(publisher.calls == 0)
        #expect(state.publish.outcome == .failed(stage: .launch, summary: PublishFeatureStore.webRepoNotGitMessage(nonGitWebDir.path)))

        // 4. Valid git repository folder + persistence in LibrarySettingsStore
        let settingsURL = tempRoot.appendingPathComponent("library_settings.json")
        let settingsStore = LibrarySettingsStore(settingsURL: settingsURL)
        var settings = settingsStore.load()
        #expect(settings.webLibraryRepoPath == nil)
        settings.webLibraryRepoPath = validGitWebDir.path
        settingsStore.save(settings)
        let reloaded = settingsStore.load()
        #expect(reloaded.webLibraryRepoPath == validGitWebDir.path)

        state.library.updateWebLibraryRepoPath(to: validGitWebDir)
        #expect(state.library.librarySettings.webLibraryRepoPath == validGitWebDir.path)
        #expect(state.publish.preflightIssue(libraryPath: libraryDir.path, webRepoPath: validGitWebDir.path) == nil)
    }

    @Test("PublishFeatureStore has no #filePath repo-root inference and computes a bundle fingerprint")
    func noSourcePathInferenceAndFingerprint() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let storeSource = try String(contentsOf: root.appendingPathComponent("Sources/SpinLabApp/Features/Publish/PublishFeatureStore.swift"), encoding: .utf8)
        #expect(!storeSource.contains("#filePath"))
        let store = PublishFeatureStore(publishRootURL: root)
        #expect(store.bundleFingerprint != "unavailable")
        #expect(store.bundleFingerprint.count == 10)
        #expect(store.scriptTemplateVersionDisplay.contains(AppVersion.current))
        #expect(store.scriptTemplateVersionDisplay.contains(store.bundleFingerprint))
    }

    @Test("every output line is in before the outcome is decided")
    func outputIsCompleteBeforeOutcome() async {
        var env = AppEnvironment.live()
        let lines = (0..<300).map { "line \($0)" } + ["No web snapshot changes to publish."]
        let publisher = GatedPublisher(exitCode: 0, lines: lines)
        env.webLibraryPublisher = publisher
        for _ in 0..<5 {
            let state = SpinLabAppState(environment: env)
            state.publish.validatePathsOnDisk = false
            state.library.librarySettings.rootPath = "/chosen/library"
            state.library.librarySettings.webLibraryRepoPath = "/chosen/web-repo"
            state.publish.publishWebLibrary(trigger: .manual)
            for _ in 0..<200 where state.publish.isRunning { try? await Task.sleep(nanoseconds: 50_000_000) }
            #expect(state.publish.outputLines.count == lines.count)
            #expect(state.publish.outputLines.map(\.line) == lines)
            #expect(state.publish.outcome == .noChanges)
        }
    }

    @Test("navigation never starts a publish")
    func navigationDoesNotPublish() {
        let publisher = GatedPublisher(exitCode: 0, lines: [])
        let state = makeState(publisher)
        _ = state.navigate(to: .publish)
        _ = state.navigate(to: .library)
        #expect(publisher.calls == 0)
        #expect(state.publish.outcome == .idle)
    }

    @Test("Library sources hold no publish state or entry")
    func libraryHasNoPublish() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = [
            "Sources/SpinLabApp/Features/Library/LibraryPrimaryView.swift",
            "Sources/SpinLabApp/Features/Library/LibraryViewModel.swift",
            "Sources/SpinLabApp/App/State/LibraryFeatureStore.swift",
            "Sources/SpinLabApp/App/State/LibraryFeatureStore+Facade.swift",
        ]
        for file in files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.contains("webLibraryPublish"), "\(file)")
            #expect(!text.contains("public to html"), "\(file)")
        }
    }

    // MARK: Navigation

    @Test("Publish is a top-level area with a deep link and no children")
    func routeAndLink() {
        let router = AppRouter()
        #expect(router.routePath(for: .area(.publish)) == .publish)
        #expect(router.deepLink(for: .publish) == "publish")
        #expect(router.deepLinkToRouteStack("publish") == AppRouteStack(.publish))
        #expect(AppArea.allCases.contains(.publish))
    }

    @Test("entering Publish and returning keeps Library selection; publish state survives area switches")
    func roundTrip() {
        let state = makeState(GatedPublisher(exitCode: 0, lines: []))
        state.publish.begin(trigger: .manual, libraryRootPath: "/lib")
        state.publish.fail(launchSummary: "x")
        state.selectedArea = .library
        #expect(state.navigate(to: .publish) == .committed)
        #expect(state.selectedArea == .publish)
        #expect(state.navigate(to: .library) == .committed)
        #expect(state.navigate(to: .workbench) == .committed)
        #expect(state.navigate(to: .publish) == .committed)
        #expect(state.publish.outcome == .failed(stage: .launch, summary: "x"))
    }

    @Test("a dirty Library draft defers entering Publish")
    func dirtyDraftDefersPublish() {
        let state = makeState(GatedPublisher(exitCode: 0, lines: []))
        state.library.librarySettings.rootPath = nil
        state.selectedArea = .library
        state.library.libraryState.sampleEditOriginalDraft = LibrarySampleEditDraft(
            sampleId: "PN1-a", batchId: "PN1", baseUpdatedAt: Date(), substrateTagsText: "clean", numericValues: [], metadataValues: [])
        state.library.librarySampleEditDraft = LibrarySampleEditDraft(
            sampleId: "PN1-a", batchId: "PN1", baseUpdatedAt: Date(), substrateTagsText: "dirty", numericValues: [], metadataValues: [])
        #expect(state.navigate(to: .publish) == .deferred)
        #expect(state.selectedArea == .library)
    }
}
