import Foundation

/// WP1 step ④ for one already stored Source: choose the adapter by container format, remember an
/// automatic-plot intent *before* standardizing, run the independent standardize step, and hand
/// back the trigger bound to that very receipt. Used by the Inbox apply and by the Library's
/// "Standardize again" action, so both go through one function.
struct V2SourceStandardizationCoordinator {
    let service: LibraryAssetService
    let rootURL: URL

    struct Outcome {
        let result: StandardizationResult
        let autoPlotTrigger: AutoPlotTrigger?
    }

    /// The applied AFM preset as the coordinator sees it now; unreadable or off means no intent.
    func currentAutoPlotIntent(workflowID: String?) -> AutoPlotIntent? {
        guard workflowID?.lowercased() == "afm",
              let preset = try? service.currentAutoPlotPreset(rootURL: rootURL).load.effective, preset.enabled else { return nil }
        return AutoPlotIntent(presetVersionID: preset.presetVersionID)
    }

    /// An already standardized Source never gets a new follow-up: a repeat must not plot again.
    private func hasDatasets(sourceID: String, sampleUID: String) throws -> Bool {
        try service.sourceStatusSummaries(forSampleUID: sampleUID, rootURL: rootURL)
            .contains { $0.sourceID == sourceID && $0.datasetCount > 0 }
    }

    func standardize(
        sourceID: String, sampleUID: String, operationID: String, fileName: String,
        confirmedWorkflowID: String?, autoPlotIntent: AutoPlotIntent?
    ) throws -> Outcome {
        let adapter = StandardizationAdapterRegistry.adapter(fileName: fileName, confirmedWorkflowID: confirmedWorkflowID)
        if let autoPlotIntent, adapter is AFMIBWStandardizationAdapter,
           try !service.standardizeOperationExists(operationID, rootURL: rootURL),
           try !hasDatasets(sourceID: sourceID, sampleUID: sampleUID) {
            // Written before the standardize call so a crash in between never forgets the intent.
            try service.recordFollowup(
                standardizeOperationID: operationID, sourceID: sourceID, kind: LibraryAssetService.autoPlotFollowupKind,
                requestJSON: service.encodeJSON(autoPlotIntent), rootURL: rootURL
            )
        }
        let result = try service.standardizeSource(
            sourceID: sourceID, adapter: adapter, operationID: operationID, rootURL: rootURL
        )
        guard case let .standardized(datasetIDs, revision) = result,
              let stored = try service.followupIntent(standardizeOperationID: operationID, rootURL: rootURL) else {
            return Outcome(result: result, autoPlotTrigger: nil)
        }
        return Outcome(
            result: result,
            autoPlotTrigger: AutoPlotTrigger(
                datasetIDs: datasetIDs, datasetRevision: revision, sampleUID: sampleUID, intent: stored, rootURL: rootURL
            )
        )
    }
}
