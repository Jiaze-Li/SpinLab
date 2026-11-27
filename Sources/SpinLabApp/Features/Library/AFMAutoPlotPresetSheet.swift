import SwiftUI

/// The Library-level AFM automatic plot preset: visible, editable, applied only on request.
/// Nothing here is a built-in research default; the user's values are what gets applied.
struct AFMAutoPlotPresetSheet: View {
    @Environment(SpinLabAppState.self) private var appState
    @Binding var isPresented: Bool

    @State private var applied: AFMAutoPlotPreset?
    @State private var loadProblem: String?
    @State private var draft = AFMAutoPlotPresetSheet.blankDraft
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var message: String?
    @State private var messageIsError = false

    static var blankDraft: AFMAutoPlotPreset {
        AFMAutoPlotPreset(
            enabled: false, presetVersionID: "", channelRule: .init(semanticType: "Height", sourceLabel: nil),
            surfaceLevel: .off, lineFlattenOrder: .off, zeroReference: .none,
            displayState: AFMWorkspaceStore.defaultDisplayState, scaleBar: .init(), globalPlotDefaults: [:]
        )
    }

    private var unavailable: String? { appState.autoPlotUnavailableReason }

    private var hasUnappliedChanges: Bool {
        guard let applied else { return true }
        var a = applied
        a.enabled = draft.enabled
        a.presetVersionID = draft.presetVersionID
        return a != draft
    }

    var body: some View {
        AdaptiveSheet(minWidth: 560) {
            HStack {
                Text("AFM Automatic Plot")
                    .font(AppFontScale.groupHeader)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
        } content: {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                statusBlock
                if let unavailable {
                    Text(unavailable).font(.callout).foregroundStyle(.orange)
                }
                channelBlock
                processingBlock
                displayBlock
                recentBlock
            }
            .disabled(isLoading)
        } actions: {
            HStack(spacing: AppSpacing.sm) {
                if let message {
                    Text(message).font(.callout).foregroundStyle(messageIsError ? Color.red : Color.secondary)
                }
                Spacer()
                Button("Fill from Workbench") { fillFromWorkbench() }
                    .buttonStyle(.bordered)
                    .disabled(unavailable != nil || isBusy)
                    .accessibilityIdentifier("autoPlot.fillFromWorkbench")
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                    .disabled(unavailable != nil || isBusy || !draft.channelRule.isUsable || !hasUnappliedChanges)
                    .accessibilityIdentifier("autoPlot.apply")
            }
        }
        .task { await load() }
    }

    // MARK: Sections

    private var statusBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Toggle("Plot automatically when a new AFM measurement is imported", isOn: Binding(
                    get: { applied?.enabled ?? false },
                    set: { setEnabled($0) }
                ))
                .disabled(applied == nil || unavailable != nil || isBusy)
                .accessibilityIdentifier("autoPlot.enabled")
                Text(statusText).font(.callout).foregroundStyle(.secondary)
                Text("Applies to measurements imported after you apply it. Existing measurements are not redrawn; use Run auto plot on a measurement to plot one.")
                    .font(.callout).foregroundStyle(.secondary)
                if let loadProblem {
                    Text(loadProblem).font(.callout).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        guard let applied else { return "No preset applied yet. Fill in the values below and press Apply, then switch automatic plotting on." }
        let state = applied.enabled ? "On" : "Off"
        return "\(state). Applied preset: \(applied.channelRule.summary())." + (hasUnappliedChanges ? " The values below are not applied yet." : "")
    }

    private var channelBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Channel").font(AppFontScale.groupHeader)
                Text("The plot is made only when exactly one channel matches. Otherwise it is skipped and the reason is shown.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Channel type") {
                    TextField("e.g. Height", text: Binding(
                        get: { draft.channelRule.semanticType ?? "" },
                        set: { draft.channelRule.semanticType = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minWidth: 200)
                    .accessibilityIdentifier("autoPlot.channelType")
                }
                LabeledContent("Channel name") {
                    TextField("e.g. HeightRetrace", text: Binding(
                        get: { draft.channelRule.sourceLabel ?? "" },
                        set: { draft.channelRule.sourceLabel = $0.isEmpty ? nil : $0 }
                    ))
                    .frame(minWidth: 200)
                    .accessibilityIdentifier("autoPlot.channelName")
                }
                if !draft.channelRule.isUsable {
                    Text("Enter a channel type, a channel name, or both.").font(.callout).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var processingBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Processing").font(AppFontScale.groupHeader)
                Picker("Surface level", selection: $draft.surfaceLevel) {
                    ForEach(AFMSurfaceLevel.allCases, id: \.self) { Text(Self.label($0.rawValue)).tag($0) }
                }
                Picker("Line flatten", selection: $draft.lineFlattenOrder) {
                    ForEach(AFMLineFlattenOrder.allCases, id: \.self) { Text(Self.label($0.rawValue)).tag($0) }
                }
                Picker("Zero reference", selection: $draft.zeroReference) {
                    ForEach(AFMZeroReference.allCases, id: \.self) { Text(Self.label($0.rawValue)).tag($0) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displayBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Display").font(AppFontScale.groupHeader)
                Picker("Colour scale", selection: $draft.displayState.colorScaleMode) {
                    Text("Linear").tag(HeatmapColorScaleMode.linear)
                    Text("Log").tag(HeatmapColorScaleMode.log10)
                }
                Toggle("Show colour bar", isOn: $draft.displayState.showColorbar)
                Toggle("Show title", isOn: $draft.displayState.showTitle)
                LabeledContent("Title") {
                    TextField("Empty uses the file's own title", text: $draft.displayState.titleOverride)
                        .frame(minWidth: 200)
                }
                Picker("Scale bar", selection: $draft.scaleBar.mode) {
                    ForEach(AFMScaleBarSetting.Mode.allCases, id: \.self) { Text(Self.label($0.rawValue)).tag($0) }
                }
                Text("The colour range and plot style follow what was filled from the Workbench (or the defaults).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var recentBlock: some View {
        let reports = appState.afmAutoPlotRunner.reports.suffix(5).reversed()
        if !reports.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Recent automatic plots").font(AppFontScale.groupHeader)
                    ForEach(Array(reports)) { report in
                        Text(AutoPlotText.describe(report.result))
                            .font(.callout)
                            .foregroundStyle(report.result.isSuccess ? Color.secondary : Color.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Actions

    private static func label(_ raw: String) -> String {
        raw.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }

    private func load() async {
        isLoading = true
        switch await appState.loadAutoPlotPreset() {
        case let .success(load):
            switch load {
            case let .loaded(preset):
                applied = preset
                draft = preset
            case .absent:
                applied = nil
            case let .unreadable(reason):
                applied = nil
                loadProblem = "The saved preset cannot be used (\(reason)). Automatic plotting is off. Apply a new preset to replace it."
            }
        case let .failure(error):
            loadProblem = error.localizedDescription
        }
        isLoading = false
    }

    private func fillFromWorkbench() {
        guard var next = appState.autoPlotDraftFromWorkbench() else {
            show("Open an AFM measurement in the Workbench first.", error: true)
            return
        }
        next.enabled = applied?.enabled ?? false
        draft = next
        show("Filled from the Workbench. Press Apply to use it.", error: false)
    }

    private func apply() {
        isBusy = true
        var toApply = draft
        toApply.enabled = applied?.enabled ?? false
        Task {
            let result = await appState.applyAutoPlotPreset(toApply)
            isBusy = false
            switch result {
            case let .success(stored):
                applied = stored
                draft = stored
                loadProblem = nil
                show(stored.enabled ? "Applied. New imports will be plotted." : "Applied. Switch automatic plotting on to use it.", error: false)
            case let .failure(error):
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func setEnabled(_ enabled: Bool) {
        isBusy = true
        Task {
            let result = await appState.setAutoPlotEnabled(enabled)
            isBusy = false
            switch result {
            case let .success(stored):
                applied = stored
                draft.enabled = stored.enabled
                draft.presetVersionID = stored.presetVersionID
                show(enabled ? "Automatic plotting is on." : "Automatic plotting is off.", error: false)
            case let .failure(error):
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}
