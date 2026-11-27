import Foundation

/// Library-level Result slot. Meaning is entirely user-defined; the software never interprets
/// `qualifier` (e.g. "300 K", "30° device") as a verified measurement condition.
struct ResultDefinition: Codable, Hashable, Identifiable, Sendable {
    var definitionID: String
    var name: String
    var unit: String
    var qualifier: String

    var id: String { definitionID }

    /// "Rxx @ 300 K (Ω)" style label.
    var displayLabel: String {
        var label = name
        if !qualifier.isEmpty { label += " @ \(qualifier)" }
        if !unit.isEmpty { label += " (\(unit))" }
        return label
    }
}

/// One confirmed current value of a Sample for a Definition. Stored in that Sample's `sample.json`.
struct SampleResultValue: Codable, Hashable, Sendable {
    var value: Double
    var updatedAt: Date
}

struct ResultDefinitionCatalog: Codable, Equatable, Sendable {
    var version: Int = 1
    var definitions: [ResultDefinition] = []
}

enum ResultCatalogLoad: Equatable {
    /// File absent: no Definitions have been created yet.
    case missing
    case ok(ResultDefinitionCatalog)
    /// Present but unreadable/corrupt. Never treated as empty and never overwritten.
    case unreadable(String)
}

enum LibraryResultError: LocalizedError, Equatable {
    case catalogUnreadable(String)
    case invalidDefinition(String)
    case unknownDefinition(String)
    case invalidValue
    case sampleUnreadable(String)
    case staleValue
    case definitionInUse(count: Int)
    case usageUnknown(String)
    case similarDefinitionExists(String)
    case changeNeedsConfirmation(affectedSamples: Int)
    /// The Definition's unit or qualifier changed since the user saw it (Workbench assignment).
    case definitionChanged
    /// The target Sample is in the Trash.
    case sampleInTrash
    /// Library root, layout, write lease or session differs from what the user confirmed against.
    case libraryChanged(String)
    /// The Workbench input does not map to exactly one assignable Sample.
    case targetUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .catalogUnreadable(reason):
            return "Result Definitions file is unreadable; write refused: \(reason)"
        case let .invalidDefinition(reason):
            return reason
        case let .unknownDefinition(id):
            return "Result Definition not found: \(id)"
        case .invalidValue:
            return "Enter a finite number (NaN and infinity are not allowed)."
        case let .sampleUnreadable(reason):
            return "Sample record is unreadable; write refused: \(reason)"
        case .staleValue:
            return "This value was updated elsewhere. Refresh and try again."
        case let .definitionInUse(count):
            return "This Definition cannot be deleted because \(count) sample(s) have recorded values."
        case let .usageUnknown(reason):
            return "Cannot verify whether this Definition is in use; operation refused: \(reason)"
        case let .similarDefinitionExists(label):
            return "A similar Definition already exists: \(label)"
        case let .changeNeedsConfirmation(count):
            return "Changing the unit or qualifier alters the meaning of values on \(count) sample(s) and requires confirmation."
        case .definitionChanged:
            return "This Result Definition's unit or qualifier changed after you opened the panel. Please review and confirm again."
        case .sampleInTrash:
            return "The target Sample is in the Trash; nothing was written."
        case let .targetUnavailable(reason):
            return reason
        case let .libraryChanged(reason):
            return "The Library changed since you opened the panel (\(reason)). Nothing was written; please confirm again."
        }
    }
}

/// What the user confirmed against, re-checked against the disk immediately before a Workbench assignment
/// is written (Task 12, design §4). Manual entry passes no guard and behaves as before.
struct ResultWriteGuard: Equatable {
    /// Library root at confirmation time.
    var rootURL: URL
    /// `LibraryWriteLease.shared.sessionID` when the panel was opened.
    var leaseSessionID: String
    /// The Definition as the user saw it (unit and qualifier are compared; the name is not).
    var definition: ResultDefinition
    /// Batch of the target Sample, resolved from disk by the caller; must match the stored Sample.
    var targetBatchID: String
}

/// Single write authority for the Result Definition Catalog and Sample Result values.
/// Every operation re-reads the authoritative file from disk, so a stale in-memory copy can never
/// overwrite newer data. Writes go through `LibraryWriteLease` (read-only Library refuses).
struct LibraryResultService {
    static let catalogRelativePath = "_spinlab/result_definitions.json"

    let libraryStore: LibraryStore
    private let fileManager: FileManager

    init(libraryStore: LibraryStore, fileManager: FileManager = .default) {
        self.libraryStore = libraryStore
        self.fileManager = fileManager
    }

    func catalogURL(_ rootURL: URL) -> URL {
        rootURL.appending(path: Self.catalogRelativePath)
    }

    // MARK: - Catalog

    func loadCatalog(rootURL: URL) -> ResultCatalogLoad {
        let url = catalogURL(rootURL)
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            let catalog = try Self.makeDecoder().decode(ResultDefinitionCatalog.self, from: data)
            var seen = Set<String>()
            for definition in catalog.definitions where !seen.insert(definition.definitionID).inserted {
                return .unreadable("duplicate definitionID \(definition.definitionID)")
            }
            return .ok(catalog)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    private func requireCatalog(rootURL: URL) throws -> ResultDefinitionCatalog {
        if case let .invalid(layoutError) = libraryStore.resolveLayout(at: rootURL) {
            throw layoutError
        }
        switch loadCatalog(rootURL: rootURL) {
        case .missing: return ResultDefinitionCatalog()
        case let .ok(catalog): return catalog
        case let .unreadable(reason): throw LibraryResultError.catalogUnreadable(reason)
        }
    }

    private func saveCatalog(_ catalog: ResultDefinitionCatalog, rootURL: URL) throws {
        let url = catalogURL(rootURL)
        try LibraryWriteLease.shared.ensureWritable(url)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try libraryStore.writeJSONChecked(catalog, to: url)
    }

    /// Creates a Definition. A name+qualifier that matches an existing one after ignoring case and spaces is
    /// refused with `similarDefinitionExists` unless `allowSimilar` is true (the user's final call).
    @discardableResult
    func createDefinition(
        name: String,
        unit: String,
        qualifier: String,
        allowSimilar: Bool = false,
        rootURL: URL
    ) throws -> ResultDefinition {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualifier = qualifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryResultError.invalidDefinition("Definition name cannot be empty.") }
        var catalog = try requireCatalog(rootURL: rootURL)
        if !allowSimilar,
           let similar = catalog.definitions.first(where: {
               Self.normalizedKey(name: $0.name, qualifier: $0.qualifier) == Self.normalizedKey(name: name, qualifier: qualifier)
           }) {
            throw LibraryResultError.similarDefinitionExists(similar.displayLabel)
        }
        var identifier = "rdef_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        while catalog.definitions.contains(where: { $0.definitionID == identifier }) {
            identifier = "rdef_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        let definition = ResultDefinition(definitionID: identifier, name: name, unit: unit, qualifier: qualifier)
        catalog.definitions.append(definition)
        try saveCatalog(catalog, rootURL: rootURL)
        return definition
    }

    /// Edits a Definition. Changing unit or qualifier of a Definition that already has values changes the
    /// meaning of those values, so it needs `confirmedMeaningChange`; nothing is converted or rewritten in Samples.
    @discardableResult
    func updateDefinition(
        definitionID: String,
        name: String,
        unit: String,
        qualifier: String,
        confirmedMeaningChange: Bool = false,
        rootURL: URL
    ) throws -> ResultDefinition {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let qualifier = qualifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LibraryResultError.invalidDefinition("Definition name cannot be empty.") }
        var catalog = try requireCatalog(rootURL: rootURL)
        guard let index = catalog.definitions.firstIndex(where: { $0.definitionID == definitionID }) else {
            throw LibraryResultError.unknownDefinition(definitionID)
        }
        let existing = catalog.definitions[index]
        let meaningChanged = existing.unit != unit || existing.qualifier != qualifier
        if meaningChanged && !confirmedMeaningChange {
            let used = try usageCount(definitionID: definitionID, rootURL: rootURL)
            if used > 0 { throw LibraryResultError.changeNeedsConfirmation(affectedSamples: used) }
        }
        catalog.definitions[index].name = name
        catalog.definitions[index].unit = unit
        catalog.definitions[index].qualifier = qualifier
        try saveCatalog(catalog, rootURL: rootURL)
        return catalog.definitions[index]
    }

    /// Only a Definition no Sample (including Trash) uses can be deleted. Any unreadable Sample refuses.
    func deleteDefinition(definitionID: String, rootURL: URL) throws {
        var catalog = try requireCatalog(rootURL: rootURL)
        guard catalog.definitions.contains(where: { $0.definitionID == definitionID }) else {
            throw LibraryResultError.unknownDefinition(definitionID)
        }
        let used = try usageCount(definitionID: definitionID, rootURL: rootURL)
        guard used == 0 else { throw LibraryResultError.definitionInUse(count: used) }
        catalog.definitions.removeAll { $0.definitionID == definitionID }
        try saveCatalog(catalog, rootURL: rootURL)
    }

    /// Number of Samples (active or Trash) that hold a value for this Definition, read from disk.
    func usageCount(definitionID: String, rootURL: URL) throws -> Int {
        try usageCounts(rootURL: rootURL)[definitionID] ?? 0
    }

    /// Per-Definition number of Samples holding a value, from one pass over the Sample files on disk.
    func usageCounts(rootURL: URL) throws -> [String: Int] {
        let scan = libraryStore.scanIndexFromFilesystem(rootURL: rootURL)
        guard scan.issues.isEmpty else {
            throw LibraryResultError.usageUnknown(scan.issues.joined(separator: "; "))
        }
        var counts: [String: Int] = [:]
        for sample in scan.index.samples {
            for key in (sample.results ?? [:]).keys { counts[key, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - Sample values

    /// Serialises the read-check-write section of every Sample value write in this process.
    private static let writeSerialisation = NSLock()

    /// Sets (`newValue`) or clears (`nil`) one Sample's value for one Definition.
    /// `expectedCurrent` is the value the user saw; if the disk differs the write is refused as stale.
    /// Touches nothing but that Sample's `results`; no Registry/XLSX write.
    /// With `writeGuard` (Workbench assignment) the confirmation context is re-verified first.
    @discardableResult
    func setValue(
        sample: LibrarySample,
        definitionID: String,
        newValue: Double?,
        expectedCurrent: Double?,
        now: Date = Date(),
        rootURL: URL,
        writeGuard: ResultWriteGuard? = nil
    ) throws -> LibrarySample {
        if let newValue, !newValue.isFinite { throw LibraryResultError.invalidValue }
        Self.writeSerialisation.lock()
        defer { Self.writeSerialisation.unlock() }

        if let writeGuard { try verifyContext(writeGuard, rootURL: rootURL) }
        let catalog = try requireCatalog(rootURL: rootURL)
        guard let definition = catalog.definitions.first(where: { $0.definitionID == definitionID }) else {
            throw LibraryResultError.unknownDefinition(definitionID)
        }
        if let writeGuard {
            guard writeGuard.definition.definitionID == definitionID,
                  definition.unit == writeGuard.definition.unit,
                  definition.qualifier == writeGuard.definition.qualifier
            else { throw LibraryResultError.definitionChanged }
        }
        let sampleURL = libraryStore.drawerRootURL(for: sample, rootURL: rootURL)
        let sampleJSONURL = sampleURL.appending(path: "sample.json")
        try LibraryWriteLease.shared.ensureWritable(sampleJSONURL)
        var disk: LibrarySample
        do {
            let data = try Data(contentsOf: sampleJSONURL)
            disk = try Self.makeDecoder().decode(LibrarySample.self, from: data)
        } catch {
            throw LibraryResultError.sampleUnreadable(error.localizedDescription)
        }
        guard disk.id == sample.id else { throw LibraryResultError.sampleUnreadable("sample id mismatch") }
        if let writeGuard {
            guard disk.deletedAt == nil else { throw LibraryResultError.sampleInTrash }
            guard disk.batchId == writeGuard.targetBatchID, !writeGuard.targetBatchID.isEmpty else {
                throw LibraryResultError.libraryChanged("target Sample identity")
            }
        }
        guard disk.results?[definitionID]?.value == expectedCurrent else { throw LibraryResultError.staleValue }

        var results = disk.results ?? [:]
        if let newValue {
            results[definitionID] = SampleResultValue(value: newValue, updatedAt: now)
        } else {
            results.removeValue(forKey: definitionID)
        }
        disk.results = results.isEmpty ? nil : results
        try libraryStore.writeJSONChecked(disk, to: sampleJSONURL)
        libraryStore.invalidateNodeCache(at: sampleURL)
        libraryStore.invalidateNodeCache(at: sampleURL.deletingLastPathComponent())
        return disk
    }

    /// Resolves the Sample a Workbench input belongs to by reading its formal V1 `sample.json` from disk
    /// (never the index cache): by `(batchID, sampleKey)` when the batch is known, otherwise by a unique `id`.
    /// Trash, missing, ambiguous or non-V1 layouts are refused; nothing is guessed from names or substrates.
    func resolveV1AssignmentTarget(batchID: String, sampleKey: String, rootURL: URL) throws -> LibrarySample {
        switch libraryStore.resolveLayout(at: rootURL) {
        case .v1: break
        case .v2:
            throw LibraryResultError.targetUnavailable("This Library's AHE inputs have not been migrated to standard data yet. Enter the value by hand in the Library.")
        case .uninitialized:
            throw LibraryResultError.targetUnavailable("The Library is not initialised.")
        case let .invalid(error):
            throw LibraryResultError.libraryChanged(error.localizedDescription)
        }
        let sample: LibrarySample
        if !batchID.isEmpty {
            let url = libraryStore.sampleDirectoryURL(rootURL, batchID: batchID, sampleKey: sampleKey).appending(path: "sample.json")
            guard fileManager.fileExists(atPath: url.path) else {
                throw LibraryResultError.targetUnavailable("No Sample for this measurement was found in the Library (\(batchID) / \(sampleKey)).")
            }
            do {
                sample = try Self.makeDecoder().decode(LibrarySample.self, from: Data(contentsOf: url))
            } catch {
                throw LibraryResultError.sampleUnreadable(error.localizedDescription)
            }
            guard sample.id == sampleKey, sample.batchId == batchID else {
                throw LibraryResultError.targetUnavailable("The Library Sample does not match the measurement source.")
            }
        } else {
            let scan = libraryStore.scanIndexFromFilesystem(rootURL: rootURL)
            guard scan.issues.isEmpty else { throw LibraryResultError.usageUnknown(scan.issues.joined(separator: "; ")) }
            let matches = scan.index.samples.filter { $0.id == sampleKey }
            guard matches.count == 1, let match = matches.first else {
                throw LibraryResultError.targetUnavailable(matches.isEmpty
                    ? "No Sample for this measurement was found in the Library."
                    : "Several Library Samples share this name, so the target cannot be determined.")
            }
            let url = libraryStore.drawerRootURL(for: match, rootURL: rootURL).appending(path: "sample.json")
            do {
                sample = try Self.makeDecoder().decode(LibrarySample.self, from: Data(contentsOf: url))
            } catch {
                throw LibraryResultError.sampleUnreadable(error.localizedDescription)
            }
            guard sample.id == sampleKey else {
                throw LibraryResultError.targetUnavailable("The Library Sample does not match the measurement source.")
            }
        }
        guard sample.deletedAt == nil else { throw LibraryResultError.sampleInTrash }
        return sample
    }

    /// Value currently stored for a Definition on the target Sample, read from disk (not the index cache).
    func currentValueOnDisk(sample: LibrarySample, definitionID: String, rootURL: URL) throws -> Double? {
        let url = libraryStore.drawerRootURL(for: sample, rootURL: rootURL).appending(path: "sample.json")
        do {
            let disk = try Self.makeDecoder().decode(LibrarySample.self, from: Data(contentsOf: url))
            return disk.results?[definitionID]?.value
        } catch {
            throw LibraryResultError.sampleUnreadable(error.localizedDescription)
        }
    }

    /// Re-checks, against the live process and disk, that the Library the user confirmed is still the one open:
    /// same root, an explicit V1 layout, this process really holds the write lease, and it is the same open session.
    private func verifyContext(_ writeGuard: ResultWriteGuard, rootURL: URL) throws {
        guard LibraryWriteLease.canonicalPath(of: rootURL) == LibraryWriteLease.canonicalPath(of: writeGuard.rootURL) else {
            throw LibraryResultError.libraryChanged("different Library")
        }
        guard LibraryWriteLease.shared.holdsWritableLease(for: rootURL) else {
            throw LibraryResultError.libraryChanged("this window does not hold the write lease")
        }
        guard let session = LibraryWriteLease.shared.sessionID, session == writeGuard.leaseSessionID else {
            throw LibraryResultError.libraryChanged("the Library was reopened")
        }
        guard libraryStore.resolveLayout(at: rootURL) == .v1 else {
            throw LibraryResultError.libraryChanged("Library layout is not a supported V1 layout")
        }
    }

    // MARK: - Helpers

    static func normalizedKey(name: String, qualifier: String) -> String {
        func squash(_ s: String) -> String {
            s.lowercased().filter { !$0.isWhitespace }
        }
        return squash(name) + "|" + squash(qualifier)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
