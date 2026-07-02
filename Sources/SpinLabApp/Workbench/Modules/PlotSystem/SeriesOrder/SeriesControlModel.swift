import Foundation

/// Read-only chip/control contract for Plot System series controls.
///
/// The model is intentionally presentation-friendly: it carries the stable
/// identity key, the semantic display label, and the current visibility /
/// reorder affordances without exposing any workflow-specific source inference.
struct SeriesControlItem: Identifiable, Hashable, Sendable {
    var identityKey: String
    var displayLabel: String
    var sourceRef: String?
    var sampleID: String?
    var originalIndex: Int
    var isVisible: Bool
    var canRename: Bool
    var canReorder: Bool
    var canMoveUp: Bool
    var canMoveDown: Bool

    var id: String { identityKey }

    /// Backward-compatible alias for older tests and call sites.
    var label: String {
        get { displayLabel }
        set { displayLabel = newValue }
    }

    init(
        identityKey: String,
        displayLabel: String,
        sourceRef: String? = nil,
        sampleID: String? = nil,
        originalIndex: Int,
        isVisible: Bool = true,
        canRename: Bool = true,
        canReorder: Bool = true,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false
    ) {
        self.identityKey = identityKey
        self.displayLabel = displayLabel
        self.sourceRef = sourceRef
        self.sampleID = sampleID
        self.originalIndex = originalIndex
        self.isVisible = isVisible
        self.canRename = canRename
        self.canReorder = canReorder
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
    }

    init(
        identityKey: String,
        sampleID: String? = nil,
        sourceRef: String? = nil,
        label: String,
        originalIndex: Int,
        displayLabel: String? = nil,
        isVisible: Bool = true,
        canRename: Bool = true,
        canReorder: Bool = true,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false
    ) {
        self.init(
            identityKey: identityKey,
            displayLabel: displayLabel ?? label,
            sourceRef: sourceRef,
            sampleID: sampleID,
            originalIndex: originalIndex,
            isVisible: isVisible,
            canRename: canRename,
            canReorder: canReorder,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown
        )
    }
}

struct SeriesControlModel: Hashable, Sendable {
    var items: [SeriesControlItem]

    init(items: [SeriesControlItem]) {
        self.items = items
    }

    var signature: String {
        items.map { item in
            [
                item.identityKey,
                item.displayLabel,
                item.sourceRef ?? "",
                item.sampleID ?? "",
                String(item.originalIndex),
                item.isVisible ? "1" : "0",
                item.canRename ? "1" : "0",
                item.canReorder ? "1" : "0",
                item.canMoveUp ? "1" : "0",
                item.canMoveDown ? "1" : "0"
            ].joined(separator: ":")
        }
        .joined(separator: "|")
    }

    var displayLabels: [String] {
        items.map(\.displayLabel)
    }

    static func fromPayload(
        _ payload: WorkbenchPlotPayload,
        currentSeriesOrder: [String]? = nil,
        hiddenSeriesKeys: [String] = [],
        displayLabelResolver: ((WorkbenchPlotSeries, WorkbenchSeriesIdentity) -> String)? = nil
    ) -> SeriesControlModel {
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
        let orderedKeys = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(currentSeriesOrder, series: payload.series)
        let hidden = Set(hiddenSeriesKeys)
        let identityLookup = Dictionary(uniqueKeysWithValues: zip(identities, payload.series).map { identity, series in
            (identity.identityKey, (identity, series))
        })

        let orderedItems = orderedKeys.compactMap { key -> SeriesControlItem? in
            guard let (identity, series) = identityLookup[key] else { return nil }
            let rawLabel = displayLabelResolver?(series, identity) ?? inferredDisplayLabel(for: payload, series: series)
            return SeriesControlItem(
                identityKey: identity.identityKey,
                displayLabel: rawLabel,
                sourceRef: identity.sourceRef,
                sampleID: identity.sampleID,
                originalIndex: identity.originalIndex,
                isVisible: !hidden.contains(identity.identityKey),
                canRename: true,
                canReorder: payload.seriesReorderable,
                canMoveUp: false,
                canMoveDown: false
            )
        }

        return SeriesControlModel(items: orderedItems.enumerated().map { index, item in
            var copy = item
            copy.canMoveUp = index > 0
            copy.canMoveDown = index < orderedItems.count - 1
            return copy
        })
    }

    private static func inferredDisplayLabel(for payload: WorkbenchPlotPayload, series: WorkbenchPlotSeries) -> String {
        let semanticLabel = semanticLabelCandidate(for: payload, series: series)
        return semanticLabel ?? series.label
    }

    private static func semanticLabelCandidate(for payload: WorkbenchPlotPayload, series: WorkbenchPlotSeries) -> String? {
        let semanticValues = payload.series.compactMap { candidateSeries in
            [
                candidateSeries.metadata["device"],
                candidateSeries.metadata["angle"],
                candidateSeries.metadata["temperature"]
            ]
            .compactMap { normalizedLabelComponent($0) }
            .first
        }
        guard semanticValues.count == payload.series.count else { return nil }
        let semanticSet = Set(semanticValues)
        let labelSet = Set(payload.series.map(\.label))
        guard semanticSet.count > 1, semanticSet != labelSet else { return nil }

        let candidates = [
            series.metadata["device"],
            series.metadata["angle"],
            series.metadata["temperature"]
        ].compactMap { normalizedLabelComponent($0) }
        return candidates.first
    }

    private static func normalizedLabelComponent(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
