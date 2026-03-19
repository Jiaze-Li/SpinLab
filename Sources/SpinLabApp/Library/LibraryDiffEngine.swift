import Foundation

final class LibraryDiffEngine {
    func diff(current: LibraryIndex, updated: LibraryIndex) -> LibraryDiff {
        var newSamples: [LibrarySample] = []
        var changed: [LibrarySampleChange] = []

        let currentSamples = Dictionary(uniqueKeysWithValues: current.samples.map { ($0.id, $0) })
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

        return LibraryDiff(newSamples: newSamples, changedSamples: changed, warnings: [])
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
}
