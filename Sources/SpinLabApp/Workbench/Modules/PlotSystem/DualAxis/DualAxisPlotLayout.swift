import CoreGraphics
import Foundation

/// Geometry type for the dual-axis render path (Plot System-owned).
/// Parallel to WorkbenchPlotLayout and HeatmapPlotLayout; must not inherit or extend either.
/// Left Y-axis: left side of plotRect.  Right Y-axis: right side of plotRect.
/// Coordinate space: CG renderer (origin bottom-left, Y increases upward).
struct DualAxisPlotLayout: Sendable {

    struct Options: Sendable {
        var width: Int = 900
        var height: Int = 600
        var pixelScale: CGFloat = 2.0
        var paddingTop: CGFloat = 64
        var paddingBottom: CGFloat = 80
        var paddingLeft: CGFloat = 96
        var paddingRight: CGFloat = 96
    }

    let rendererSize: CGSize
    /// Plot area in CG renderer pixel space.
    let plotRect: CGRect
    let titleCenter: CGPoint
    let xLabelCenter: CGPoint
    /// Center for the left Y-axis label, drawn rotated 90° counter-clockwise.
    let leftYLabelCenter: CGPoint
    /// Center for the right Y-axis label, drawn rotated 90° clockwise.
    let rightYLabelCenter: CGPoint
    /// Shared X data range used for rendering.
    let axisXMin: Double
    let axisXMax: Double
    /// Independent left Y data range.
    let axisLeftYMin: Double
    let axisLeftYMax: Double
    /// Independent right Y data range.
    let axisRightYMin: Double
    let axisRightYMax: Double
    let xTicks: [PlotAxisTick]
    let leftYTicks: [PlotAxisTick]
    let rightYTicks: [PlotAxisTick]

    // MARK: - Factory

    static func compute(
        payload: DualAxisPlotPayload,
        options: Options = .init(),
        style: WorkbenchChartStyle = .init(),
        displayState: DualAxisDisplayStateSnapshot = .default
    ) -> DualAxisPlotLayout {
        let validLeft = payload.leftSeries.filter {
            $0.x.count == $0.y.count && $0.x.contains(where: \.isFinite)
        }
        let validRight = payload.rightSeries.filter {
            $0.x.count == $0.y.count && $0.x.contains(where: \.isFinite)
        }
        return compute(
            payload: payload,
            validLeftSeries: validLeft,
            validRightSeries: validRight,
            options: options,
            style: style,
            displayState: displayState
        )
    }

    static func compute(
        payload: DualAxisPlotPayload,
        validLeftSeries: [DualAxisPlotSeries],
        validRightSeries: [DualAxisPlotSeries],
        options: Options = .init(),
        style: WorkbenchChartStyle = .init(),
        displayState: DualAxisDisplayStateSnapshot = .default
    ) -> DualAxisPlotLayout {
        let w = CGFloat(options.width)
        let h = CGFloat(options.height)

        let autoX = dataRange(from: (validLeftSeries + validRightSeries).flatMap(\.x))
        let autoLeftY = dataRange(from: validLeftSeries.flatMap(\.y))
        let autoRightY = dataRange(from: validRightSeries.flatMap(\.y))
        let rangeOverride = displayState.axisRangeOverride

        let (xMin, xMax) = applyRangeOverride(
            auto: autoX,
            manualMin: rangeOverride?.xMin,
            manualMax: rangeOverride?.xMax
        )
        let (leftYMin, leftYMax) = applyRangeOverride(
            auto: autoLeftY,
            manualMin: rangeOverride?.leftYMin,
            manualMax: rangeOverride?.leftYMax
        )
        let (rightYMin, rightYMax) = applyRangeOverride(
            auto: autoRightY,
            manualMin: rangeOverride?.rightYMin,
            manualMax: rangeOverride?.rightYMax
        )

        let (xTickValues, xStep) = PlotAxisSpacingCalculator.niceTicks(
            min: xMin, max: xMax, targetCount: style.tickTargetX
        )
        let (leftYTickValues, leftStep) = PlotAxisSpacingCalculator.niceTicks(
            min: leftYMin, max: leftYMax, targetCount: style.tickTargetY
        )
        let (rightYTickValues, rightStep) = PlotAxisSpacingCalculator.niceTicks(
            min: rightYMin, max: rightYMax, targetCount: style.tickTargetY
        )

        let leftTickLabels = leftYTickValues.map { formatTick($0, step: leftStep) }
        let rightTickLabels = rightYTickValues.map { formatTick($0, step: rightStep) }

        let leftTickLabelWidth = PlotTextMeasurer.maxTickLabelWidth(
            leftTickLabels, fontSize: style.tickLabelFontSize, fontName: style.fontName
        )
        let rightTickLabelWidth = PlotTextMeasurer.maxTickLabelWidth(
            rightTickLabels, fontSize: style.tickLabelFontSize, fontName: style.fontName
        )

        let tickLen: CGFloat = 6
        let tickGap: CGFloat = 4
        let axisTitleLane = PlotTextMeasurer.measuredLineHeight(
            fontSize: style.axisTitleFontSize, fontName: style.fontName
        )
        let axisTitleGap: CGFloat = 8

        let requiredLeft = max(
            options.paddingLeft,
            axisTitleLane + axisTitleGap + leftTickLabelWidth + tickGap + tickLen
        )
        let requiredRight = max(
            options.paddingRight,
            tickLen + tickGap + rightTickLabelWidth + axisTitleGap + axisTitleLane
        )

        let plotRect = CGRect(
            x: requiredLeft,
            y: CGFloat(options.paddingBottom),
            width: max(0, w - requiredLeft - requiredRight),
            height: max(0, h - CGFloat(options.paddingTop) - CGFloat(options.paddingBottom))
        )

        let xRange = xMax - xMin
        let leftRange = leftYMax - leftYMin
        let rightRange = rightYMax - rightYMin

        let xTicks: [PlotAxisTick] = xTickValues.map { v in
            let cgX = xRange > 0
                ? plotRect.minX + CGFloat((v - xMin) / xRange) * plotRect.width
                : plotRect.midX
            let label = formatTick(v, step: xStep)
            return PlotAxisTick(
                value: v,
                label: label,
                tickPoint: CGPoint(x: cgX, y: plotRect.minY),
                labelPoint: CGPoint(x: cgX, y: plotRect.minY - tickLen - tickGap)
            )
        }

        let leftYTicks: [PlotAxisTick] = leftYTickValues.map { v in
            let cgY = leftRange > 0
                ? plotRect.minY + CGFloat((v - leftYMin) / leftRange) * plotRect.height
                : plotRect.midY
            let label = formatTick(v, step: leftStep)
            return PlotAxisTick(
                value: v,
                label: label,
                tickPoint: CGPoint(x: plotRect.minX, y: cgY),
                labelPoint: CGPoint(x: plotRect.minX - tickLen - tickGap, y: cgY)
            )
        }

        let rightYTicks: [PlotAxisTick] = rightYTickValues.map { v in
            let cgY = rightRange > 0
                ? plotRect.minY + CGFloat((v - rightYMin) / rightRange) * plotRect.height
                : plotRect.midY
            let label = formatTick(v, step: rightStep)
            return PlotAxisTick(
                value: v,
                label: label,
                tickPoint: CGPoint(x: plotRect.maxX, y: cgY),
                labelPoint: CGPoint(x: plotRect.maxX + tickLen + tickGap, y: cgY)
            )
        }

        let titleCenter = CGPoint(x: plotRect.midX, y: h - CGFloat(options.paddingTop) * 0.45)
        let xLabelCenter = CGPoint(x: plotRect.midX, y: CGFloat(options.paddingBottom) * 0.35)
        let leftYLabelCenter = CGPoint(x: axisTitleLane * 0.5 + 4, y: plotRect.midY)
        let rightYLabelCenter = CGPoint(x: w - axisTitleLane * 0.5 - 4, y: plotRect.midY)

        return DualAxisPlotLayout(
            rendererSize: CGSize(width: w, height: h),
            plotRect: plotRect,
            titleCenter: titleCenter,
            xLabelCenter: xLabelCenter,
            leftYLabelCenter: leftYLabelCenter,
            rightYLabelCenter: rightYLabelCenter,
            axisXMin: xMin,
            axisXMax: xMax,
            axisLeftYMin: leftYMin,
            axisLeftYMax: leftYMax,
            axisRightYMin: rightYMin,
            axisRightYMax: rightYMax,
            xTicks: xTicks,
            leftYTicks: leftYTicks,
            rightYTicks: rightYTicks
        )
    }

    // MARK: - Helpers

    static func dataRange(from values: [Double]) -> (min: Double, max: Double) {
        let finite = values.filter(\.isFinite)
        guard !finite.isEmpty else { return (0, 1) }
        let lo = finite.min()!
        let hi = finite.max()!
        guard hi > lo else { return (lo - 1, lo + 1) }
        return (lo, hi)
    }

    static func applyRangeOverride(
        auto: (min: Double, max: Double),
        manualMin: Double?,
        manualMax: Double?
    ) -> (min: Double, max: Double) {
        let lo = manualMin?.isFinite == true ? manualMin! : auto.min
        let hi = manualMax?.isFinite == true ? manualMax! : auto.max
        guard hi > lo else { return auto }
        return (lo, hi)
    }

    static func formatTick(_ value: Double, step: Double) -> String {
        if abs(value) < 1e-15 { return "0" }
        if step == 0 { return String(format: "%.3g", value) }
        if step >= 1e4 || (step > 0 && step < 0.01) {
            return String(format: "%.2g", value)
        } else if step >= 100 { return String(format: "%.0f", value) }
        else if step >= 10    { return String(format: "%.1f", value) }
        else if step >= 1     { return String(format: "%.0f", value) }
        else if step >= 0.1   { return String(format: "%.1f", value) }
        else if step >= 0.01  { return String(format: "%.2f", value) }
        else                   { return String(format: "%.2g", value) }
    }
}
