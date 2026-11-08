import Foundation

/// Input parameters for creating a new native Sample without XLSX Registry or instrument files.
struct CreateNativeSampleDraft: Sendable, Equatable {
    var batchId: String
    /// The distinguishing substrate or piece identity within the batch (e.g. "S1", "Piece 1", "A").
    var substrateIdentity: String
    /// Substrate description (e.g. "STO(001)" or free text).
    var substrateDescription: String = ""
    /// Optional user-facing display name. If omitted or empty, a readable default is generated.
    var displayName: String? = nil
    var metadata: [String: String] = [:]
    var numericTags: [String: Double] = [:]
    var numericDisplay: [String: String] = [:]
}

/// Errors occurring during native Sample creation.
enum CreateNativeSampleError: LocalizedError, Equatable {
    case missingLibraryRoot
    case unreadableLibrary(String)
    case invalidInput(String)
    case duplicateSample(sampleId: String, substrateIdentity: String, batchId: String)
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
        case let .duplicateSample(sampleId, substrateIdentity, batchId):
            return "A sample with identity '\(substrateIdentity)' (ID: \(sampleId)) already exists in batch '\(batchId)'."
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
        let substrateIdentity = draft.substrateIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputBatchId.isEmpty else {
            return .failure(error: .invalidInput("Batch ID cannot be empty."))
        }
        guard !substrateIdentity.isEmpty else {
            return .failure(error: .invalidInput("Substrate identity cannot be empty."))
        }
        if let violation = Self.validatePathComponentSafety(inputBatchId, label: "Batch ID") {
            return .failure(error: .invalidInput(violation))
        }
        if let violation = Self.validatePathComponentSafety(substrateIdentity, label: "Substrate identity") {
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

        // 4. Duplicate & Conflict Detection:
        // A physical sample is identified by (canonicalBatchId, substrateIdentity).
        let normalizedSubstrate = substrateIdentity.lowercased()
        let sanitizedSubstrate = libraryStore.sanitizedPathComponent(substrateIdentity)
        let sampleId = "\(canonicalBatchId)_\(sanitizedSubstrate)"

        let matchingBatchSamples = completeIndex.samples.filter { sample in
            sample.batchId.caseInsensitiveCompare(canonicalBatchId) == .orderedSame
        }

        for existing in matchingBatchSamples {
            let existingSubId = existing.substrateIdentity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let existingSanitizedSub = libraryStore.sanitizedPathComponent(existingSubId)

            // Case A: Sample has explicit substrateIdentity
            if !existingSubId.isEmpty {
                if existingSubId.caseInsensitiveCompare(normalizedSubstrate) == .orderedSame || existingSubId.caseInsensitiveCompare(substrateIdentity) == .orderedSame {
                    return .failure(error: .duplicateSample(
                        sampleId: existing.id,
                        substrateIdentity: substrateIdentity,
                        batchId: canonicalBatchId
                    ))
                }
                // Different substrate identities that sanitize to the same path component (Collision)
                if existingSanitizedSub.caseInsensitiveCompare(sanitizedSubstrate) == .orderedSame {
                    return .failure(error: .directoryCollision(
                        "Substrate identity '\(substrateIdentity)' collides with existing sample '\(existing.id)' (substrate '\(existingSubId)') on filesystem directory component '\(sanitizedSubstrate)'."
                    ))
                }
            } else {
                // Case B: Legacy sample lacking substrateIdentity
                if existing.id.caseInsensitiveCompare(sampleId) == .orderedSame ||
                   existing.id.caseInsensitiveCompare(substrateIdentity) == .orderedSame ||
                   existing.displayName.caseInsensitiveCompare(substrateIdentity) == .orderedSame ||
                   existing.substrateDisplay.caseInsensitiveCompare(substrateIdentity) == .orderedSame ||
                   existing.substrateRaw.caseInsensitiveCompare(substrateIdentity) == .orderedSame {
                    return .failure(error: .duplicateSample(
                        sampleId: existing.id,
                        substrateIdentity: substrateIdentity,
                        batchId: canonicalBatchId
                    ))
                }
            }

            // Check if sample ID collides with existing sample ID
            if existing.id.caseInsensitiveCompare(sampleId) == .orderedSame {
                return .failure(error: .duplicateSample(
                    sampleId: existing.id,
                    substrateIdentity: substrateIdentity,
                    batchId: canonicalBatchId
                ))
            }
        }

        // Check if sampleId already exists globally in the library index
        if let existingById = completeIndex.samples.first(where: { $0.id.caseInsensitiveCompare(sampleId) == .orderedSame }) {
            return .failure(error: .duplicateSample(
                sampleId: existingById.id,
                substrateIdentity: substrateIdentity,
                batchId: canonicalBatchId
            ))
        }

        // Check for multiple conflicting candidates in index
        let identicalKeys = completeIndex.samples.filter { $0.id.caseInsensitiveCompare(sampleId) == .orderedSame }
        if identicalKeys.count > 1 {
            return .failure(error: .conflictingIdentity("Multiple samples already share ID '\(sampleId)'. Manual repair required."))
        }

        // 5. Parse substrate attributes without guessing unknown properties.
        let classifier = SubstrateSemanticClassifier(compiled: ruleProvider.ruleSet().compiled)
        let rawDesc = draft.substrateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let material = classifier.material(inSegment: rawDesc)
        let orientation = classifier.orientation(inSegment: rawDesc)
        let treatments = classifier.treatments(inSegment: rawDesc)

        let substrateDisplay: String
        if let material {
            let oriPart = orientation.map { "(\($0))" } ?? ""
            let treatPart = treatments.isEmpty ? "" : " " + treatments.joined(separator: "+")
            substrateDisplay = "\(material)\(oriPart)\(treatPart)".trimmingCharacters(in: .whitespacesAndNewlines)
        } else if !rawDesc.isEmpty {
            substrateDisplay = rawDesc
        } else {
            substrateDisplay = substrateIdentity
        }

        // 6. Stable identity generation:
        // Decoupled from display name and filesystem path. Determined once at creation.
        let sampleUID = "smp_" + UUID().uuidString.lowercased()
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))

        let userDisplayName = (draft.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDisplayName: String
        if !userDisplayName.isEmpty {
            finalDisplayName = userDisplayName
        } else if substrateDisplay != substrateIdentity && !substrateDisplay.isEmpty {
            finalDisplayName = "\(canonicalBatchId) - \(substrateDisplay) (\(substrateIdentity))"
        } else {
            finalDisplayName = "\(canonicalBatchId) - \(substrateIdentity)"
        }

        let sample = LibrarySample(
            id: sampleId,
            displayName: finalDisplayName,
            batchId: canonicalBatchId,
            substrateRaw: rawDesc,
            substrateDisplay: substrateDisplay,
            substrateTokens: classifier.treatments(inSegment: rawDesc) + [substrateIdentity.lowercased()],
            substrateTags: [substrateIdentity],
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
            legacySampleKey: sampleId,
            substrateIdentity: substrateIdentity,
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
        let batchExistedBefore = preferredExistedBefore || legacyExistedBefore

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
                    if diskSample.id.caseInsensitiveCompare(sampleId) == .orderedSame &&
                       (diskSample.substrateIdentity == nil || diskSample.substrateIdentity?.caseInsensitiveCompare(substrateIdentity) == .orderedSame) {
                        return .failure(error: .duplicateSample(sampleId: sampleId, substrateIdentity: substrateIdentity, batchId: canonicalBatchId))
                    } else {
                        return .failure(error: .directoryCollision(
                            "Sample directory '\(sampleURL.lastPathComponent)' already exists on disk and belongs to sample ID '\(diskSample.id)' (substrate '\(diskSample.substrateIdentity ?? "")')."
                        ))
                    }
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
        // and expected parent directories, and that no symbolic links exist that could bypass boundary checks.
        let batchesURL = libraryStore.batchesDirectoryURL(rootURL)
        guard libraryStore.isPathContained(batchesURL, within: rootURL) else {
            return .failure(error: .pathContainmentViolation("Batches directory '\(batchesURL.path)' escapes library root '\(rootURL.path)'."))
        }

        guard libraryStore.isPathContained(prefixURL, within: batchesURL) else {
            return .failure(error: .pathContainmentViolation("Batch prefix directory '\(prefixURL.path)' escapes batches directory '\(batchesURL.path)'."))
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

        if libraryStore.containsSymbolicLink(batchURL, relativeTo: rootURL) {
            return .failure(error: .pathContainmentViolation("Batch directory '\(batchURL.path)' contains or traverses a symbolic link."))
        }
        if libraryStore.containsSymbolicLink(sampleURL, relativeTo: rootURL) {
            return .failure(error: .pathContainmentViolation("Sample directory '\(sampleURL.path)' contains or traverses a symbolic link."))
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
                if !prefixExistedBefore && fileManager.fileExists(atPath: prefixURL.path) {
                    if libraryStore.isPathContained(prefixURL, within: rootURL) {
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

    /// Validates that an input path component (such as batchId or substrateIdentity) does not contain
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
