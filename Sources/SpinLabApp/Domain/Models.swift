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
        var sampleId: String?
        var source: String
        var tags: [String] = []
        var warning: String?
        var warningReason: RoutingWarningReason? = nil

        enum CodingKeys: String, CodingKey {
            case channel
            case sampleId
            case sampleKey
            case source
            case tags
            case warning
            case warningReason
        }

        init(
            channel: String,
            sampleId: String?,
            source: String,
            tags: [String] = [],
            warning: String? = nil,
            warningReason: RoutingWarningReason? = nil
        ) {
            self.channel = channel
            self.sampleId = sampleId
            self.source = source
            self.tags = tags
            self.warning = warning
            self.warningReason = warningReason
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            channel = try container.decode(String.self, forKey: .channel)
            sampleId = try container.decodeIfPresent(String.self, forKey: .sampleId)
                ?? container.decodeIfPresent(String.self, forKey: .sampleKey)
            source = try container.decode(String.self, forKey: .source)
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            warning = try container.decodeIfPresent(String.self, forKey: .warning)
            warningReason = try container.decodeIfPresent(RoutingWarningReason.self, forKey: .warningReason)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(channel, forKey: .channel)
            try container.encodeIfPresent(sampleId, forKey: .sampleId)
            try container.encode(source, forKey: .source)
            try container.encode(tags, forKey: .tags)
            try container.encodeIfPresent(warning, forKey: .warning)
            try container.encodeIfPresent(warningReason, forKey: .warningReason)
        }
    }

    struct RouteTarget: Codable, Hashable, Identifiable {
        var id: String { sampleId }
        var sampleId: String
        var channels: [String] = []

        enum CodingKeys: String, CodingKey {
            case sampleId
            case sampleKey
            case channels
        }

        init(sampleId: String, channels: [String] = []) {
            self.sampleId = sampleId
            self.channels = channels
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sampleId = try container.decodeIfPresent(String.self, forKey: .sampleId)
                ?? container.decode(String.self, forKey: .sampleKey)
            channels = try container.decodeIfPresent([String].self, forKey: .channels) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sampleId, forKey: .sampleId)
            try container.encode(channels, forKey: .channels)
        }
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
        var sampleId: String?
        var matchedDrawer: String?
        var tags: [String] = []
        var warning: String?
        var warningReason: RoutingWarningReason? = nil

        var isMatched: Bool {
            matchedDrawer != nil
        }

        enum CodingKeys: String, CodingKey {
            case scope
            case sampleId
            case sampleKey
            case matchedDrawer
            case tags
            case warning
            case warningReason
        }

        init(
            scope: String,
            sampleId: String?,
            matchedDrawer: String?,
            tags: [String] = [],
            warning: String? = nil,
            warningReason: RoutingWarningReason? = nil
        ) {
            self.scope = scope
            self.sampleId = sampleId
            self.matchedDrawer = matchedDrawer
            self.tags = tags
            self.warning = warning
            self.warningReason = warningReason
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            scope = try container.decode(String.self, forKey: .scope)
            sampleId = try container.decodeIfPresent(String.self, forKey: .sampleId)
                ?? container.decodeIfPresent(String.self, forKey: .sampleKey)
            matchedDrawer = try container.decodeIfPresent(String.self, forKey: .matchedDrawer)
            tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
            warning = try container.decodeIfPresent(String.self, forKey: .warning)
            warningReason = try container.decodeIfPresent(RoutingWarningReason.self, forKey: .warningReason)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(scope, forKey: .scope)
            try container.encodeIfPresent(sampleId, forKey: .sampleId)
            try container.encodeIfPresent(matchedDrawer, forKey: .matchedDrawer)
            try container.encode(tags, forKey: .tags)
            try container.encodeIfPresent(warning, forKey: .warning)
            try container.encodeIfPresent(warningReason, forKey: .warningReason)
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
        case dummy = "Dummy"

        var id: String { rawValue }
    }

    enum MeasurementType: String, Codable, CaseIterable, Hashable, Identifiable {
        case amrPhe = "AMR/PHE"
        case dummy = "Dummy"

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
        var extraConditionValues: [String: String] = [:]
        var rotationHint: String?
        var warnings: [String] = []

        init(
            batchName: String? = nil,
            sampleName: String? = nil,
            defaultSampleKey: String? = nil,
            folderDerivedSampleKeys: [String] = [],
            measurementName: String? = nil,
            deviceName: String? = nil,
            workflowName: String? = nil,
            sampleIDs: [String] = [],
            channelHints: [ParsedChannelHint] = [],
            measurementTags: [String] = [],
            substrateTags: [String] = [],
            temperature: String? = nil,
            growthTemperature: String? = nil,
            current: String? = nil,
            field: String? = nil,
            extraConditionValues: [String: String] = [:],
            rotationHint: String? = nil,
            warnings: [String] = []
        ) {
            self.batchName = batchName
            self.sampleName = sampleName
            self.defaultSampleKey = defaultSampleKey
            self.folderDerivedSampleKeys = folderDerivedSampleKeys
            self.measurementName = measurementName
            self.deviceName = deviceName
            self.workflowName = workflowName
            self.sampleIDs = sampleIDs
            self.channelHints = channelHints
            self.measurementTags = measurementTags
            self.substrateTags = substrateTags
            self.temperature = temperature
            self.growthTemperature = growthTemperature
            self.current = current
            self.field = field
            self.extraConditionValues = extraConditionValues
            self.rotationHint = rotationHint
            self.warnings = warnings
        }

        private enum CodingKeys: String, CodingKey {
            case batchName
            case sampleName
            case defaultSampleKey
            case folderDerivedSampleKeys
            case measurementName
            case deviceName
            case workflowName
            case sampleIDs
            case channelHints
            case measurementTags
            case substrateTags
            case temperature
            case growthTemperature
            case current
            case field
            case extraConditionValues
            case rotationHint
            case warnings
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            batchName = try container.decodeIfPresent(String.self, forKey: .batchName)
            sampleName = try container.decodeIfPresent(String.self, forKey: .sampleName)
            defaultSampleKey = try container.decodeIfPresent(String.self, forKey: .defaultSampleKey)
            folderDerivedSampleKeys = try container.decodeIfPresent([String].self, forKey: .folderDerivedSampleKeys) ?? []
            measurementName = try container.decodeIfPresent(String.self, forKey: .measurementName)
            deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
            workflowName = try container.decodeIfPresent(String.self, forKey: .workflowName)
            sampleIDs = try container.decodeIfPresent([String].self, forKey: .sampleIDs) ?? []
            channelHints = try container.decodeIfPresent([ParsedChannelHint].self, forKey: .channelHints) ?? []
            measurementTags = try container.decodeIfPresent([String].self, forKey: .measurementTags) ?? []
            substrateTags = try container.decodeIfPresent([String].self, forKey: .substrateTags) ?? []
            temperature = try container.decodeIfPresent(String.self, forKey: .temperature)
            growthTemperature = try container.decodeIfPresent(String.self, forKey: .growthTemperature)
            current = try container.decodeIfPresent(String.self, forKey: .current)
            field = try container.decodeIfPresent(String.self, forKey: .field)
            extraConditionValues = try container.decodeIfPresent([String: String].self, forKey: .extraConditionValues) ?? [:]
            rotationHint = try container.decodeIfPresent(String.self, forKey: .rotationHint)
            warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        }
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
