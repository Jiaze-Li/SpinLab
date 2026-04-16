import AppKit
import SwiftUI

/// Latest metric values for this Library sample, displayed in an adaptive 1/2-column
/// grid that mirrors the Numeric Tags layout. Collapses by default.
///
/// - `availableWidth`: the width of the enclosing detail column (used for column count).
struct MeasurementDataSectionView: View {
    let measurementData: WorkbenchMeasurementDataStore?
    let conditionAliasBook: ConditionAliasBook?
    let availableWidth: CGFloat
    var onDeleteMetric: ((String) -> Void)? = nil  // identity key
    @State private var isExpanded = false
    @State private var pendingDeleteKeys: Set<String> = []

    // A range column within a method card.
    private struct RangeColumn: Identifiable {
        var id: String   // range string or "default"
        var range: String
        var entries: [(metric: String, value: String, identityKey: String)]
    }

    // A card grouped by (workflow, method). Contains 1+ range columns.
    private struct MethodCard: Identifiable {
        var id: String
        var method: String       // e.g. "HFE", "" for AHE
        var columns: [RangeColumn]
    }

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

    // Top-level: workflow + device. e.g. "3W · 0deg"
    private struct DeviceGroup: Identifiable {
        var id: String
        var workflowID: String
        var device: String      // "" for workflows without device
        var cards: [MethodCard]

        var displayHeader: String {
            if device.isEmpty { return workflowID.uppercased() }
            return "\(workflowID.uppercased()) · \(device)"
        }
    }

    private var deviceGroups: [DeviceGroup] {
        guard let store = measurementData, !store.latestIndex.isEmpty else { return [] }
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

        // Group: workflowID → device → method → range
        let byWfDevice = Dictionary(grouping: resolved, by: { "\($0.workflowID)|\($0.device)" })
        var groups: [DeviceGroup] = []

        for wfDeviceKey in byWfDevice.keys.sorted() {
            let records = byWfDevice[wfDeviceKey]!
            let wfID = records.first?.workflowID ?? ""
            let device = records.first?.device ?? ""

            let byMethod = Dictionary(grouping: records, by: { $0.method })
            var cards: [MethodCard] = []

            for method in byMethod.keys.sorted() {
                let methodRecords = byMethod[method]!

                // Collect unit legend for header: metric → unit (skip empty units)
                var unitMap: [(metric: String, unit: String)] = []
                var seenMetrics = Set<String>()
                for r in methodRecords.sorted(by: { $0.metric < $1.metric }) {
                    if !r.unit.isEmpty && seenMetrics.insert(r.metric).inserted {
                        let displayMetric = r.metric == "r_squared" ? "r²" : r.metric
                        unitMap.append((metric: displayMetric, unit: r.unit))
                    }
                }

                let byRange = Dictionary(grouping: methodRecords, by: { $0.range })
                var columns: [RangeColumn] = []

                for range in byRange.keys.sorted() {
                    let rangeRecords = byRange[range]!
                    let entries = rangeRecords
                        .sorted(by: { $0.metric < $1.metric })
                        .map { r in
                            // Value only, no unit (unit is in header)
                            let formatted = String(format: "%g", r.value)
                            return (metric: r.metric, value: formatted, identityKey: r.identityKey)
                        }
                    columns.append(RangeColumn(
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

                cards.append(MethodCard(
                    id: "\(wfID)|\(device)|\(method)",
                    method: cardMethod,
                    columns: columns
                ))
            }
            groups.append(DeviceGroup(
                id: wfDeviceKey,
                workflowID: wfID,
                device: device,
                cards: cards
            ))
        }
        return groups
    }

    private var useTwoColumns: Bool { availableWidth >= 320 }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let groups = deviceGroups
            if groups.isEmpty {
                Text("No measurement data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.displayHeader)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            ForEach(group.cards) { card in
                                methodCardView(card)
                            }
                        }
                    }
                }
            }
        } label: {
            Text("Measurement Data")
                .font(AppFontScale.sectionHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
    }

    @ViewBuilder
    private func methodCardView(_ card: MethodCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !card.method.isEmpty {
                Text(card.method)
                    .font(.callout.weight(.semibold))
            }

            if useTwoColumns && card.columns.count >= 2 {
                // Side-by-side: same method, different ranges
                let pairIndices: [Int] = Array(stride(from: 0, to: card.columns.count, by: 2))
                ForEach(pairIndices, id: \.self) { i in
                    let first: RangeColumn = card.columns[i]
                    let second: RangeColumn? = i + 1 < card.columns.count ? card.columns[i + 1] : nil
                    HStack(alignment: .top, spacing: 8) {
                        rangeColumnView(first)
                        if let second {
                            rangeColumnView(second)
                        }
                    }
                }
            } else {
                ForEach(card.columns) { col in
                    rangeColumnView(col)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        .contextMenu { methodCardContextMenu(card) }
    }

    @ViewBuilder
    private func methodCardContextMenu(_ card: MethodCard) -> some View {
        Button("Copy All") {
            let text = card.columns.map { col in
                let header = col.range.isEmpty ? "" : "\(col.range)\n"
                let body = col.entries.map { e in
                    let name = e.metric == "r_squared" ? "r²" : e.metric
                    return "  \(name) = \(e.value)"
                }.joined(separator: "\n")
                return header + body
            }.joined(separator: "\n\n")
            let full = card.method.isEmpty ? text : "\(card.method)\n\(text)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(full, forType: .string)
        }
        if onDeleteMetric != nil {
            Divider()
            ForEach(card.columns) { col in
                let label = [card.method, col.range].filter { !$0.isEmpty }.joined(separator: " ")
                Button("Delete \(label.isEmpty ? "all" : label)", role: .destructive) {
                    for entry in col.entries {
                        onDeleteMetric?(entry.identityKey)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rangeColumnView(_ col: RangeColumn) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !col.range.isEmpty {
                Text(col.range)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
                ForEach(col.entries, id: \.identityKey) { entry in
                    GridRow {
                        Text(entry.metric == "r_squared" ? "r²" : entry.metric)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(entry.value)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Formatting helpers (internal for testing)

/// Formats a metric value + unit for display in `MeasurementDataSectionView`.
/// Appends ` *` when the value was manually overridden.
func measurementValueText(value: Double, unit: String, isOverridden: Bool) -> String {
    let formatted = String(format: "%g", value)
    return isOverridden ? "\(formatted) \(unit) *" : "\(formatted) \(unit)"
}

/// Returns the display label for a condition key, using alias book when available.
/// Falls back to the raw key when `aliasBook` is nil.
func conditionDisplayLabel(key: String, aliasBook: ConditionAliasBook?) -> String {
    aliasBook?.displayLabel(for: key) ?? key
}
