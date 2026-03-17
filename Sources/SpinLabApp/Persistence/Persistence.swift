import Foundation

protocol SpinLabPersistence {
    func loadPendingImports() -> [SpinLabDomain.PendingImport]
    func savePendingImports(_ imports: [SpinLabDomain.PendingImport])
    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord]
    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord])
    func loadProjects() -> [SpinLabDomain.Project]
    func saveProjects(_ projects: [SpinLabDomain.Project])
}

final class LocalJSONPersistence: SpinLabPersistence {
    private let fileManager = FileManager.default
    private let pendingImportsFileURL: URL
    private let archivedRecordsFileURL: URL
    private let projectsFileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
        let spinLabURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        pendingImportsFileURL = spinLabURL.appending(path: "pending_imports.json")
        archivedRecordsFileURL = spinLabURL.appending(path: "archived_records.json")
        projectsFileURL = spinLabURL.appending(path: "projects.json")

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

    private func readJSON<T: Decodable>(from fileURL: URL) -> T? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? decoder.decode(T.self, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T, to fileURL: URL) {
        guard let data = try? encoder.encode(value) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}

final class LocalPersistenceStub: SpinLabPersistence {
    private var pendingImports: [SpinLabDomain.PendingImport]
    private var archivedRecords: [SpinLabDomain.ArchivedRecord]
    private var projects: [SpinLabDomain.Project]

    init(
        pendingImports: [SpinLabDomain.PendingImport] = SampleData.pendingImports,
        archivedRecords: [SpinLabDomain.ArchivedRecord] = SampleData.archivedRecords,
        projects: [SpinLabDomain.Project] = SampleData.projects
    ) {
        self.pendingImports = pendingImports
        self.archivedRecords = archivedRecords
        self.projects = projects
    }

    func loadPendingImports() -> [SpinLabDomain.PendingImport] {
        pendingImports
    }

    func savePendingImports(_ imports: [SpinLabDomain.PendingImport]) {
        pendingImports = imports
    }

    func loadArchivedRecords() -> [SpinLabDomain.ArchivedRecord] {
        archivedRecords
    }

    func saveArchivedRecords(_ records: [SpinLabDomain.ArchivedRecord]) {
        archivedRecords = records
    }

    func loadProjects() -> [SpinLabDomain.Project] {
        projects
    }

    func saveProjects(_ projects: [SpinLabDomain.Project]) {
        self.projects = projects
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
            sourceFilePath: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appending(path: "SpinLab/measurements/AMR_PHE_scan_001.csv").path ?? "/tmp/AMR_PHE_scan_001.csv",
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
            sourceFilePath: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appending(path: "SpinLab/measurements/B2404_S18_AMR_PHE_Device2.csv").path ?? "/tmp/B2404_S18_AMR_PHE_Device2.csv",
            originalFilePath: "/tmp/B2404_S18_AMR_PHE_Device2.csv",
            parsedHints: SpinLabDomain.ParsedFilenameHints(
                batchName: "B2404",
                sampleName: "S18",
                measurementName: "AMR_PHE",
                deviceName: "Device2"
            )
        )
    ]
}
