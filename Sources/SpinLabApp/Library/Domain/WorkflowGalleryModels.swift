import Foundation

/// Status of a gallery asset on disk (image or manifest).
enum WorkflowGalleryAssetStatus: String, Sendable, Codable, Hashable {
    case available
    case missingFile
    case unreadable
}

/// Classifies and maps workflows using the application's Single Source of Truth
/// (`[WorkflowDefinition]` from `workflow.json` / `WorkflowDefinitionStore`).
///
/// Does NOT maintain a duplicate registry of workflows.
enum WorkflowClassifier {
    /// Maps a raw workflow string (e.g. from results_index or manifest) to a canonical definition ID.
    /// Uses case-insensitive comparison against active Rule Book definitions, matching either
    /// `definition.id` or `definition.displayName`.
    static func canonicalID(for raw: String?, definitions: [WorkflowDefinition]) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "unknown"
        }

        // Match case-insensitively against active Rule Book definitions
        if let match = definitions.first(where: {
            $0.id.caseInsensitiveCompare(trimmed) == .orderedSame ||
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return match.id
        }

        // Documented historical convention: "3ω" symbol maps to canonical "3w"
        if trimmed == "3ω" || trimmed == "3W" {
            if let threeOmegaDef = definitions.first(where: { $0.id.caseInsensitiveCompare(WorkflowKey.threeOmega.rawValue) == .orderedSame }) {
                return threeOmegaDef.id
            }
            return WorkflowKey.threeOmega.rawValue
        }

        // If not found in definitions, fallback to the raw trimmed identifier (never discard)
        return trimmed
    }

    /// User-facing display name for a workflow ID, derived directly from `[WorkflowDefinition]`.
    static func displayName(for workflowID: String, definitions: [WorkflowDefinition]) -> String {
        let canonical = canonicalID(for: workflowID, definitions: definitions)

        if let def = definitions.first(where: { $0.id.caseInsensitiveCompare(canonical) == .orderedSame }),
           !def.displayName.isEmpty {
            // Documented SpinLab typography standard: "3w" displays as "3ω" in UI
            if def.id.caseInsensitiveCompare(WorkflowKey.threeOmega.rawValue) == .orderedSame {
                return "3ω"
            }
            return def.displayName
        }

        if canonical.caseInsensitiveCompare(WorkflowKey.threeOmega.rawValue) == .orderedSame {
            return "3ω"
        }

        return canonical
    }
}

/// Unified, read-only representation of a saved chart in the Workflow Gallery.
struct WorkflowGalleryItem: Identifiable, Hashable, Sendable {
    var id: String { chartIdentityKey }

    /// Primary identity key from results_index.json.
    var chartIdentityKey: String

    /// Relative image path from Library root (e.g. `samples/PN104/charts/foo.png` or `_spinlab/multi-sample/charts/bar.png`).
    var chartImagePath: String

    /// Relative manifest path from Library root.
    var manifestPath: String

    /// Canonical workflow ID from Rule Book definitions (e.g. "3w", "ahe", "RT", "XY", "IV", "afm", "rsm").
    var canonicalWorkflowID: String

    /// Raw workflow ID as stored in results_index.json or manifest.
    var rawWorkflowID: String

    /// Creation/generation timestamp.
    var generatedAt: Date

    /// Tab or analysis sub-type key (e.g. "fieldSweep3omega", "rahe3omegaVsT", "rtCurve", "scaling").
    var tabKey: String?

    /// All sample keys associated with this chart (deduplicated, sorted).
    var associatedSampleKeys: [String]

    /// True if the chart compares multiple samples or resides in the multi-sample store.
    var isMultiSample: Bool

    /// Status of the PNG image on disk (.available, .missingFile, .unreadable).
    var imageStatus: WorkflowGalleryAssetStatus

    /// Status of the .manifest.json on disk (.available, .missingFile, .unreadable).
    var manifestStatus: WorkflowGalleryAssetStatus

    /// True if at least one sample's `measurement_plot_index.json` links to this chart identity.
    var hasMeasurementAssociation: Bool

    /// Sanitized human-readable title extracted from chart filename or tab key.
    var displayTitle: String

    init(
        chartIdentityKey: String,
        chartImagePath: String,
        manifestPath: String,
        canonicalWorkflowID: String,
        rawWorkflowID: String,
        generatedAt: Date,
        tabKey: String?,
        associatedSampleKeys: [String],
        isMultiSample: Bool,
        imageStatus: WorkflowGalleryAssetStatus,
        manifestStatus: WorkflowGalleryAssetStatus,
        hasMeasurementAssociation: Bool,
        displayTitle: String
    ) {
        self.chartIdentityKey = chartIdentityKey
        self.chartImagePath = chartImagePath
        self.manifestPath = manifestPath
        self.canonicalWorkflowID = canonicalWorkflowID
        self.rawWorkflowID = rawWorkflowID
        self.generatedAt = generatedAt
        self.tabKey = tabKey
        self.associatedSampleKeys = associatedSampleKeys
        self.isMultiSample = isMultiSample
        self.imageStatus = imageStatus
        self.manifestStatus = manifestStatus
        self.hasMeasurementAssociation = hasMeasurementAssociation
        self.displayTitle = displayTitle
    }
}

/// Aggregated result of a Workflow Gallery scan.
struct WorkflowGalleryQueryResult: Sendable {
    var items: [WorkflowGalleryItem]
    var totalReferenceCount: Int
    var uniqueChartCount: Int
    var missingImageCount: Int
    var missingManifestCount: Int
    var unreadableSampleIndices: [String]
    var workflowCounts: [String: Int] // canonicalWorkflowID -> count

    init(
        items: [WorkflowGalleryItem] = [],
        totalReferenceCount: Int = 0,
        uniqueChartCount: Int = 0,
        missingImageCount: Int = 0,
        missingManifestCount: Int = 0,
        unreadableSampleIndices: [String] = [],
        workflowCounts: [String: Int] = [:]
    ) {
        self.items = items
        self.totalReferenceCount = totalReferenceCount
        self.uniqueChartCount = uniqueChartCount
        self.missingImageCount = missingImageCount
        self.missingManifestCount = missingManifestCount
        self.unreadableSampleIndices = unreadableSampleIndices
        self.workflowCounts = workflowCounts
    }
}
