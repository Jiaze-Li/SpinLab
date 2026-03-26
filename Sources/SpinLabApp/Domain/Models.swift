import Foundation

enum SpinLabDomain { }

extension SpinLabDomain {
    enum RoutingScopeMode: String, Codable, Hashable {
        case fileLevel = "file-level"
        case channelLevel = "channel-level"
    }

    enum RouteStatus: String, Codable, Hashable, CaseIterable, Identifiable {
        case libraryMatched = "library-matched"
        case reviewRequired = "review-required"

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .libraryMatched:
                return "Library Matched"
            case .reviewRequired:
                return "Review Required"
            }
        }
    }

    enum RoutingWarningReason: String, Codable, Hashable {
        case channelSampleSignalWithoutToken = "channel-sample-signal-without-token"
        case noMatchingLibraryDrawer = "no-matching-library-drawer"
        case upstreamResolutionWarning = "upstream-resolution-warning"
    }

    struct RouteChannelResolution: Codable, Hashable {
        var channel: String
        var sampleKey: String?
        var source: String
        var tags: [String] = []
        var warning: String?
        var warningReason: RoutingWarningReason? = nil
    }

    struct RouteTarget: Codable, Hashable, Identifiable {
        var id: String { sampleKey }
        var sampleKey: String
        var channels: [String] = []
    }

    struct RoutePlan: Codable, Hashable {
        var planningStatus: RouteStatus = .reviewRequired
        var targets: [RouteTarget] = []
        var channelResolutions: [RouteChannelResolution] = []
        var unresolvedChannels: [String] = []
        var conflicts: [String] = []

        @available(*, deprecated, message: "Use planningStatus. Final business state should come from PendingRoutingSnapshot.verdict.")
        var status: RouteStatus {
            get { planningStatus }
            set { planningStatus = newValue }
        }

        enum CodingKeys: String, CodingKey {
            case planningStatus
            case status
            case targets
            case channelResolutions
            case unresolvedChannels
            case conflicts
        }

        init(
            planningStatus: RouteStatus = .reviewRequired,
            targets: [RouteTarget] = [],
            channelResolutions: [RouteChannelResolution] = [],
            unresolvedChannels: [String] = [],
            conflicts: [String] = []
        ) {
            self.planningStatus = planningStatus
            self.targets = targets
            self.channelResolutions = channelResolutions
            self.unresolvedChannels = unresolvedChannels
            self.conflicts = conflicts
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            planningStatus = try container.decodeIfPresent(RouteStatus.self, forKey: .planningStatus)
                ?? container.decodeIfPresent(RouteStatus.self, forKey: .status)
                ?? .reviewRequired
            targets = try container.decodeIfPresent([RouteTarget].self, forKey: .targets) ?? []
            channelResolutions = try container.decodeIfPresent([RouteChannelResolution].self, forKey: .channelResolutions) ?? []
            unresolvedChannels = try container.decodeIfPresent([String].self, forKey: .unresolvedChannels) ?? []
            conflicts = try container.decodeIfPresent([String].self, forKey: .conflicts) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(planningStatus, forKey: .planningStatus)
            try container.encode(targets, forKey: .targets)
            try container.encode(channelResolutions, forKey: .channelResolutions)
            try container.encode(unresolvedChannels, forKey: .unresolvedChannels)
            try container.encode(conflicts, forKey: .conflicts)
        }
    }

    struct RoutingScopeEvaluation: Codable, Hashable, Identifiable {
        var id: String { scope }
        var scope: String
        var sampleKey: String?
        var matchedDrawer: String?
        var tags: [String] = []
        var warning: String?
        var warningReason: RoutingWarningReason? = nil

        var isMatched: Bool {
            matchedDrawer != nil
        }
    }

    struct PendingRoutingSnapshot: Codable, Hashable {
        var mode: RoutingScopeMode
        var verdict: RouteStatus
        var scopes: [RoutingScopeEvaluation] = []
        var unresolvedScopes: [String] = []
        var conflicts: [String] = []
        var routePlan: RoutePlan
    }

    struct ParsedChannelHint: Codable, Hashable, Identifiable {
        var id: String { channel }
        var channel: String
        var sampleID: String?
        var tags: [String] = []
        var testInfoTags: [String] = []
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
        var defaultSampleKey: String?
        var folderDerivedSampleKeys: [String] = []
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
