import SwiftUI

/// The single formal Save for a workflow that stores Live Plots: “New Plot” and “Replace Plot”.
/// The Library record decides which one is recommended; the user can always pick either.
struct FormalPlotSaveBar: View {
    @Environment(SpinLabAppState.self) private var appState
    let store: any FormalPlotSaving

    @State private var summaries: [FormalPlotSummary] = []
    @State private var loadError: String?
    @State private var showSelector = false

    var body: some View {
        let rootURL = appState.v2LibraryRootURL
        let reason = store.formalPlotUnavailableReason(currentRootURL: rootURL, isV2Library: appState.isV2LibraryLayout)
        let subject = store.formalPlotSaveSubject
        let recommendation = subject.map { FormalPlotRanker.recommend(summaries, subject: $0) } ?? .new
        let ranked = subject.map { FormalPlotRanker.rank(summaries, subject: $0) } ?? []
        let busy = store.isSavingFormalPlot

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.md) {
                Text("Save plot")
                    .font(.callout.weight(.semibold))
                actionButton("New Plot", prominent: recommendation == .new, id: "formalPlot.new", disabled: reason != nil || busy) {
                    saveNew(rootURL)
                }
                actionButton("Replace Plot…", prominent: recommendation != .new, id: "formalPlot.replace", disabled: reason != nil || busy) {
                    showSelector = true
                }
                if busy { ProgressView().controlSize(.small) }
                Spacer()
            }
            if let reason {
                Text(reason).font(.callout).foregroundStyle(.secondary)
            } else if case let .replace(plotID) = recommendation, let plot = summaries.first(where: { $0.plotID == plotID }) {
                Text("Recommended: replace “\(plot.title)” (\(FormalPlotText.savedAt(plot)))")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Recommended: save as a new plot.").font(.callout).foregroundStyle(.secondary)
            }
            if let loadError {
                Text(loadError).font(.callout).foregroundStyle(.red)
            }
        }
        .task(id: appState.libraryFeatureStore.librarySettings.rootPath) { reload() }
        .onChange(of: store.formalPlotSaveSubject) { _, _ in reload() }
        .sheet(isPresented: $showSelector) {
            FormalPlotSelectorSheet(
                plots: ranked,
                subjectDescription: store.formalPlotSubjectDescription,
                preselectedPlotID: { if case let .replace(id) = recommendation { return id } else { return nil } }(),
                currentInputs: subject?.inputs ?? [],
                onConfirm: { plot in
                    store.saveFormalPlot(
                        mode: .replace(FormalPlotReplaceTarget(
                            plotID: plot.plotID, expectedRevision: plot.revision, expectedInputs: plot.inputs
                        )),
                        currentRootURL: appState.v2LibraryRootURL, service: nil, onComplete: afterSave
                    )
                }
            )
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, prominent: Bool, id: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(title, action: action).buttonStyle(.borderedProminent).disabled(disabled).accessibilityIdentifier(id)
        } else {
            Button(title, action: action).buttonStyle(.bordered).disabled(disabled).accessibilityIdentifier(id)
        }
    }

    private func saveNew(_ rootURL: URL?) {
        store.saveFormalPlot(mode: .new, currentRootURL: rootURL, service: nil, onComplete: afterSave)
    }

    private func afterSave() {
        appState.library.loadWorkbenchResultsForCurrentSelection()
        appState.library.loadMeasurementDataForCurrentSelection()
        reload()
    }

    private func reload() {
        guard appState.isV2LibraryLayout else { summaries = []; return }
        switch appState.loadFormalPlotSummaries() {
        case let .success(list): summaries = list; loadError = nil
        case let .failure(error): summaries = []; loadError = error.localizedDescription
        }
    }
}
