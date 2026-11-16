import CryptoKit
import Foundation
import Observation

/// What started a web library publish.
enum PublishTrigger: String, Sendable, Equatable {
    case manual
    case automatic
}

/// The step of the publish script that failed.
enum PublishFailureStage: String, Sendable, Equatable {
    case export
    case validate
    case check
    case publish
    case process
    case launch
}

enum PublishOutcome: Equatable {
    case idle
    case running
    case noChanges
    /// Changes were committed and pushed to the web repository. Whether Cloudflare finished deploying is not known.
    case pushedToRemote
    case failed(stage: PublishFailureStage, summary: String)
}

struct PublishOutputLine: Sendable, Hashable {
    var kind: WebLibraryPublishOutputKind
    var line: String
}

/// Pure interpretation of a finished publish script run.
enum PublishOutcomeResolver {
    static let noChangesMarker = "No web snapshot changes"

    static func resolve(exitCode: Int32, outputLines: [PublishOutputLine]) -> PublishOutcome {
        if exitCode == 0 {
            let hasNoChanges = outputLines.contains { $0.line.contains(noChangesMarker) }
            return hasNoChanges ? .noChanges : .pushedToRemote
        }
        return .failed(stage: failureStage(outputLines: outputLines), summary: failureSummary(exitCode: exitCode, outputLines: outputLines))
    }

    static func failureStage(outputLines: [PublishOutputLine]) -> PublishFailureStage {
        for entry in outputLines.reversed() {
            let line = entry.line
            guard line.hasPrefix("[publish-web] ") else { continue }
            if line.contains("Exporting") { return .export }
            if line.contains("Validating") { return .validate }
            if line.contains("Checking") { return .check }
            if line.contains("Publishing") { return .publish }
        }
        return .process
    }

    static func failureSummary(exitCode: Int32, outputLines: [PublishOutputLine]) -> String {
        if let stderrLine = outputLines.reversed().first(where: { $0.kind == .stderr })?.line.trimmingCharacters(in: .whitespacesAndNewlines),
           !stderrLine.isEmpty {
            return stderrLine
        }
        if let lastLine = outputLines.last?.line.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty {
            return lastLine
        }
        return "Publish script exited with code \(exitCode)."
    }
}

/// The single owner of web library publishing: its status (memory only) and the one orchestration entry.
/// Manual and automatic publishes both go through `publishWebLibrary(trigger:)`. Both the Library to publish
/// (`selectedLibraryRootPath`) and the target Web Repository (`selectedWebRepoPath`) come solely from SpinLab
/// settings; scripts and templates come from the app's bundled `Publish/` directory.
@MainActor
@Observable
final class PublishFeatureStore {
    nonisolated static let siteURLString = "https://spinlab-web-library.pages.dev"
    nonisolated static let noLibrarySelectedMessage = "No Library is selected. Choose a Library in the Library area first."
    nonisolated static let noWebRepoSelectedMessage = "No Web Repository is selected. Choose a Web Repository folder on this page first."
    nonisolated static let deploymentUnverifiedMessage = "Pushed to GitHub. Cloudflare deployment not verified."

    nonisolated static func libraryNotFoundMessage(_ path: String) -> String {
        "Selected Library folder does not exist on disk: \(path). Choose a valid Library in the Library area."
    }

    nonisolated static func webRepoNotFoundMessage(_ path: String) -> String {
        "Selected Web Repository folder does not exist on disk: \(path). Choose an existing SpinLab-Web-Library clone."
    }

    nonisolated static func webRepoNotGitMessage(_ path: String) -> String {
        "Selected Web Repository is not a Git repository (missing .git): \(path). Choose a Git clone of SpinLab-Web-Library."
    }

    nonisolated static func missingBundledAssetsMessage(_ path: String) -> String {
        "Bundled Publish scripts or templates were not found at \(path). Rebuild SpinLab.app with build_desktop_app.sh."
    }

    /// Resolves the bundled Publish runtime directory (`Contents/Resources/Publish` in a packaged `.app`),
    /// falling back to the current working directory only during non-packaged CLI test runs (`swift test`).
    nonisolated static var defaultPublishRootURL: URL {
        if let bundled = Bundle.main.resourceURL?.appending(path: "Publish"),
           FileManager.default.fileExists(atPath: bundled.appending(path: "scripts/publish_web_library.sh").path) {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// Computes a short SHA-1 fingerprint across the bundled scripts and web template files.
    nonisolated static func computeBundleFingerprint(at publishRootURL: URL) -> String {
        let fm = FileManager.default
        let templateDir: URL = {
            let bundled = publishRootURL.appending(path: "WebLibraryTemplate")
            if fm.fileExists(atPath: bundled.path) { return bundled }
            return publishRootURL.appending(path: "Resources/WebLibraryTemplate")
        }()
        let scriptsDir = publishRootURL.appending(path: "scripts")
        var candidateURLs: [URL] = []

        if let templateItems = try? fm.contentsOfDirectory(at: templateDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            candidateURLs.append(contentsOf: templateItems.sorted { $0.lastPathComponent < $1.lastPathComponent })
        }
        for scriptName in [
            "publish_web_library.sh",
            "export_static_library.py",
            "validate_web_library.py",
            "check_web_library_page.py",
            "check_web_library_changes.py",
        ] {
            let url = scriptsDir.appending(path: scriptName)
            if fm.fileExists(atPath: url.path) {
                candidateURLs.append(url)
            }
        }

        var hasher = Insecure.SHA1()
        var hashedCount = 0
        for fileURL in candidateURLs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue,
                  let data = try? Data(contentsOf: fileURL) else {
                continue
            }
            hasher.update(data: data)
            hashedCount += 1
        }
        guard hashedCount > 0 else { return "unavailable" }
        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(10))
    }

    private(set) var outcome: PublishOutcome = .idle
    private(set) var trigger: PublishTrigger?
    /// The Library this run publishes (SpinLab's selected Library); nil when none was selected.
    private(set) var libraryRootPath: String?
    /// The Web Repository this run targets (SpinLab's configured Web Repository); nil when none was selected.
    private(set) var webRepoPath: String?
    private(set) var outputLines: [PublishOutputLine] = []
    private(set) var completedAt: Date?

    /// Set only by the real app window: automatic publishing never runs from tests or previews.
    var autoPublishEnabled = false
    /// SpinLab's currently selected Library path (the only source of truth for what is published).
    @ObservationIgnored var selectedLibraryRootPath: () -> String? = { nil }
    /// SpinLab's currently configured Web Repository path (`LibrarySettings.webLibraryRepoPath`).
    @ObservationIgnored var selectedWebRepoPath: () -> String? = { nil }

    @ObservationIgnored private let publisher: any WebLibraryPublishingCapability
    @ObservationIgnored let publishRootURL: URL
    @ObservationIgnored let bundleFingerprint: String
    /// When true (the default in production), `publishWebLibrary` verifies that `libraryRootPath` and
    /// `webRepoPath/.git` exist on disk before invoking `publisher`. Tests that pass synthetic path strings
    /// with a mock `publisher` may set this to `false` or create real temporary directories.
    @ObservationIgnored var validatePathsOnDisk: Bool
    @ObservationIgnored private lazy var autoPublisher = WebLibraryAutoPublisher(
        isPublishing: { [weak self] in self?.isRunning ?? false },
        startPublish: { [weak self] in self?.publishWebLibrary(trigger: .automatic) }
    )

    init(
        publisher: any WebLibraryPublishingCapability = WebLibraryPublishService(),
        publishRootURL: URL = PublishFeatureStore.defaultPublishRootURL,
        validatePathsOnDisk: Bool = true
    ) {
        self.publisher = publisher
        self.publishRootURL = publishRootURL
        self.bundleFingerprint = Self.computeBundleFingerprint(at: publishRootURL)
        self.validatePathsOnDisk = validatePathsOnDisk
    }

    var isRunning: Bool { outcome == .running }

    var scriptTemplateVersionDisplay: String {
        "\(AppVersion.current) (\(bundleFingerprint))"
    }

    /// Returns a human-readable reason if Library or Web Repository settings are missing or invalid, or `nil` when ready.
    func preflightIssue(libraryPath: String?, webRepoPath: String?) -> String? {
        let fm = FileManager.default
        let trimmedLibrary = libraryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedLibrary.isEmpty else {
            return Self.noLibrarySelectedMessage
        }
        if validatePathsOnDisk {
            var isLibDir: ObjCBool = false
            if !fm.fileExists(atPath: trimmedLibrary, isDirectory: &isLibDir) || !isLibDir.boolValue {
                return Self.libraryNotFoundMessage(trimmedLibrary)
            }
        }

        let trimmedWebRepo = webRepoPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedWebRepo.isEmpty else {
            return Self.noWebRepoSelectedMessage
        }
        if validatePathsOnDisk {
            var isWebDir: ObjCBool = false
            if !fm.fileExists(atPath: trimmedWebRepo, isDirectory: &isWebDir) || !isWebDir.boolValue {
                return Self.webRepoNotFoundMessage(trimmedWebRepo)
            }
            let gitPath = URL(fileURLWithPath: trimmedWebRepo).appending(path: ".git").path
            if !fm.fileExists(atPath: gitPath) {
                return Self.webRepoNotGitMessage(trimmedWebRepo)
            }
        }
        return nil
    }

    // MARK: Triggers

    /// Only the lists the phone page shows (labs, growth materials, substrates) matter to it.
    nonisolated static func shouldAutoPublishAfterRulesSave(section: RulesPanelSection, autoPublishEnabled: Bool) -> Bool {
        autoPublishEnabled && (section == .sampleIdentification || section == .libraryRegistry)
    }

    /// A Rules Book section was saved: publish again shortly if it changes what the phone page shows.
    func rulesSectionSaved(_ section: RulesPanelSection) {
        guard Self.shouldAutoPublishAfterRulesSave(section: section, autoPublishEnabled: autoPublishEnabled) else { return }
        autoPublisher.requestPublish()
    }

    /// The Library changed (launch load, new / edited / imported / collected samples). Repeated changes
    /// become one publish, and a publish with nothing new is a no-op.
    func libraryChanged() {
        guard autoPublishEnabled else { return }
        autoPublisher.requestPublish()
    }

    // MARK: Orchestration (the one entry)

    func publishWebLibrary(trigger: PublishTrigger = .manual) {
        guard !isRunning else { return }
        let rawLibraryPath = selectedLibraryRootPath()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawWebRepoPath = selectedWebRepoPath()?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveLibraryPath = (rawLibraryPath?.isEmpty == false) ? rawLibraryPath : nil
        let effectiveWebRepoPath = (rawWebRepoPath?.isEmpty == false) ? rawWebRepoPath : nil

        if let issue = preflightIssue(libraryPath: effectiveLibraryPath, webRepoPath: effectiveWebRepoPath) {
            begin(trigger: trigger, libraryRootPath: effectiveLibraryPath, webRepoPath: effectiveWebRepoPath)
            fail(launchSummary: issue)
            autoPublisher.publishFinished()
            return
        }

        guard let rootPath = effectiveLibraryPath, let webPath = effectiveWebRepoPath else { return }
        let libraryRootURL = URL(fileURLWithPath: rootPath)
        let webRepoURL = URL(fileURLWithPath: webPath)
        let publishRootURL = self.publishRootURL
        let publisher = self.publisher

        begin(trigger: trigger, libraryRootPath: rootPath, webRepoPath: webPath)

        // Output lines go through one ordered stream and are all appended before the outcome is decided,
        // so the result never reads incomplete output and late lines cannot reach the next run.
        let (lines, continuation) = AsyncStream.makeStream(of: PublishOutputLine.self)
        let consumer = Task { @MainActor [weak self] in
            for await entry in lines {
                self?.appendOutput(kind: entry.kind, line: entry.line)
            }
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            do {
                let exitCode = try await publisher.publishWebLibrary(
                    publishRootURL: publishRootURL,
                    libraryRootURL: libraryRootURL,
                    webRepoURL: webRepoURL
                ) { kind, line in
                    continuation.yield(PublishOutputLine(kind: kind, line: line))
                }
                continuation.finish()
                await consumer.value
                await MainActor.run {
                    self.finish(exitCode: exitCode)
                    self.autoPublisher.publishFinished()
                }
            } catch {
                continuation.finish()
                await consumer.value
                let appError = AppError.from(error, fallback: "Failed to publish web library.")
                await MainActor.run {
                    self.fail(launchSummary: appError.localizedDescription)
                    self.autoPublisher.publishFinished()
                }
            }
        }
    }

    // MARK: State transitions

    func begin(trigger: PublishTrigger, libraryRootPath: String?, webRepoPath: String? = nil) {
        outcome = .running
        self.trigger = trigger
        self.libraryRootPath = libraryRootPath
        self.webRepoPath = webRepoPath
        outputLines = []
        completedAt = nil
    }

    func appendOutput(kind: WebLibraryPublishOutputKind, line: String) {
        outputLines.append(.init(kind: kind, line: line))
    }

    func finish(exitCode: Int32, now: Date = Date()) {
        outcome = PublishOutcomeResolver.resolve(exitCode: exitCode, outputLines: outputLines)
        completedAt = now
    }

    func fail(launchSummary: String, now: Date = Date()) {
        outcome = .failed(stage: .launch, summary: launchSummary)
        completedAt = now
    }
}
