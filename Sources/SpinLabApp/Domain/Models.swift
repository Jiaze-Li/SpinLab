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
        case nameConflictInLibrary = "name-conflict-in-library"
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
        var nameConflictWarning: String?
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
        case threeOmegaAHE = "3w"
        case xyRotation = "XY Rotation"
        case dummy = "Dummy"

        var id: String { rawValue }
    }

    enum MeasurementType: String, Codable, CaseIterable, Hashable, Identifiable {
        case amrPhe = "AMR/PHE"
        case threeOmegaAHE = "3w"
        case xyRotation = "XY Rotation"
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
        var fileSampleKey: String?
        var folderDerivedSampleKeys: [String] = []
        var measurementName: String?
        var workflowID: String?
        var sampleIDs: [String] = []
        var channelHints: [ParsedChannelHint] = []
        var measurementTags: [String] = []
        var substrateTags: [String] = []
        var growthTemperature: String?
        /// All condition values keyed by definition ID (e.g. "temperature", "current", "field", "device").
        /// Custom conditions are stored here alongside built-in ones.
        var conditionValues: [String: String] = [:]
        var rotationHint: String?
        var warnings: [String] = []
        /// key → ruleRef string; consumed only by the sidecar write path (s3 §2.5). Not serialized.
        var hintSources: [String: String] = [:]

        // Named accessors for built-in condition fields (callsite convenience).
        var temperature: String? { conditionValues[ConditionFieldCatalog.temperatureID] }
        var current: String?     { conditionValues[ConditionFieldCatalog.currentID] }
        var field: String?       { conditionValues[ConditionFieldCatalog.fieldID] }
        var deviceName: String?  { conditionValues[ConditionFieldCatalog.deviceID] }

        init(
            batchName: String? = nil,
            sampleName: String? = nil,
            fileSampleKey: String? = nil,
            folderDerivedSampleKeys: [String] = [],
            measurementName: String? = nil,
            workflowID: String? = nil,
            sampleIDs: [String] = [],
            channelHints: [ParsedChannelHint] = [],
            measurementTags: [String] = [],
            substrateTags: [String] = [],
            growthTemperature: String? = nil,
            conditionValues: [String: String] = [:],
            rotationHint: String? = nil,
            warnings: [String] = [],
            hintSources: [String: String] = [:]
        ) {
            self.batchName = batchName
            self.sampleName = sampleName
            self.fileSampleKey = fileSampleKey
            self.folderDerivedSampleKeys = folderDerivedSampleKeys
            self.measurementName = measurementName
            self.workflowID = workflowID
            self.sampleIDs = sampleIDs
            self.channelHints = channelHints
            self.measurementTags = measurementTags
            self.substrateTags = substrateTags
            self.growthTemperature = growthTemperature
            self.conditionValues = conditionValues
            self.rotationHint = rotationHint
            self.warnings = warnings
            self.hintSources = hintSources
        }

        private enum CodingKeys: String, CodingKey {
            case batchName
            case sampleName
            case fileSampleKey
            case folderDerivedSampleKeys
            case measurementName
            case workflowID
            case workflowName
            case sampleIDs
            case channelHints
            case measurementTags
            case substrateTags
            case growthTemperature
            case conditionValues
            // Legacy decode keys
            case defaultSampleKey
            case deviceName
            case temperature
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
            fileSampleKey = try container.decodeIfPresent(String.self, forKey: .fileSampleKey)
                ?? container.decodeIfPresent(String.self, forKey: .defaultSampleKey)
            folderDerivedSampleKeys = try container.decodeIfPresent([String].self, forKey: .folderDerivedSampleKeys) ?? []
            measurementName = try container.decodeIfPresent(String.self, forKey: .measurementName)
            workflowID = try container.decodeIfPresent(String.self, forKey: .workflowID)
                ?? container.decodeIfPresent(String.self, forKey: .workflowName)
            sampleIDs = try container.decodeIfPresent([String].self, forKey: .sampleIDs) ?? []
            channelHints = try container.decodeIfPresent([ParsedChannelHint].self, forKey: .channelHints) ?? []
            measurementTags = try container.decodeIfPresent([String].self, forKey: .measurementTags) ?? []
            substrateTags = try container.decodeIfPresent([String].self, forKey: .substrateTags) ?? []
            growthTemperature = try container.decodeIfPresent(String.self, forKey: .growthTemperature)
            rotationHint = try container.decodeIfPresent(String.self, forKey: .rotationHint)
            warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
            // Decode conditionValues: new format first; fall back to migrating legacy named fields.
            if let cv = try container.decodeIfPresent([String: String].self, forKey: .conditionValues) {
                conditionValues = cv
            } else {
                var cv: [String: String] = [:]
                if let v = try container.decodeIfPresent(String.self, forKey: .temperature), !v.isEmpty {
                    cv[ConditionFieldCatalog.temperatureID] = v
                }
                if let v = try container.decodeIfPresent(String.self, forKey: .current), !v.isEmpty {
                    cv[ConditionFieldCatalog.currentID] = v
                }
                if let v = try container.decodeIfPresent(String.self, forKey: .field), !v.isEmpty {
                    cv[ConditionFieldCatalog.fieldID] = v
                }
                if let v = try container.decodeIfPresent(String.self, forKey: .deviceName), !v.isEmpty {
                    cv[ConditionFieldCatalog.deviceID] = v
                }
                let extra = try container.decodeIfPresent([String: String].self, forKey: .extraConditionValues) ?? [:]
                for (k, v) in extra where !k.isEmpty && !v.isEmpty {
                    if cv[k] == nil { cv[k] = v }
                }
                conditionValues = cv
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(batchName, forKey: .batchName)
            try container.encodeIfPresent(sampleName, forKey: .sampleName)
            try container.encodeIfPresent(fileSampleKey, forKey: .fileSampleKey)
            try container.encode(folderDerivedSampleKeys, forKey: .folderDerivedSampleKeys)
            try container.encodeIfPresent(measurementName, forKey: .measurementName)
            try container.encodeIfPresent(workflowID, forKey: .workflowID)
            try container.encode(sampleIDs, forKey: .sampleIDs)
            try container.encode(channelHints, forKey: .channelHints)
            try container.encode(measurementTags, forKey: .measurementTags)
            try container.encode(substrateTags, forKey: .substrateTags)
            try container.encodeIfPresent(growthTemperature, forKey: .growthTemperature)
            try container.encode(conditionValues, forKey: .conditionValues)
            try container.encodeIfPresent(rotationHint, forKey: .rotationHint)
            try container.encode(warnings, forKey: .warnings)
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
