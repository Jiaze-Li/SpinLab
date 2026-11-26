import SwiftUI

/// Shared single-select window for choosing the formal Plot to replace. Browser-style sheet (a searchable,
/// scrollable list), so search and the confirm/cancel row stay outside the scroll area. It only consumes
/// `FormalPlotSummary` values; it never reads the Library database or decides research ownership itself.
struct FormalPlotSelectorSheet: View {
    @Environment(SpinLabAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let plots: [RankedFormalPlot]
    let subjectDescription: String
    let preselectedPlotID: String?
    let currentInputs: Set<PlotInputKey>
    let onConfirm: (FormalPlotSummary) -> Void

    @State private var query = ""
    @State private var selectedID: String?
    @State private var pendingConfirmation: FormalPlotSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(pendingConfirmation == nil ? "Replace Plot" : "Confirm Replacement")
                .font(AppFontScale.sectionHeader)

            if let target = pendingConfirmation {
                confirmationBody(target)
            } else {
                selectionBody
            }
        }
        .padding(AppSpacing.xxl)
        .frame(minWidth: 460, idealWidth: 560, minHeight: 340, idealHeight: 480)
        .onAppear {
            if selectedID == nil {
                selectedID = preselectedPlotID.flatMap { id in plots.contains { $0.id == id } ? id : nil }
            }
        }
    }

    // MARK: Selection

    private var visible: [RankedFormalPlot] { FormalPlotRanker.filter(plots, query: query) }

    @ViewBuilder
    private var selectionBody: some View {
        TextField("Search title, sample, batch, file", text: $query)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("formalPlotSelector.search")

        if plots.isEmpty {
            Text("No plot can be replaced yet. Use New Plot to save this one.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if visible.isEmpty {
            Text("No plot matches “\(query)”.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.sm, pinnedViews: []) {
                    ForEach(FormalPlotRelevance.allCases, id: \.self) { group in
                        let items = visible.filter { $0.relevance == group }
                        if !items.isEmpty {
                            Text(group.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, AppSpacing.sm)
                            ForEach(items) { item in
                                row(item.summary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }

        HStack(spacing: AppSpacing.md) {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button("Replace…") {
                pendingConfirmation = plots.first { $0.id == selectedID }?.summary
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedID == nil)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func row(_ plot: FormalPlotSummary) -> some View {
        let isSelected = plot.plotID == selectedID
        return HStack(alignment: .top, spacing: AppSpacing.md) {
            FormalPlotThumbnail(plotID: plot.plotID, size: 56)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.sm) {
                    Text(plot.title).font(AppFontScale.groupHeader).lineLimit(1)
                    if plot.isStale {
                        Text("Out of date").font(.callout).foregroundStyle(.orange)
                    }
                }
                Text(FormalPlotText.detail(plot)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Text(FormalPlotText.savedAt(plot)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25)))
        .contentShape(Rectangle())
        .onTapGesture { selectedID = plot.plotID }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("formalPlotSelector.row")
    }

    // MARK: Confirmation (old → new)

    @ViewBuilder
    private func confirmationBody(_ target: FormalPlotSummary) -> some View {
        let changes = target.inputSet != currentInputs
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(changes
                 ? "This plot will change from the data below to the current analysis."
                 : "This plot will be replaced by the current analysis.")
                .font(.body)
            GroupBox {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    labeled("Now", "\(target.title) — \(FormalPlotText.detail(target))")
                    labeled("After", subjectDescription)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("The old plot is not kept. The measurement data is not changed.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        HStack(spacing: AppSpacing.md) {
            Spacer()
            Button("Back") { pendingConfirmation = nil }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
            Button("Replace Plot") {
                onConfirm(target)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
            Text(label).font(.callout).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            Text(value).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}


enum FormalPlotText {
    static func detail(_ plot: FormalPlotSummary) -> String {
        let sample = plot.sampleLabels.isEmpty ? plot.sampleUIDs.joined(separator: ", ") : plot.sampleLabels.joined(separator: ", ")
        return [plot.workflowLabel, sample, plot.fileNames.joined(separator: ", "), plot.channelSummary]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func savedAt(_ plot: FormalPlotSummary) -> String {
        plot.savedAt == .distantPast ? "Saved: unknown" : "Saved " + plot.savedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Stored PNG, loaded on demand so a long list never decodes everything up front.
struct FormalPlotThumbnail: View {
    @Environment(SpinLabAppState.self) private var appState
    let plotID: String
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
        .task(id: plotID) {
            let id = plotID
            let data = await Task.detached { await MainActor.run { appState.formalPlotThumbnail(plotID: id) } }.value
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
