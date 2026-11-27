import Foundation

/// The two AHE metrics that can be offered for Sample Result assignment.
enum AHEResultMetric: String, CaseIterable, Sendable {
    case hc
    case rAHE

    var displayName: String { self == .hc ? "Hc" : "R_AHE" }
    var canonicalUnit: String { self == .hc ? "T" : "Ω" }
}

/// What the Workbench can offer for one Sample and one metric right now.
struct AHEResultOffer: Equatable {
    /// Computed first, then (when valid and current) the manual correction.
    var candidates: [SampleResultCandidate]
    /// Why nothing can be assigned; nil when `candidates` is non-empty.
    var unavailableReason: String?
}

extension AHEWorkspaceStore {

    /// Candidates for one metric of one Sample from the latest successful run (design §3).
    /// Never derived from `lastExtractedHc/RAHE` or any display convenience value.
    func resultOffer(sampleKey: String, metric: AHEResultMetric) -> AHEResultOffer {
        if isPlotRendering {
            return AHEResultOffer(candidates: [], unavailableReason: "Analysis is running; assignment is available when it finishes.")
        }
        guard candidateVerdictsRunToken == resultRunToken, lastRenderedSampleKeys.contains(sampleKey) else {
            return AHEResultOffer(candidates: [], unavailableReason: "Run Analyze on the current selection first.")
        }
        switch candidateVerdicts[sampleKey] {
        case .none:
            return AHEResultOffer(candidates: [], unavailableReason: "This sample has no usable curve.")
        case let .unavailable(reason)?:
            return AHEResultOffer(candidates: [], unavailableReason: reason)
        case let .available(base)?:
            var candidates = [SampleResultCandidate(
                metricName: metric.displayName,
                value: metric == .hc ? base.hc : base.rAHE,
                unit: metric.canonicalUnit,
                sourceSampleKey: base.sourceSampleKey,
                sourceBatchID: base.sourceBatchID,
                inputSummary: base.inputSummary,
                conditions: base.conditions,
                origin: .computed,
                runToken: resultRunToken,
                overrideRevision: nil
            )]
            let override = metric == .hc ? pendingMetricOverride : pendingRAHEOverride
            let overrideRunToken = metric == .hc ? hcOverrideRunToken : raheOverrideRunToken
            if let override, override.proposedValue.isFinite,
               lastRenderedSampleKeys.count == 1, overrideRunToken == resultRunToken {
                candidates.append(SampleResultCandidate(
                    metricName: metric.displayName,
                    value: override.proposedValue,
                    unit: metric.canonicalUnit,
                    sourceSampleKey: base.sourceSampleKey,
                    sourceBatchID: base.sourceBatchID,
                    inputSummary: base.inputSummary,
                    conditions: base.conditions,
                    origin: .manualOverride(reason: override.reason),
                    runToken: resultRunToken,
                    overrideRevision: resultOverrideRevision
                ))
            }
            return AHEResultOffer(candidates: candidates, unavailableReason: nil)
        }
    }

    /// True while `candidate` still describes the current run (and override edit, for a correction).
    func isCurrent(_ candidate: SampleResultCandidate) -> Bool {
        guard !isPlotRendering, candidate.runToken == resultRunToken else { return false }
        let offer = resultOffer(
            sampleKey: candidate.sourceSampleKey,
            metric: candidate.metricName == AHEResultMetric.hc.displayName ? .hc : .rAHE
        )
        return offer.candidates.contains(candidate)
    }
}

extension AHEWorkspaceStore {
    /// Records a human-readable confirmation; changes no analysis, Pack or plot state.
    func noteResultAssigned(metric: AHEResultMetric, definitionLabel: String, value: Double) {
        resultAssignmentMessage = "\(metric.displayName) written to \(definitionLabel): \(String(format: "%.10g", value))"
    }
}
