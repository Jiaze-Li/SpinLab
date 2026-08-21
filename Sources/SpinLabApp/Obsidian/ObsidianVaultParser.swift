import Foundation

/// Read-only, deterministic, side-effect-free parser turning Obsidian growth
/// and sample notes into an `ObsidianVaultIndex`. Never writes to the vault.
///
/// Identity resolution reuses the exact same substrate classifier every other
/// import path uses (`SubstrateSemanticClassifier`, compiled from the shared
/// rule provider) so a substrate token means the same thing here as it does
/// in the Registry and filename/free-text paths (Phase 3B). Batch identity is
/// a filename-derived alpha+digit token (e.g. `PN109`, `LNO17`) — the same
/// kind of token the Registry/import paths already treat as batch identity,
/// not a new Obsidian-specific ID.
enum ObsidianVaultParser {
    private static var classifier: SubstrateSemanticClassifier {
        SubstrateSemanticClassifier(compiled: SpinLabRuleProvider.shared.ruleSet().compiled)
    }

    private static let batchTokenPattern = #"^[A-Za-z]+[0-9]+$"#

    private static let sampleObservationKeys: Set<String> = ["core", "purpose", "note"]

    static func parseVault(at rootURL: URL, fileManager: FileManager = .default) -> ObsidianVaultIndex {
        let noteURLs = enumerateMarkdownFiles(at: rootURL, fileManager: fileManager)
        var notes: [ObsidianNoteRecord] = []
        var diagnostics: [ObsidianDiagnostic] = []

        for url in noteURLs {
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            guard let record = parseNote(contents: contents, url: url, rootURL: rootURL, diagnostics: &diagnostics) else {
                continue
            }
            notes.append(record)
        }

        let batches = aggregateBatches(from: notes)
        let samples = aggregateSamples(from: notes)

        return ObsidianVaultIndex(
            sourceRootPath: rootURL.path,
            noteCount: noteURLs.count,
            batches: batches,
            samples: samples,
            diagnostics: diagnostics,
            notes: notes
        )
    }

    // MARK: - Per-note parse

    private static func parseNote(
        contents: String,
        url: URL,
        rootURL: URL,
        diagnostics: inout [ObsidianDiagnostic]
    ) -> ObsidianNoteRecord? {
        guard let frontmatter = ObsidianFrontmatterParser.parse(contents) else {
            return nil
        }
        let notePath = relativePath(of: url, under: rootURL)
        let fileStem = url.deletingPathExtension().lastPathComponent

        let (batchId, batchDiagnostic) = resolveBatchId(fromFileStem: fileStem, notePath: notePath)
        if let batchDiagnostic {
            diagnostics.append(batchDiagnostic)
        }

        var growthClaims: [ObsidianGrowthField: ObsidianFieldClaim] = [:]
        var rawFields: [ObsidianFieldClaim] = []
        var testStatus: [String: ObsidianFieldClaim] = [:]
        var sampleObservations: [ObsidianFieldClaim] = []
        var parsedSubstrateEntries: [ObsidianSubstrateEntry] = []

        for (key, value) in frontmatter {
            let normalizedKey = key.lowercased()

            if normalizedKey == "substrate" {
                parsedSubstrateEntries.append(contentsOf: substrateEntries(from: value, rawKey: key, notePath: notePath))
                continue
            }

            if let workflowToken = testWorkflowToken(fromKey: normalizedKey) {
                if case .scalar(let raw) = value, !raw.isEmpty {
                    testStatus[workflowToken] = ObsidianFieldClaim(
                        value: raw,
                        provenance: ObsidianProvenance(notePath: notePath, rawKey: key, rawValue: raw)
                    )
                }
                continue
            }

            if sampleObservationKeys.contains(normalizedKey) {
                if case .scalar(let raw) = value, !raw.isEmpty {
                    sampleObservations.append(ObsidianFieldClaim(
                        value: raw,
                        provenance: ObsidianProvenance(notePath: notePath, rawKey: key, rawValue: raw)
                    ))
                }
                continue
            }

            guard case .scalar(let raw) = value else {
                continue
            }
            if raw.isEmpty {
                continue
            }
            let claim = ObsidianFieldClaim(
                value: raw,
                provenance: ObsidianProvenance(notePath: notePath, rawKey: key, rawValue: raw)
            )
            if let field = ObsidianGrowthField.matching(rawKey: normalizedKey) {
                growthClaims[field] = claim
            } else {
                rawFields.append(claim)
            }
        }

        let hasGrowthSignal = !growthClaims.isEmpty || !parsedSubstrateEntries.isEmpty
        if hasGrowthSignal, growthClaims[.growthDate] == nil {
            diagnostics.append(ObsidianDiagnostic(
                kind: .missingGrowthDate,
                notePath: notePath,
                message: "Note has growth signal but no growth date; recorded as-is, not guessed."
            ))
        }

        let identity = resolveIdentity(
            batchId: batchId,
            fileStem: fileStem,
            substrateEntries: parsedSubstrateEntries,
            notePath: notePath,
            diagnostics: &diagnostics
        )

        return ObsidianNoteRecord(
            notePath: notePath,
            batchId: batchId,
            identity: identity,
            growthClaims: growthClaims,
            rawFields: rawFields,
            testStatus: testStatus,
            sampleObservations: sampleObservations,
            substrateEntries: parsedSubstrateEntries
        )
    }

    // MARK: - Batch identity

    /// The batch candidate is the leftmost batch-shaped (letters+digits)
    /// filename token — batch identity always appears first in every note
    /// name observed in the real vault (e.g. `pn104 110`, `pn106 SRO1`,
    /// `lno17`); any later batch-shaped token (`SRO1`, `sro3`, …) is a
    /// free-text nickname, not a competing batch candidate, so it is treated
    /// as a substrate/orientation hint instead (see `resolveIdentity`).
    /// `.ambiguousBatchIdentity` is reserved for a future evidence source
    /// (e.g. a conflicting frontmatter batch field) that this phase's vault
    /// schema does not yet carry.
    private static func resolveBatchId(fromFileStem fileStem: String, notePath: String) -> (String?, ObsidianDiagnostic?) {
        let tokens = fileStem
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
            .map(String.init)
        guard let first = tokens.first(where: { $0.range(of: batchTokenPattern, options: .regularExpression) != nil }) else {
            return (nil, ObsidianDiagnostic(
                kind: .unresolvedBatchIdentity,
                notePath: notePath,
                message: "No batch-shaped token (letters+digits) found in filename '\(fileStem)'."
            ))
        }
        return (first.uppercased(), nil)
    }

    // MARK: - Substrate entries

    private static func substrateEntries(
        from value: ObsidianFrontmatterValue,
        rawKey: String,
        notePath: String
    ) -> [ObsidianSubstrateEntry] {
        let rawValues: [String]
        switch value {
        case .scalar(let raw):
            rawValues = raw.isEmpty ? [] : [raw]
        case .list(let items):
            rawValues = items.filter { !$0.isEmpty }
        }
        return rawValues.map { raw in
            ObsidianSubstrateEntry(
                raw: raw,
                provenance: ObsidianProvenance(notePath: notePath, rawKey: rawKey, rawValue: raw),
                material: classifier.material(inSegment: raw),
                orientation: classifier.orientation(inSegment: raw)
            )
        }
    }

    // MARK: - Sample identity resolution

    private static func resolveIdentity(
        batchId: String?,
        fileStem: String,
        substrateEntries: [ObsidianSubstrateEntry],
        notePath: String,
        diagnostics: inout [ObsidianDiagnostic]
    ) -> ObsidianIdentityResolution {
        guard let batchId else {
            // Batch-level diagnostic already recorded by resolveBatchId.
            return .unresolvedBatch
        }

        func filenameOrientationHints() -> Set<String> {
            let batchTokenUpper = batchId
            let tokens = fileStem
                .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
                .map(String.init)
                .filter { $0.uppercased() != batchTokenUpper }
            return Set(tokens.compactMap { classifier.orientation(inSegment: $0) })
        }

        switch substrateEntries.count {
        case 0:
            diagnostics.append(ObsidianDiagnostic(
                kind: .unresolvedSampleIdentity,
                notePath: notePath,
                message: "Batch '\(batchId)' resolved but note carries no substrate entry to resolve a Sample identity from."
            ))
            return .unresolvedSample

        case 1:
            let entry = substrateEntries[0]
            guard let material = entry.material, let orientation = entry.orientation else {
                diagnostics.append(ObsidianDiagnostic(
                    kind: .unresolvedSampleIdentity,
                    notePath: notePath,
                    message: "Batch '\(batchId)' resolved but substrate entry '\(entry.raw)' did not classify to both material and orientation."
                ))
                return .unresolvedSample
            }
            let key = canonicalKey(batch: batchId, material: material, orientation: orientation)
            return .resolvedSample(sampleKey: key)

        default:
            let hints = filenameOrientationHints()
            guard hints.count == 1, let hint = hints.first else {
                diagnostics.append(ObsidianDiagnostic(
                    kind: .ambiguousSampleIdentity,
                    notePath: notePath,
                    message: "Batch '\(batchId)' has \(substrateEntries.count) substrate entries and no unique filename disambiguator; Sample identity left unresolved."
                ))
                return .unresolvedSample
            }
            let matching = substrateEntries.filter { $0.orientation == hint }
            guard matching.count == 1, let entry = matching.first, let material = entry.material else {
                diagnostics.append(ObsidianDiagnostic(
                    kind: .ambiguousSampleIdentity,
                    notePath: notePath,
                    message: "Batch '\(batchId)' filename hint '\(hint)' did not uniquely resolve one of \(substrateEntries.count) substrate entries."
                ))
                return .unresolvedSample
            }
            let key = canonicalKey(batch: batchId, material: material, orientation: entry.orientation ?? hint)
            return .resolvedSample(sampleKey: key)
        }
    }

    private static func canonicalKey(batch: String, material: String, orientation: String) -> String {
        let descriptor = SampleSemanticDescriptor.withPrevalidatedTokens(
            batch: batch,
            processingTokens: [],
            material: material,
            orientation: orientation
        )
        // material/orientation are both non-nil by construction at every call
        // site above, so canonicalKey never falls back to "UNKNOWN" here.
        return descriptor.canonicalKey ?? "\(batch)||\(material)|\(orientation)"
    }

    private static func testWorkflowToken(fromKey normalizedKey: String) -> String? {
        guard normalizedKey.hasPrefix("test") else {
            return nil
        }
        var remainder = normalizedKey.dropFirst(4)
        if remainder.hasPrefix("_") || remainder.hasPrefix(" ") {
            remainder = remainder.dropFirst()
        }
        let token = String(remainder).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    // MARK: - Aggregation

    private static func aggregateBatches(from notes: [ObsidianNoteRecord]) -> [ObsidianVaultIndex.BatchRecord] {
        var byBatch: [String: [ObsidianNoteRecord]] = [:]
        for note in notes {
            guard let batchId = note.batchId else { continue }
            byBatch[batchId, default: []].append(note)
        }

        var records: [ObsidianVaultIndex.BatchRecord] = []
        for (batchId, group) in byBatch.sorted(by: { $0.key < $1.key }) {
            var growthClaims: [ObsidianGrowthField: [ObsidianFieldClaim]] = [:]
            var notePaths: [String] = []
            for note in group {
                notePaths.append(note.notePath)
                for (field, claim) in note.growthClaims {
                    growthClaims[field, default: []].append(claim)
                }
            }
            records.append(ObsidianVaultIndex.BatchRecord(
                batchId: batchId,
                growthClaims: growthClaims,
                notePaths: notePaths.sorted()
            ))
        }
        return records
    }

    private static func aggregateSamples(from notes: [ObsidianNoteRecord]) -> [ObsidianVaultIndex.SampleRecord] {
        var bySampleKey: [String: [ObsidianNoteRecord]] = [:]
        for note in notes {
            guard case .resolvedSample(let sampleKey) = note.identity else { continue }
            bySampleKey[sampleKey, default: []].append(note)
        }

        var records: [ObsidianVaultIndex.SampleRecord] = []
        for (sampleKey, group) in bySampleKey.sorted(by: { $0.key < $1.key }) {
            guard let batchId = group.first?.batchId else { continue }
            var testStatus: [String: [ObsidianFieldClaim]] = [:]
            var sampleObservations: [ObsidianFieldClaim] = []
            var notePaths: [String] = []
            for note in group {
                notePaths.append(note.notePath)
                for (token, claim) in note.testStatus {
                    testStatus[token, default: []].append(claim)
                }
                sampleObservations.append(contentsOf: note.sampleObservations)
            }
            records.append(ObsidianVaultIndex.SampleRecord(
                sampleKey: sampleKey,
                batchId: batchId,
                testStatus: testStatus,
                sampleObservations: sampleObservations,
                notePaths: notePaths.sorted()
            ))
        }
        return records
    }

    // MARK: - Filesystem

    private static func enumerateMarkdownFiles(at rootURL: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var results: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            results.append(url)
        }
        return results.sorted { $0.path < $1.path }
    }

    private static func relativePath(of url: URL, under rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath) else {
            return fullPath
        }
        var relative = String(fullPath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }
        return relative
    }
}
