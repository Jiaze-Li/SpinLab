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

    func updateScalingAngleCandidate(_ candidate: String?) {
        guard scalingAngleCandidate != candidate else { return }
        scalingAngleCandidate = candidate
        _refreshScalingVsAngleResult()
        _refreshManifestPayloads()
        rerenderForStyleChange()
    }

    func _refreshScalingVsAngleResult() {
        var allRecords: [WorkbenchMetricRecord] = []

        // 1. Gather all metric records from Library for cachedSampleKeys
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

        // 2. Also incorporate current in-memory scalingResult if available
        if let currentScaling = scalingResult, let ingestion = ingestionResult {
            let currentDev = ingestion.device
            let currentMethod = v3Method == .highField ? "HFE" : "WA"
            let currentSampleKey = keys.first ?? "current"
            for seg in currentScaling.segments {
                let rangeStr = "\(Int(seg.tLo.rounded()))K–\(Int(seg.tHi.rounded()))K"
                let segConditions: [String: String] = [
                    "range": rangeStr,
                    "v3method": currentMethod,
                    "device": currentDev
                ]
                allRecords.append(WorkbenchMetricRecord(
                    recordID: seg.id.uuidString,
                    sampleKey: currentSampleKey,
                    displayKey: currentSampleKey,
                    workflowID: "3w",
                    metric: "alpha",
                    value: seg.alpha * ThreeOmegaDisplayScale.scalingLawFitSlope.scaleFactor,
                    canonicalUnit: "Ω·μm³·cm²·V⁻²·S⁻²",
                    conditions: segConditions,
                    generatedAt: Date(),
                    runID: "in-memory"
                ))
                allRecords.append(WorkbenchMetricRecord(
                    recordID: seg.id.uuidString,
                    sampleKey: currentSampleKey,
                    displayKey: currentSampleKey,
                    workflowID: "3w",
                    metric: "beta",
                    value: seg.beta * ThreeOmegaDisplayScale.scalingLawY.scaleFactor,
                    canonicalUnit: "Ω·μm³·V⁻²",
                    conditions: segConditions,
                    generatedAt: Date(),
                    runID: "in-memory"
                ))
                allRecords.append(WorkbenchMetricRecord(
                    recordID: seg.id.uuidString,
                    sampleKey: currentSampleKey,
                    displayKey: currentSampleKey,
                    workflowID: "3w",
                    metric: "r_squared",
                    value: seg.rSquared,
                    canonicalUnit: "",
                    conditions: segConditions,
                    generatedAt: Date(),
                    runID: "in-memory"
                ))
            }
        }

        // 3. Execute use case
        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(
            records: allRecords,
            selectedCoefficient: scalingAngleCoefficient,
            selectedMethod: scalingAngleMethod,
            selectedFitRange: scalingAngleFitRange,
            selectedCandidate: scalingAngleCandidate
        )

        self.scalingVsAngleResult = result
        if scalingAngleMethod == nil && result.selectedMethod != nil {
            scalingAngleMethod = result.selectedMethod
        }
        if scalingAngleFitRange == nil && result.selectedFitRange != nil {
            scalingAngleFitRange = result.selectedFitRange
        }
        if scalingAngleCandidate == nil && result.selectedCandidate != nil {
            scalingAngleCandidate = result.selectedCandidate
        }
    }
}
