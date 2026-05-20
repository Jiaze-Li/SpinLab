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

    private var useTwoColumns: Bool { availableWidth >= 320 }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            let groups = LibraryMeasurementDataPresenter.buildDeviceGroups(from: measurementData)
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
    private func methodCardView(_ card: MeasurementDataMethodCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !card.method.isEmpty {
                Text(card.method)
                    .font(.callout.weight(.semibold))
            }

            if useTwoColumns && card.columns.count >= 2 {
                let pairIndices: [Int] = Array(stride(from: 0, to: card.columns.count, by: 2))
                ForEach(pairIndices, id: \.self) { i in
                    let first: MeasurementDataRangeColumn = card.columns[i]
                    let second: MeasurementDataRangeColumn? = i + 1 < card.columns.count ? card.columns[i + 1] : nil
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
    private func methodCardContextMenu(_ card: MeasurementDataMethodCard) -> some View {
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
    private func rangeColumnView(_ col: MeasurementDataRangeColumn) -> some View {
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
