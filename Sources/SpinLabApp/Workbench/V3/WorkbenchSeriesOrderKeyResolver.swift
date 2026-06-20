import Foundation

/// Shared identity-key resolver for reorderable Workbench series.
///
/// The resolver is intentionally workflow-agnostic so Plot System code can persist
/// stable order tokens without depending on workflow store helpers.
enum WorkbenchSeriesOrderKeyResolver {
    static func resolve(for series: WorkbenchPlotSeries, originalIndex: Int) -> String {
        if let sourceRef = series.sourceRef, !sourceRef.isEmpty {
            return sourceRef
        }
        if let sampleID = series.sampleID, !sampleID.isEmpty {
            return sampleID
        }
        return String(originalIndex)
    }

    static func resolveOrderKeys(_ currentSeriesOrder: [String]?, series: [WorkbenchPlotSeries]) -> [String] {
        let keyedSeries = series.enumerated().map { index, series in
            (
                key: resolve(for: series, originalIndex: index),
                sampleID: series.sampleID ?? "",
                index: index
            )
        }
        guard let currentSeriesOrder, !currentSeriesOrder.isEmpty else {
            return keyedSeries.map(\.key)
        }

        let byKey = Dictionary(uniqueKeysWithValues: keyedSeries.map { ($0.key, $0.index) })
        let bySampleID = Dictionary(grouping: keyedSeries, by: { $0.sampleID })
        var orderedKeys: [String] = []
        var consumed = Set<Int>()

        func append(index: Int) {
            guard consumed.insert(index).inserted else { return }
            orderedKeys.append(keyedSeries[index].key)
        }

        for token in currentSeriesOrder {
            if let index = byKey[token] {
                append(index: index)
                continue
            }
            // Legacy migration only: old persisted orders may still use sampleID tokens.
            if let matches = bySampleID[token], !matches.isEmpty {
                for match in matches.sorted(by: { $0.index < $1.index }) {
                    append(index: match.index)
                }
            }
        }

        for item in keyedSeries where !consumed.contains(item.index) {
            append(index: item.index)
        }
        return orderedKeys
    }
}
