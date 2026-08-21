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
                let obsidianClaims = obsidianBatch?.growthClaims[field] ?? []
                if let reconciliation = reconcile(field: field, library: libraryValue, obsidianClaims: obsidianClaims) {
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

    /// `obsidianClaims` may hold more than one note's claim for the same
    /// batch/field. If any two disagree after field-specific normalization,
    /// that disagreement is Obsidian-internal — surfaced as
    /// `.obsidianInternalConflict` with every claim (value + provenance)
    /// attached, never collapsed to a first-wins value (Phase 4 spec §16).
    /// Library's value (if any) rides along on that case rather than forcing
    /// a `.conflict`/`.agreement` verdict against it, since the disagreement
    /// itself is the thing to surface, not a Library-vs-Obsidian verdict.
    private static func reconcile(
        field: ObsidianGrowthField,
        library: String?,
        obsidianClaims: [ObsidianFieldClaim]
    ) -> DossierFieldReconciliation<String>? {
        guard !obsidianClaims.isEmpty else {
            return library.map { .libraryOnly($0) }
        }

        let distinctNormalized = Set(obsidianClaims.map { normalizedForCompare(field: field, $0.value) })
        if distinctNormalized.count > 1 {
            return .obsidianInternalConflict(claims: obsidianClaims, libraryValue: library)
        }

        let obsidianValue = obsidianClaims[0].value
        guard let library else {
            return .obsidianOnly(obsidianValue)
        }
        if normalizedForCompare(field: field, library) == normalizedForCompare(field: field, obsidianValue) {
            return .agreement(obsidianValue)
        }
        return .conflict(library: library, obsidian: obsidianValue)
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

    /// Field-specific normalization — a leading-number-only compare (the
    /// prior implementation) silently agreed "500/600" with "500/3000" and
    /// "2026-08-10" with "2026-08-20" by truncating everything after the
    /// first number. Each field's actual semantics decide what "the same
    /// value" means (Phase 4 spec §10/§3 issue 3).
    private static func normalizedForCompare(field: ObsidianGrowthField, _ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .growthTemperature, .oxygenPressure, .laserEnergy, .targetSubstrateDistance:
            // Numeric/unit-light: compare the leading magnitude only, so
            // "700 C" and "700 °C" agree regardless of unit spelling — but
            // nothing past that number (unlike pulse/date) carries meaning
            // for these fields.
            if let leadingNumber = trimmed.range(of: #"^-?\d+(?:\.\d+)?"#, options: .regularExpression),
               let magnitude = Double(trimmed[leadingNumber]) {
                return String(magnitude)
            }
            return trimmed.lowercased()
        case .growthDate:
            // Date-aware: compare the full yyyy-MM-dd, not just a leading
            // number — "2026-08-10" must never agree with "2026-08-20".
            if let isoDate = trimmed.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
                return String(trimmed[isoDate])
            }
            return trimmed.lowercased()
        case .pulseCount:
            // Full pre/growth-count semantics ("500/600") — never truncate
            // to the first number, since "500/600" and "500/3000" are
            // different growth recipes, not the same value.
            return trimmed.lowercased()
        case .growthEnvironment:
            return trimmed.lowercased()
        }
    }

    private static func batchId(forNotePath notePath: String, in obsidian: ObsidianVaultIndex) -> String? {
        obsidian.notes.first { $0.notePath == notePath }?.batchId
    }
}
