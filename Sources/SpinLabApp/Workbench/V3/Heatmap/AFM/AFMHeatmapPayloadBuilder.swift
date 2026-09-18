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
        var xLabel: String = "X (\(CanonicalAFMDataset.xUnit))"
        var yLabel: String = "Y (\(CanonicalAFMDataset.yUnit))"
        /// Empty = "`<displayLabel>` (`<canonicalUnit>`)".
        var zLabel: String = ""
        var colormapKey: String? = nil
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
        let resolvedZLabel = options.zLabel.isEmpty
            ? "\(processed.displayLabel) (\(processed.canonicalUnit))"
            : options.zLabel

        return HeatmapPlotPayload(
            workflowID: options.workflowID,
            title: resolvedTitle,
            xLabel: options.xLabel,
            yLabel: options.yLabel,
            zLabel: resolvedZLabel,
            grid: HeatmapGrid(xValues: dataset.xCoordinates, yValues: dataset.yCoordinates, zMatrix: processed.values),
            colormapKey: options.colormapKey
        )
    }
}
