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
/// Manual and automatic publishes both go through `publishWebLibrary(trigger:)`. The Library to publish
/// is always the one SpinLab has selected (`selectedLibraryRootPath`); the script has no Library of its own.
@MainActor
@Observable
final class PublishFeatureStore {
    nonisolated static let siteURLString = "https://spinlab-web-library.pages.dev"
    nonisolated static let noLibrarySelectedMessage = "No Library is selected. Choose a Library in the Library area first."
    nonisolated static let deploymentUnverifiedMessage = "Pushed to GitHub. Cloudflare deployment not verified."

    /// Repository root that holds `scripts/publish_web_library.sh`.
    nonisolated static let defaultRepoRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PublishFeatureStore.swift -> Features/Publish
        .deletingLastPathComponent() // -> Features
        .deletingLastPathComponent() // -> Sources/SpinLabApp
        .deletingLastPathComponent() // -> Sources
        .deletingLastPathComponent() // -> repo root

    private(set) var outcome: PublishOutcome = .idle
    private(set) var trigger: PublishTrigger?
    /// The Library this run publishes (SpinLab's selected Library); nil when none was selected.
    private(set) var libraryRootPath: String?
    private(set) var outputLines: [PublishOutputLine] = []
    private(set) var completedAt: Date?

    /// Set only by the real app window: automatic publishing never runs from tests or previews.
    var autoPublishEnabled = false
    /// SpinLab's currently selected Library path (the only source of truth for what is published).
    @ObservationIgnored var selectedLibraryRootPath: () -> String? = { nil }

    @ObservationIgnored private let publisher: any WebLibraryPublishingCapability
    @ObservationIgnored private let repoRootURL: URL
    @ObservationIgnored private lazy var autoPublisher = WebLibraryAutoPublisher(
        isPublishing: { [weak self] in self?.isRunning ?? false },
        startPublish: { [weak self] in self?.publishWebLibrary(trigger: .automatic) }
    )

    init(
        publisher: any WebLibraryPublishingCapability = WebLibraryPublishService(),
        repoRootURL: URL = PublishFeatureStore.defaultRepoRootURL
    ) {
        self.publisher = publisher
        self.repoRootURL = repoRootURL
    }

    var isRunning: Bool { outcome == .running }

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
        let rootPath = selectedLibraryRootPath()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rootPath, !rootPath.isEmpty else {
            begin(trigger: trigger, libraryRootPath: nil)
            fail(launchSummary: Self.noLibrarySelectedMessage)
            autoPublisher.publishFinished()
            return
        }
        let libraryRootURL = URL(fileURLWithPath: rootPath)
        let repoRootURL = self.repoRootURL
        let publisher = self.publisher

        begin(trigger: trigger, libraryRootPath: rootPath)

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let exitCode = try await publisher.publishWebLibrary(repoRootURL: repoRootURL, libraryRootURL: libraryRootURL) { kind, line in
                    Task { @MainActor in
                        self.appendOutput(kind: kind, line: line)
                    }
                }
                await MainActor.run {
                    self.finish(exitCode: exitCode)
                    self.autoPublisher.publishFinished()
                }
            } catch {
                let appError = AppError.from(error, fallback: "Failed to publish web library.")
                await MainActor.run {
                    self.fail(launchSummary: appError.localizedDescription)
                    self.autoPublisher.publishFinished()
                }
            }
        }
    }

    // MARK: State transitions

    func begin(trigger: PublishTrigger, libraryRootPath: String?) {
        outcome = .running
        self.trigger = trigger
        self.libraryRootPath = libraryRootPath
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
