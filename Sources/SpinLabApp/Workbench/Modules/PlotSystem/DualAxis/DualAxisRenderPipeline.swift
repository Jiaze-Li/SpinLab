import CoreGraphics
import Foundation

/// Dual-axis render path orchestrator (Plot System-owned).
/// Parallel to WorkbenchRenderPipeline and HeatmapRenderPipeline; does not call or extend them.
/// Validates series, collects warnings, delegates to DualAxisChartRenderer.
enum DualAxisRenderPipeline {

    struct Input: Sendable {
        var payload: DualAxisPlotPayload
        var options: DualAxisPlotLayout.Options = .init()
        var style: WorkbenchChartStyle = .init()
        var legendPoint: CGPoint? = nil
        /// Captured display state. The renderer must not read live control/store state.
        var displayState: DualAxisDisplayStateSnapshot = .default
    }

    struct Output: Sendable {
        let imageData: Data
        let layout: DualAxisPlotLayout
        let warnings: [String]
    }

    static func render(_ input: Input) throws -> Output {
        let displayState = input.displayState
        let payload = displayState.applying(to: input.payload)
        var warnings: [String] = []

        // Validate: require at least one non-empty series
        let allEmpty = (payload.leftSeries + payload.rightSeries).allSatisfy(\.x.isEmpty)
        if payload.leftSeries.isEmpty && payload.rightSeries.isEmpty {
            warnings.append("DualAxisRenderPipeline: payload has no series.")
        } else if allEmpty {
            warnings.append("DualAxisRenderPipeline: all series are empty.")
        }

        var validLeft: [DualAxisPlotSeries] = []
        var validRight: [DualAxisPlotSeries] = []

        for s in payload.leftSeries {
            if s.x.count != s.y.count {
                warnings.append("Left '\(s.label)': x.count (\(s.x.count)) ≠ y.count (\(s.y.count)); series skipped.")
                continue
            }
            if !s.x.contains(where: \.isFinite) {
                warnings.append("Left '\(s.label)': no finite x values; series skipped.")
                continue
            }
            if !s.y.contains(where: \.isFinite) {
                warnings.append("Left '\(s.label)': no finite y values; series skipped.")
                continue
            }
            validLeft.append(s)
        }

        for s in payload.rightSeries {
            if s.x.count != s.y.count {
                warnings.append("Right '\(s.label)': x.count (\(s.x.count)) ≠ y.count (\(s.y.count)); series skipped.")
                continue
            }
            if !s.x.contains(where: \.isFinite) {
                warnings.append("Right '\(s.label)': no finite x values; series skipped.")
                continue
            }
            if !s.y.contains(where: \.isFinite) {
                warnings.append("Right '\(s.label)': no finite y values; series skipped.")
                continue
            }
            validRight.append(s)
        }

        let layout = DualAxisPlotLayout.compute(
            payload: payload,
            validLeftSeries: validLeft,
            validRightSeries: validRight,
            options: input.options,
            style: input.style,
            displayState: displayState,
            legendPoint: input.legendPoint
        )

        let imageData = try DualAxisChartRenderer().renderPNG(
            payload: payload,
            validLeftSeries: validLeft,
            validRightSeries: validRight,
            layout: layout,
            options: input.options,
            style: input.style,
            displayState: displayState
        )

        return Output(imageData: imageData, layout: layout, warnings: warnings)
    }
}
