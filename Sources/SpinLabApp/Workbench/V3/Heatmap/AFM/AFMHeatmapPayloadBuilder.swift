import Foundation

/// Errors produced converting a `ProcessedAFMChannel` into a `HeatmapPlotPayload`.
enum AFMHeatmapPayloadBuilderError: Error, Sendable, Equatable, LocalizedError {
    case dimensionMismatch(expectedX: Int, expectedY: Int, foundY: Int, foundX: Int?)

    var errorDescription: String? {
        switch self {
        case let .dimensionMismatch(expectedX, expectedY, foundY, foundX):
            return "AFM processed channel is \(foundY)×\(foundX.map(String.init) ?? "?"); expected \(expectedY)×\(expectedX) to match the dataset's Y×X coordinates."
        }
    }
}

/// Converts a `CanonicalAFMDataset` + `ProcessedAFMChannel` into a `HeatmapPlotPayload`. AFM
/// data is already a dense rectangular matrix (unlike RSM's scattered points), so this needs no
/// grid-fitting — it maps coordinates and the processed matrix straight across. AFM owns which
/// channel, physical units, and default labels; Heatmap owns everything about how the payload
/// is drawn. See `docs/architecture/workbench/datasets/AFMDatasetContract.md`.
enum AFMHeatmapPayloadBuilder {
    struct Options: Sendable {
        var workflowID: String
        /// Empty = use `dataset.title`.
        var title: String = ""
        /// Default AFM palette: approved Gwyddion palette with a slightly warm top end.
        var colormapKey: String? = "gwyddionWarm"
        var scaleBar: AFMScaleBarSetting = .init()
        var aspectPolicy: HeatmapAspectPolicy = .physical
    }

    static func build(
        dataset: CanonicalAFMDataset,
        processed: ProcessedAFMChannel,
        options: Options
    ) throws -> HeatmapPlotPayload {
        let nX = dataset.xCoordinates.count
        let nY = dataset.yCoordinates.count
        guard processed.values.count == nY, processed.values.allSatisfy({ $0.count == nX }) else {
            throw AFMHeatmapPayloadBuilderError.dimensionMismatch(
                expectedX: nX, expectedY: nY,
                foundY: processed.values.count, foundX: processed.values.first?.count
            )
        }

        let resolvedTitle = options.title.isEmpty ? dataset.title : options.title

        let scanWidth = Self.scanWidthMicrometers(dataset.xCoordinates)

        return HeatmapPlotPayload(
            workflowID: options.workflowID,
            title: resolvedTitle,
            // AFM figures carry no axes and no Z title: the colorbar endpoints carry the unit.
            xLabel: "",
            yLabel: "",
            zLabel: "",
            grid: HeatmapGrid(xValues: dataset.xCoordinates, yValues: dataset.yCoordinates, zMatrix: processed.values),
            colormapKey: options.colormapKey,
            aspectPolicy: options.aspectPolicy,
            scaleBarOverlay: scanWidth.flatMap { options.scaleBar.overlay(scanWidthMicrometers: $0) },
            hideSpatialAxes: true
        )
    }

    /// Full drawn scan width in µm (center-to-center span plus one pixel pitch).
    static func scanWidthMicrometers(_ xCoordinates: [Double]) -> Double? {
        guard xCoordinates.count > 1, let lo = xCoordinates.min(), let hi = xCoordinates.max(), hi > lo else {
            return nil
        }
        return (hi - lo) * Double(xCoordinates.count) / Double(xCoordinates.count - 1)
    }
}
