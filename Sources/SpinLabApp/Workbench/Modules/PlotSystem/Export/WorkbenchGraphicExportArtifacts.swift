import Foundation

/// Render-path-agnostic envelope of the currently rendered graphic artifacts for the
/// active plot tab. Every render path (Cartesian XY, DualAxis, Heatmap/RSM) produces its
/// own pngData/pdfData through its own pipeline; this type only carries the result so
/// `WorkbenchPlotCanvas` can display/copy it without knowing which render path produced it.
///
/// `pdfData` is nil when a render path does not yet produce a PDF artifact for the active
/// output — Copy PDF is omitted from the canvas context menu in that case.
struct WorkbenchGraphicExportArtifacts: Sendable, Equatable {
    var pngData: Data?
    var pdfData: Data?

    static let empty = WorkbenchGraphicExportArtifacts()
}
