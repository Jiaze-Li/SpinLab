import Foundation
import Observation

/// In-memory vault for saved analysis packs, with optional disk persistence.
/// Owned by WorkbenchFeatureStore.
///
/// Persistence layout: `<libraryRoot>/_spinlab/analysis_packs/<workflowID>/<packID>.json`
@MainActor
@Observable
final class AnalysisVault {

    private(set) var packs: [AnalysisPack.ID: AnalysisPack] = [:]

    /// Root directory for pack files. Set via `configurePersistence(libraryRootPath:)`.
    @ObservationIgnored private var persistenceBaseURL: URL?

    @ObservationIgnored private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    @ObservationIgnored private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Persistence configuration

    /// Sets the library root and loads all packs from disk.
    /// Safe to call multiple times — skips reload if root hasn't changed.
    func configurePersistence(libraryRootPath: String) {
        let baseURL = URL(fileURLWithPath: libraryRootPath)
            .appendingPathComponent("_spinlab/analysis_packs", isDirectory: true)
        guard baseURL != persistenceBaseURL else { return }
        persistenceBaseURL = baseURL
        _loadAllFromDisk()
    }

    // MARK: - CRUD

    func add(_ pack: AnalysisPack) {
        packs[pack.id] = pack
        _writeToDisk(pack)
    }

    func remove(id: AnalysisPack.ID) {
        guard let pack = packs.removeValue(forKey: id) else { return }
        _deleteFromDisk(pack)
    }

    func update(_ pack: AnalysisPack) {
        guard packs[pack.id] != nil else { return }
        packs[pack.id] = pack
        _writeToDisk(pack)
    }

    func get(id: AnalysisPack.ID) -> AnalysisPack? {
        packs[id]
    }

    /// Finds a pack by source fingerprint within a workflow.
    func pack(forWorkflow wfID: String, fingerprint: String) -> AnalysisPack? {
        packs.values.first { $0.workflowID == wfID && $0.sourceFingerprint == fingerprint }
    }

    /// Returns packs for a given workflow, sorted by label.
    func packs(forWorkflow wfID: String) -> [AnalysisPack] {
        packs.values
            .filter { $0.workflowID == wfID }
            .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    // MARK: - Disk I/O (private)

    private func _fileURL(for pack: AnalysisPack) -> URL? {
        persistenceBaseURL?
            .appendingPathComponent(pack.workflowID, isDirectory: true)
            .appendingPathComponent("\(pack.id.uuidString).json")
    }

    private func _writeToDisk(_ pack: AnalysisPack) {
        guard let url = _fileURL(for: pack) else { return }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(pack)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[SpinLab][AnalysisVault] Write failed for \(pack.id): \(error)")
        }
    }

    private func _deleteFromDisk(_ pack: AnalysisPack) {
        guard let url = _fileURL(for: pack) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func _loadAllFromDisk() {
        guard let baseURL = persistenceBaseURL else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseURL.path) else { return }

        // Scan <baseURL>/<workflowID>/<packID>.json
        guard let workflowDirs = try? fm.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        var loaded: [AnalysisPack.ID: AnalysisPack] = [:]
        for wfDir in workflowDirs where wfDir.hasDirectoryPath {
            guard let files = try? fm.contentsOfDirectory(
                at: wfDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let pack = try? Self.decoder.decode(AnalysisPack.self, from: data) else {
                    print("[SpinLab][AnalysisVault] Failed to load: \(file.lastPathComponent)")
                    continue
                }
                loaded[pack.id] = pack
            }
        }
        packs = loaded
    }
}
