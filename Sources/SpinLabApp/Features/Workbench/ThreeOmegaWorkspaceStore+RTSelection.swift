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
    }


    func clearRTSelection() {
        selectedRTHit = nil
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
    nonisolated static func rebuildRTHit(fromSidecarPath sidecarPath: String, fileManager: FileManager = .default) -> WorkflowMeasurementSearchHit? {
        let fm = fileManager
        guard fm.fileExists(atPath: sidecarPath) else { return nil }

        let suffix = ".spinlab.json"
        guard sidecarPath.hasSuffix(suffix) else { return nil }
        let baseName = String(sidecarPath.dropLast(suffix.count))
        guard fm.fileExists(atPath: baseName) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sidecarPath)),
              let sidecar = try? decoder.decode(SpinLabFileSidecar.self, from: data) else { return nil }

        let wfID = sidecar.resolvedWorkflow.lowercased()
        guard wfID == "3w" || wfID == "rt" else { return nil }

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
