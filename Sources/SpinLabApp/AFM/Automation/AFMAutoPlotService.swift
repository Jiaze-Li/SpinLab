import Foundation

/// Final state of one automatic-plot attempt for one Dataset.
enum AutoPlotRunResult: Equatable, Sendable {
    case published(plotID: String)
    /// A committed publish already exists for this Dataset revision (the plot may since have been deleted).
    case alreadyPublished
    /// Deterministically not done: nothing wrong, the reason is shown to the user.
    case skipped(String)
    case failed(String, retryable: Bool)
    /// The preset, Library session or Dataset changed before commit; nothing was written.
    case cancelled(String)

    var isSuccess: Bool {
        switch self {
        case .published, .alreadyPublished: return true
        default: return false
        }
    }
}

/// Headless AFM auto plot: standard Dataset + applied preset -> formal Plot. No page, no WorkspaceStore,
/// no raw parser: loadDatasetForAnalysis -> AFMPlotComputation.run -> AFMPlotCodec -> publishAutoPlot.
/// Synchronous and blocking by design; call it from a background task.
struct AFMAutoPlotService: @unchecked Sendable {
    let assetService: LibraryAssetService
    var appVersion: String = AppVersion.current
    var now: @Sendable () -> Date = { Date() }

    /// `expectedRevision` is the revision the intent was created for; nil means "the Dataset as it is now"
    /// (explicit single-Dataset re-run).
    func run(
        datasetID: String,
        expectedRevision: Int?,
        rootURL: URL,
        context: AutoPlotTaskContext,
        preset: AFMAutoPlotPreset
    ) -> AutoPlotRunResult {
        let guardCheck = assetService.autoPlotGuard(context)
        do {
            if let expectedRevision {
                let opID = AutoPlotIdentity.operationID(datasetID: datasetID, revision: expectedRevision)
                if try assetService.plotPublishReceipt(operationID: opID, rootURL: rootURL) != nil {
                    return .alreadyPublished
                }
            }
            try guardCheck()

            let loaded: AnalysisDatasetContext<CanonicalAFMDataset>
            do {
                loaded = try assetService.loadDatasetForAnalysis(datasetID: datasetID, codec: AFMDatasetCodec(), rootURL: rootURL)
            } catch let error as LibraryAssetError {
                switch error {
                case .assetNotFound, .assetNotReady, .ownershipViolation:
                    return .skipped("The measurement is no longer available in the Library.")
                case .invalidPayload:
                    return .skipped("This is not a standard AFM measurement.")
                default:
                    return .failed(error.localizedDescription, retryable: true)
                }
            }
            if let expectedRevision, loaded.revision != expectedRevision {
                return .skipped("The measurement was corrected after it was imported; no automatic plot was made.")
            }
            if loaded.isSampleTrashed { return .skipped("The sample is in the Trash.") }
            if expectedRevision == nil {
                let opID = AutoPlotIdentity.operationID(datasetID: datasetID, revision: loaded.revision)
                if try assetService.plotPublishReceipt(operationID: opID, rootURL: rootURL) != nil {
                    return .alreadyPublished
                }
            }

            let channelID: String
            switch AFMAutoChannelSelector.select(rule: preset.channelRule, in: loaded.dataset.channels) {
            case let .selected(id): channelID = id
            case let other: return .skipped(other.skipReason ?? "No channel could be chosen.")
            }

            var display = preset.displayState
            display.titleTemplate = ""   // templates need a Workbench search hit; the auto plot uses an explicit title or the file's own
            let title = display.titleOverride.isEmpty ? loaded.dataset.title : display.titleOverride
            display.titleOverride = title
            let input = PlotInputRef(datasetID: datasetID, channelID: channelID, revision: loaded.revision)
            let candidate = try AFMPlotComputation.run(
                dataset: loaded.dataset, configuration: preset.processingConfiguration(channelID: channelID),
                display: .init(displayState: display, scaleBar: preset.scaleBar, globalPlotDefaults: preset.globalPlotDefaults)
            )
            let content = try AFMPlotCodec.encode(
                candidate: candidate, input: input, sampleUIDs: [loaded.sampleUID], title: title, displayState: display,
                savedAt: now(), appVersion: appVersion, automatic: .init(presetVersionID: context.presetVersionID)
            )
            switch try assetService.publishAutoPlot(
                content: content, input: input, capturedRootURL: rootURL, rootURL: rootURL, context: context
            ) {
            case let .published(result): return .published(plotID: result.plotID)
            case .alreadyPublished: return .alreadyPublished
            }
        } catch let error as LibraryAssetError {
            switch error {
            case let .autoPlotCancelled(reason): return .cancelled(reason)
            case let .libraryContextChanged(reason): return .cancelled(reason)
            case .staleRevision: return .skipped("The measurement was corrected before the plot was saved.")
            case .assetNotFound, .assetNotReady, .ownershipViolation:
                return .skipped("The measurement or its sample is no longer available.")
            default: return .failed(error.localizedDescription, retryable: true)
            }
        } catch let error as AFMPlotComputation.ComputationError {
            return .failed(error.localizedDescription, retryable: false)
        } catch {
            return .failed(error.localizedDescription, retryable: true)
        }
    }
}
