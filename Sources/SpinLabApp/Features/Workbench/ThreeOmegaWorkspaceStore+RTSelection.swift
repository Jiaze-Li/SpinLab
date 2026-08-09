import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    func updateRTQuery(_ newValue: String) {
        rtQuery = newValue
        persistRTQuery()
    }


    func persistRTQuery() {
        UserDefaults.standard.set(rtQuery, forKey: Self.rtQueryDefaultsKey)
    }


    func selectRTHit(_ hit: WorkflowMeasurementSearchHit) {
        selectedRTHit = hit
        rtSearchResults = []
        showRTPopover = false
        launchRTAnalysis(for: hit)
    }

    func launchRTAnalysis(for hit: WorkflowMeasurementSearchHit) {
        isAnalyzingRT = true
        rtAnalysisMessage = nil
        cachedRTResult = nil
        let useCase = AnalyzeRTWorkflowUseCase()
        let capturedWorkflowID = workflowID
        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) {
                useCase.execute(hit: hit, workflowID: capturedWorkflowID)
            }.value
            await MainActor.run {
                self.cachedRTResult = result
                self.ingestionResult?.rtResult = ThreeOmegaRTResult(
                    device: result.device,
                    temperatureK: result.temperatureK,
                    rxx: result.rxx
                )
                self.isAnalyzingRT = false
                self.rtAnalysisMessage = result.warnings.isEmpty ? nil : result.warnings.joined(separator: " | ")
                self.refreshTransportDerivedPlots(reason: "RT analysis completed")
            }
        }
    }


    func clearRTSelection() {
        selectedRTHit = nil
        cachedRTResult = nil
        ingestionResult?.rtResult = nil
        isAnalyzingRT = false
        rtAnalysisMessage = nil
        refreshTransportDerivedPlots(reason: "RT selection cleared")
    }


    /// Applies a pre-built hit from background restoration. Called by WorkbenchFeatureStore.
    func applyRestoredRTHit(_ hit: WorkflowMeasurementSearchHit) {
        selectRTHit(hit)
        pendingRTSidecarPath = nil
    }


    /// Clears pending restore (called when restore fails).
    func clearPendingRTRestore() {
        pendingRTSidecarPath = nil
    }


    /// Parses a sidecar file and rebuilds a lightweight hit. Runs off MainActor.
    nonisolated static func rebuildRTHit(
        fromSidecarPath sidecarPath: String,
        workflowID: String,
        relatedRTWorkflowID: String?,
        fileManager: FileManager = .default,
        sidecarReader: any LibrarySidecarReaderCapability = LibrarySidecarReader()
    ) -> WorkflowMeasurementSearchHit? {
        let fm = fileManager
        guard fm.fileExists(atPath: sidecarPath) else { return nil }

        let suffix = ".spinlab.json"
        guard sidecarPath.hasSuffix(suffix) else { return nil }
        let baseName = String(sidecarPath.dropLast(suffix.count))
        guard fm.fileExists(atPath: baseName) else { return nil }

        guard let sidecar = sidecarReader.loadSidecar(atPath: sidecarPath) else { return nil }

        let wfID = sidecar.resolvedWorkflow
        guard wfID == workflowID || wfID == relatedRTWorkflowID else { return nil }

        return WorkflowMeasurementSearchHit(
            sidecarPath: sidecarPath,
            measurementFilePath: baseName,
            sourceFilePath: sidecar.sourceFilePath,
            workflowID: sidecar.resolvedWorkflow,
            workflowDisplayName: sidecar.workflowDisplayName,
            workflowCanonicalID: wfID,
            batchID: "",
            sampleKey: "",
            sampleSubstrate: "",
            conditions: sidecar.effectiveConditions,
            channels: sidecar.channels,
            appliedAt: sidecar.appliedAt
        )
    }
}
