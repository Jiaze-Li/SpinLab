import SwiftUI

/// Generic series control strip for PlotSystem tabs.
///
/// Displays visibility, rename, and reorder controls for each series.
struct WorkbenchSeriesOrderPanel: View {
    let payload: WorkbenchPlotPayload?
    let currentSeriesOrder: [String]?
    let hiddenSeriesKeys: [String]
    let isVisible: Bool
    let onCommit: ([String]) -> Void
    /// When false, rename and visibility controls remain but drag and arrow reorder UI is hidden.
    var allowsReordering: Bool = true
    /// Current series label overrides keyed by stable series identity.
    var seriesLabelOverrides: [String: String] = [:]
    /// Called with (identityKey, isVisible) when the user toggles series visibility.
    var onVisibilityChange: ((String, Bool) -> Void)? = nil
    /// Called with (identityKey, newLabel) when the user renames a series chip.
    var onRenameLabel: ((String, String) -> Void)? = nil

    @State private var rows: [SeriesOrderRow] = []
    @State private var lastCommittedSignature: String = ""
    @State private var chipWidths: [String: CGFloat] = [:]
    @State private var editingChipKey: String? = nil
    @State private var editChipText: String = ""
    @FocusState private var chipEditorFocused: Bool
    @State private var dragTargetKey: String? = nil
    @State private var dropIsRight: Bool = false

    var body: some View {
        if isVisible {
            let displayedRows = Self.presentedRows(from: rows)
            let visibleCount = displayedRows.filter(\.isVisible).count
            VStack(alignment: .leading, spacing: 0) {
                if displayedRows.isEmpty {
                    Text("No series")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(displayedRows.enumerated()), id: \.element.identityKey) { index, row in
                            let chip = seriesChip(
                                row,
                                index: index,
                                rowCount: displayedRows.count,
                                visibleCount: visibleCount,
                                showsReorderControls: allowsReordering
                            )
                            if allowsReordering {
                                chip
                                    .draggable(row.identityKey)
                                    .dropDestination(for: String.self) { items, location in
                                        guard let draggedKey = items.first else { return false }
                                        let width = chipWidths[row.identityKey] ?? 0
                                        let normalizedDropLocationX = width > 0 ? location.x / width : 0.5
                                        moveDisplayedRow(withDraggedKey: draggedKey, onto: row.identityKey, dropLocationX: normalizedDropLocationX)
                                        return true
                                    } isTargeted: { isOver in
                                        if isOver {
                                            dragTargetKey = row.identityKey
                                        } else if dragTargetKey == row.identityKey {
                                            dragTargetKey = nil
                                        }
                                    }
                                    .onContinuousHover { phase in
                                        if case .active(let location) = phase {
                                            let width = chipWidths[row.identityKey] ?? 100
                                            dropIsRight = width > 0 ? location.x / width >= 0.5 : false
                                        }
                                    }
                            } else {
                                chip
                            }
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
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
        return zip(identities, payload.series).map { identity, series in
            "\(identity.identityKey):\(series.label)"
        }.joined(separator: "|")
    }

    /// Payload fingerprint that ignores presentation order but still refreshes on label/identity changes.
    private var payloadIdentitySignature: String {
        guard let payload else { return "nil" }
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
        return zip(identities, payload.series).map { identity, series in
            "\(identity.identityKey):\(series.label)"
        }
        .sorted()
        .joined(separator: "|")
    }

    private var taskSignature: String {
        let hiddenSignature = hiddenSeriesKeys.sorted().joined(separator: "|")
        if let currentSeriesOrder, !currentSeriesOrder.isEmpty {
            return "order:\(currentSeriesOrder.joined(separator: "|"))||hidden:\(hiddenSignature)||\(payloadIdentitySignature)"
        }
        return "payload:\(payloadSignature)||hidden:\(hiddenSignature)"
    }

    private func seriesChip(_ row: SeriesOrderRow, index: Int, rowCount: Int, visibleCount: Int, showsReorderControls: Bool) -> some View {
        let displayLabel = seriesLabelOverrides[row.identityKey] ?? row.displayLabel
        let isEditing = editingChipKey == row.identityKey
        let canHide = !row.isVisible || visibleCount > 1
        let canMoveUp = index > 0
        let canMoveDown = index < rowCount - 1

        return HStack(spacing: 6) {
            Button {
                toggleVisibility(row: row)
            } label: {
                Image(systemName: row.isVisible ? "checkmark.square" : "square")
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .controlSize(.mini)
            .disabled(!canHide || onVisibilityChange == nil)

            if isEditing {
                TextField("", text: $editChipText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(minWidth: 60, maxWidth: 140)
                    .focused($chipEditorFocused)
                    .onSubmit { commitChipRename(row: row) }
                Button("OK") { commitChipRename(row: row) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                Button("Cancel") { editingChipKey = nil }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            } else {
                Text(displayLabel)
                    .font(.system(size: 12))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120, alignment: .leading)
                    .accessibilityIdentifier("series-order-row-\(row.identityKey)")

                if row.canRename, onRenameLabel != nil {
                    Button {
                        editChipText = displayLabel
                        editingChipKey = row.identityKey
                        chipEditorFocused = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12, weight: .regular))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                }

                if showsReorderControls {
                    Button {
                        moveDisplayedRow(from: index, to: index - 1)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .disabled(!canMoveUp)

                    Button {
                        moveDisplayedRow(from: index, to: index + 1)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .disabled(!canMoveDown)
                }
            }
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
        .overlay(alignment: dropIsRight ? .trailing : .leading) {
            if dragTargetKey == row.identityKey {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .clipShape(Capsule(style: .continuous))
            }
        }
    }

    private func toggleVisibility(row: SeriesOrderRow) {
        guard let onVisibilityChange else { return }
        if row.isVisible {
            let visibleCount = rows.filter(\.isVisible).count
            guard visibleCount > 1 else { return }
        }
        onVisibilityChange(row.identityKey, !row.isVisible)
    }

    private func commitChipRename(row: SeriesOrderRow) {
        let trimmed = editChipText.trimmingCharacters(in: .whitespacesAndNewlines)
        onRenameLabel?(row.identityKey, trimmed)
        editingChipKey = nil
        editChipText = ""
        chipEditorFocused = false
    }

    private func syncRows() {
        rows = Self.makeRows(payload: payload, currentSeriesOrder: currentSeriesOrder, hiddenSeriesKeys: hiddenSeriesKeys)
        if payload?.seriesReorderable == true {
            assert(Set(rows.map(\.identityKey)).count == rows.count,
                   "reorderable series rows must have unique identity keys")
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

    static func makeRows(
        payload: WorkbenchPlotPayload?,
        currentSeriesOrder: [String]?,
        hiddenSeriesKeys: [String] = []
    ) -> [SeriesOrderRow] {
        guard let payload else { return [] }
        let identities = WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: payload.series)
        let hidden = Set(hiddenSeriesKeys)
        let rows = zip(identities, payload.series).map { identity, series in
            SeriesOrderRow(
                identityKey: identity.identityKey,
                sampleID: identity.sampleID,
                sourceRef: identity.sourceRef,
                label: series.label,
                originalIndex: identity.originalIndex,
                displayLabel: series.label,
                isVisible: !hidden.contains(identity.identityKey),
                canRename: true,
                canMoveUp: false,
                canMoveDown: false
            )
        }
        let lookup = Dictionary(uniqueKeysWithValues: rows.map { ($0.identityKey, $0) })
        let baseOrder = WorkbenchSeriesOrderKeyResolver.resolveOrderKeys(currentSeriesOrder, series: payload.series)
        let ordered = baseOrder.compactMap { lookup[$0] }
        return ordered.enumerated().map { index, item in
            var copy = item
            copy.canMoveUp = index > 0
            copy.canMoveDown = index < ordered.count - 1
            return copy
        }
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
    var displayLabel: String
    var isVisible: Bool
    var canRename: Bool
    var canMoveUp: Bool
    var canMoveDown: Bool

    var id: String { identityKey }

    init(
        identityKey: String,
        sampleID: String? = nil,
        sourceRef: String? = nil,
        label: String,
        originalIndex: Int,
        displayLabel: String? = nil,
        isVisible: Bool = true,
        canRename: Bool = true,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false
    ) {
        self.identityKey = identityKey
        self.sampleID = sampleID
        self.sourceRef = sourceRef
        self.label = label
        self.originalIndex = originalIndex
        self.displayLabel = displayLabel ?? label
        self.isVisible = isVisible
        self.canRename = canRename
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
    }
}

typealias SeriesControlItem = SeriesOrderRow
