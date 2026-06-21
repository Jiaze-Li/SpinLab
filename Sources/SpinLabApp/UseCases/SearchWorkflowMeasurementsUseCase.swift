import Foundation

struct SearchWorkflowMeasurementsUseCase {
    private let sampleKeyNormalizer: SampleKeyNormalizer
    private let rootAccess = LibraryRootAccess()

    init(sampleKeyNormalizer: SampleKeyNormalizer = SampleKeyNormalizer()) {
        self.sampleKeyNormalizer = sampleKeyNormalizer
    }

    func execute(
        query: WorkflowSearchQuery,
        settings: LibrarySettings = .default,
        libraryRootURL: URL,
        workflowDefinitions: [WorkflowDefinition] = [],
        fileManager: FileManager = .default,
        libraryAccess: any LibraryAccessCapability = LibraryStore()
    ) throws -> [WorkflowMeasurementSearchHit] {
        guard fileManager.fileExists(atPath: libraryRootURL.path) else {
            throw AppError.notFound("Library root not found at \(libraryRootURL.path).")
        }

        let parsed = parseQuery(query.rawText)
        let numericTermStrings = parsed.numericTerms.map { "\($0.field)=\($0.value)" }
        print("[SpinLab][Search] query=\"\(query.rawText)\" textTokens=\(parsed.textTokens) numericTerms=\(numericTermStrings)")

        let effectiveSettings = settings.rootPath == nil
            ? LibrarySettings(
                rootPath: libraryRootURL.path,
                rootBookmarkData: nil,
                registryInternalPath: settings.registryInternalPath,
                registrySourcePath: settings.registrySourcePath,
                backupPath: settings.backupPath,
                backupLastSyncedAt: settings.backupLastSyncedAt,
                allowedBatchPrefixes: settings.allowedBatchPrefixes,
                lastRefreshAt: settings.lastRefreshAt
            )
            : settings
        let rootResolution = rootAccess.resolveRootURL(settings: effectiveSettings)
        let resolvedLibraryRootURL: URL
        switch rootResolution {
        case .available(let rootURL), .staleBookmark(let rootURL), .fallback(let rootURL):
            resolvedLibraryRootURL = rootURL
        case .missingBookmark:
            throw AppError.validation("Please reselect Library Root.")
        }

        // Load library index for numeric matching (graceful: empty map if missing)
        let numericTagsBySampleKey = loadNumericTags(libraryRootURL: resolvedLibraryRootURL, libraryAccess: libraryAccess)

        let result = rootAccess.enumerateSidecarURLs(settings: effectiveSettings, fileManager: fileManager)
        if case .fallback(let rootURL) = result.status {
            print("[SpinLab][Search] warning=fallback path access used for \(rootURL.path)")
        }
        if case .missingBookmark = result.status {
            throw AppError.validation("Please reselect Library Root.")
        }
        if case .staleBookmark = result.status {
            throw AppError.validation("Please reselect Library Root.")
        }
        let sidecarURLs = result.urls
        print("[SpinLab][Search] scannedSidecars=\(sidecarURLs.count)")
        if sidecarURLs.isEmpty {
            print("[SpinLab][Search] warning=no sidecars discovered under \(resolvedLibraryRootURL.path)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let displayNameByID = Dictionary(
            workflowDefinitions.map { ($0.id.lowercased(), $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )

        var hits: [WorkflowMeasurementSearchHit] = []
        hits.reserveCapacity(sidecarURLs.count)

        for sidecarURL in sidecarURLs {
            let data = try Data(contentsOf: sidecarURL, options: [.mappedIfSafe])
            let sidecar = try decoder.decode(SpinLabFileSidecar.self, from: data)
            let (hit, resolvedWorkflowID) = buildHit(sidecar: sidecar, sidecarURL: sidecarURL, displayNameByID: displayNameByID)
            let sampleNumericTags = numericTagsBySampleKey[hit.sampleKey] ?? [:]
            if matches(hit: hit, resolvedWorkflowID: resolvedWorkflowID, textTokens: parsed.textTokens, numericTerms: parsed.numericTerms, sampleNumericTags: sampleNumericTags) {
                hits.append(hit)
            }
        }
        print("[SpinLab][Search] matchedHits=\(hits.count)")

        return hits.sorted(by: compareHit)
    }

    private func buildHit(sidecar: SpinLabFileSidecar, sidecarURL: URL, displayNameByID: [String: String]) -> (hit: WorkflowMeasurementSearchHit, resolvedWorkflowID: String) {
        let pathInfo = parsePathInfo(sidecarURL: sidecarURL)
        // resolvedWorkflowID: from sidecar only — never falls back to folder path.
        // workflowID: may fall back to folder for display purposes only.
        let resolvedWorkflowID = sidecar.resolvedWorkflow
        let workflowID = firstNonEmpty(sidecar.resolvedWorkflow, pathInfo.workflowFolder) ?? ""
        let workflowCanonicalID = canonicalWorkflowID(from: workflowID, displayName: sidecar.workflowDisplayName)
        let workflowDisplayName = preferredWorkflowDisplayName(
            sidecarDisplayName: sidecar.workflowDisplayName,
            workflowID: workflowID,
            canonicalID: workflowCanonicalID,
            displayNameByID: displayNameByID
        )

        let hit = WorkflowMeasurementSearchHit(
            sidecarPath: sidecarURL.path,
            measurementFilePath: measurementFilePath(fromSidecarURL: sidecarURL),
            sourceFilePath: sidecar.sourceFilePath,
            workflowID: workflowID,
            workflowDisplayName: workflowDisplayName,
            workflowCanonicalID: workflowCanonicalID,
            batchID: pathInfo.batchID,
            sampleKey: pathInfo.sampleKey,
            sampleSubstrate: pathInfo.sampleSubstrate,
            conditions: sidecar.effectiveConditions,
            channels: sidecar.channels,
            appliedAt: sidecar.appliedAt
        )
        return (hit: hit, resolvedWorkflowID: resolvedWorkflowID)
    }

    private func preferredWorkflowDisplayName(
        sidecarDisplayName: String,
        workflowID: String,
        canonicalID: String,
        displayNameByID: [String: String]
    ) -> String {
        // Look up from registry definitions (case-insensitive via lowercased key).
        if let registryName = displayNameByID[workflowID.lowercased()]
            ?? displayNameByID[canonicalID.lowercased()],
           !registryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return registryName
        }

        let trimmedSidecar = sidecarDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSidecar.isEmpty {
            return trimmedSidecar
        }

        let trimmedID = workflowID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? canonicalID.uppercased() : trimmedID
    }

    private func measurementFilePath(fromSidecarURL sidecarURL: URL) -> String {
        let suffix = ".spinlab.json"
        guard sidecarURL.lastPathComponent.hasSuffix(suffix) else {
            return sidecarURL.deletingPathExtension().path
        }
        let baseName = String(sidecarURL.lastPathComponent.dropLast(suffix.count))
        return sidecarURL.deletingLastPathComponent().appending(path: baseName).path
    }

    private func matches(
        hit: WorkflowMeasurementSearchHit,
        resolvedWorkflowID: String,
        textTokens: [String],
        numericTerms: [(value: Double, field: String, fallbackToken: String)],
        sampleNumericTags: [String: Double]
    ) -> Bool {
        if textTokens.isEmpty && numericTerms.isEmpty { return true }

        let searchableTokens = searchTokens(for: hit, resolvedWorkflowID: resolvedWorkflowID)

        // Text tokens: all must match (existing logic)
        let textOK = textTokens.allSatisfy { searchableTokens.contains($0) }
        guard textOK else { return false }

        // Numeric terms: each must match via tolerance OR fall back to text matching
        for term in numericTerms {
            let tol = NumericUnitMap.tolerance(for: term.value)
            if let actual = sampleNumericTags[term.field] {
                // Tag exists — numeric match is authoritative; skip fallback
                if abs(actual - term.value) <= tol { continue }
                return false
            }
            // Tag missing — fall back to text token
            if searchableTokens.contains(term.fallbackToken) { continue }
            return false
        }

        return true
    }

    private func searchTokens(for hit: WorkflowMeasurementSearchHit, resolvedWorkflowID: String) -> Set<String> {
        // Workflow tokens are only included when the workflow identity comes from sidecar metadata.
        // pathInfo.workflowFolder (path-derived) is intentionally excluded to prevent folder names
        // from matching queries that should only match real workflow identities.
        var workflowValues: [String] = []
        var workflowTokens: [String] = []
        if !resolvedWorkflowID.isEmpty {
            let resolvedCanonical = canonicalWorkflowID(from: resolvedWorkflowID, displayName: hit.workflowDisplayName)
            workflowValues = [resolvedWorkflowID, hit.workflowDisplayName, resolvedCanonical]
            workflowTokens = workflowAliases(
                canonicalID: resolvedCanonical,
                workflowID: resolvedWorkflowID,
                workflowDisplayName: hit.workflowDisplayName
            )
        }

        let baseValues: [String] = workflowValues + [
            hit.batchID,
            hit.sampleKey,
            hit.sampleSubstrate,
            hit.sampleBatchAndSubstrate
        ] + workflowTokens + hit.channels

        var tokens: Set<String> = []
        for value in baseValues {
            appendSearchTokens(from: value, to: &tokens)
        }

        for (key, value) in hit.conditions {
            appendSearchTokens(from: key, to: &tokens)
            appendSearchTokens(from: value, to: &tokens)
        }

        return tokens
    }

    private func workflowAliases(canonicalID: String, workflowID: String, workflowDisplayName: String) -> [String] {
        let normalizedWorkflowID = normalizeToken(workflowID)
        let normalizedDisplayName = normalizeToken(workflowDisplayName)

        guard let knownWorkflowID = WorkflowID.from(alias: canonicalID) else {
            return [normalizedWorkflowID, normalizedDisplayName, canonicalID]
        }

        return knownWorkflowID.searchAliases + [normalizedWorkflowID, normalizedDisplayName]
    }

    private func canonicalWorkflowID(from workflowID: String, displayName: String) -> String {
        let normalizedID = normalizeToken(workflowID)
        let normalizedDisplayName = normalizeToken(displayName)

        if let knownWorkflowID = WorkflowID.from(alias: normalizedID) {
            return knownWorkflowID.rawValue
        }
        if let knownWorkflowID = WorkflowID.from(alias: normalizedDisplayName) {
            return knownWorkflowID.rawValue
        }
        if let knownWorkflowID = WorkflowID.allCases.first(where: { $0.matchesDisplayNameContains(normalizedDisplayName) }) {
            return knownWorkflowID.rawValue
        }

        return normalizedID.isEmpty ? normalizedDisplayName : normalizedID
    }

    private func parsePathInfo(sidecarURL: URL) -> (batchID: String, sampleKey: String, sampleSubstrate: String, workflowFolder: String) {
        let components = sidecarURL.pathComponents
        let normalizedComponents = components.map { $0.lowercased() }

        let batchID: String = {
            guard let batchesIndex = normalizedComponents.firstIndex(of: "batches"),
                  batchesIndex + 2 < components.count else {
                return ""
            }
            return components[batchesIndex + 2]
        }()

        let sampleKey: String = {
            guard let samplesIndex = normalizedComponents.firstIndex(of: "samples"),
                  samplesIndex + 1 < components.count else {
                return ""
            }
            return components[samplesIndex + 1]
        }()

        let workflowFolder: String = {
            guard let measurementsIndex = normalizedComponents.firstIndex(of: "measurements"),
                  measurementsIndex + 1 < components.count else {
                return ""
            }
            return components[measurementsIndex + 1]
        }()

        let normalizedSampleKey = sampleKeyNormalizer.canonicalOrOriginal(
            from: sampleKey,
            fallbackBatchID: batchID,
            fallbackSampleTags: fallbackSampleTags(from: sampleKey)
        )
        let sampleSubstrate = sampleSubstrate(from: normalizedSampleKey)
        return (batchID: batchID, sampleKey: normalizedSampleKey, sampleSubstrate: sampleSubstrate, workflowFolder: workflowFolder)
    }

    private func sampleSubstrate(from sampleKey: String) -> String {
        if let descriptor = SampleSemanticDescriptor.fromSampleKey(sampleKey) {
            let material = descriptor.material ?? ""
            let orientation = descriptor.orientation ?? ""
            return "\(material)\(orientation)"
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tokens = sampleKey.split(separator: "|").map(String.init)
        guard tokens.count >= 3 else {
            return ""
        }
        return tokens[2]
    }

    private func fallbackSampleTags(from sampleKey: String) -> [String] {
        if sampleKey.contains("|") {
            return sampleKey
                .split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .map(String.init)
                .flatMap { SampleTokenization.matchingTokens(from: $0) }
        }
        return SampleTokenization.matchingTokens(from: sampleKey)
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func normalizeToken(_ value: String) -> String {
        let normalizedOmega = value
            .replacingOccurrences(of: "ω", with: "w")
            .replacingOccurrences(of: "Ω", with: "w")
            .lowercased()

        let parts = normalizedOmega
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return parts.joined(separator: "")
    }

    private struct ParsedQuery {
        var textTokens: [String]
        var numericTerms: [(value: Double, field: String, fallbackToken: String)]
    }

    /// Parses raw query text into text tokens and numeric terms.
    /// Numeric terms are extracted from raw tokens BEFORE normalizeToken (to preserve decimals).
    private func parseQuery(_ rawText: String) -> ParsedQuery {
        let rawTokens = rawText.split(whereSeparator: \.isWhitespace).map(String.init)
        var textTokens: [String] = []
        var numericTerms: [(value: Double, field: String, fallbackToken: String)] = []

        for raw in rawTokens {
            if let parsed = NumericUnitMap.parse(raw) {
                numericTerms.append((value: parsed.value, field: parsed.field, fallbackToken: normalizeToken(raw)))
            } else {
                let normalized = normalizeToken(raw)
                if !normalized.isEmpty {
                    textTokens.append(normalized)
                }
            }
        }
        return ParsedQuery(textTokens: textTokens, numericTerms: numericTerms)
    }

    private func loadNumericTags(libraryRootURL: URL, libraryAccess: any LibraryAccessCapability) -> [String: [String: Double]] {
        guard let index = libraryAccess.loadIndex(from: libraryRootURL) else { return [:] }
        var map: [String: [String: Double]] = [:]
        map.reserveCapacity(index.samples.count)
        for sample in index.samples {
            if !sample.numericTags.isEmpty {
                map[sample.id] = sample.numericTags
            }
        }
        return map
    }

    private func appendSearchTokens(from value: String, to tokens: inout Set<String>) {
        let whole = normalizeToken(value)
        if !whole.isEmpty {
            tokens.insert(whole)
        }

        let normalizedOmega = value
            .replacingOccurrences(of: "ω", with: "w")
            .replacingOccurrences(of: "Ω", with: "w")
            .lowercased()

        let parts = normalizedOmega
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(normalizeToken)
            .filter { !$0.isEmpty }

        for part in parts {
            tokens.insert(part)
        }
    }

    private func compareHit(_ lhs: WorkflowMeasurementSearchHit, _ rhs: WorkflowMeasurementSearchHit) -> Bool {
        if lhs.batchID != rhs.batchID {
            return lhs.batchID.localizedStandardCompare(rhs.batchID) == .orderedAscending
        }
        if lhs.sampleKey != rhs.sampleKey {
            return lhs.sampleKey.localizedStandardCompare(rhs.sampleKey) == .orderedAscending
        }
        return lhs.measurementFilePath.localizedStandardCompare(rhs.measurementFilePath) == .orderedAscending
    }
}
