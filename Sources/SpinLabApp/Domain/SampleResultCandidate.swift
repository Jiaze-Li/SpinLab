import Foundation

/// One computed (or manually corrected) Workbench value the user may explicitly assign to a Sample Result
/// (Task 12, design §3). In-memory and one-shot: never persisted, never written to a Pack. `runToken` /
/// `overrideRevision` only decide whether it is still current.
struct SampleResultCandidate: Equatable, Sendable, Identifiable {
    enum Origin: Equatable, Sendable {
        case computed
        case manualOverride(reason: String)
    }

    /// "Hc" / "R_AHE"; display only.
    let metricName: String
    /// Always finite.
    let value: Double
    /// Canonical unit of the metric ("T" / "Ω").
    let unit: String
    let sourceSampleKey: String
    /// Batch of the originating hit; used on confirmation to re-resolve the target Sample from disk.
    let sourceBatchID: String
    /// Source file name and channel; display only.
    let inputSummary: String
    /// Verbatim conditions of the selection that produced the surviving curve; empty means unknown.
    let conditions: [String: String]
    let origin: Origin
    /// The analysis run that produced it.
    let runToken: UInt64
    /// Only for `.manualOverride`: the override revision it was built from.
    let overrideRevision: UInt64?

    var id: String {
        let originKey: String
        switch origin {
        case .computed: originKey = "computed"
        case .manualOverride: originKey = "override"
        }
        return "\(sourceSampleKey)|\(metricName)|\(originKey)"
    }
}

/// Per-sample verdict of the candidate builder. Decided on the final curves, not on the selection count.
enum AHECandidateAvailability: Equatable, Sendable {
    case available(AHECandidateBase)
    case unavailable(reason: String)
}

/// Run-independent facts about the one surviving curve of a Sample.
struct AHECandidateBase: Equatable, Sendable {
    let sourceSampleKey: String
    let sourceBatchID: String
    let inputSummary: String
    let conditions: [String: String]
    let hc: Double
    let rAHE: Double
}
