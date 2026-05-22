import SwiftUI

/// Series reordering control for stacked charts.
///
/// Displays the current stack order and commits bottom-to-top per-series keys.
struct WorkbenchSeriesOrderPanel: View {
    let payload: WorkbenchPlotPayload?
    let currentSeriesOrder: [String]?
    let isVisible: Bool
    let onCommit: ([String]) -> Void

    @State private var rows: [SeriesOrderRow] = []
    @State private var lastCommittedSignature: String = ""
    @State private var chipWidths: [String: CGFloat] = [:]

    var body: some View {
        if isVisible {
            GroupBox("Series Order") {
                let displayedRows = Self.presentedRows(from: rows)
                if displayedRows.isEmpty {
                    Text("No reorderable series")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(displayedRows.enumerated()), id: \.element.identityKey) { index, row in
                            seriesChip(row, index: index)
                                .draggable(row.identityKey)
                                .dropDestination(for: String.self) { items, location in
                                    guard let draggedKey = items.first else { return false }
                                    let width = chipWidths[row.identityKey] ?? 0
                                    let normalizedDropLocationX = width > 0 ? location.x / width : 0.5
                                    moveDisplayedRow(withDraggedKey: draggedKey, onto: row.identityKey, dropLocationX: normalizedDropLocationX)
                                    return true
                                } isTargeted: { _ in }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onPreferenceChange(SeriesOrderChipWidthPreferenceKey.self) { widths in
                        chipWidths = widths
                    }
                }
            }
            .task(id: taskSignature) { syncRows() }
        }
    }

    private var payloadSignature: String {
        guard let payload else { return "nil" }
        return payload.series.enumerated().map { index, series in
            "\(ThreeOmegaWorkspaceStore.seriesOrderKey(for: series, index: index)):\(series.label)"
        }.joined(separator: "|")
    }

    /// Payload fingerprint that ignores presentation order but still refreshes on label/identity changes.
    private var payloadIdentitySignature: String {
        guard let payload else { return "nil" }
        return payload.series.enumerated().map { index, series in
            "\(ThreeOmegaWorkspaceStore.seriesOrderKey(for: series, index: index)):\(series.label)"
        }
        .sorted()
        .joined(separator: "|")
    }

    private var taskSignature: String {
        if let currentSeriesOrder, !currentSeriesOrder.isEmpty {
            return "order:\(currentSeriesOrder.joined(separator: "|"))||\(payloadIdentitySignature)"
        }
        return "payload:\(payloadSignature)"
    }

    private func seriesChip(_ row: SeriesOrderRow, index: Int) -> some View {
        HStack(spacing: 6) {
            Text(row.label)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120, alignment: .leading)
                .accessibilityIdentifier("series-order-row-\(row.identityKey)")

            Button {
                moveDisplayedRow(from: index, to: index - 1)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .disabled(index == 0)

            Button {
                moveDisplayedRow(from: index, to: index + 1)
            } label: {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .disabled(index == Self.presentedRows(from: rows).count - 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SeriesOrderChipWidthPreferenceKey.self, value: [row.identityKey: proxy.size.width])
            }
        )
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func syncRows() {
        rows = Self.makeRows(payload: payload, currentSeriesOrder: currentSeriesOrder)
        if payload?.seriesReorderable == true {
            assert(rows.allSatisfy { ($0.sourceRef?.isEmpty == false) },
                   "reorderable series rows must carry sourceRef keys")
        }
        lastCommittedSignature = rows.map(\.identityKey).joined(separator: "|")
    }

    private func moveDisplayedRow(from source: Int, to proposedDestination: Int) {
        let displayedRows = Self.presentedRows(from: rows)
        guard displayedRows.indices.contains(source) else { return }
        let destination = max(0, min(proposedDestination, displayedRows.count - 1))
        guard source != destination else { return }
        var updated = displayedRows
        let row = updated.remove(at: source)
        updated.insert(row, at: destination)
        rows = Self.internalRows(fromPresentedRows: updated)
        commitCurrentRows()
    }

    private func moveDisplayedRow(withDraggedKey draggedKey: String, onto targetKey: String, dropLocationX: CGFloat) {
        let displayedRows = Self.presentedRows(from: rows)
        guard let sourceIndex = displayedRows.firstIndex(where: { $0.identityKey == draggedKey }),
              let targetIndex = displayedRows.firstIndex(where: { $0.identityKey == targetKey }) else {
            return
        }
        guard sourceIndex != targetIndex else {
            let updated = Self.reorderedRows(displayedRows, draggedKey: draggedKey, targetKey: targetKey, dropLocationX: dropLocationX)
            guard updated != displayedRows else { return }
            rows = Self.internalRows(fromPresentedRows: updated)
            commitCurrentRows()
            return
        }
        let updated = Self.reorderedRows(displayedRows, draggedKey: draggedKey, targetKey: targetKey, dropLocationX: dropLocationX)
        guard updated != displayedRows else { return }
        rows = Self.internalRows(fromPresentedRows: updated)
        commitCurrentRows()
    }

    private func commitCurrentRows() {
        if payload?.seriesReorderable == true {
            assert(rows.allSatisfy { ($0.sourceRef?.isEmpty == false) },
                   "series reorder commits must use sourceRef keys")
        }
        let order = rows.map(\.identityKey)
        let signature = order.joined(separator: "|")
        guard signature != lastCommittedSignature else { return }
        lastCommittedSignature = signature
        onCommit(order)
    }

    static func reorderedRows(
        _ rows: [SeriesOrderRow],
        draggedKey: String,
        targetKey: String,
        dropLocationX: CGFloat
    ) -> [SeriesOrderRow] {
        guard let sourceIndex = rows.firstIndex(where: { $0.identityKey == draggedKey }),
              let targetIndex = rows.firstIndex(where: { $0.identityKey == targetKey }),
              sourceIndex != targetIndex else {
            return rows
        }

        var updated = rows
        let dragged = updated.remove(at: sourceIndex)
        let dropAfter = dropLocationX >= 0.5
        var insertionIndex = targetIndex + (dropAfter ? 1 : 0)
        if sourceIndex < insertionIndex { insertionIndex -= 1 }
        insertionIndex = max(0, min(insertionIndex, updated.count))
        updated.insert(dragged, at: insertionIndex)
        return updated
    }

    static func presentedRows(from rows: [SeriesOrderRow]) -> [SeriesOrderRow] {
        Array(rows.reversed())
    }

    static func internalRows(fromPresentedRows rows: [SeriesOrderRow]) -> [SeriesOrderRow] {
        Array(rows.reversed())
    }

    static func makeRows(payload: WorkbenchPlotPayload?, currentSeriesOrder: [String]?) -> [SeriesOrderRow] {
        guard let payload else { return [] }
        let rows = payload.series.enumerated().map { index, series in
            SeriesOrderRow(
                identityKey: ThreeOmegaWorkspaceStore.seriesOrderKey(for: series, index: index),
                sampleID: series.sampleID,
                sourceRef: series.sourceRef,
                label: series.label,
                originalIndex: index
            )
        }
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.identityKey, $0) })
        let defaultOrder = rows.reversed().map(\.identityKey)
        let baseOrder = resolveOrderKeys(currentSeriesOrder, rows: rows, defaultOrder: defaultOrder)
        return baseOrder.compactMap { lookup[$0] }
    }

    private static func resolveOrderKeys(
        _ currentSeriesOrder: [String]?,
        rows: [SeriesOrderRow],
        defaultOrder: [String]
    ) -> [String] {
        guard let currentSeriesOrder, !currentSeriesOrder.isEmpty else { return defaultOrder }

        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.identityKey, $0) })
        let sampleIDLookup = Dictionary(grouping: rows, by: { $0.sampleID ?? "" })
        var orderedKeys: [String] = []
        var consumed = Set<String>()

        func append(_ key: String) {
            guard consumed.insert(key).inserted else { return }
            orderedKeys.append(key)
        }

        for token in currentSeriesOrder {
            if lookup[token] != nil {
                append(token)
                continue
            }
            // Legacy migration only: old persisted orders may still use sampleID tokens.
            if let matches = sampleIDLookup[token], !matches.isEmpty {
                for row in matches.sorted(by: { $0.originalIndex < $1.originalIndex }) {
                    append(row.identityKey)
                }
            }
        }

        for key in defaultOrder where !consumed.contains(key) {
            append(key)
        }
        return orderedKeys
    }
}

private struct SeriesOrderChipWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SeriesOrderRow: Identifiable, Hashable, Sendable {
    var identityKey: String
    var sampleID: String?
    var sourceRef: String?
    var label: String
    var originalIndex: Int

    var id: String { identityKey }
}
