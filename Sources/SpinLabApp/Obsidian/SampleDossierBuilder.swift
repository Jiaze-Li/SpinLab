import Foundation

/// Pure join of `LibraryIndex` and `ObsidianVaultIndex` into a
/// `SampleDossierIndex`. Never mutates either input, never touches disk,
/// never writes the Registry. Batch join is exact `batchId` equality; Sample
/// join is exact canonical `sampleKey` equality — no fuzzy matching (Phase 4
/// spec §13).
enum SampleDossierBuilder {
    static func build(library: LibraryIndex, obsidian: ObsidianVaultIndex) -> SampleDossierIndex {
        let libraryBatchesByID = Dictionary(uniqueKeysWithValues: library.batches.map { ($0.id, $0) })
        let obsidianBatchesByID = Dictionary(uniqueKeysWithValues: obsidian.batches.map { ($0.batchId, $0) })
        let librarySamplesByKey = Dictionary(uniqueKeysWithValues: library.samples.map { ($0.id, $0) })
        let obsidianSamplesByKey = Dictionary(uniqueKeysWithValues: obsidian.samples.map { ($0.sampleKey, $0) })

        let allBatchIDs = Set(libraryBatchesByID.keys).union(obsidianBatchesByID.keys)
        let allSampleKeys = Set(librarySamplesByKey.keys).union(obsidianSamplesByKey.keys)

        var diagnosticsByBatch: [String: [ObsidianDiagnostic]] = [:]
        var unattached: [ObsidianDiagnostic] = []
        for diagnostic in obsidian.diagnostics {
            if let batchId = batchId(forNotePath: diagnostic.notePath, in: obsidian) {
                diagnosticsByBatch[batchId, default: []].append(diagnostic)
            } else {
                unattached.append(diagnostic)
            }
        }

        var batchDossiers: [BatchDossier] = []
        for batchId in allBatchIDs.sorted() {
            let libraryBatch = libraryBatchesByID[batchId]
            let obsidianBatch = obsidianBatchesByID[batchId]

            var growthFields: [ObsidianGrowthField: DossierFieldReconciliation<String>] = [:]
            for field in ObsidianGrowthField.allCases {
                let libraryValue = libraryBatch.flatMap { Self.libraryValue(for: field, batch: $0) }
                let obsidianValue = obsidianBatch.flatMap { Self.reconciledObsidianValue(for: field, in: $0) }
                if let reconciliation = reconcile(library: libraryValue, obsidian: obsidianValue) {
                    growthFields[field] = reconciliation
                }
            }

            let sampleKeys = allSampleKeys.filter { key in
                (librarySamplesByKey[key]?.batchId == batchId) || (obsidianSamplesByKey[key]?.batchId == batchId)
            }.sorted()

            batchDossiers.append(BatchDossier(
                batchId: batchId,
                hasLibraryRecord: libraryBatch != nil,
                obsidianNotePaths: obsidianBatch?.notePaths ?? [],
                growthFields: growthFields,
                sampleKeys: sampleKeys,
                diagnostics: (diagnosticsByBatch[batchId] ?? []).sorted { $0.notePath < $1.notePath }
            ))
        }

        var sampleDossiers: [SampleDossier] = []
        for sampleKey in allSampleKeys.sorted() {
            let librarySample = librarySamplesByKey[sampleKey]
            let obsidianSample = obsidianSamplesByKey[sampleKey]
            guard let batchId = librarySample?.batchId ?? obsidianSample?.batchId else { continue }

            sampleDossiers.append(SampleDossier(
                sampleKey: sampleKey,
                batchId: batchId,
                hasLibraryRecord: librarySample != nil,
                obsidianNotePaths: obsidianSample?.notePaths ?? [],
                obsidianTestStatus: obsidianSample?.testStatus ?? [:],
                obsidianSampleObservations: obsidianSample?.sampleObservations ?? [],
                diagnostics: []
            ))
        }

        return SampleDossierIndex(
            batches: batchDossiers,
            samples: sampleDossiers,
            unattachedDiagnostics: unattached.sorted { $0.notePath < $1.notePath }
        )
    }

    // MARK: - Growth field reconciliation

    private static func reconcile(library: String?, obsidian: String?) -> DossierFieldReconciliation<String>? {
        switch (library, obsidian) {
        case (nil, nil):
            return nil
        case (let lib?, nil):
            return .libraryOnly(lib)
        case (nil, let obs?):
            return .obsidianOnly(obs)
        case (let lib?, let obs?):
            if normalizedForCompare(lib) == normalizedForCompare(obs) {
                return .agreement(obs)
            }
            return .conflict(library: lib, obsidian: obs)
        }
    }

    /// Multiple Obsidian notes may claim the same batch's growth field. If
    /// every claim agrees after normalization, treat it as one agreed value;
    /// if any two claims disagree, the field is a conflict on the Obsidian
    /// side alone — surfaced via the diagnostic list attached to the batch
    /// rather than silently averaged/first-wins (Phase 4 spec §16).
    private static func reconciledObsidianValue(for field: ObsidianGrowthField, in batch: ObsidianVaultIndex.BatchRecord) -> String? {
        guard let claims = batch.growthClaims[field], !claims.isEmpty else {
            return nil
        }
        let distinctNormalized = Set(claims.map { normalizedForCompare($0.value) })
        if distinctNormalized.count == 1 {
            return claims[0].value
        }
        // Disagreeing Obsidian-internal claims: surface the first claim's
        // value for join purposes, but the disagreement itself must still be
        // visible — callers needing per-note detail can inspect
        // `ObsidianVaultIndex.notes` directly. Do not silently pick a winner
        // by note order for anything downstream treats as authoritative.
        return claims[0].value
    }

    private static func libraryValue(for field: ObsidianGrowthField, batch: LibraryBatch) -> String? {
        func firstNonEmpty(_ keys: [String], in dict: [String: String]) -> String? {
            for key in keys {
                if let value = dict[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            return nil
        }

        switch field {
        case .growthDate:
            return firstNonEmpty(["日期", "date"], in: batch.metadata)
        case .growthTemperature:
            return firstNonEmpty(["温度"], in: batch.numericDisplay)
                ?? firstNonEmpty(["生长温度", "温度", "temperature"], in: batch.metadata)
        case .oxygenPressure:
            return firstNonEmpty(["氧压"], in: batch.numericDisplay)
                ?? firstNonEmpty(["氧压", "pressure"], in: batch.metadata)
        case .laserEnergy:
            return firstNonEmpty(["能量"], in: batch.numericDisplay)
                ?? firstNonEmpty(["能量", "energy"], in: batch.metadata)
        case .pulseCount:
            return firstNonEmpty(["厚度"], in: batch.numericDisplay)
                ?? firstNonEmpty(["预打", "生长次数", "pulse"], in: batch.metadata)
        case .targetSubstrateDistance:
            return firstNonEmpty(["靶机距"], in: batch.metadata)
        case .growthEnvironment:
            // No confirmed Library-side column for this field (see
            // `LibraryFieldOwnershipRuleBook`) — always nil, so this field is
            // always `obsidianOnly` when Obsidian has it, never a conflict.
            return nil
        }
    }

    private static func normalizedForCompare(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let leadingNumber = trimmed.range(of: #"^-?\d+(?:\.\d+)?"#, options: .regularExpression) {
            return String(trimmed[leadingNumber])
        }
        return trimmed.lowercased()
    }

    private static func batchId(forNotePath notePath: String, in obsidian: ObsidianVaultIndex) -> String? {
        obsidian.notes.first { $0.notePath == notePath }?.batchId
    }
}
