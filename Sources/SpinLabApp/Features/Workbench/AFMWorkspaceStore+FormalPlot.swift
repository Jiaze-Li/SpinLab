import Foundation

/// How the user wants to save the current AFM analysis as a formal Plot.
enum FormalPlotSaveMode: Equatable, Sendable {
    case new
    case replace(FormalPlotReplaceTarget)
}

/// A Plot chosen for replacement, with the revision and inputs observed when it was chosen.
struct FormalPlotReplaceTarget: Equatable, Sendable {
    let plotID: String
    let expectedRevision: Int
    let expectedInputs: [PlotInputKey]
}

/// Shared by every Workbench workflow that saves formal Plots (AFM first). The shell shows the
/// two actions for stores that conform and keeps the legacy Save for the rest.
@MainActor
protocol FormalPlotSaving: AnyObject {
    /// Why saving is unavailable right now, or nil when it can proceed.
    func formalPlotUnavailableReason(currentRootURL: URL?, isV2Library: Bool) -> String?
    var formalPlotSaveSubject: FormalPlotSaveSubject? { get }
    var openedFormalPlot: FormalPlotReplaceTarget? { get }
    var isSavingFormalPlot: Bool { get }
    /// Plain-language description of what is being saved, for the Plot Selector's old → new summary.
    var formalPlotSubjectDescription: String { get }
    var formalPlotSaveMessage: String? { get }
    func saveFormalPlot(
        mode: FormalPlotSaveMode, currentRootURL: URL?, service: LibraryAssetService?, onComplete: (() -> Void)?
    )
}

extension AFMWorkspaceStore: FormalPlotSaving {

    var formalPlotSaveMessage: String? { saveMessage }

    var formalPlotSubjectDescription: String {
        let file: String
        if case let .datasetV2(_, _, _, name, _)? = analyzedHit?.inputRef { file = name } else { file = "this measurement" }
        let channel = activeChannel?.displayLabel ?? processingConfiguration.activeChannelID
        let sample = analyzedHit?.sampleKey ?? ""
        return [sample, file, channel].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var formalPlotSaveSubject: FormalPlotSaveSubject? {
        guard let capture = analysisCapture else { return nil }
        let channel = processingConfiguration.activeChannelID
        return FormalPlotSaveSubject(
            inputs: [PlotInputKey(datasetID: capture.datasetID, channelID: channel)],
            sampleUIDs: [capture.sampleUID], workflowLabel: "AFM", openedPlotID: openedFormalPlot?.plotID
        )
    }

    func formalPlotUnavailableReason(currentRootURL: URL?, isV2Library: Bool) -> String? {
        guard isV2Library, currentRootURL != nil else {
            return "Saving a plot needs a standard (V2) Library. Migrate this Library first."
        }
        if LibraryWriteLease.shared.isReadOnly { return LibraryWriteLease.readOnlyMessage }
        guard analysisCapture != nil else {
            return "Open a measurement from the standard Library and run Analyze to save a plot."
        }
        guard !isAnalyzing else { return "Analysis is still running." }
        guard latestCandidate != nil else { return "The preview is out of date. Wait for it to render, then save." }
        return nil
    }

    /// Records the user's explicit Open-from-Library target. It is dropped as soon as the Dataset or channel changes.
    func setOpenedFormalPlot(_ target: FormalPlotReplaceTarget?) {
        openedFormalPlotTarget = target
    }

    func saveFormalPlot(
        mode: FormalPlotSaveMode, currentRootURL: URL?, service: LibraryAssetService? = nil, onComplete: (() -> Void)? = nil
    ) {
        guard !isSavingFormalPlot else { return }
        guard let rootURL = currentRootURL,
              let capture = analysisCapture, let candidate = latestCandidate, !isAnalyzing else {
            saveMessage = "Nothing to save yet. Run Analyze first."
            return
        }
        let channelID = candidate.processed.channelID
        // The candidate must be exactly what the controls show now: never pair an old figure with new settings.
        guard candidate.processed.configuration == processingConfiguration, channelID == processingConfiguration.activeChannelID else {
            saveMessage = "The preview is out of date. Wait for it to render, then save."
            return
        }
        let input = PlotInputRef(datasetID: capture.datasetID, channelID: channelID, revision: capture.datasetRevision)
        let title = candidate.display.displayState.titleOverride.isEmpty
            ? (parsedDataset?.title ?? "AFM") : candidate.display.displayState.titleOverride
        let display = heatmapDisplayState
        let sampleUID = capture.sampleUID
        let capturedRoot = URL(fileURLWithPath: capture.libraryRootPath, isDirectory: true)
        let fingerprint = "\(mode)|\(input)|\(candidate.processed.configuration)|\(display)|\(title)"
        let operationID: String
        if let pending = pendingFormalPlotSave, pending.fingerprint == fingerprint {
            operationID = pending.operationID   // same request retried: the service resolves it idempotently
        } else {
            operationID = "plot-save-\(UUID().uuidString)"
            pendingFormalPlotSave = (fingerprint, operationID)
        }
        isSavingFormalPlot = true
        saveMessage = nil
        let assetService = service ?? LibraryAssetService(libraryStore: LibraryStore())

        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<PlotCommitResult, Error> in
                do {
                    let content = try AFMPlotCodec.encode(
                        candidate: candidate, input: input, sampleUIDs: [sampleUID], title: title,
                        displayState: display, savedAt: Date(), appVersion: AppVersion.current
                    )
                    switch mode {
                    case .new:
                        return .success(try assetService.publishPlot(
                            content: content, inputs: [input], operationID: operationID,
                            capturedRootURL: capturedRoot, rootURL: rootURL
                        ))
                    case let .replace(target):
                        let same = Set(target.expectedInputs) == [PlotInputKey(datasetID: input.datasetID, channelID: input.channelID)]
                        return .success(try assetService.updatePlot(
                            plotID: target.plotID, expectedPlotRevision: target.expectedRevision,
                            expectedUpstream: target.expectedInputs, newInputs: [input],
                            mode: same ? .sameSet : .manualSwap, content: content, operationID: operationID,
                            capturedRootURL: capturedRoot, rootURL: rootURL
                        ))
                    }
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            self.isSavingFormalPlot = false
            switch outcome {
            case let .success(result):
                self.pendingFormalPlotSave = nil
                self.openedFormalPlotTarget = FormalPlotReplaceTarget(
                    plotID: result.plotID, expectedRevision: result.revision,
                    expectedInputs: [PlotInputKey(datasetID: input.datasetID, channelID: input.channelID)]
                )
                switch mode {
                case .new: self.saveMessage = "Saved a new plot to the Library."
                case .replace: self.saveMessage = "Replaced the plot in the Library."
                }
                onComplete?()
            case let .failure(error):
                var message = error.localizedDescription
                if case .replace = mode {
                    message += " Use New Plot to keep your result."
                }
                self.saveMessage = message
            }
        }
    }
}
