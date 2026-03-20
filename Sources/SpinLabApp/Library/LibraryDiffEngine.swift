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
        var changes: [LibraryFieldChange] = []
        let oldMeta = old.metadata
        let newMeta = new.metadata
        let keys = Set(oldMeta.keys).union(newMeta.keys)
        for key in keys.sorted() {
            let oldValue = oldMeta[key]
            let newValue = newMeta[key]
            if oldValue != newValue {
                let isNumeric = LibraryRegistryParser.normalizeNumericKey(key) != nil
                changes.append(LibraryFieldChange(key: key, oldValue: oldValue, newValue: newValue, isNumeric: isNumeric))
            }
        }
        return changes
    }

    private func batchFieldChanges(old: LibraryBatch, new: LibraryBatch) -> [LibraryFieldChange] {
        var changes: [LibraryFieldChange] = []

        if old.displayName != new.displayName {
            changes.append(LibraryFieldChange(key: "Batch.displayName", oldValue: old.displayName, newValue: new.displayName, isNumeric: false))
        }
        if old.sheetName != new.sheetName {
            changes.append(LibraryFieldChange(key: "Batch.sheetName", oldValue: old.sheetName, newValue: new.sheetName, isNumeric: false))
        }

        let oldMeta = old.metadata
        let newMeta = new.metadata
        let keys = Set(oldMeta.keys).union(newMeta.keys)
        for key in keys.sorted() {
            let oldValue = oldMeta[key]
            let newValue = newMeta[key]
            if oldValue != newValue {
                let isNumeric = LibraryRegistryParser.normalizeNumericKey(key) != nil
                changes.append(LibraryFieldChange(key: key, oldValue: oldValue, newValue: newValue, isNumeric: isNumeric))
            }
        }

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
}
