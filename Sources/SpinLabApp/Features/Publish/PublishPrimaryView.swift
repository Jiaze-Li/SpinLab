import SwiftUI

/// Publish area: the one place that starts web library publishing and shows its status.
struct PublishPrimaryView: View {
    @Environment(SpinLabAppState.self) private var appState

    private var publish: PublishFeatureStore { appState.publish }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.sm) {
                    Text("Publish")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text(AppVersion.current)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text("Export the Library to the phone web page and push it to GitHub.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Publish to web") {
                    appState.publishWebLibrary(trigger: .manual)
                }
                .font(.callout)
                .buttonStyle(.borderedProminent)
                .disabled(publish.isRunning)
                .accessibilityIdentifier("Publish.PublishButton")

                statusView
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if publish.outcome != .idle {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Image(systemName: PublishPresentation.iconName(for: publish.outcome))
                        .font(.callout.weight(.semibold))
                    Text(PublishPresentation.title(for: publish.outcome))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PublishPresentation.isFailure(publish.outcome) ? Color.red : Color.primary)
                    if publish.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                if let detail = PublishPresentation.detail(for: publish.outcome) {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let trigger = publish.trigger {
                    Text(trigger == .automatic ? "Started automatically after a Library change." : "Started manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let completedAt = publish.completedAt {
                    Text("Finished \(completedAt, format: .dateTime.year().month().day().hour().minute())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if publish.outcome == .pushedToRemote, let url = URL(string: PublishFeatureStore.siteURLString) {
                    Link(PublishFeatureStore.siteURLString + " (not verified)", destination: url)
                        .font(.callout)
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .padding(.horizontal, AppSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .accessibilityIdentifier("Publish.StatusCard")
        }
    }
}

/// Plain-language text for a publish outcome.
enum PublishPresentation {
    static func title(for outcome: PublishOutcome) -> String {
        switch outcome {
        case .idle: return "Not published in this session."
        case .running: return "Publishing..."
        case .noChanges: return "No changes to publish."
        case .pushedToRemote: return "Pushed to GitHub."
        case let .failed(stage, _): return "Publish failed (\(stageLabel(stage)))."
        }
    }

    static func detail(for outcome: PublishOutcome) -> String? {
        switch outcome {
        case .pushedToRemote: return PublishFeatureStore.deploymentUnverifiedMessage
        case .noChanges: return "Site is already up to date."
        case let .failed(_, summary): return summary
        case .idle, .running: return nil
        }
    }

    static func iconName(for outcome: PublishOutcome) -> String {
        switch outcome {
        case .running: return "arrow.triangle.2.circlepath"
        case .noChanges, .pushedToRemote: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .idle: return "square.and.arrow.up"
        }
    }

    static func isFailure(_ outcome: PublishOutcome) -> Bool {
        if case .failed = outcome { return true }
        return false
    }

    static func stageLabel(_ stage: PublishFailureStage) -> String {
        switch stage {
        case .export: return "export"
        case .validate: return "validation"
        case .check: return "change check"
        case .publish: return "git publish"
        case .process: return "script"
        case .launch: return "could not start"
        }
    }
}
