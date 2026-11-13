import Foundation

/// Input parameters for creating a new native Sample without XLSX Registry or instrument files.
struct CreateNativeSampleDraft: Sendable, Equatable {
    var batchId: String
    /// Substrate description (e.g. "STO(001)" or free text).
    var substrateDescription: String = ""
    /// Optional user-facing display name. If omitted or empty, a readable default is generated.
    var displayName: String? = nil
    var metadata: [String: String] = [:]
    /// Permanent machine identity, generated once when the creation form opens (K1, K2).
    /// Re-submitting the same UID returns the already-created sample instead of creating another (K4).
    var sampleUID: String = NativeSampleCreationService.makeSampleUID()
    var numericTags: [String: Double] = [:]
    var numericDisplay: [String: String] = [:]
}

/// Errors occurring during native Sample creation.
enum CreateNativeSampleError: LocalizedError, Equatable {
    case missingLibraryRoot
    case unreadableLibrary(String)
    case invalidInput(String)
    case conflictingIdentity(String)
    case directoryCollision(String)
    case pathContainmentViolation(String)
    case writeFailed(String)
    case indexSyncFailed(String)
    case rollbackFailed(primaryError: String, rollbackErrors: [String])

    var errorDescription: String? {
        switch self {
        case .missingLibraryRoot:
            return "Select a Library Root first."
        case let .unreadableLibrary(reason):
            return "Library could not be read completely: \(reason). Nothing was created."
        case let .invalidInput(reason):
            return "Invalid sample input: \(reason)"
        case let .conflictingIdentity(reason):
            return "Identity conflict: \(reason)"
        case let .directoryCollision(reason):
            return "Filesystem directory collision: \(reason)"
        case let .pathContainmentViolation(reason):
            return "Path containment violation: \(reason)"
        case let .writeFailed(reason):
            return "Failed to save sample: \(reason)"
        case let .indexSyncFailed(reason):
            return "Sample was saved but index could not be updated: \(reason)"
        case let .rollbackFailed(primaryError, rollbackErrors):
            return "Failed to save sample (\(primaryError)) and rollback failed: \(rollbackErrors.joined(separator: "; ")). Manual inspection required."
        }
    }
}

/// Result of a native Sample creation operation.
enum CreateNativeSampleOutcome: Sendable {
    case success(sample: LibrarySample, batch: LibraryBatch, syncedIndex: LibraryIndex)
    case failure(error: CreateNativeSampleError)
}

/// Service providing atomic, formal Sample creation in SpinLab.
/// Enforces fail-closed library validation, stable machine identity generation,
/// duplicate protection, batch relationship persistence, and rollback on failure.
struct NativeSampleCreationService {
    private let ruleProvider: any SpinLabRuleProviding

    init(ruleProvider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) {
        self.ruleProvider = ruleProvider
    }

    func createSample(
        draft: CreateNativeSampleDraft,
        rootURL: URL?,
        libraryStore: LibraryStore,
        settings: LibrarySettings
    ) -> CreateNativeSampleOutcome {
        guard let rootURL else {
            return .failure(error: .missingLibraryRoot)
        }

        // 1. Fail-closed: Read complete index before making any mutations.
        // Unreadable or partially readable library must never be treated as empty.
        let completeIndex: LibraryIndex
        do {
            completeIndex = try libraryStore.readOnlyCompleteIndex(rootURL: rootURL)
        } catch {
            return .failure(error: .unreadableLibrary(error.localizedDescription))
        }

        // 2. Validate input fields and reject path traversal / boundary escape inputs.
        let inputBatchId = draft.batchId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputBatchId.isEmpty else {
            return .failure(error: .invalidInput("Batch ID cannot be empty."))
        }
        if let violation = Self.validatePathComponentSafety(inputBatchId, label: "Batch ID") {
            return .failure(error: .invalidInput(violation))
        }

        // 3. Resolve canonical Batch ID casing and detect directory collisions.
        let inputSanitizedBatch = libraryStore.sanitizedPathComponent(inputBatchId)

        // 3a. Collision check against all existing batches in index
        for existingBatch in completeIndex.batches {
            let existingSanitized = libraryStore.sanitizedPathComponent(existingBatch.id)
            if existingSanitized.caseInsensitiveCompare(inputSanitizedBatch) == .orderedSame {
                if existingBatch.id.caseInsensitiveCompare(inputBatchId) != .orderedSame {
                    return .failure(error: .directoryCollision(
                        "Batch ID '\(inputBatchId)' collides with existing batch '\(existingBatch.id)' on filesystem directory '\(inputSanitizedBatch)'. Different batches cannot share the same directory."
                    ))
                }
            }
        }

        // 3b. Resolve canonical Batch ID casing
        let canonicalBatchId: String
        let existingBatchMatch = completeIndex.batches.first { $0.id.caseInsensitiveCompare(inputBatchId) == .orderedSame }
        if let existingBatchMatch {
            canonicalBatchId = existingBatchMatch.id
        } else {
            canonicalBatchId = inputBatchId
        }

        let fileManager = libraryStore.fileManager

        // 3c. Collision check on disk: check if the resolved batch directory already exists with a different batch.json ID
        let batchURL = libraryStore.resolvedBatchDirectoryURL(rootURL, batchID: canonicalBatchId)
        let batchJSONURL = batchURL.appending(path: "batch.json")
        if fileManager.fileExists(atPath: batchJSONURL.path) {
            if let diskBatch = libraryStore.decodeBatch(from: batchJSONURL) {
                if diskBatch.id.caseInsensitiveCompare(canonicalBatchId) != .orderedSame {
                    return .failure(error: .directoryCollision(
                        "Filesystem directory for batch '\(canonicalBatchId)' already exists on disk and belongs to a different batch ID '\(diskBatch.id)'."
                    ))
                }
            }
        }

        // 4. Identity (K1-K4): the sample id (and folder name) is the machine sampleUID itself.
        // Batch and substrate are plain attributes: two samples with identical attributes may coexist (K3).
        let sampleUID = draft.sampleUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidSampleUID(sampleUID) else {
            return .failure(error: .invalidInput("Sample UID is missing or malformed."))
        }
        let sampleId = sampleUID

        // 4a. Idempotent re-submit (K4): a sample with this UID already exists -> return it, create nothing.
        let sameUIDSamples = completeIndex.samples.filter { $0.id == sampleUID || $0.sampleUID == sampleUID }
        if sameUIDSamples.count > 1 {
            return .failure(error: .conflictingIdentity("Multiple samples already share UID '\(sampleUID)'. Manual repair required."))
        }
        if let existing = sameUIDSamples.first {
            let existingBatch = completeIndex.batches.first { $0.id == existing.batchId }
                ?? LibraryBatch(id: existing.batchId, displayName: existing.batchId, sheetName: "", metadata: [:], numericTags: [:], numericDisplay: [:], sampleKeys: [existing.id], updatedAt: existing.updatedAt, origin: "native")
            return .success(sample: existing, batch: existingBatch, syncedIndex: completeIndex)
        }

        // 5. Parse substrate attributes without guessing unknown properties.
        let classifier = SubstrateSemanticClassifier(compiled: ruleProvider.ruleSet().compiled)
        let rawDesc = draft.substrateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let material = classifier.material(inSegment: rawDesc)
        let orientation = classifier.orientation(inSegment: rawDesc)
        let treatments = classifier.treatments(inSegment: rawDesc)

        // Same shape as Registry-imported substrates: "<treatments> <Material>(<Orientation>)",
        // tokens = treatments + material + orientation, tags = material, base, "<treatments> <base>".
        let sortedTreatments = treatments.sorted()
        let baseMaterial = material ?? rawDesc
        let baseTag = baseMaterial + (orientation.map { "(\($0))" } ?? "")
        let treatmentPrefix = sortedTreatments.joined(separator: " ")
        let composedDisplay = ((treatmentPrefix.isEmpty ? "" : treatmentPrefix + " ") + baseTag)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let substrateDisplay = composedDisplay.isEmpty ? "Unspecified" : composedDisplay
        let substrateTokens = rawDesc.isEmpty ? [] : treatments + [material ?? "UNKNOWN", orientation ?? "UNKNOWN"]
        var substrateTags: [String] = []
        if !rawDesc.isEmpty {
            substrateTags = [material ?? "UNKNOWN", baseTag]
            if !sortedTreatments.isEmpty {
                substrateTags.append("\(treatmentPrefix) \(baseTag)")
            }
        }

        // 6. Identity was fixed when the form opened (see step 4); nothing is derived from names or paths.
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))

        let userDisplayName = (draft.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDisplayName: String
        if !userDisplayName.isEmpty {
            finalDisplayName = userDisplayName
        } else if !rawDesc.isEmpty {
            finalDisplayName = "\(canonicalBatchId) - \(substrateDisplay)"
        } else {
            finalDisplayName = "\(canonicalBatchId) - Sample"
        }

        let sample = LibrarySample(
            id: sampleId,
            displayName: finalDisplayName,
            batchId: canonicalBatchId,
            substrateRaw: rawDesc,
            substrateDisplay: substrateDisplay,
            substrateTokens: substrateTokens,
            substrateTags: substrateTags,
            metadata: draft.metadata,
            orderedMetadata: draft.metadata.sorted(by: { $0.key < $1.key }).map { LibraryMetadataItem(key: $0.key, value: $0.value) },
            numericTags: draft.numericTags,
            numericDisplay: draft.numericDisplay,
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: now,
            appliedMeasurements: [],
            measurementSets: [],
            sampleUID: sampleUID,
            legacySampleKey: nil,
            origin: "native"
        )

        // 7. Batch preparation:
        var batch: LibraryBatch
        if var existingBatch = existingBatchMatch {
            if !existingBatch.sampleKeys.contains(sampleId) {
                existingBatch.sampleKeys.append(sampleId)
            }
            existingBatch.updatedAt = now
            batch = existingBatch
        } else {
            batch = LibraryBatch(
                id: canonicalBatchId,
                displayName: canonicalBatchId,
                sheetName: "",
                metadata: [:],
                numericTags: [:],
                numericDisplay: [:],
                sampleKeys: [sampleId],
                updatedAt: now,
                origin: "native"
            )
        }

        // 8. Atomic creation with full batch, sample, and index rollback protection:
        let preferredBatchURL = libraryStore.preferredBatchDirectoryURL(rootURL, batchID: canonicalBatchId)
        let legacyBatchURL = libraryStore.legacyBatchDirectoryURL(rootURL, batchID: canonicalBatchId)
        let preferredExistedBefore = fileManager.fileExists(atPath: preferredBatchURL.path)
        let legacyExistedBefore = fileManager.fileExists(atPath: legacyBatchURL.path)
        if preferredExistedBefore && legacyExistedBefore && preferredBatchURL.path != legacyBatchURL.path {
            return .failure(error: .directoryCollision(
                "Batch '\(canonicalBatchId)' exists in multiple physical layouts ('\(preferredBatchURL.path)' and '\(legacyBatchURL.path)'). Refusing mutation to avoid ambiguous data modification."
            ))
        }
        let batchExistedBefore = preferredExistedBefore || legacyExistedBefore
        let isLegacyLayout = legacyExistedBefore && !preferredExistedBefore

        let originalBatchData: Data? = try? Data(contentsOf: batchJSONURL)

        let prefixURL = batchURL.deletingLastPathComponent()
        let prefixExistedBefore = fileManager.fileExists(atPath: prefixURL.path)

        let samplesDir = batchURL.appending(path: "samples", directoryHint: .isDirectory)
        let samplesDirExistedBefore = fileManager.fileExists(atPath: samplesDir.path)

        let sampleURL = libraryStore.sampleDirectoryURL(rootURL, batchID: canonicalBatchId, sampleKey: sampleId)
        let sampleExistedBefore = fileManager.fileExists(atPath: sampleURL.path)
        if sampleExistedBefore {
            let sampleJSON = sampleURL.appending(path: "sample.json")
            if fileManager.fileExists(atPath: sampleJSON.path) {
                if let diskSample = libraryStore.decodeSample(from: sampleJSON) {
                    return .failure(error: .directoryCollision(
                        "Sample directory '\(sampleURL.lastPathComponent)' already exists on disk (sample ID '\(diskSample.id)') but is missing from the index. Refusing to overwrite."
                    ))
                } else {
                    return .failure(error: .directoryCollision(
                        "Sample directory '\(sampleURL.lastPathComponent)' already exists on disk with unreadable sample data."
                    ))
                }
            } else {
                return .failure(error: .directoryCollision(
                    "Directory '\(sampleURL.lastPathComponent)' already exists on disk and is not a valid sample drawer."
                ))
            }
        }

        // Snapshot index state before any mutation:
        let indexURL = libraryStore.indexFileURL(rootURL)
        let indexExistedBefore = fileManager.fileExists(atPath: indexURL.path)
        let originalIndexData: Data? = indexExistedBefore ? (try? Data(contentsOf: indexURL)) : nil

        // Path Containment Preflight:
        // Validate that all generated paths are strictly contained within library root
        // and expected parent directories, distinguishing preferred and legacy batch layouts,
        // and ensuring no symbolic links exist that could bypass boundary checks.
        let batchesURL = libraryStore.batchesDirectoryURL(rootURL)
        guard libraryStore.isPathContained(batchesURL, within: rootURL) else {
            return .failure(error: .pathContainmentViolation("Batches directory '\(batchesURL.path)' escapes library root '\(rootURL.path)'."))
        }

        // 1. Symbolic Link Inspection:
        // Check for symbolic links first to guarantee that symlink attacks trigger
        // the dedicated symbolic link protection rather than generic containment errors.
        if libraryStore.containsSymbolicLink(batchURL, relativeTo: rootURL) {
            return .failure(error: .pathContainmentViolation("Batch directory '\(batchURL.path)' contains or traverses a symbolic link."))
        }
        if libraryStore.containsSymbolicLink(sampleURL, relativeTo: rootURL) {
            return .failure(error: .pathContainmentViolation("Sample directory '\(sampleURL.path)' contains or traverses a symbolic link."))
        }

        // 2. Layout Structure & Containment Verification:
        if isLegacyLayout {
            // Legacy batch layout: <root>/batches/<batchID>
            // batchURL is located directly inside batchesURL without a separate prefix directory (prefixURL == batchesURL).
            guard batchURL.deletingLastPathComponent().standardizedFileURL.path == batchesURL.standardizedFileURL.path else {
                return .failure(error: .pathContainmentViolation("Legacy batch directory '\(batchURL.path)' is not directly inside batches directory '\(batchesURL.path)'."))
            }
        } else {
            // Preferred batch layout: <root>/batches/<prefix>/<batchID>
            // prefixURL must be strictly inside batchesURL, and batchURL must be strictly inside prefixURL.
            guard libraryStore.isPathContained(prefixURL, within: batchesURL) else {
                return .failure(error: .pathContainmentViolation("Batch prefix directory '\(prefixURL.path)' escapes batches directory '\(batchesURL.path)'."))
            }
            guard libraryStore.isPathContained(batchURL, within: prefixURL) else {
                return .failure(error: .pathContainmentViolation("Batch directory '\(batchURL.path)' escapes prefix directory '\(prefixURL.path)'."))
            }
        }

        guard libraryStore.isPathContained(batchURL, within: batchesURL) else {
            return .failure(error: .pathContainmentViolation("Batch directory '\(batchURL.path)' escapes batches directory '\(batchesURL.path)'."))
        }

        guard libraryStore.isPathContained(sampleURL, within: samplesDir) else {
            return .failure(error: .pathContainmentViolation("Sample directory '\(sampleURL.path)' escapes sample folder '\(samplesDir.path)'."))
        }

        guard libraryStore.isPathContained(sampleURL, within: rootURL) else {
            return .failure(error: .pathContainmentViolation("Sample directory '\(sampleURL.path)' escapes library root '\(rootURL.path)'."))
        }

        let expectedIndexDir = libraryStore.indexDirectoryURL(rootURL)
        guard libraryStore.isPathContained(indexURL, within: expectedIndexDir) else {
            return .failure(error: .pathContainmentViolation("Index file '\(indexURL.path)' escapes index directory '\(expectedIndexDir.path)'."))
        }

        func rollbackCreatedState() -> [String] {
            var rollbackFailures: [String] = []

            // Safety guard: Verify rootURL containment before deleting or restoring anything
            guard libraryStore.isPathContained(batchURL, within: rootURL),
                  libraryStore.isPathContained(sampleURL, within: rootURL) else {
                rollbackFailures.append("Rollback aborted: batch or sample path is not safely contained within library root.")
                return rollbackFailures
            }

            // 1. Roll back sample drawer
            if !sampleExistedBefore && fileManager.fileExists(atPath: sampleURL.path) {
                if libraryStore.isPathContained(sampleURL, within: rootURL) {
                    do {
                        try fileManager.removeItem(at: sampleURL)
                    } catch {
                        rollbackFailures.append("Failed to remove created sample drawer at \(sampleURL.lastPathComponent): \(error.localizedDescription)")
                    }
                } else {
                    rollbackFailures.append("Rollback refused to remove sample drawer outside library root: \(sampleURL.path)")
                }
            }
            if !samplesDirExistedBefore && fileManager.fileExists(atPath: samplesDir.path) {
                if libraryStore.isPathContained(samplesDir, within: rootURL) {
                    let remaining = (try? fileManager.contentsOfDirectory(atPath: samplesDir.path)) ?? []
                    if remaining.isEmpty {
                        do {
                            try fileManager.removeItem(at: samplesDir)
                        } catch {
                            rollbackFailures.append("Failed to clean up empty samples directory: \(error.localizedDescription)")
                        }
                    }
                } else {
                    rollbackFailures.append("Rollback refused to remove samples directory outside library root: \(samplesDir.path)")
                }
            }

            // 2. Roll back batch state
            if !batchExistedBefore {
                if fileManager.fileExists(atPath: batchURL.path) {
                    if libraryStore.isPathContained(batchURL, within: rootURL) {
                        do {
                            try fileManager.removeItem(at: batchURL)
                        } catch {
                            rollbackFailures.append("Failed to remove created batch directory at \(batchURL.lastPathComponent): \(error.localizedDescription)")
                        }
                    } else {
                        rollbackFailures.append("Rollback refused to remove batch directory outside library root: \(batchURL.path)")
                    }
                }
                if !prefixExistedBefore && !isLegacyLayout {
                    if libraryStore.isPathContained(prefixURL, within: batchesURL) {
                        let remaining = (try? fileManager.contentsOfDirectory(atPath: prefixURL.path)) ?? []
                        if remaining.isEmpty {
                            do {
                                try fileManager.removeItem(at: prefixURL)
                            } catch {
                                rollbackFailures.append("Failed to clean up empty prefix directory: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        rollbackFailures.append("Rollback refused to remove prefix directory outside library root: \(prefixURL.path)")
                    }
                }
            } else if let originalBatchData {
                // Batch already existed: ONLY restore batch.json, NEVER delete the batch directory or any other samples/measurements/plots
                if libraryStore.isPathContained(batchJSONURL, within: rootURL) {
                    let currentBatchData = try? Data(contentsOf: batchJSONURL)
                    if currentBatchData != originalBatchData {
                        do {
                            try originalBatchData.write(to: batchJSONURL, options: .atomic)
                        } catch {
                            rollbackFailures.append("Failed to restore original batch.json: \(error.localizedDescription)")
                        }
                    }
                } else {
                    rollbackFailures.append("Rollback refused to write batch.json outside library root: \(batchJSONURL.path)")
                }
            }

            // 3. Roll back LibraryIndex
            if libraryStore.isPathContained(indexURL, within: rootURL) {
                if indexExistedBefore {
                    if let originalIndexData {
                        let currentIndexData = try? Data(contentsOf: indexURL)
                        if currentIndexData != originalIndexData {
                            do {
                                try originalIndexData.write(to: indexURL, options: .atomic)
                            } catch {
                                rollbackFailures.append("Failed to restore original library_index.json: \(error.localizedDescription)")
                            }
                        }
                    }
                } else if fileManager.fileExists(atPath: indexURL.path) {
                    do {
                        try fileManager.removeItem(at: indexURL)
                    } catch {
                        rollbackFailures.append("Failed to remove created library_index.json: \(error.localizedDescription)")
                    }
                }
            } else {
                rollbackFailures.append("Rollback refused to touch index file outside library root: \(indexURL.path)")
            }

            // Invalidate caches
            libraryStore.invalidateNodeCache(at: sampleURL)
            libraryStore.invalidateNodeCache(at: batchURL)
            libraryStore.invalidateNodeCache(at: libraryStore.indexDirectoryURL(rootURL))

            return rollbackFailures
        }

        do {
            try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
        } catch {
            let rollbackFailures = rollbackCreatedState()
            if !rollbackFailures.isEmpty {
                return .failure(error: .rollbackFailed(
                    primaryError: error.localizedDescription,
                    rollbackErrors: rollbackFailures
                ))
            }
            return .failure(error: .writeFailed(error.localizedDescription))
        }

        // 9. Rebuild and persist LibraryIndex in a single formal commit boundary:
        let syncedIndex: LibraryIndex
        do {
            // Pure in-memory scan: no double-write, no unintended legacy migration
            let scan = libraryStore.scanIndexFromFilesystem(rootURL: rootURL)
            guard scan.rootExists else {
                throw LibraryIndexSyncError.rootMissing(rootURL.path)
            }
            guard scan.issues.isEmpty else {
                throw LibraryIndexSyncError.incomplete(scan.issues)
            }
            guard scan.index.samples.contains(where: { $0.id == sample.id }) else {
                throw LibraryIndexSyncError.incomplete(["Newly created sample was not found in rebuilt index."])
            }

            var finalIndex = scan.index
            finalIndex.updatedAt = now
            finalIndex.registryInternalPath = settings.registryInternalPath
            finalIndex.registrySourcePath = settings.registrySourcePath

            // Single formal persistence point
            guard libraryStore.saveIndex(finalIndex, to: rootURL) else {
                throw LibraryIndexSyncError.writeFailed
            }
            syncedIndex = finalIndex
        } catch {
            let rollbackFailures = rollbackCreatedState()
            if !rollbackFailures.isEmpty {
                return .failure(error: .rollbackFailed(
                    primaryError: error.localizedDescription,
                    rollbackErrors: rollbackFailures
                ))
            }
            return .failure(error: .indexSyncFailed(error.localizedDescription))
        }

        return .success(sample: sample, batch: batch, syncedIndex: syncedIndex)
    }

    static func makeSampleUID() -> String {
        "smp_" + UUID().uuidString.lowercased()
    }

    /// A UID is path-safe by construction: `smp_` + lowercase hex/dash only.
    static func isValidSampleUID(_ value: String) -> Bool {
        guard value.hasPrefix("smp_"), value.count > 4 else { return false }
        return value.dropFirst(4).allSatisfy { $0.isNumber || ("a"..."f").contains($0) || $0 == "-" }
    }

    /// Validates that an input path component (such as batchId) does not contain
    /// relative traversal segments ("." or ".."), null bytes, or boundary escape attempts.
    static func validatePathComponentSafety(_ value: String, label: String) -> String? {
        if value == "." || value == ".." {
            return "\(label) cannot be '.' or '..'."
        }
        if value.contains("\0") {
            return "\(label) contains invalid null byte."
        }
        let segments = value.components(separatedBy: CharacterSet(charactersIn: "/\\"))
        for segment in segments {
            let segTrimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if segTrimmed == "." || segTrimmed == ".." {
                return "\(label) contains relative traversal component '\(segment)'."
            }
        }
        return nil
    }
}
