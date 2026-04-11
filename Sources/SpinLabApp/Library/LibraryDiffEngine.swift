import Foundation

final class LibraryDiffEngine {
    func diff(current: LibraryIndex, updated: LibraryIndex) -> LibraryDiff {
        var newSamples: [LibrarySample] = []
        var changed: [LibrarySampleChange] = []
        var removedSamples: [LibrarySample] = []
        var changedBatches: [LibraryBatchChange] = []
        var removedBatches: [LibraryBatch] = []

        let currentSamples = Dictionary(uniqueKeysWithValues: current.samples.map { ($0.id, $0) })
        let updatedSamples = Dictionary(uniqueKeysWithValues: updated.samples.map { ($0.id, $0) })
        for sample in updated.samples {
            guard let existing = currentSamples[sample.id] else {
                newSamples.append(sample)
                continue
            }
            let changes = fieldChanges(old: existing, new: sample)
            if !changes.isEmpty {
                let requiresConfirm = changes.contains(where: { $0.isNumeric })
                changed.append(LibrarySampleChange(sample: sample, fieldChanges: changes, requiresConfirm: requiresConfirm))
            }
        }
        for sample in current.samples where updatedSamples[sample.id] == nil {
            removedSamples.append(sample)
        }

        let currentBatches = Dictionary(uniqueKeysWithValues: current.batches.map { ($0.id, $0) })
        let updatedBatches = Dictionary(uniqueKeysWithValues: updated.batches.map { ($0.id, $0) })
        for batch in updated.batches {
            guard let existing = currentBatches[batch.id] else {
                continue
            }
            let fieldChanges = batchFieldChanges(old: existing, new: batch)
            if !fieldChanges.isEmpty {
                changedBatches.append(LibraryBatchChange(batch: batch, fieldChanges: fieldChanges))
            }
        }
        for batch in current.batches where updatedBatches[batch.id] == nil {
            removedBatches.append(batch)
        }

        return LibraryDiff(
            newSamples: newSamples,
            changedSamples: changed,
            removedSamples: removedSamples,
            changedBatches: changedBatches,
            removedBatches: removedBatches,
            warnings: []
        )
    }

    private func fieldChanges(old: LibrarySample, new: LibrarySample) -> [LibraryFieldChange] {
        var changes = metadataFieldChanges(old: old.metadata, new: new.metadata)
        changes.append(contentsOf: numericFieldChanges(old: old.numericDisplay, new: new.numericDisplay))
        return changes
    }

    private func numericFieldChanges(old: [String: String], new: [String: String]) -> [LibraryFieldChange] {
        var changes: [LibraryFieldChange] = []
        let keys = Set(old.keys).union(new.keys)
        for key in keys.sorted() {
            let oldValue = old[key]
            let newValue = new[key]
            guard oldValue != newValue else { continue }
            changes.append(LibraryFieldChange(key: "numeric.\(key)", oldValue: oldValue, newValue: newValue, isNumeric: true))
        }
        return changes
    }

    private func batchFieldChanges(old: LibraryBatch, new: LibraryBatch) -> [LibraryFieldChange] {
        var changes: [LibraryFieldChange] = []

        let oldDisplayName = normalizedFieldValue(old.displayName)
        let newDisplayName = normalizedFieldValue(new.displayName)
        if oldDisplayName != newDisplayName {
            changes.append(
                LibraryFieldChange(
                    key: "Batch.displayName",
                    oldValue: oldDisplayName,
                    newValue: newDisplayName,
                    isNumeric: false
                )
            )
        }
        let oldSheetName = normalizedFieldValue(old.sheetName)
        let newSheetName = normalizedFieldValue(new.sheetName)
        if oldSheetName != newSheetName {
            changes.append(
                LibraryFieldChange(
                    key: "Batch.sheetName",
                    oldValue: oldSheetName,
                    newValue: newSheetName,
                    isNumeric: false
                )
            )
        }

        changes.append(contentsOf: metadataFieldChanges(old: old.metadata, new: new.metadata))

        let oldSampleKeys = old.sampleKeys.sorted()
        let newSampleKeys = new.sampleKeys.sorted()
        if oldSampleKeys != newSampleKeys {
            changes.append(
                LibraryFieldChange(
                    key: "Batch.sampleKeys",
                    oldValue: oldSampleKeys.joined(separator: ","),
                    newValue: newSampleKeys.joined(separator: ","),
                    isNumeric: false
                )
            )
        }
        return changes
    }

    private func metadataFieldChanges(old oldMetadata: [String: String], new newMetadata: [String: String]) -> [LibraryFieldChange] {
        var changes: [LibraryFieldChange] = []
        let old = normalizedMetadata(oldMetadata)
        let new = normalizedMetadata(newMetadata)
        let keys = Set(old.keys).union(new.keys)

        for key in keys.sorted() {
            let oldValue = old[key]
            let newValue = new[key]
            guard oldValue != newValue else {
                continue
            }
            let isNumeric = LibraryRegistryParser.normalizeNumericKey(key) != nil
            changes.append(
                LibraryFieldChange(
                    key: key,
                    oldValue: oldValue,
                    newValue: newValue,
                    isNumeric: isNumeric
                )
            )
        }
        return changes
    }

    private func normalizedMetadata(_ metadata: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for rawKey in metadata.keys.sorted() {
            let key = normalizedFieldKey(rawKey)
            guard !key.isEmpty else {
                continue
            }
            guard let value = normalizedFieldValue(metadata[rawKey]) else {
                continue
            }
            if normalized[key] == nil {
                normalized[key] = value
            }
        }
        return normalized
    }

    private func normalizedFieldValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedFieldKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let cleanedScalars = trimmed.unicodeScalars.filter { scalar in
            let category = scalar.properties.generalCategory
            return category != .control && category != .format
        }
        let cleaned = String(String.UnicodeScalarView(cleanedScalars))
        let collapsed = cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
