import Foundation

enum SpinLabDomain { }

extension SpinLabDomain {
    struct ParsedChannelHint: Codable, Hashable, Identifiable {
        var id: String { channel }
        var channel: String
        var sampleID: String?
        var tags: [String] = []
    }

    enum WorkflowKind: String, Codable, CaseIterable, Hashable, Identifiable {
        case amrPhe = "AMR/PHE"

        var id: String { rawValue }
    }

    enum MeasurementType: String, Codable, CaseIterable, Hashable, Identifiable {
        case amrPhe = "AMR/PHE"

        var id: String { rawValue }
    }

    enum PendingImportStatus: String, Codable, CaseIterable, Hashable, Identifiable {
        case imported = "Imported"
        case needsConfirmation = "Needs Confirmation"

        var id: String { rawValue }
    }

    struct ParsedFilenameHints: Codable, Hashable {
        var batchName: String?
        var sampleName: String?
        var measurementName: String?
        var deviceName: String?
        var workflowName: String?
        var sampleIDs: [String] = []
        var channelHints: [ParsedChannelHint] = []
        var measurementTags: [String] = []
        var substrateTags: [String] = []
        var temperature: String?
        var growthTemperature: String?
        var current: String?
        var field: String?
        var rotationHint: String?
        var warnings: [String] = []
    }

    struct Project: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var name: String
        var sampleIDs: [UUID] = []
    }

    struct Batch: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var name: String
        var notes: String = ""
    }

    struct Sample: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var name: String
        var projectIDs: [UUID] = []
        var notes: String = ""
    }

    struct Device: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var sampleID: UUID
        var name: String
        var notes: String = ""
    }

    struct Measurement: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var name: String
        var measurementType: MeasurementType = .amrPhe
        var sampleID: UUID
        var batchID: UUID?
        var deviceID: UUID?
        var sourceFilePath: String
        var originalFilePath: String?
        var acquiredAt: Date?
        var notes: String = ""
    }

    struct PlotSeries: Codable, Hashable, Identifiable {
        var id: UUID = UUID()
        var name: String
        var points: [PlotPoint]
    }

    struct PlotPoint: Codable, Hashable, Identifiable {
        var id: UUID = UUID()
        var x: Double
        var y: Double
    }

    struct Dataset: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var measurementID: UUID
        var sourceFilePath: String
        var originalFilePath: String?
        var columns: [String]
        var series: [PlotSeries]
    }

    struct Result: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var measurementID: UUID
        var summary: String
        var rating: Int?
        var updatedAt: Date = .now
    }

    struct Comparison: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var leftMeasurementID: UUID
        var rightMeasurementID: UUID
        var notes: String = ""
    }

    struct PendingImport: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var workflow: WorkflowKind = .amrPhe
        var fileName: String
        var sourceFilePath: String
        var originalFilePath: String?
        var importedAt: Date = .now
        var status: PendingImportStatus = .needsConfirmation
        var parsedHints: ParsedFilenameHints
    }

    struct ArchivedRecord: Identifiable, Codable, Hashable {
        var id: UUID = UUID()
        var workflow: WorkflowKind = .amrPhe
        var archivedAt: Date = .now
        var project: Project?
        var batch: Batch?
        var sample: Sample
        var device: Device?
        var measurement: Measurement
        var dataset: Dataset
        var latestResult: Result?
    }
}
