import AppKit
import Foundation

/// Formal Plot access for the Library and the Workbench: summaries, Open, permanent delete, PDF export.
/// All reads go through `LibraryAssetService`; nothing here reads SQLite or storage files itself.
extension SpinLabAppState {

    private var formalPlotService: LibraryAssetService {
        LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
    }

    func loadFormalPlotSummaries() -> Result<[FormalPlotSummary], Error> {
        guard let rootURL = v2LibraryRootURL else { return .success([]) }
        let service = formalPlotService
        return Result { try FormalPlotLibrary(service: service).summaries(rootURL: rootURL) }
    }

    func formalPlotThumbnail(plotID: String) -> Data? {
        guard let rootURL = v2LibraryRootURL else { return nil }
        return FormalPlotLibrary(service: formalPlotService).png(plotID: plotID, rootURL: rootURL)
    }

    /// Permanent delete of one formal Plot (confirmed by the caller). The Plot's input data stays.
    func planFormalPlotDeletion(plotID: String) -> Result<PermanentDeletionPlan, Error> {
        planV2AssetDeletion(target: .plot(plotID))
    }

    func commitFormalPlotDeletion(plotID: String, plan: PermanentDeletionPlan) -> Result<PermanentDeletionResult, Error> {
        commitV2AssetDeletion(target: .plot(plotID), plan: plan, operationPrefix: "delete-plot-\(plotID)")
    }

    /// Redraws a stored Plot as PDF from its matrix alone and asks where to save it.
    func exportFormalPlotPDF(plotID: String, suggestedName: String) -> String? {
        guard let rootURL = v2LibraryRootURL else { return "No standard Library is open." }
        do {
            let loaded = try formalPlotService.loadPlot(plotID: plotID, rootURL: rootURL)
            let stored = try AFMPlotCodec.decode(files: loaded.files)
            let pdf = try AFMPlotCodec.render(stored: stored, styleDefaults: workbench.globalPlotDefaults).pdfData
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = suggestedName.isEmpty ? "AFM Plot.pdf" : suggestedName + ".pdf"
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            try pdf.write(to: url, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Opens a stored Plot in the AFM Workbench: restores the Dataset selection and the effective science and
    /// display settings, re-runs the shared analysis on the Dataset's current revision, and makes this Plot the
    /// explicit replace target. Returns an error message, or nil on success.
    @discardableResult
    func openFormalPlotInWorkbench(plotID: String) -> String? {
        guard let rootURL = v2LibraryRootURL else { return "No standard Library is open." }
        let service = formalPlotService
        let afm = workbench.afmWorkspace
        do {
            let loaded = try service.loadPlot(plotID: plotID, rootURL: rootURL)
            let stored = try AFMPlotCodec.decode(files: loaded.files)
            let manifest = stored.manifest
            guard let summary = try service.listAnalysisDatasets(format: AFMDatasetCodec.format, rootURL: rootURL)
                .first(where: { $0.datasetID == manifest.input.datasetID }) else {
                return "The data behind this plot is no longer available (its sample may be in the Trash)."
            }
            let hit = SearchWorkflowMeasurementsUseCase.standardHit(summary: summary, displayName: "AFM")
            let wf = afm.workflowID
            afm.prepareToOpenFormalPlot(
                manifest: manifest,
                target: FormalPlotReplaceTarget(
                    plotID: plotID, expectedRevision: loaded.row.record.currentRevision, expectedInputs: loaded.row.inputs
                ),
                libraryRootPath: rootURL.path
            )
            workbench.restoreSearchState(results: [hit], queryText: "afm", for: wf)
            workbench.seedSelection([hit.id], hits: [hit], for: wf)
            navigate(to: AppRouteStack(paths: [.workbench, .workbenchWorkflow(id: wf)]))
            afm.runAnalysis(selectedHitsSnapshot: workbench.selectedHitsSnapshot(for: wf))
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
