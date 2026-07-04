import Foundation

enum SeriesStackingPolicy: Hashable, Sendable {
    case none
    case orderEnforcingVertical(multiplier: Double, minGapFraction: Double)
}

struct SeriesVisualPlanningInput: Hashable, Sendable {
    var series: [WorkbenchPlotSeries]
    var visualSeriesOrder: [String]?
    var hiddenSeriesKeys: [String]
    var stackingPolicy: SeriesStackingPolicy
}

struct SeriesVisualPlan: Hashable, Sendable {
    var visualSeries: [WorkbenchPlotSeries]
    var displaySeries: [WorkbenchPlotSeries]
    var warnings: [String]
}

enum SeriesVisualPlanner {
    static func plan(_ input: SeriesVisualPlanningInput) -> SeriesVisualPlan {
        let orderedVisualSeries = orderedSeries(
            input.series,
            visualSeriesOrder: input.visualSeriesOrder
        )
        let hiddenVisibility = filterHiddenStackSeries(
            orderedVisualSeries,
            hiddenSeriesKeys: input.hiddenSeriesKeys
        )

        switch input.stackingPolicy {
        case .none:
            return SeriesVisualPlan(
                visualSeries: orderedVisualSeries,
                displaySeries: hiddenVisibility.ignoredAllHidden ? orderedVisualSeries : hiddenVisibility.series,
                warnings: hiddenVisibility.ignoredAllHidden ? [allHiddenSeriesWarning] : []
            )

        case let .orderEnforcingVertical(multiplier, minGapFraction):
            let visibleTopToBottom = hiddenVisibility.ignoredAllHidden ? orderedVisualSeries : hiddenVisibility.series
            let placementBottomToTop = Array(visibleTopToBottom.reversed())
            let offsets = ThreeOmegaStackOffsetUseCase().execute(
                yValues: placementBottomToTop.map(\.y),
                multiplier: multiplier,
                minGapFraction: minGapFraction,
                placementMode: .orderEnforcingBottomToTop
            )
            let stackedBottomToTop = zip(placementBottomToTop, offsets).map { series, offset in
                guard offset != 0 else { return series }
                var shifted = series
                shifted.y = series.y.map { $0 + offset }
                return shifted
            }

            return SeriesVisualPlan(
                visualSeries: orderedVisualSeries,
                displaySeries: Array(stackedBottomToTop.reversed()),
                warnings: hiddenVisibility.ignoredAllHidden ? [allHiddenSeriesWarning] : []
            )
        }
    }

    private static let allHiddenSeriesWarning = "series visibility ignored: all series were hidden"

    private static func orderedSeries(
        _ series: [WorkbenchPlotSeries],
        visualSeriesOrder: [String]?
    ) -> [WorkbenchPlotSeries] {
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series)
        let orderedKeys = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(visualSeriesOrder, series: series)
        let lookup = Dictionary(uniqueKeysWithValues: zip(identities, series).map { identity, series in
            (identity.identityKey, series)
        })
        return orderedKeys.compactMap { lookup[$0] }
    }
}
