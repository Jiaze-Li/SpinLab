import Foundation

final class LibraryDiffEngine {
    /// For every incoming Registry sample that refers to an already stored Registry-managed sample (found through
    /// `SampleLegacyKeyMapping`, never a hand-made / phone one): incoming id -> stored id. Samples whose id already
    /// equals the stored one are not listed.
    func identityRemap(current: LibraryIndex, updated: LibraryIndex) -> [String: String] {
        var remap: [String: String] = [:]
        for incoming in updated.samples {
            let cue = incoming.legacySampleKey ?? incoming.id
            guard let match = SampleLegacyKeyMapping.findRegistryMatch(forIncomingCue: cue, batchId: incoming.batchId, in: current),
                  match.id != incoming.id else { continue }
            remap[incoming.id] = match.id
        }
        return remap
    }

    /// Re-keys the incoming Registry samples onto their stored ids so the rest of the diff sees one sample whether it
    /// is an un-backfilled legacy sample or an already issued `smp_` one.
    private func resolvingStoredIdentities(current: LibraryIndex, updated: LibraryIndex) -> LibraryIndex {
        let remap = identityRemap(current: current, updated: updated)
        guard !remap.isEmpty else { return updated }
        var result = updated
        for index in result.samples.indices {
            if let stored = remap[result.samples[index].id] { result.samples[index].id = stored }
        }
        for index in result.batches.indices {
            result.batches[index].sampleKeys = result.batches[index].sampleKeys.map { remap[$0] ?? $0 }
        }
        return result
    }

    func diff(current: LibraryIndex, updated rawUpdated: LibraryIndex) -> LibraryDiff {
        let updated = resolvingStoredIdentities(current: current, updated: rawUpdated)
        var newSamples: [LibrarySample] = []
        var changed: [LibrarySampleChange] = []
        var removedSamples: [LibrarySample] = []
        var changedBatches: [LibraryBatchChange] = []
        var removedBatches: [LibraryBatch] = []
        var warnings: [LibraryWarning] = []

        let currentSamples = Dictionary(uniqueKeysWithValues: current.samples.map { ($0.id, $0) })
        let updatedSamples = Dictionary(uniqueKeysWithValues: updated.samples.map { ($0.id, $0) })
        for sample in updated.samples {
            guard let existing = currentSamples[sample.id] else {
                newSamples.append(sample)
                continue
            }
            if existing.isTrashed {
                warnings.append(LibraryWarning(
                    message: "Registry update skipped trashed sample '\(sample.id)' ('\(existing.displayName)').",
                    affectedSampleKey: sample.id,
                    severity: .warning
                ))
                continue
            }
            if existing.conflictsWithIncomingRegistrySample(sample) {
                warnings.append(LibraryWarning(
                    message: "Registry update contains sample key '\(sample.id)' which conflicts with existing non-registry sample '\(existing.displayName)'. Sample was protected.",
                    affectedSampleKey: sample.id,
                    severity: .warning
                ))
                continue
            }
            let changes = fieldChanges(old: existing, new: sample)
            if !changes.isEmpty {
                let requiresConfirm = changes.contains(where: { $0.isNumeric })
                var sampleToUpdate = sample
                if sampleToUpdate.sampleUID == nil || sampleToUpdate.sampleUID?.isEmpty == true {
                    sampleToUpdate.sampleUID = existing.sampleUID
                }
                if sampleToUpdate.legacySampleKey == nil || sampleToUpdate.legacySampleKey?.isEmpty == true {
                    sampleToUpdate.legacySampleKey = existing.legacySampleKey
                }
                if sampleToUpdate.origin == nil || sampleToUpdate.origin?.isEmpty == true {
                    sampleToUpdate.origin = existing.origin
                }
                changed.append(LibrarySampleChange(sample: sampleToUpdate, fieldChanges: changes, requiresConfirm: requiresConfirm))
            }
        }
        for sample in current.samples where updatedSamples[sample.id] == nil {
            // Trashed samples must neither resurrect nor trigger unauthorized removal / physical deletion.
            guard !sample.isTrashed else {
                continue
            }
            // Native or manual samples must NEVER be removed by Registry diff.
            guard !sample.isNativeOrManual else {
                continue
            }
            removedSamples.append(sample)
        }

        let currentBatches = Dictionary(uniqueKeysWithValues: current.batches.map { ($0.id, $0) })
        let updatedBatches = Dictionary(uniqueKeysWithValues: updated.batches.map { ($0.id, $0) })
        let currentProtectedSampleKeys = Set(
            current.samples.filter { $0.isNativeOrManual || $0.isTrashed }.map(\.id)
        )

        for batch in updated.batches {
            guard let existing = currentBatches[batch.id] else {
                continue
            }
            let fieldChanges = batchFieldChanges(old: existing, new: batch, nativeSampleKeys: currentProtectedSampleKeys)
            if !fieldChanges.isEmpty {
                var batchToApply = batch
                if batchToApply.origin == nil || batchToApply.origin?.isEmpty == true {
                    batchToApply.origin = existing.origin
                }
                let protectedKeysToPreserve = existing.sampleKeys.filter { currentProtectedSampleKeys.contains($0) }
                batchToApply.sampleKeys = Set(batch.sampleKeys).union(protectedKeysToPreserve).sorted()
                changedBatches.append(LibraryBatchChange(batch: batchToApply, fieldChanges: fieldChanges))
            }
        }
        for batch in current.batches where updatedBatches[batch.id] == nil {
            // Native batches or batches with native/trashed samples must NEVER be removed by Registry diff.
            guard batch.origin != "native" else {
                continue
            }
            let hasProtectedSamples = current.samples.contains {
                $0.batchId == batch.id && ($0.isNativeOrManual || $0.isTrashed)
            }
            guard !hasProtectedSamples else {
                continue
            }
            removedBatches.append(batch)
        }

        return LibraryDiff(
            newSamples: newSamples,
            changedSamples: changed,
            removedSamples: removedSamples,
            changedBatches: changedBatches,
            removedBatches: removedBatches,
            warnings: warnings
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

    private func batchFieldChanges(old: LibraryBatch, new: LibraryBatch, nativeSampleKeys: Set<String> = []) -> [LibraryFieldChange] {
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

        // Exclude native sample keys from old batch keys when comparing with Registry preview,
        // because Registry does not manage native samples and their presence is not a drift from Registry.
        let oldNonNativeKeys = old.sampleKeys.filter { !nativeSampleKeys.contains($0) }.sorted()
        let newSampleKeys = new.sampleKeys.sorted()
        if oldNonNativeKeys != newSampleKeys {
            changes.append(
                LibraryFieldChange(
                    key: "Batch.sampleKeys",
                    oldValue: oldNonNativeKeys.joined(separator: ","),
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
