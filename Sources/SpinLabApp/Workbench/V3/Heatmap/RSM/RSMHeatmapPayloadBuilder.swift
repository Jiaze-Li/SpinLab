import Foundation

/// Errors produced during RSM → HeatmapPlotPayload conversion.
enum RSMHeatmapPayloadBuilderError: Error, Sendable, LocalizedError, Equatable {
    case emptyDataset
    /// Dataset points do not form a complete rectangular grid in the selected view.
    case irregularGrid(view: RSMView, nX: Int, nY: Int, pointCount: Int)

    var errorDescription: String? {
        switch self {
        case .emptyDataset:
            return "RSM dataset has no points."
        case let .irregularGrid(view, nX, nY, n):
            return "RSM \(view.rawValue.uppercased()) view: expected \(nX)×\(nY)=\(nX * nY) points, found \(n)."
        }
    }
}

/// Converts a CanonicalRSMDataset into a HeatmapPlotPayload for the selected 2D view.
///
/// Grid policy (V1):
/// - Points must form a complete rectangular grid in the chosen view's x/y axes.
///   "Complete" means pointCount == nX × nY (exact; no missing cells allowed).
/// - Duplicate (x, y) cells: last point in source order wins.
/// - Non-monotonic axes: accepted by HeatmapGrid but visual tick alignment will
///   be inverted. Caller should ensure ascending axis values for correct display.
enum RSMHeatmapPayloadBuilder {

    struct Options: Sendable {
        var workflowID: String = WorkflowKey.rsm.rawValue
        var view: RSMView = .hl
        var title: String = ""
        /// Explicit z-axis label. Empty = use dataset.detectorColumnName.
        var zLabel: String = ""
        /// Tolerance for grouping floating-point axis values as equal (same grid step).
        var tolerance: Double = 1e-9
    }

    static func build(
        from dataset: CanonicalRSMDataset,
        options: Options = .init()
    ) throws -> HeatmapPlotPayload {
        guard !dataset.points.isEmpty else {
            throw RSMHeatmapPayloadBuilderError.emptyDataset
        }

        let view = options.view
        let tol  = options.tolerance
        let pts  = dataset.points

        let xValues = uniqueSorted(pts.map { view.xValue(of: $0) }, tolerance: tol)
        let yValues = uniqueSorted(pts.map { view.yValue(of: $0) }, tolerance: tol)
        let nX = xValues.count
        let nY = yValues.count

        guard pts.count == nX * nY else {
            throw RSMHeatmapPayloadBuilderError.irregularGrid(
                view: view, nX: nX, nY: nY, pointCount: pts.count
            )
        }

        // zMatrix[row][col]: row = y-index (ascending L/K), col = x-index (ascending H/K)
        var zMatrix = Array(
            repeating: Array(repeating: Double.nan, count: nX),
            count: nY
        )
        var filledCells = Set<Int>()
        for pt in pts {
            if let xi = nearestIndex(in: xValues, for: view.xValue(of: pt), tolerance: tol),
               let yi = nearestIndex(in: yValues, for: view.yValue(of: pt), tolerance: tol) {
                let cellIndex = yi * nX + xi
                guard filledCells.insert(cellIndex).inserted else {
                    throw RSMHeatmapPayloadBuilderError.irregularGrid(
                        view: view, nX: nX, nY: nY, pointCount: pts.count
                    )
                }
                zMatrix[yi][xi] = pt.detector
            }
        }
        guard filledCells.count == nX * nY else {
            throw RSMHeatmapPayloadBuilderError.irregularGrid(
                view: view, nX: nX, nY: nY, pointCount: pts.count
            )
        }

        let resolvedTitle  = options.title.isEmpty ? dataset.title : options.title
        let resolvedZLabel = options.zLabel.isEmpty ? dataset.detectorColumnName : options.zLabel

        return HeatmapPlotPayload(
            workflowID: options.workflowID,
            title: resolvedTitle,
            xLabel: view.xLabel,
            yLabel: view.yLabel,
            zLabel: resolvedZLabel,
            grid: HeatmapGrid(xValues: xValues, yValues: yValues, zMatrix: zMatrix)
        )
    }

    // MARK: - Helpers

    private static func uniqueSorted(_ values: [Double], tolerance: Double) -> [Double] {
        let sorted = values.sorted()
        var unique: [Double] = []
        for v in sorted {
            if unique.isEmpty || abs(v - unique.last!) > tolerance {
                unique.append(v)
            }
        }
        return unique
    }

    private static func nearestIndex(in sorted: [Double], for value: Double, tolerance: Double) -> Int? {
        sorted.firstIndex { abs($0 - value) <= tolerance }
    }
}
