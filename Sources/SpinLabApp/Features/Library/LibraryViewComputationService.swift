import AppKit
import Foundation

struct LibrarySearchFilters {
    var batchText: String
    var substrateText: String
    var keywordText: String
    var thickness: Double?
    var oxygen: Double?
    var temperature: Double?
    var energy: Double?
    var thicknessTolerance: Double?
    var oxygenTolerance: Double?
    var temperatureTolerance: Double?
    var energyTolerance: Double?
}

struct LibraryViewComputationService {
    func displayValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : "∅"
    }

    func isLongField(_ value: String) -> Bool {
        if value.count > 68 {
            return true
        }
        let markers = ["/", "\\", "\n", "\t"]
        return markers.contains { value.contains($0) } && value.count > 34
    }

    func orderedNumericTagKeys(for sample: LibrarySample) -> [String] {
        let preferred = ["厚度", "氧压", "温度", "能量", "电压", "磁场", "电阻"]
        var keys: [String] = []
        for key in preferred where sample.numericDisplay[key] != nil {
            keys.append(key)
        }
        for key in sample.numericDisplay.keys where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    func makeDetailSections(for sample: LibrarySample) -> SampleDetailSections {
        let sampleFields: [DetailField] = [
            DetailField(label: "Sample", value: sample.displayName, fullWidth: isLongField(sample.displayName)),
            DetailField(label: "Batch", value: sample.batchId),
            DetailField(label: "Sample Key", value: sample.id, monospaced: true, fullWidth: true),
            DetailField(label: "Substrate", value: sample.substrateDisplay)
        ]
        let substrateFields: [DetailField] = sample.substrateTags.isEmpty
            ? []
            : [DetailField(label: "Substrate Tags", value: sample.substrateTags.joined(separator: ", "), fullWidth: true)]
        let numericFields: [DetailField] = orderedNumericTagKeys(for: sample).map { key in
            DetailField(label: key, value: sample.numericDisplay[key] ?? "")
        }
        let metadataFields: [DetailField] = sample.orderedMetadata.map { item in
            DetailField(label: item.key, value: item.value, fullWidth: isLongField(item.value))
        }
        return SampleDetailSections(
            sampleFields: sampleFields,
            substrateFields: substrateFields,
            numericFields: numericFields,
            metadataFields: metadataFields
        )
    }

    func groupedFields(_ fields: [DetailField]) -> [[DetailField]] {
        var rows: [[DetailField]] = []
        var pending: DetailField?
        for field in fields {
            if field.fullWidth {
                if let pendingField = pending {
                    rows.append([pendingField])
                    pending = nil
                }
                rows.append([field])
                continue
            }
            if let pendingField = pending {
                rows.append([pendingField, field])
                pending = nil
            } else {
                pending = field
            }
        }
        if let pendingField = pending {
            rows.append([pendingField])
        }
        return rows
    }

    func alignedFirstColumnWidth(fields: [DetailField], availableWidth: CGFloat) -> CGFloat? {
        let rows = groupedFields(fields)
        return sectionFirstColumnWidth(rows: rows, availableWidth: availableWidth)
    }

    func sectionFirstColumnWidth(rows: [[DetailField]], availableWidth: CGFloat) -> CGFloat? {
        twoColumnWidths(rows: rows, availableWidth: availableWidth)?.first
    }

    func adaptiveDetailSectionSpacing(for height: CGFloat) -> CGFloat {
        let base: CGFloat = 12
        let extraHeight = max(height - 720, 0)
        return min(base + extraHeight / 28, 26)
    }

    func selectedChangeHighlights(
        for sample: LibrarySample,
        sampleSyncChangesByID: [String: [LibraryFieldChange]],
        batchSyncChangesByID: [String: [LibraryFieldChange]]
    ) -> [ChangeHighlight] {
        let sampleChanges = sampleSyncChangesByID[sample.id] ?? []
        let batchChanges = batchSyncChangesByID[sample.batchId] ?? []
        let sampleHighlights = sampleChanges.map {
            ChangeHighlight(key: $0.key, description: "\(displayValue($0.oldValue)) -> \(displayValue($0.newValue))")
        }
        let batchHighlights = batchChanges.map {
            ChangeHighlight(key: "Batch.\($0.key)", description: "\(displayValue($0.oldValue)) -> \(displayValue($0.newValue))")
        }
        return sampleHighlights + batchHighlights
    }

    func matchesSearch(sample: LibrarySample, filters: LibrarySearchFilters) -> Bool {
        let batchText = filters.batchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let substrateText = filters.substrateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywordText = filters.keywordText.trimmingCharacters(in: .whitespacesAndNewlines)

        if !batchText.isEmpty,
           !sample.batchId.localizedCaseInsensitiveContains(batchText) {
            return false
        }

        if !substrateText.isEmpty {
            let queryTags = normalizedSubstrateQueryTags(from: substrateText)
            let sampleTags = Set(
                ([sample.substrateDisplay] + sample.substrateTags)
                    .map(normalizedSubstrateTag)
                    .filter { !$0.isEmpty }
            )
            let matched = queryTags.contains { sampleTags.contains($0) }
            if !matched {
                return false
            }
        }

        if !keywordText.isEmpty {
            let keywordHaystack = [
                sample.batchId,
                sample.displayName,
                sample.id,
                sample.substrateDisplay,
                sample.substrateRaw,
                sample.substrateTags.joined(separator: " "),
                sample.metadata.values.joined(separator: " ")
            ].joined(separator: " ")
            if !keywordHaystack.localizedCaseInsensitiveContains(keywordText) {
                return false
            }
        }

        if let thickness = filters.thickness,
           !numericMatches(sample.numericTags["厚度"], expected: thickness, tolerance: filters.thicknessTolerance) {
            return false
        }

        if let oxygen = filters.oxygen,
           !numericMatches(sample.numericTags["氧压"], expected: oxygen, tolerance: filters.oxygenTolerance) {
            return false
        }

        if let temperature = filters.temperature,
           !numericMatches(sample.numericTags["温度"], expected: temperature, tolerance: filters.temperatureTolerance) {
            return false
        }

        if let energy = filters.energy,
           !numericMatches(sample.numericTags["能量"], expected: energy, tolerance: filters.energyTolerance) {
            return false
        }

        return true
    }

    /// Floor width for a single metadata column: enough for a wrapped label/value
    /// pair to stay readable (values wrap rather than truncate — see
    /// `WrappingValueText`), tuned against real Library metadata content.
    static let metadataColumnMinWidth: CGFloat = 200
    static let metadataColumnSpacing: CGFloat = 12

    /// The pure width threshold for entering 2-column mode. Column count is a
    /// direct function of available width — never of measured content — so it
    /// doesn't collapse just because one row happens to hold a long value.
    static var twoColumnRequiredWidth: CGFloat {
        2 * metadataColumnMinWidth + metadataColumnSpacing
    }

    private func twoColumnWidths(rows: [[DetailField]], availableWidth: CGFloat) -> (first: CGFloat, second: CGFloat)? {
        let spacing = Self.metadataColumnSpacing
        let minColumnWidth = Self.metadataColumnMinWidth
        let firstColumnMaxWidth: CGFloat = 420

        let pairRows = rows.filter { $0.count == 2 }
        guard !pairRows.isEmpty else {
            return nil
        }
        guard availableWidth >= Self.twoColumnRequiredWidth else {
            return nil
        }

        let redundancyInChars: CGFloat = 5
        let averageCharWidth = estimatedTextWidth("MMMMM", font: .systemFont(ofSize: NSFont.systemFontSize)) / 5
        let redundancyWidth = max(averageCharWidth * redundancyInChars, 24)

        let firstContentNeeded = pairRows
            .map { estimatedFieldWidth($0[0]) }
            .max() ?? minColumnWidth
        let secondContentNeeded = pairRows
            .map { estimatedFieldWidth($0[1]) }
            .max() ?? minColumnWidth

        let firstPreferred = max(firstContentNeeded + redundancyWidth, minColumnWidth)
        let secondPreferred = max(secondContentNeeded + redundancyWidth, minColumnWidth)
        let preferredTotal = firstPreferred + secondPreferred + spacing

        var first: CGFloat
        var second: CGFloat

        if availableWidth >= preferredTotal {
            let extra = availableWidth - preferredTotal
            first = firstPreferred + extra / 2
            second = secondPreferred + extra / 2

            if first > firstColumnMaxWidth {
                let overflow = first - firstColumnMaxWidth
                first = firstColumnMaxWidth
                second += overflow
            }
        } else {
            // Not enough room to fully satisfy content preferences, but still
            // above the semantic 2-column floor: split proportionally instead
            // of falling back to 1 column.
            let usable = availableWidth - spacing
            let ratio = firstPreferred / preferredTotal
            first = max(usable * ratio, minColumnWidth)
            second = usable - first
        }

        if second < minColumnWidth {
            let needed = minColumnWidth - second
            first -= needed
            second = minColumnWidth
        }

        let maxFirstGivenAvailable = availableWidth - minColumnWidth - spacing
        first = min(first, maxFirstGivenAvailable)
        second = availableWidth - first - spacing
        guard first >= minColumnWidth, second >= minColumnWidth else {
            return nil
        }
        return (first: first, second: second)
    }

    private func estimatedFieldWidth(_ field: DetailField) -> CGFloat {
        let labelWidth = estimatedTextWidth(field.label, font: .systemFont(ofSize: NSFont.smallSystemFontSize))
        let valueFont: NSFont = field.monospaced
            ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
        let valueWidth = estimatedTextWidth(field.value, font: valueFont)
        let clampedValueWidth = min(max(valueWidth, 80), 360)
        return max(labelWidth, clampedValueWidth)
    }

    private func estimatedTextWidth(_ text: String, font: NSFont) -> CGFloat {
        let sample = text.isEmpty ? " " : text
        let singleLine = sample
            .split(separator: "\n")
            .map(String.init)
            .max(by: { $0.count < $1.count }) ?? sample
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil((singleLine as NSString).size(withAttributes: attributes).width)
    }

    private func numericMatches(_ source: Double?, expected: Double, tolerance: Double?) -> Bool {
        guard let source else { return false }
        if let tol = tolerance, tol > 0 {
            return abs(source - expected) <= tol
        }
        return abs(source - expected) < 1e-9
    }

    private func normalizedSubstrateQueryTags(from input: String) -> [String] {
        let normalizedInput = input
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "；", with: ";")
        let parts = normalizedInput
            .split(whereSeparator: { ",;\n".contains($0) })
            .map { normalizedSubstrateTag(String($0)) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            let single = normalizedSubstrateTag(normalizedInput)
            return single.isEmpty ? [] : [single]
        }
        return parts
    }

    private func normalizedSubstrateTag(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        value = value
            .replacingOccurrences(of: " (", with: "(")
            .replacingOccurrences(of: ") ", with: ")")
        value = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return value
    }
}
