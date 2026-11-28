import SwiftUI

/// Audited supplement of what a stored Source does not know yet (workflow, channels).
/// Only unknown values can be filled; confirmed values are shown and cannot be changed here.
struct SourceContextAmendSheet: View {
    @Environment(SpinLabAppState.self) private var appState
    let source: AssetRecord
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var workflowID = ""
    @State private var channels: Set<String> = []
    @State private var known: SourceContextRecord?
    @State private var knownChannels: [EffectiveChannel]?
    @State private var errorMessage: String?

    private var channelCandidates: [String] {
        ((source.originalFilename ?? "") as NSString).pathExtension.lowercased() == "dat" ? ["ch1", "ch2", "ch3"] : []
    }
    private var workflowIsKnown: Bool { known?.workflowOrigin.isConfirmed == true && known?.workflowID != nil }
    private var canSave: Bool {
        (!workflowIsKnown && !workflowID.isEmpty) || (knownChannels == nil && !channels.isEmpty)
    }

    var body: some View {
        AdaptiveSheet(minWidth: 520) {
            HStack {
                Text("Fill in Missing Information")
                    .font(AppFontScale.groupHeader)
                Spacer()
            }
        } content: {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(source.originalFilename ?? source.id)
                    .font(.callout.monospaced())
                Text("Only values that are still unknown can be filled. Each change is recorded; the stored file itself never changes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Workflow").font(AppFontScale.groupHeader)
                    if workflowIsKnown, let id = known?.workflowID {
                        Text("Confirmed: \(id)").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Picker("Workflow", selection: $workflowID) {
                            Text("Unknown").tag("")
                            ForEach(appState.workflowDefinitions) { definition in
                                Text(definition.displayName).tag(definition.id)
                            }
                        }
                        .labelsHidden()
                    }
                }

                if !channelCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Channels of this Sample").font(AppFontScale.groupHeader)
                        if let knownChannels {
                            Text("Confirmed: \(knownChannels.map(\.id).joined(separator: ", "))")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: AppSpacing.md) {
                                ForEach(channelCandidates, id: \.self) { channel in
                                    Toggle(channel, isOn: Binding(
                                        get: { channels.contains(channel) },
                                        set: { isOn in if isOn { channels.insert(channel) } else { channels.remove(channel) } }
                                    ))
                                    .toggleStyle(.checkbox)
                                }
                            }
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.red)
                }
            }
        } actions: {
            HStack(spacing: AppSpacing.sm) {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .accessibilityIdentifier("sourceContext.save")
            }
        }
        .onAppear {
            let loaded = appState.loadV2SourceContext(sourceID: source.id)
            known = loaded.context
            knownChannels = loaded.channels
        }
    }

    private func save() {
        let changes = SourceContextAmendment(
            workflowID: workflowIsKnown ? nil : (workflowID.isEmpty ? nil : workflowID),
            effectiveChannels: knownChannels == nil && !channels.isEmpty ? channels.sorted().map { EffectiveChannel(id: $0) } : nil
        )
        switch appState.amendV2SourceContext(sourceID: source.id, changes: changes) {
        case .success:
            onFinished()
            dismiss()
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }
}
