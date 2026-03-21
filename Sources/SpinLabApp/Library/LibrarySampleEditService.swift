import Foundation

final class LibrarySampleEditService {
    enum EditError: LocalizedError {
        case missingSample
        case invalidNumericValue(key: String, value: String)

        var errorDescription: String? {
            switch self {
            case .missingSample:
                return "No sample selected for editing."
            case let .invalidNumericValue(key, value):
                return "Numeric tag \(key) has invalid value: \(value)."
            }
        }
    }

    func makeDraft(from sample: LibrarySample) -> LibrarySampleEditDraft {
        let substrateTagsText = sample.substrateTags.joined(separator: ", ")

        let numericValues = sample.numericDisplay
            .keys
            .sorted()
            .map { key in
                let rawValue = sample.numericDisplay[key] ?? ""
                let parts = numericValueAndUnit(from: rawValue)
                return LibraryEditableNumericValue(
                    key: key,
                    value: parts.value,
                    unit: parts.unit
                )
            }

        var metadataValues = sample.orderedMetadata.map {
            LibraryEditableKeyValue(key: $0.key, value: $0.value)
        }
        let existingMetadataKeys = Set(metadataValues.map(\.key))
        let additionalMetadataKeys = sample.metadata.keys
            .filter { !existingMetadataKeys.contains($0) }
            .sorted()
        metadataValues.append(contentsOf: additionalMetadataKeys.map {
            LibraryEditableKeyValue(key: $0, value: sample.metadata[$0] ?? "")
        })

        return LibrarySampleEditDraft(
            sampleId: sample.id,
            batchId: sample.batchId,
            baseUpdatedAt: sample.updatedAt,
            substrateTagsText: substrateTagsText,
            numericValues: numericValues,
            metadataValues: metadataValues
        )
    }

    func isDirty(draft: LibrarySampleEditDraft, base sample: LibrarySample) -> Bool {
        guard draft.sampleId == sample.id else {
            return false
        }
        do {
            let candidate = try apply(draft: draft, to: sample, at: sample.updatedAt)
            return candidate != sample
        } catch {
            // Keep Save enabled on invalid numeric input so user can correct then retry.
            return true
        }
    }

    func apply(draft: LibrarySampleEditDraft, to base: LibrarySample, at timestamp: Date = .now) throws -> LibrarySample {
        guard draft.sampleId == base.id else {
            throw EditError.missingSample
        }

        var updated = base
        updated.substrateTags = normalizedTokens(from: draft.substrateTagsText)
        updated.substrateTokens = normalizedSearchTokens(from: updated.substrateTags)

        let numeric = try normalizedNumeric(from: draft.numericValues)
        updated.numericDisplay = numeric.display
        updated.numericTags = numeric.values

        let metadata = normalizedMetadata(from: draft.metadataValues)
        updated.orderedMetadata = metadata.ordered
        updated.metadata = metadata.values

        updated.updatedAt = timestamp
        return updated
    }

    private func normalizedTokens(from raw: String) -> [String] {
        var seen: Set<String> = []
        var values: [String] = []
        let separators = CharacterSet(charactersIn: ",\n;")
        for piece in raw.components(separatedBy: separators) {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let normalizedKey = trimmed.lowercased()
            guard !seen.contains(normalizedKey) else {
                continue
            }
            seen.insert(normalizedKey)
            values.append(trimmed)
        }
        return values
    }

    private func normalizedSearchTokens(from tags: [String]) -> [String] {
        var seen: Set<String> = []
        var values: [String] = []
        for tag in tags {
            let normalized = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else {
                continue
            }
            guard !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            values.append(normalized)
        }
        return values
    }

    private func normalizedNumeric(from entries: [LibraryEditableNumericValue]) throws -> (display: [String: String], values: [String: Double]) {
        var display: [String: String] = [:]
        var values: [String: Double] = [:]

        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }

            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                continue
            }

            guard let number = Double(value) else {
                throw EditError.invalidNumericValue(key: key, value: value)
            }

            let unit = entry.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            display[key] = unit.isEmpty ? value : "\(value) \(unit)"
            values[key] = number
        }

        return (display: display, values: values)
    }

    private func normalizedMetadata(from entries: [LibraryEditableKeyValue]) -> (ordered: [LibraryMetadataItem], values: [String: String]) {
        var ordered: [LibraryMetadataItem] = []
        var values: [String: String] = [:]

        for entry in entries {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                continue
            }

            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            ordered.append(LibraryMetadataItem(key: key, value: value))
            values[key] = value
        }

        return (ordered: ordered, values: values)
    }

    private func numericValueAndUnit(from raw: String) -> (value: String, unit: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("", "")
        }

        let pattern = #"^([+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][+-]?\d+)?)(?:\s*(.*))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let valueRange = Range(match.range(at: 1), in: trimmed) else {
            return (trimmed, "")
        }

        let value = String(trimmed[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var unit = ""
        if match.numberOfRanges > 2,
           let unitRange = Range(match.range(at: 2), in: trimmed) {
            unit = String(trimmed[unitRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (value, unit)
    }
}
