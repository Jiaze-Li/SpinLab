import Foundation

/// Read-only projection of a completed plot run for UI display.
/// Must be built from a persisted WorkbenchRunManifest — no recomputation from live payload.
struct WorkbenchRunTraceProjection: Sendable {
    var runID: String
    var workflowID: String
    var inputFiles: [String]
    var axisMapping: WorkbenchAxisMapping
    var semanticParams: [String: String]
    var outputImagePath: String   // library-root-relative
    var manifestPath: String      // library-root-relative
    var generatedAt: Date
}

struct BuildRunTraceProjectionUseCase {
    func execute(
        manifest: WorkbenchRunManifest,
        manifestPath: String
    ) -> WorkbenchRunTraceProjection {
        WorkbenchRunTraceProjection(
            runID: manifest.runID,
            workflowID: manifest.workflowID,
            inputFiles: manifest.inputFiles,
            axisMapping: manifest.axisMapping,
            semanticParams: manifest.semanticParams,
            outputImagePath: manifest.outputImagePath,
            manifestPath: manifestPath,
            generatedAt: manifest.generatedAt
        )
    }
}
