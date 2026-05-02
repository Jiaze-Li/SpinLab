import Foundation

/// Aligns XY rotation series order across persisted state, selected hits, and legend display.
struct AlignXYSeriesOrderUseCase {

    struct Input {
        let analysisIdentifiers: [String]
        let persistedOrder: [String]?
        let selectedHitIDs: [String]
        let legendReversed: Bool
    }

    struct Output {
        let alignedOrder: [String]
        let legendIndexMap: [String: Int]
    }

    func execute(_ input: Input) -> Output {
        let baseOrder: [String]
        if let aligned = alignSeriesOrder(old: input.persistedOrder, defaultIDs: input.analysisIdentifiers) {
            baseOrder = aligned
        } else {
            baseOrder = input.analysisIdentifiers
        }

        let selectedSet = Set(input.selectedHitIDs)
        let alignedOrder: [String]
        if selectedSet.isEmpty {
            alignedOrder = baseOrder
        } else {
            var selected: [String] = []
            var remaining: [String] = []
            for id in baseOrder {
                if selectedSet.contains(id) {
                    selected.append(id)
                } else {
                    remaining.append(id)
                }
            }
            alignedOrder = selected + remaining
        }

        let n = alignedOrder.count
        var legendIndexMap: [String: Int] = [:]
        for (i, id) in alignedOrder.enumerated() {
            legendIndexMap[id] = input.legendReversed ? (n - 1 - i) : i
        }

        return Output(alignedOrder: alignedOrder, legendIndexMap: legendIndexMap)
    }

    static func applySeriesOrder(_ order: [String]?, to sweeps: [XYRotationAngleSweep]) -> [XYRotationAngleSweep] {
        guard let order, !order.isEmpty else { return sweeps }
        let byID = Dictionary(uniqueKeysWithValues: sweeps.map { ($0.id, $0) })
        var result: [XYRotationAngleSweep] = []
        var consumed = Set<String>()
        for id in order {
            if let s = byID[id] {
                result.append(s)
                consumed.insert(id)
            }
        }
        for s in sweeps where !consumed.contains(s.id) {
            result.append(s)
        }
        return result
    }
}
