import Foundation

struct MeasurementDataRangeColumn: Identifiable {
    var id: String   // range string or "default"
    var range: String
    var entries: [(metric: String, value: String, identityKey: String)]
}

struct MeasurementDataMethodCard: Identifiable {
    var id: String
    var method: String
    var columns: [MeasurementDataRangeColumn]
}

struct MeasurementDataDeviceGroup: Identifiable {
    var id: String
    var workflowID: String
    var device: String

    var displayHeader: String {
        device.isEmpty ? workflowID.uppercased() : "\(workflowID.uppercased()) · \(device)"
    }

    var cards: [MeasurementDataMethodCard]
}

enum LibraryMeasurementDataPresenter {
    private struct ResolvedRecord {
        var identityKey: String
        var workflowID: String
        var metric: String
        var value: Double
        var unit: String
        var method: String
        var range: String
        var device: String
    }

    static func buildDeviceGroups(from store: WorkbenchMeasurementDataStore?) -> [MeasurementDataDeviceGroup] {
        guard let store, !store.latestIndex.isEmpty else { return [] }
        let recordsByID = Dictionary(uniqueKeysWithValues: store.records.map { ($0.recordID, $0) })

        var resolved: [ResolvedRecord] = []
        for (key, pointer) in store.latestIndex {
            guard let record = recordsByID[pointer.recordID] else { continue }
            resolved.append(ResolvedRecord(
                identityKey: key,
                workflowID: record.workflowID,
                metric: record.metric,
                value: pointer.value,
                unit: pointer.canonicalUnit,
                method: record.conditions["v3method"] ?? "",
                range: record.conditions["range"] ?? "",
                device: record.conditions["device"] ?? ""
            ))
        }

        let byWfDevice = Dictionary(grouping: resolved, by: { "\($0.workflowID)|\($0.device)" })
        var groups: [MeasurementDataDeviceGroup] = []

        for wfDeviceKey in byWfDevice.keys.sorted() {
            let records = byWfDevice[wfDeviceKey]!
            let wfID = records.first?.workflowID ?? ""
            let device = records.first?.device ?? ""

            let byMethod = Dictionary(grouping: records, by: { $0.method })
            var cards: [MeasurementDataMethodCard] = []

            for method in byMethod.keys.sorted() {
                let methodRecords = byMethod[method]!

                var unitMap: [(metric: String, unit: String)] = []
                var seenMetrics = Set<String>()
                for r in methodRecords.sorted(by: { $0.metric < $1.metric }) {
                    if !r.unit.isEmpty && seenMetrics.insert(r.metric).inserted {
                        let displayMetric = r.metric == "r_squared" ? "r²" : r.metric
                        unitMap.append((metric: displayMetric, unit: r.unit))
                    }
                }

                let byRange = Dictionary(grouping: methodRecords, by: { $0.range })
                var columns: [MeasurementDataRangeColumn] = []

                for range in byRange.keys.sorted() {
                    let rangeRecords = byRange[range]!
                    let entries = rangeRecords
                        .sorted(by: { $0.metric < $1.metric })
                        .map { r in
                            let formatted = String(format: "%g", r.value)
                            return (metric: r.metric, value: formatted, identityKey: r.identityKey)
                        }
                    columns.append(MeasurementDataRangeColumn(
                        id: range.isEmpty ? "default" : range,
                        range: range,
                        entries: entries
                    ))
                }

                var cardMethod = method
                if !unitMap.isEmpty {
                    let unitStr = unitMap.map { "\($0.metric): \($0.unit)" }.joined(separator: ", ")
                    cardMethod = method.isEmpty ? "(\(unitStr))" : "\(method) (\(unitStr))"
                }

                cards.append(MeasurementDataMethodCard(
                    id: "\(wfID)|\(device)|\(method)",
                    method: cardMethod,
                    columns: columns
                ))
            }
            groups.append(MeasurementDataDeviceGroup(
                id: wfDeviceKey,
                workflowID: wfID,
                device: device,
                cards: cards
            ))
        }
        return groups
    }
}
