import Foundation

/// Supported coefficient types for the Scaling vs Angle analysis.
enum ThreeOmegaScalingCoefficientKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case beta = "β"
    case alpha = "α"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var metricKey: String {
        switch self {
        case .beta: return "beta"
        case .alpha: return "alpha"
        }
    }
}

/// A single aggregated point in the Scaling vs Angle workflow.
struct ThreeOmegaScalingAnglePoint: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var sourceID: String
    var sampleKey: String
    var device: String
    var angleDeg: Double
    /// Alpha in display units: Ω·μm³·cm²·V⁻²·S⁻²
    var alpha: Double?
    /// Beta in display units: Ω·μm³·V⁻²
    var beta: Double?
    var rSquared: Double?
    var method: String
    var fitRange: String
    var generatedAt: Date?
    var candidateID: String

    init(
        id: String = UUID().uuidString,
        sourceID: String = "",
        sampleKey: String = "",
        device: String = "",
        angleDeg: Double,
        alpha: Double? = nil,
        beta: Double? = nil,
        rSquared: Double? = nil,
        method: String = "",
        fitRange: String = "",
        generatedAt: Date? = nil,
        candidateID: String = ""
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sampleKey = sampleKey
        self.device = device
        self.angleDeg = angleDeg
        self.alpha = alpha
        self.beta = beta
        self.rSquared = rSquared
        self.method = method
        self.fitRange = fitRange
        self.generatedAt = generatedAt
        self.candidateID = candidateID.isEmpty ? sampleKey : candidateID
    }
}

/// The aggregate result of the Scaling vs Angle query/filtering.
struct ThreeOmegaScalingVsAngleResult: Hashable, Codable, Sendable {
    /// The only methods the Scaling vs Angle workflow supports, regardless of
    /// what strings happen to be present in the underlying scaling records.
    static let applicableMethods: [String] = ["HFE", "WA"]

    /// Normalizes a raw record method string to one of `applicableMethods`.
    /// Returns `nil` when the string is empty or does not map to a supported method.
    static func normalizedMethod(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty else { return nil }
        switch token {
        case "hfe", "highfield", "high-field", "high_field", "high field":
            return "HFE"
        case "wa", "waveapprox", "wave-approx", "wave_approx", "waveapproximation", "wave approximation":
            return "WA"
        default:
            return nil
        }
    }

    var points: [ThreeOmegaScalingAnglePoint] = []
    var warnings: [String] = []
    var availableMethods: [String] = []
    var availableFitRanges: [String] = []
    /// Flattened, sorted union of every ambiguous angle's candidate options.
    var availableCandidates: [String] = []
    var selectedCoefficient: ThreeOmegaScalingCoefficientKind = .beta
    var selectedMethod: String? = nil
    var selectedFitRange: String? = nil
    /// Legacy single global candidate echo (pre-per-angle packs). Not used by the
    /// resolver anymore except as a best-effort migration hint.
    var selectedCandidate: String? = nil
    /// angleKey -> sorted candidate IDs, for each angle that resolves to more than
    /// one distinct fit/run under the current method + fit-range condition.
    var ambiguousAnglesByKey: [String: [String]] = [:]
    /// angleKey -> chosen candidate ID, the selections actually applied by the resolver.
    var candidateSelections: [String: String] = [:]

    /// Canonical string key for an angle value, shared by the use case, the store,
    /// and the chart-identity projection so per-angle selections line up.
    static func angleKey(_ angle: Double) -> String {
        String(format: "%g", angle)
    }

    // Backward-compatible decode: aggregates persisted by packs saved before the
    // per-angle selection model default their new fields instead of throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points              = try c.decodeIfPresent([ThreeOmegaScalingAnglePoint].self, forKey: .points) ?? []
        warnings            = try c.decodeIfPresent([String].self, forKey: .warnings) ?? []
        availableMethods    = try c.decodeIfPresent([String].self, forKey: .availableMethods) ?? []
        availableFitRanges  = try c.decodeIfPresent([String].self, forKey: .availableFitRanges) ?? []
        availableCandidates = try c.decodeIfPresent([String].self, forKey: .availableCandidates) ?? []
        selectedCoefficient = try c.decodeIfPresent(ThreeOmegaScalingCoefficientKind.self, forKey: .selectedCoefficient) ?? .beta
        selectedMethod      = try c.decodeIfPresent(String.self, forKey: .selectedMethod)
        selectedFitRange    = try c.decodeIfPresent(String.self, forKey: .selectedFitRange)
        selectedCandidate   = try c.decodeIfPresent(String.self, forKey: .selectedCandidate)
        ambiguousAnglesByKey = try c.decodeIfPresent([String: [String]].self, forKey: .ambiguousAnglesByKey) ?? [:]
        candidateSelections = try c.decodeIfPresent([String: String].self, forKey: .candidateSelections) ?? [:]
    }

    init(
        points: [ThreeOmegaScalingAnglePoint] = [],
        warnings: [String] = [],
        availableMethods: [String] = [],
        availableFitRanges: [String] = [],
        availableCandidates: [String] = [],
        selectedCoefficient: ThreeOmegaScalingCoefficientKind = .beta,
        selectedMethod: String? = nil,
        selectedFitRange: String? = nil,
        selectedCandidate: String? = nil,
        ambiguousAnglesByKey: [String: [String]] = [:],
        candidateSelections: [String: String] = [:]
    ) {
        self.points = points
        self.warnings = warnings
        self.availableMethods = availableMethods
        self.availableFitRanges = availableFitRanges
        self.availableCandidates = availableCandidates
        self.selectedCoefficient = selectedCoefficient
        self.selectedMethod = selectedMethod
        self.selectedFitRange = selectedFitRange
        self.selectedCandidate = selectedCandidate
        self.ambiguousAnglesByKey = ambiguousAnglesByKey
        self.candidateSelections = candidateSelections
    }
}

// MARK: - Result-table projection

/// Column headers for the Scaling vs Angle result table, in display order.
enum ThreeOmegaScalingAngleTableColumn: String, CaseIterable, Sendable {
    case angle = "Angle"
    case device = "Device"
    case coefficient = "β/α"
    case rSquared = "R²"
    case range = "Range"
    case method = "Method"
}

/// A single row of the Scaling vs Angle result table. This is a pure projection
/// of one aggregated `ThreeOmegaScalingAnglePoint` — no recomputation, folding,
/// sign-stripping, or normalization of the underlying α/β values.
struct ThreeOmegaScalingAngleTableRow: Identifiable, Hashable, Sendable {
    var id: String
    var candidateID: String
    var sourceID: String
    var angleDeg: Double
    var device: String
    /// Signed coefficient value for `coefficientKind`; `nil` when absent.
    var coefficientValue: Double?
    var coefficientKind: ThreeOmegaScalingCoefficientKind
    var rSquared: Double?
    var fitRange: String
    var method: String
    var generatedAt: Date?
}

/// Diagnostic warnings partitioned so the result panel can group missing-data,
/// conflicting-data, and ambiguous-data messages.
struct ThreeOmegaScalingAngleDiagnostics: Sendable {
    var missing: [String] = []
    var conflicting: [String] = []
    var ambiguous: [String] = []
    var other: [String] = []

    init(warnings: [String]) {
        for warning in warnings {
            let lower = warning.lowercased()
            if lower.contains("multiple records") {
                conflicting.append(warning)
            } else if lower.contains("candidate") {
                ambiguous.append(warning)
            } else if lower.contains("cannot be parsed")
                || lower.contains("no recognized method")
                || lower.contains("no 3ω")
                || lower.contains("no saved")
                || lower.contains("no α/β")
                || lower.contains("no scaling") {
                missing.append(warning)
            } else {
                other.append(warning)
            }
        }
    }

    var isEmpty: Bool {
        missing.isEmpty && conflicting.isEmpty && ambiguous.isEmpty && other.isEmpty
    }

    var all: [String] { missing + conflicting + ambiguous + other }
}

extension ThreeOmegaScalingVsAngleResult {

    /// Ordered table rows for the given coefficient (defaults to the selected one).
    /// Preserves the numeric-angle ordering established by the use case, keeps
    /// candidate identity stable, and never strips the sign of α/β values.
    func tableRows(coefficient: ThreeOmegaScalingCoefficientKind? = nil) -> [ThreeOmegaScalingAngleTableRow] {
        let kind = coefficient ?? selectedCoefficient
        return points.map { point in
            ThreeOmegaScalingAngleTableRow(
                id: point.id,
                candidateID: point.candidateID,
                sourceID: point.sourceID,
                angleDeg: point.angleDeg,
                device: point.device,
                coefficientValue: kind == .beta ? point.beta : point.alpha,
                coefficientKind: kind,
                rSquared: point.rSquared,
                fitRange: point.fitRange,
                method: point.method,
                generatedAt: point.generatedAt
            )
        }
    }

    /// Warnings grouped into missing / conflicting / ambiguous buckets.
    var diagnostics: ThreeOmegaScalingAngleDiagnostics {
        ThreeOmegaScalingAngleDiagnostics(warnings: warnings)
    }
}
