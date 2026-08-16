import Foundation

private enum InteractionSnapshotSchema {
    static let currentVersion = 2
}

private struct InteractionSnapshotEnvelope: Codable {
    var schemaVersion: Int
    var snapshot: SpinLabInteractionSnapshot
}

enum InteractionSnapshotMigration {
    static func migrate(_ snapshot: SpinLabInteractionSnapshot, from schemaVersion: Int) -> SpinLabInteractionSnapshot {
        switch schemaVersion {
        case 0, 1:
            return migrateLegacyLibrarySelectionSplit(snapshot)
        case InteractionSnapshotSchema.currentVersion:
            return snapshot
        default:
            // Preserve forward compatibility: if a newer schema is somehow read by
            // this build, do not reinterpret state using an older migration rule.
            return snapshot
        }
    }

    private static func migrateLegacyLibrarySelectionSplit(
        _ snapshot: SpinLabInteractionSnapshot
    ) -> SpinLabInteractionSnapshot {
        var migrated = snapshot

        // Schema v0/v1 had one Library selection triple. The source marker defined
        // whether that triple belonged to Browser/Preview or Existing Drawer.
        // Schema v2 gives each surface independent ownership, so migrate both the
        // top-level snapshot and the nested LibraryInteractionState consistently.
        switch snapshot.libraryActiveSelectionSource {
        case .browser:
            migrated.libraryBrowserSelectedPrefix = snapshot.librarySelectedPrefix
            migrated.libraryBrowserSelectedBatchId = snapshot.librarySelectedBatchId
            migrated.libraryBrowserSelectedSampleId = snapshot.librarySelectedSampleId
            migrated.librarySelectedPrefix = nil
            migrated.librarySelectedBatchId = nil
            migrated.librarySelectedSampleId = nil

            migrated.libraryView.browserSelectedPrefix = snapshot.libraryView.selectedPrefix
            migrated.libraryView.browserSelectedBatchId = snapshot.libraryView.selectedBatchId
            migrated.libraryView.browserSelectedSampleId = snapshot.libraryView.selectedSampleId
            migrated.libraryView.selectedPrefix = nil
            migrated.libraryView.selectedBatchId = nil
            migrated.libraryView.selectedSampleId = nil

        case .drawer:
            // The legacy triple already has the drawer meaning in v2. Explicitly
            // clear browser state so stale in-memory values cannot be mistaken for
            // persisted browser ownership during restore.
            migrated.libraryBrowserSelectedPrefix = nil
            migrated.libraryBrowserSelectedBatchId = nil
            migrated.libraryBrowserSelectedSampleId = nil
            migrated.libraryView.browserSelectedPrefix = nil
            migrated.libraryView.browserSelectedBatchId = nil
            migrated.libraryView.browserSelectedSampleId = nil
        }

        return migrated
    }
}

protocol SpinLabPersistence {
    func loadPendingImports() -> [SpinLabDomain.PendingImport]
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport])
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord]
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord])
    func loadProjects() -> [SpinLabDomain.Project]
    func saveProjects(_ projects: [SpinLabDomain.Project])
    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot
    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot)
}

final class LocalJSONPersistence: SpinLabPersistence {
    private let fileManager = FileManager.default
    private let pendingImportsFileURL: URL
    private let archivedRecordsFileURL: URL
    private let projectsFileURL: URL
    private let interactionSnapshotFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        let spinLabURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        pendingImportsFileURL = spinLabURL.appending(path: "pending_imports.json")
        archivedRecordsFileURL = spinLabURL.appending(path: "archived_records.json")
        projectsFileURL = spinLabURL.appending(path: "projects.json")
        interactionSnapshotFileURL = spinLabURL.appending(path: "interaction_snapshot.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: spinLabURL, withIntermediateDirectories: true)
    }

    func loadPendingImports() -> [SpinLabDomain.PendingImport] {
        if let stored: [SpinLabDomain.PendingImport] = readJSON(from: pendingImportsFileURL) {
            return stored
        }

        let seeded = SampleData.pendingImports
        savePendingImports(seeded)
        return seeded
    }

    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) {
        writeJSON(imports, to: pendingImportsFileURL)
    }

    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] {
        if let stored: [SpinLabDomain.ArchivedRecord] = readJSON(from: archivedRecordsFileURL) {
            return stored
        }

        let seeded = SampleData.archivedRecords
        saveArchivedRecords(seeded)
        return seeded
    }

    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) {
        writeJSON(records, to: archivedRecordsFileURL)
    }

    func loadProjects() -> [SpinLabDomain.Project] {
        if let stored: [SpinLabDomain.Project] = readJSON(from: projectsFileURL) {
            return stored
        }

        let seeded = SampleData.projects
        saveProjects(seeded)
        return seeded
    }

    func saveProjects(_ projects: [SpinLabDomain.Project]) {
        writeJSON(projects, to: projectsFileURL)
    }

    func loadInteractionSnapshot() -> SpinLabInteractionSnapshot {
        guard fileManager.fileExists(atPath: interactionSnapshotFileURL.path),
              let data = try? Data(contentsOf: interactionSnapshotFileURL) else {
            return SpinLabInteractionSnapshot()
        }

        if let envelope = try? decoder.decode(InteractionSnapshotEnvelope.self, from: data) {
            return InteractionSnapshotMigration.migrate(envelope.snapshot, from: envelope.schemaVersion)
        }

        // Legacy compatibility: previously we stored the raw snapshot without envelope.
        if let legacySnapshot = try? decoder.decode(SpinLabInteractionSnapshot.self, from: data) {
            return InteractionSnapshotMigration.migrate(legacySnapshot, from: 0)
        }

        return SpinLabInteractionSnapshot()
    }

    func saveInteractionSnapshot(_ snapshot: SpinLabInteractionSnapshot) {
        writeJSON(
            InteractionSnapshotEnvelope(
                schemaVersion: InteractionSnapshotSchema.currentVersion,
                snapshot: snapshot
            ),
            to: interactionSnapshotFileURL
        )
    }

    private func readJSON<T: Decodable>(from fileURL: URL) -> T? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            AppLogger.shared.error(
                .system,
                "Failed to read JSON payload",
                metadata: [
                    "target": fileURL.lastPathComponent,
                    "reason": error.localizedDescription
                ]
            )
            return nil
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            AppLogger.shared.error(
                .system,
                "Failed to decode JSON payload",
                metadata: [
                    "target": fileURL.lastPathComponent,
                    "reason": error.localizedDescription
                ]
            )
            return nil
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to fileURL: URL) {
        guard let data = try? encoder.encode(value) else {
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            AppLogger.shared.error(
                .system,
                "Failed to persist JSON payload",
                metadata: [
                    "target": fileURL.lastPathComponent,
                    "reason": error.localizedDescription
                ]
            )
        }
    }
}

enum SampleData {
    static let projects: [SpinLabDomain.Project] = [
        SpinLabDomain.Project(name: "Spin Orbit Group")
    ]

    static let archivedRecords: [SpinLabDomain.ArchivedRecord] = {
        let project = projects[0]
        let batch = SpinLabDomain.Batch(name: "B2403")
        let sample = SpinLabDomain.Sample(name: "S12", projectIDs: [project.id])
        let device = SpinLabDomain.Device(sampleID: sample.id, name: "HallBar-45deg")
        let measurement = SpinLabDomain.Measurement(
            name: "AMR_PHE_scan_001",
            measurementType: .amrPhe,
            sampleID: sample.id,
            batchID: batch.id,
            deviceID: device.id,
            sourceFilePath: "/tmp/AMR_PHE_scan_001.csv",
            originalFilePath: "/tmp/AMR_PHE_scan_001.csv",
            acquiredAt: .now
        )
        let dataset = SpinLabDomain.Dataset(
            measurementID: measurement.id,
            sourceFilePath: measurement.sourceFilePath,
            originalFilePath: measurement.originalFilePath,
            columns: ["Field", "Rxx", "Rxy"],
            series: [
                SpinLabDomain.PlotSeries(
                    name: "Rxx",
                    points: [
                        SpinLabDomain.PlotPoint(x: -2.0, y: 10.2),
                        SpinLabDomain.PlotPoint(x: 0.0, y: 10.8),
                        SpinLabDomain.PlotPoint(x: 2.0, y: 11.0)
                    ]
                )
            ]
        )
        let result = SpinLabDomain.Result(
            measurementID: measurement.id,
            summary: "Placeholder AMR/PHE result for the archived record.",
            rating: 4
        )

        return [
            SpinLabDomain.ArchivedRecord(
                project: project,
                batch: batch,
                sample: sample,
                device: device,
                measurement: measurement,
                dataset: dataset,
                latestResult: result
            )
        ]
    }()

    static let pendingImports: [SpinLabDomain.PendingImport] = [
        SpinLabDomain.PendingImport(
            fileName: "B2404_S18_AMR_PHE_Device2.csv",
            sourceFilePath: "/tmp/B2404_S18_AMR_PHE_Device2.csv",
            originalFilePath: "/tmp/B2404_S18_AMR_PHE_Device2.csv",
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                batchName: "B2404",
                sampleName: "S18",
                measurementName: "AMR_PHE",
                conditionValues: ["device": "Device2"]
            )
        )
    ]
}
