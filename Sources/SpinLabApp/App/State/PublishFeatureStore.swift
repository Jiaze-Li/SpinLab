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

/// Owns the in-memory state of web library publishing. The single orchestration entry lives on
/// `SpinLabAppState.publishWebLibrary`; this store only holds status and output.
@MainActor
@Observable
final class PublishFeatureStore {
    nonisolated static let siteURLString = "https://spinlab-web-library.pages.dev"
    nonisolated static let deploymentUnverifiedMessage = "Pushed to GitHub. Cloudflare deployment not verified."

    private(set) var outcome: PublishOutcome = .idle
    private(set) var trigger: PublishTrigger?
    private(set) var outputLines: [PublishOutputLine] = []
    private(set) var completedAt: Date?

    var isRunning: Bool { outcome == .running }

    func begin(trigger: PublishTrigger) {
        outcome = .running
        self.trigger = trigger
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
