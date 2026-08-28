import Foundation

@MainActor
extension ThreeOmegaWorkspaceStore {

    func updateScalingAngleCoefficient(_ kind: ThreeOmegaScalingCoefficientKind) {
        guard scalingAngleCoefficient != kind else { return }
        scalingAngleCoefficient = kind
        _refreshScalingVsAngleResult()
        _refreshManifestPayloads()
        rerenderForStyleChange()
    }

    func updateScalingAngleMethod(_ method: String) {
        guard scalingAngleMethod != method else { return }
        scalingAngleMethod = method
        _refreshScalingVsAngleResult()
        _refreshManifestPayloads()
        rerenderForStyleChange()
    }

    func updateScalingAngleFitRange(_ fitRange: String) {
        guard scalingAngleFitRange != fitRange else { return }
        scalingAngleFitRange = fitRange
        _refreshScalingVsAngleResult()
        _refreshManifestPayloads()
        rerenderForStyleChange()
    }

    /// Sets (or clears, when `candidateID` is nil) the chosen fit/run for a single
    /// ambiguous angle. Other angles are untouched.
    func updateScalingAngleCandidate(angleKey: String, candidateID: String?) {
        if let candidateID, !candidateID.isEmpty {
            guard scalingAngleCandidateSelections[angleKey] != candidateID else { return }
            scalingAngleCandidateSelections[angleKey] = candidateID
        } else {
            guard scalingAngleCandidateSelections[angleKey] != nil else { return }
            scalingAngleCandidateSelections.removeValue(forKey: angleKey)
        }
        // A per-angle selection change supersedes any legacy global candidate.
        scalingAngleCandidate = nil
        _refreshScalingVsAngleResult()
        _refreshManifestPayloads()
        rerenderForStyleChange()
    }

    /// Deterministic identity string for the current per-angle candidate selection,
    /// used only as a chart-identity discriminator (semanticParams / manifest cache).
    var scalingAngleCandidateIdentityString: String {
        if !scalingAngleCandidateSelections.isEmpty {
            return scalingAngleCandidateSelections
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ";")
        }
        return scalingAngleCandidate ?? ""
    }

    func _refreshScalingVsAngleResult() {
        // Library-only source: Scaling vs Angle consumes ONLY Scaling results that
        // the user has already saved to the Library. An in-memory, not-yet-saved
        // `scalingResult` is deliberately NOT mixed in — it is not an approved β/α
        // until the user saves that single-device Scaling Law.
        var allRecords: [WorkbenchMetricRecord] = []

        let rootPath = lastLibraryRootPath
        let keys = cachedSampleKeys
        if !rootPath.isEmpty && !keys.isEmpty {
            let resolver = LibraryPathResolver(libraryRootURL: URL(fileURLWithPath: rootPath))
            let loader = LoadMeasurementDataUseCase(pathResolver: resolver)
            for key in keys {
                if let store = loader.execute(sampleKey: key) {
                    allRecords.append(contentsOf: store.records.filter { $0.workflowID == "3w" })
                }
            }
        }

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(
            records: allRecords,
            selectedCoefficient: scalingAngleCoefficient,
            selectedMethod: scalingAngleMethod,
            selectedFitRange: scalingAngleFitRange,
            candidateSelections: scalingAngleCandidateSelections,
            legacyCandidate: scalingAngleCandidate
        )

        self.scalingVsAngleResult = result
        if scalingAngleMethod == nil && result.selectedMethod != nil {
            scalingAngleMethod = result.selectedMethod
        }
        if scalingAngleFitRange == nil && result.selectedFitRange != nil {
            scalingAngleFitRange = result.selectedFitRange
        }
        // Drop per-angle selections for angles that are no longer ambiguous so a
        // stale choice can't silently keep filtering a since-changed dataset.
        let stillAmbiguous = Set(result.ambiguousAnglesByKey.keys)
        scalingAngleCandidateSelections = scalingAngleCandidateSelections.filter { stillAmbiguous.contains($0.key) }
    }
}
