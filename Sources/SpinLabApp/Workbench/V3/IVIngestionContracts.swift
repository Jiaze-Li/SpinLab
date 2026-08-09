import Foundation

// MARK: - IV Signal Component

enum IVSignalComponent: String, Codable, Hashable, Sendable, CaseIterable {
    case x = "X"
    case y = "Y"
}

// MARK: - IV Current Basis

enum IVCurrentBasis: String, Codable, Hashable, Sendable, CaseIterable {
    case peak
    case rms

    var displayName: String {
        switch self {
        case .peak: return "Peak"
        case .rms: return "RMS"
        }
    }

    /// Multiplier that converts raw `current_A` to displayed current in mA.
    var scaleFactor: Double {
        switch self {
        case .peak: return 1000.0
        case .rms: return 1000.0 / sqrt(2.0)
        }
    }

    /// Current axis label — single source of truth is `WorkbenchPlotDisplayVocabulary`.
    /// Uses `plotLabel` because this is compared against the axis text actually rendered
    /// on the chart (see `matchesAutoAxisLabel`), not manifest/log text.
    var axisLabel: String {
        WorkbenchPlotDisplayVocabulary.plotLabel(for: .current, currentBasis: workbenchCurrentBasis)
    }

    /// Pre-migration axis-label text (unit was "A", not "mA"). Kept only to detect and
    /// migrate old pack overrides stored before that unit change — not a vocabulary duplicate.
    var legacyAxisLabel: String {
        switch self {
        case .peak: return "Current (A, peak)"
        case .rms: return "Current (A, RMS)"
        }
    }

    var autoAxisLabels: Set<String> {
        [axisLabel, legacyAxisLabel]
    }

    func matchesAutoAxisLabel(_ label: String) -> Bool {
        autoAxisLabels.contains(label)
    }

    var workbenchCurrentBasis: WorkbenchCurrentBasis {
        switch self {
        case .peak: return .peak
        case .rms: return .rms
        }
    }
}

// MARK: - IV Channel State

/// Auto-detected dominant component for one lock-in channel.
struct IVChannelState: Codable, Hashable, Sendable {
    /// Auto-detected component (larger median |signal|).
    var autoComponent: IVSignalComponent
    /// Ratio max(scoreX, scoreY) / min(scoreX, scoreY). 1.0 when indeterminate.
    var confidence: Double

    init(autoComponent: IVSignalComponent = .x, confidence: Double = 1.0) {
        self.autoComponent = autoComponent
        self.confidence = confidence
    }
}

// MARK: - IV Raw Sweep

/// Raw data from one IV measurement file.
/// All channel data preserved; component selection is deferred to the store.
struct IVSweep: Codable, Hashable, Sendable, Identifiable {
    var id: String {
        let path = measurementFilePath ?? ""
        return path.isEmpty ? stem : path
    }

    var stem: String
    var temperatureK: Double
    var fieldT: Double

    // Column 0: Peak current (A)
    var current: [Double]

    // Channel 1: columns 1 (1st X), 2 (1st Y)
    var ch1X: [Double]
    var ch1Y: [Double]

    // Channel 2: columns 5 (2nd X), 6 (2nd Y)
    var ch2X: [Double]
    var ch2Y: [Double]

    // Raw audit/reference columns from the LVM export.
    var firstR: [Double]?
    var firstTheta: [Double]?
    var secondR: [Double]?
    var secondTheta: [Double]?
    var firstRH: [Double]?
    var frequencyAfter: [Double]?

    var measurementFilePath: String?

    /// Metadata carried from search hit for legend resolution.
    var sampleMetadata: [String: String]?

    /// The originating `WorkflowMeasurementSearchHit.id` (sidecarPath), carried through so the
    /// rendered series can be looked up directly from Selected-hits state without fuzzy matching.
    /// Optional so legacy packs without this field decode safely.
    var sourceHitID: String? = nil
}

// MARK: - IV Ingestion Result

struct IVIngestionResult: Codable, Hashable, Sendable {
    var sweeps: [IVSweep] = []
    var device: String = ""
    var warnings: [String] = []

    /// Auto-detected channel states, computed during ingestion.
    var ch1State: IVChannelState = IVChannelState()
    var ch2State: IVChannelState = IVChannelState()

    init(sweeps: [IVSweep] = [],
         device: String = "",
         warnings: [String] = [],
         ch1State: IVChannelState = IVChannelState(),
         ch2State: IVChannelState = IVChannelState()) {
        self.sweeps = sweeps
        self.device = device
        self.warnings = warnings
        self.ch1State = ch1State
        self.ch2State = ch2State
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sweeps   = try c.decodeIfPresent([IVSweep].self,       forKey: .sweeps)   ?? []
        device   = try c.decodeIfPresent(String.self,          forKey: .device)   ?? ""
        warnings = try c.decodeIfPresent([String].self,        forKey: .warnings) ?? []
        ch1State = try c.decodeIfPresent(IVChannelState.self,  forKey: .ch1State) ?? IVChannelState()
        ch2State = try c.decodeIfPresent(IVChannelState.self,  forKey: .ch2State) ?? IVChannelState()
    }
}

// MARK: - IV Workbench Tabs

enum IVWorkbenchTab: String, CaseIterable, Hashable, Identifiable, Sendable {
    case voltage
    case resistance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .voltage:    return "1st / I"
        case .resistance: return "2nd / I"
        }
    }
}
