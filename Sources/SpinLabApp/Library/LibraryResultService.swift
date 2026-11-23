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
        }
    }
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

    /// Sets (`newValue`) or clears (`nil`) one Sample's value for one Definition.
    /// `expectedCurrent` is the value the user saw; if the disk differs the write is refused as stale.
    /// Touches nothing but that Sample's `results`; no Registry/XLSX write.
    @discardableResult
    func setValue(
        sample: LibrarySample,
        definitionID: String,
        newValue: Double?,
        expectedCurrent: Double?,
        now: Date = Date(),
        rootURL: URL
    ) throws -> LibrarySample {
        if let newValue, !newValue.isFinite { throw LibraryResultError.invalidValue }
        let catalog = try requireCatalog(rootURL: rootURL)
        guard catalog.definitions.contains(where: { $0.definitionID == definitionID }) else {
            throw LibraryResultError.unknownDefinition(definitionID)
        }
        let sampleURL = libraryStore.sampleDirectoryURL(rootURL, batchID: sample.batchId, sampleKey: sample.id)
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
