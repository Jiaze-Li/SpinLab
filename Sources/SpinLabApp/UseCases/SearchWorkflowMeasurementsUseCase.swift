import Foundation

struct SearchWorkflowMeasurementsUseCase {
    private let sampleKeyNormalizer = SampleKeyNormalizer()

    func execute(
        query: WorkflowSearchQuery,
        libraryRootURL: URL,
        workflowDefinitions: [WorkflowDefinition] = [],
        fileManager: FileManager = .default,
        libraryAccess: any LibraryAccessCapability = LibraryStore()
    ) throws -> [WorkflowMeasurementSearchHit] {
        guard fileManager.fileExists(atPath: libraryRootURL.path) else {
            throw AppError.notFound("Library root not found at \(libraryRootURL.path).")
        }

        let parsed = parseQuery(query.rawText)

        // Load library index for numeric matching (graceful: empty map if missing)
        let numericTagsBySampleKey = loadNumericTags(libraryRootURL: libraryRootURL, libraryAccess: libraryAccess)

        let sidecarURLs = collectSidecarURLs(libraryRootURL: libraryRootURL, fileManager: fileManager)
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
            let hit = buildHit(sidecar: sidecar, sidecarURL: sidecarURL, displayNameByID: displayNameByID)
            let sampleNumericTags = numericTagsBySampleKey[hit.sampleKey] ?? [:]
            if matches(hit: hit, textTokens: parsed.textTokens, numericTerms: parsed.numericTerms, sampleNumericTags: sampleNumericTags) {
                hits.append(hit)
            }
        }

        return hits.sorted(by: compareHit)
    }

    private func collectSidecarURLs(libraryRootURL: URL, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: libraryRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasSuffix(".spinlab.json") else {
                continue
            }
            let normalizedPath = fileURL.path.replacingOccurrences(of: "\\", with: "/").lowercased()
            guard normalizedPath.contains("/measurements/") else {
                continue
            }
            urls.append(fileURL)
        }
        return urls
    }

    private func buildHit(sidecar: SpinLabFileSidecar, sidecarURL: URL, displayNameByID: [String: String]) -> WorkflowMeasurementSearchHit {
        let pathInfo = parsePathInfo(sidecarURL: sidecarURL)
        let workflowID = firstNonEmpty(sidecar.workflow, pathInfo.workflowFolder) ?? ""
        let workflowCanonicalID = canonicalWorkflowID(from: workflowID, displayName: sidecar.workflowDisplayName)
        let workflowDisplayName = preferredWorkflowDisplayName(
            sidecarDisplayName: sidecar.workflowDisplayName,
            workflowID: workflowID,
            canonicalID: workflowCanonicalID,
            displayNameByID: displayNameByID
        )

        return WorkflowMeasurementSearchHit(
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
    }

    private func preferredWorkflowDisplayName(
        sidecarDisplayName: String,
        workflowID: String,
        canonicalID: String,
        displayNameByID: [String: String]
    ) -> String {
        let trimmedSidecar = sidecarDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSidecar.isEmpty {
            return trimmedSidecar
        }

        // Look up from registry definitions (case-insensitive via lowercased key).
        if let registryName = displayNameByID[workflowID.lowercased()]
            ?? displayNameByID[canonicalID.lowercased()],
           !registryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return registryName
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
        textTokens: [String],
        numericTerms: [(value: Double, field: String, fallbackToken: String)],
        sampleNumericTags: [String: Double]
    ) -> Bool {
        if textTokens.isEmpty && numericTerms.isEmpty { return true }

        let searchableTokens = searchTokens(for: hit)

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

    private func searchTokens(for hit: WorkflowMeasurementSearchHit) -> Set<String> {
        let workflowTokens = workflowAliases(
            canonicalID: hit.workflowCanonicalID,
            workflowID: hit.workflowID,
            workflowDisplayName: hit.workflowDisplayName
        )
        let baseValues: [String] = [
            hit.workflowID,
            hit.workflowDisplayName,
            hit.workflowCanonicalID,
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
