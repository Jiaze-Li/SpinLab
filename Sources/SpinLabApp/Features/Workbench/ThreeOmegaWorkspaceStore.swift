import Foundation
import Observation

/// Isolated state and actions for the 3ω AHE workflow workspace.
///
/// Owned by `WorkbenchFeatureStore`. Views bind directly to this store.
/// Geometry parameters are session-only (not persisted).
@MainActor
@Observable
final class ThreeOmegaWorkspaceStore {

    // MARK: - Search / Selection

    var selectedSearchResultIDs: Set<String> = []
    var cachedSearchResults: [WorkflowMeasurementSearchHit] = []

    // MARK: - Geometry (session-only, not persisted)

    var geometry = ThreeOmegaGeometry()

    // MARK: - Analysis output

    private(set) var ingestionResult: ThreeOmegaIngestionResult?
    private(set) var scalingResult: ThreeOmegaScalingResult?
    private(set) var isAnalyzing: Bool = false
    var analysisMessage: String?

    // MARK: - Tab selection

    var activeTab: ThreeOmegaWorkbenchTab = .fieldSweep1omega

    // MARK: - Rendered plots (PNG Data per tab)

    private(set) var plotR1omega: Data?
    private(set) var plotR3omega: Data?
    private(set) var plotRAHEvsT: Data?
    private(set) var plotHcvsT: Data?
    private(set) var plotRT: Data?
    private(set) var plotScaling: Data?

    // MARK: - Private

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var scalingTask: Task<Void, Never>?

    deinit {
        analysisTask?.cancel()
        scalingTask?.cancel()
    }

    // MARK: - Selection

    func toggleSearchHitSelection(_ id: String) {
        if selectedSearchResultIDs.contains(id) {
            selectedSearchResultIDs.remove(id)
        } else {
            selectedSearchResultIDs.insert(id)
        }
    }

    // MARK: - Analysis

    /// Parse all selected files, fit RAHE/Hc, render tabs 1–5.
    /// Automatically runs scaling if geometry is complete.
    func runAnalysis() {
        let selectedHits = cachedSearchResults.filter { selectedSearchResultIDs.contains($0.id) }
        guard !selectedHits.isEmpty else {
            analysisMessage = "Select at least one 3ω AHE measurement file."
            return
        }

        analysisTask?.cancel()
        isAnalyzing = true
        analysisMessage = nil
        _clearPlots()

        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (result, plots, scalingRes) = try await Task.detached(priority: .userInitiated) { [selectedHits] in
                    let ingestUseCase = IngestThreeOmegaSelectionsUseCase()
                    let result = ingestUseCase.execute(hits: selectedHits)

                    let renderer = ThreeOmegaPlotRenderer()
                    let plots = renderer.renderAllTabs(result: result)

                    // Run scaling if geometry is ready (uses the iRmsValues stored in result)
                    var scalingRes: ThreeOmegaScalingResult? = nil
                    if let rt = result.rtResult {
                        let scalingUseCase = ThreeOmegaScalingUseCase()
                        let geom = ThreeOmegaGeometry()  // default — user updates later
                        if geom.isComplete {
                            scalingRes = scalingUseCase.executeWithIRms(
                                fieldSweeps: result.fieldSweeps,
                                rtResult: rt,
                                geometry: geom,
                                iRmsValues: result.iRmsValues
                            )
                        }
                    }

                    return (result, plots, scalingRes)
                }.value

                guard !Task.isCancelled else { return }
                self.ingestionResult = result
                self.scalingResult = scalingRes
                self.plotR1omega  = plots.r1omega
                self.plotR3omega  = plots.r3omega
                self.plotRAHEvsT = plots.raheVsT
                self.plotHcvsT   = plots.hcVsT
                self.plotRT      = plots.rtCurve
                self.plotScaling = plots.scaling

                let sweepCount = result.fieldSweeps.count
                let rtNote = result.rtResult != nil ? ", RT curve loaded" : ""
                let warnNote = result.warnings.isEmpty ? "" : " (\(result.warnings.count) warning(s))"
                self.analysisMessage = "Analyzed \(sweepCount) field-sweep file(s)\(rtNote)\(warnNote)."
                self.isAnalyzing = false
            } catch is CancellationError {
                self.isAnalyzing = false
            } catch {
                self.isAnalyzing = false
                self.analysisMessage = "Analysis failed: \(error.localizedDescription)"
            }
        }
    }

    /// Re-runs only the scaling (cheap). Called when geometry parameters change.
    func runScaling() {
        guard let result = ingestionResult, let rt = result.rtResult else {
            analysisMessage = "Run analysis first before applying geometry."
            return
        }
        guard geometry.isComplete else {
            analysisMessage = "Enter L_xx, L_xy, and d to compute Fig 5b scaling."
            return
        }

        let capturedResult = result
        let capturedGeometry = geometry

        scalingTask?.cancel()
        scalingTask = Task { [weak self] in
            guard let self else { return }
            let (scalingRes, scalingPlot) = await Task.detached(priority: .userInitiated) {
                let scalingUseCase = ThreeOmegaScalingUseCase()
                let res = scalingUseCase.executeWithIRms(
                    fieldSweeps: capturedResult.fieldSweeps,
                    rtResult: rt,
                    geometry: capturedGeometry,
                    iRmsValues: capturedResult.iRmsValues
                )
                let renderer = ThreeOmegaPlotRenderer()
                let plot = renderer.renderScaling(result: res)
                return (res, plot)
            }.value

            guard !Task.isCancelled else { return }
            self.scalingResult = scalingRes
            self.plotScaling = scalingPlot

            if let beta = scalingRes.beta, let r2 = scalingRes.rSquared {
                self.analysisMessage = String(format: "Scaling: β = %.4e, R² = %.4f", beta, r2)
            } else if !scalingRes.warnings.isEmpty {
                self.analysisMessage = scalingRes.warnings.first
            }
        }
    }

    /// Clear all state.
    func clearAll() {
        analysisTask?.cancel()
        scalingTask?.cancel()
        selectedSearchResultIDs = []
        ingestionResult = nil
        scalingResult = nil
        isAnalyzing = false
        analysisMessage = nil
        geometry = ThreeOmegaGeometry()
        activeTab = .fieldSweep1omega
        _clearPlots()
    }

    private func _clearPlots() {
        plotR1omega  = nil
        plotR3omega  = nil
        plotRAHEvsT = nil
        plotHcvsT   = nil
        plotRT      = nil
        plotScaling = nil
    }
}

// MARK: - Rendered plot bundle

struct ThreeOmegaRenderedPlots: Sendable {
    var r1omega:  Data?
    var r3omega:  Data?
    var raheVsT:  Data?
    var hcVsT:    Data?
    var rtCurve:  Data?
    var scaling:  Data?
}
