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
    var displayOffsetsByIdentityKey: [String: Double]
    var warnings: [String]
}

/// Thread-safe last-input/plan cache — `plan(_:)` is called from both the
/// main actor (live workspace stores) and nonisolated contexts (manifest cache helpers).
private final class SeriesVisualPlanCache: @unchecked Sendable {
    private let lock = NSLock()
    private var lastInput: SeriesVisualPlanningInput?
    private var lastPlan: SeriesVisualPlan?

    func plan(for input: SeriesVisualPlanningInput, compute: () -> SeriesVisualPlan) -> SeriesVisualPlan {
        lock.lock()
        defer { lock.unlock() }
        if let lastInput, lastInput == input, let lastPlan {
            print("[PERF][planner] cache hit")
            return lastPlan
        }
        print("[PERF][planner] cache miss")
        let plan = compute()
        lastInput = input
        lastPlan = plan
        return plan
    }
}

enum SeriesVisualPlanner {
    private static let cache = SeriesVisualPlanCache()

    static func plan(_ input: SeriesVisualPlanningInput) -> SeriesVisualPlan {
        cache.plan(for: input) { _plan(input) }
    }

    private static func _plan(_ input: SeriesVisualPlanningInput) -> SeriesVisualPlan {
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
                displayOffsetsByIdentityKey: Dictionary(uniqueKeysWithValues: WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: hiddenVisibility.ignoredAllHidden ? orderedVisualSeries : hiddenVisibility.series).map { ($0.identityKey, 0.0) }),
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

            let visibleIdentityKeys = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: visibleTopToBottom).map(\.identityKey)
            let displayOffsets = Dictionary(uniqueKeysWithValues: zip(visibleIdentityKeys, offsets.reversed()).map { ($0, $1) })

            return SeriesVisualPlan(
                visualSeries: orderedVisualSeries,
                displaySeries: Array(stackedBottomToTop.reversed()),
                displayOffsetsByIdentityKey: displayOffsets,
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
