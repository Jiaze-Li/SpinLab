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
    case writeFailed(String)
    case indexSyncFailed(String)

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
        case let .writeFailed(reason):
            return "Failed to save sample: \(reason)"
        case let .indexSyncFailed(reason):
            return "Sample was saved but index could not be updated: \(reason)"
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

        // 2. Validate input fields.
        let inputBatchId = draft.batchId.trimmingCharacters(in: .whitespacesAndNewlines)
        let substrateIdentity = draft.substrateIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inputBatchId.isEmpty else {
            return .failure(error: .invalidInput("Batch ID cannot be empty."))
        }
        guard !substrateIdentity.isEmpty else {
            return .failure(error: .invalidInput("Substrate identity cannot be empty."))
        }

        // 3. Resolve canonical Batch ID casing.
        // If an existing batch matches case-insensitively, adopt its canonical casing to prevent duplicate folders.
        let canonicalBatchId: String
        let existingBatchMatch = completeIndex.batches.first { $0.id.caseInsensitiveCompare(inputBatchId) == .orderedSame }
        if let existingBatchMatch {
            canonicalBatchId = existingBatchMatch.id
        } else {
            canonicalBatchId = inputBatchId
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
            // Case A: Sample has explicit substrateIdentity
            if let existingSubId = existing.substrateIdentity?.trimmingCharacters(in: .whitespacesAndNewlines), !existingSubId.isEmpty {
                if existingSubId.caseInsensitiveCompare(normalizedSubstrate) == .orderedSame {
                    return .failure(error: .duplicateSample(
                        sampleId: existing.id,
                        substrateIdentity: substrateIdentity,
                        batchId: canonicalBatchId
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
        let batchURL = libraryStore.resolvedBatchDirectoryURL(rootURL, batchID: canonicalBatchId)
        let preferredBatchURL = libraryStore.preferredBatchDirectoryURL(rootURL, batchID: canonicalBatchId)
        let legacyBatchURL = libraryStore.legacyBatchDirectoryURL(rootURL, batchID: canonicalBatchId)
        let preferredExistedBefore = FileManager.default.fileExists(atPath: preferredBatchURL.path)
        let legacyExistedBefore = FileManager.default.fileExists(atPath: legacyBatchURL.path)
        let batchExistedBefore = preferredExistedBefore || legacyExistedBefore

        let batchJSONURL = batchURL.appending(path: "batch.json")
        let originalBatchData: Data? = try? Data(contentsOf: batchJSONURL)

        let prefixURL = batchURL.deletingLastPathComponent()
        let prefixExistedBefore = FileManager.default.fileExists(atPath: prefixURL.path)

        let samplesDir = batchURL.appending(path: "samples", directoryHint: .isDirectory)
        let samplesDirExistedBefore = FileManager.default.fileExists(atPath: samplesDir.path)

        let sampleURL = libraryStore.sampleDirectoryURL(rootURL, batchID: canonicalBatchId, sampleKey: sampleId)
        let sampleExistedBefore = FileManager.default.fileExists(atPath: sampleURL.path)
        if sampleExistedBefore {
            let sampleJSON = sampleURL.appending(path: "sample.json")
            if FileManager.default.fileExists(atPath: sampleJSON.path) {
                return .failure(error: .duplicateSample(sampleId: sampleId, substrateIdentity: substrateIdentity, batchId: canonicalBatchId))
            }
        }

        // Snapshot index state before any mutation:
        let indexURL = libraryStore.indexFileURL(rootURL)
        let indexExistedBefore = FileManager.default.fileExists(atPath: indexURL.path)
        let originalIndexData: Data? = indexExistedBefore ? (try? Data(contentsOf: indexURL)) : nil

        func rollbackCreatedState() {
            // 1. Roll back sample drawer
            if !sampleExistedBefore {
                try? FileManager.default.removeItem(at: sampleURL)
            }
            if !samplesDirExistedBefore {
                let remaining = (try? FileManager.default.contentsOfDirectory(atPath: samplesDir.path)) ?? []
                if remaining.isEmpty {
                    try? FileManager.default.removeItem(at: samplesDir)
                }
            }

            // 2. Roll back batch state
            if !batchExistedBefore {
                try? FileManager.default.removeItem(at: batchURL)
                if !prefixExistedBefore {
                    let remaining = (try? FileManager.default.contentsOfDirectory(atPath: prefixURL.path)) ?? []
                    if remaining.isEmpty {
                        try? FileManager.default.removeItem(at: prefixURL)
                    }
                }
            } else if let originalBatchData {
                // Batch already existed: ONLY restore batch.json, NEVER delete the batch directory or any other samples/measurements/plots
                try? originalBatchData.write(to: batchJSONURL, options: .atomic)
            }

            // 3. Roll back LibraryIndex
            if indexExistedBefore {
                if let originalIndexData {
                    try? originalIndexData.write(to: indexURL, options: .atomic)
                }
            } else {
                try? FileManager.default.removeItem(at: indexURL)
            }

            // Invalidate caches
            libraryStore.invalidateNodeCache(at: sampleURL)
            libraryStore.invalidateNodeCache(at: batchURL)
            libraryStore.invalidateNodeCache(at: libraryStore.indexDirectoryURL(rootURL))
        }

        do {
            try libraryStore.createDrawer(for: sample, batch: batch, rootURL: rootURL)
        } catch {
            rollbackCreatedState()
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
            rollbackCreatedState()
            return .failure(error: .indexSyncFailed(error.localizedDescription))
        }

        return .success(sample: sample, batch: batch, syncedIndex: syncedIndex)
    }
}
