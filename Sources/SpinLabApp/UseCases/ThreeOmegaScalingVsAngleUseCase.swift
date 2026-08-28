import Foundation

// MARK: - ThreeOmegaScalingVsAngleUseCase
//
// Queries, filters, validates, aggregates, and sorts independent device Scaling results
// into an angle-resolved Scaling vs Angle dataset (β vs θ or α vs θ).
//
// Invariants:
// - Does not recompute scaling physics across devices.
// - Preserves signed coefficient values (no abs, no folding, no symmetrization).
// - Sorts by physical numeric angle.
// - Handles duplicates safely without silent overwrite or unauthorized averaging.
// - Fully resilient to empty, single-point, or missing-data conditions.
// - Consumes only already-saved (approved) Library scaling metrics; never live previews.
// - Candidate identity is the concrete fit/run provenance (sampleKey|runID), not just
//   the sample — so multiple runs of the same sample/device/method/range stay distinct.
// - Candidate resolution is per-angle: selecting a run for one ambiguous angle never
//   filters out the other angles.

struct ThreeOmegaScalingRecordGroup: Sendable {
    var sourceID: String
    var sampleKey: String
    var device: String
    var method: String
    var fitRange: String
    var alpha: Double?
    var beta: Double?
    var rSquared: Double?
    var generatedAt: Date?
    var candidateID: String
}

struct ThreeOmegaScalingVsAngleUseCase {

    func execute(
        records: [WorkbenchMetricRecord],
        selectedCoefficient: ThreeOmegaScalingCoefficientKind = .beta,
        selectedMethod: String? = nil,
        selectedFitRange: String? = nil,
        candidateSelections: [String: String] = [:],
        legacyCandidate: String? = nil
    ) -> ThreeOmegaScalingVsAngleResult {
        // 1. Filter to 3w records
        let threeOmegaRecords = records.filter { $0.workflowID == WorkflowKey.threeOmega.rawValue || $0.workflowID == "3w" }
        guard !threeOmegaRecords.isEmpty else {
            return ThreeOmegaScalingVsAngleResult(
                points: [],
                warnings: ["No saved 3ω Scaling Law results available."],
                availableMethods: [],
                availableFitRanges: [],
                availableCandidates: [],
                selectedCoefficient: selectedCoefficient,
                selectedMethod: nil,
                selectedFitRange: nil,
                selectedCandidate: nil,
                ambiguousAnglesByKey: [:],
                candidateSelections: [:]
            )
        }

        var warnings: [String] = []

        // 2. Group records into logical scaling results.
        // Grouping key: sampleKey + runID + device + method + range. The candidate
        // identity is the concrete fit provenance (sampleKey|runID), NOT the sample,
        // so repeated runs of the same sample/device/method/range remain distinct
        // selectable fits.
        var groups: [String: ThreeOmegaScalingRecordGroup] = [:]
        for record in threeOmegaRecords {
            let metric = record.metric.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard metric == "alpha" || metric == "beta" || metric == "r_squared" || metric == "r2" else {
                continue
            }

            let device = record.conditions["device"] ?? record.conditions["dev"] ?? ""
            let method = record.conditions["v3method"] ?? record.conditions["method"] ?? ""
            let fitRange = record.conditions["range"] ?? record.conditions["fitranges"] ?? "default"
            let runID = record.runID.isEmpty ? record.recordID : record.runID
            let groupKey = "\(record.sampleKey)|\(runID)|\(device)|\(method)|\(fitRange)"
            let candidateID = record.sampleKey.isEmpty ? runID : "\(record.sampleKey)|\(runID)"

            var group = groups[groupKey] ?? ThreeOmegaScalingRecordGroup(
                sourceID: runID,
                sampleKey: record.sampleKey,
                device: device,
                method: method,
                fitRange: fitRange,
                alpha: nil,
                beta: nil,
                rSquared: nil,
                generatedAt: record.generatedAt,
                candidateID: candidateID
            )

            if metric == "alpha" {
                group.alpha = record.value
            } else if metric == "beta" {
                group.beta = record.value
            } else if metric == "r_squared" || metric == "r2" {
                group.rSquared = record.value
            }
            if group.generatedAt == nil || (record.generatedAt > (group.generatedAt ?? Date.distantPast)) {
                group.generatedAt = record.generatedAt
            }
            groups[groupKey] = group
        }

        let allGroups = Array(groups.values)
        guard !allGroups.isEmpty else {
            return ThreeOmegaScalingVsAngleResult(
                points: [],
                warnings: ["No α/β/R² scaling metrics found in saved results."],
                availableMethods: [],
                availableFitRanges: [],
                availableCandidates: [],
                selectedCoefficient: selectedCoefficient,
                selectedMethod: nil,
                selectedFitRange: nil,
                selectedCandidate: nil,
                ambiguousAnglesByKey: [:],
                candidateSelections: [:]
            )
        }

        // 3. Extract available methods, fit ranges.
        // The method picker is constrained to exactly the HFE / WA choices the
        // Scaling vs Angle workflow supports, never to arbitrary record strings.
        let availableMethods = ThreeOmegaScalingVsAngleResult.applicableMethods
        let availableFitRanges = Array(Set(allGroups.map(\.fitRange).filter { !$0.isEmpty })).sorted()

        // 4. Resolve effective method and fit range. Default coefficient method is HFE.
        let effectiveMethod: String = {
            if let selectedMethod,
               let normalized = ThreeOmegaScalingVsAngleResult.normalizedMethod(selectedMethod) {
                return normalized
            }
            return "HFE"
        }()

        let effectiveFitRange: String? = {
            if let selectedFitRange, availableFitRanges.contains(selectedFitRange) {
                return selectedFitRange
            }
            return availableFitRanges.first
        }()

        // 5. Filter by method and fit range.
        // A missing / unrecognized method is NEVER silently assumed to be HFE or WA —
        // such a record is skipped from the filtered plot with a diagnostic. History
        // and the Library are left untouched; this is an angle-projection guard only.
        var candidateGroups: [ThreeOmegaScalingRecordGroup] = []
        var skippedUnknownMethodDevices: Set<String> = []
        for group in allGroups {
            guard let normalized = ThreeOmegaScalingVsAngleResult.normalizedMethod(group.method) else {
                let label = group.device.isEmpty ? (group.sampleKey.isEmpty ? "unknown" : group.sampleKey) : group.device
                if skippedUnknownMethodDevices.insert(label).inserted {
                    warnings.append("Scaling record for '\(label)' has no recognized method — skipped from the \(effectiveMethod) plot.")
                }
                continue
            }
            if normalized == effectiveMethod {
                candidateGroups.append(group)
            }
        }
        if let effectiveFitRange {
            // Strict: a record only counts for the exact selected fit range. No
            // borrowing from another range, no averaging, no auto-pick.
            candidateGroups = candidateGroups.filter { $0.fitRange == effectiveFitRange }
        }

        var points: [ThreeOmegaScalingAnglePoint] = []

        // 6. Filter by coefficient availability and parse angle
        for item in candidateGroups {
            switch selectedCoefficient {
            case .beta:
                guard item.beta != nil else { continue }
            case .alpha:
                guard item.alpha != nil else { continue }
            }

            guard let angle = ThreeOmegaDeviceAngleParser.parseDegrees(item.device) else {
                if !item.device.isEmpty {
                    warnings.append("Device '\(item.device)' angle cannot be parsed — skipped.")
                }
                continue
            }

            points.append(ThreeOmegaScalingAnglePoint(
                id: "\(item.sampleKey)-\(item.sourceID)-\(item.device)-\(item.method)-\(item.fitRange)",
                sourceID: item.sourceID,
                sampleKey: item.sampleKey,
                device: item.device,
                angleDeg: angle,
                alpha: item.alpha,
                beta: item.beta,
                rSquared: item.rSquared,
                method: item.method,
                fitRange: item.fitRange,
                generatedAt: item.generatedAt,
                candidateID: item.candidateID
            ))
        }

        // 7. Per-angle ambiguity map for the current method + fit-range condition.
        // An angle is ambiguous when more than one distinct candidate (fit/run)
        // resolves to it. Computed BEFORE applying any candidate selection so the
        // ambiguity set is stable across selection changes.
        let pointsByAngleKey = Dictionary(grouping: points, by: { ThreeOmegaScalingVsAngleResult.angleKey($0.angleDeg) })
        var ambiguousAnglesByKey: [String: [String]] = [:]
        for (key, pts) in pointsByAngleKey {
            let distinct = Set(pts.map(\.candidateID).filter { !$0.isEmpty })
            if distinct.count > 1 {
                ambiguousAnglesByKey[key] = distinct.sorted()
            }
        }
        let availableCandidates = Set(ambiguousAnglesByKey.values.flatMap { $0 }).sorted()

        // 8. Duplicate angle diagnostics (do NOT overwrite or average). Emitted from
        // the pre-resolution points so the ambiguity is always surfaced.
        for (_, pts) in pointsByAngleKey where pts.count > 1 {
            let angle = pts[0].angleDeg
            let devNames = pts.map(\.device).joined(separator: ", ")
            warnings.append("Multiple records found for angle \(Int(angle.rounded()))° (\(devNames)).")
        }

        // 9. Resolve each ambiguous angle independently. Non-ambiguous angles are
        // always kept; resolving one angle never filters out the others.
        var effectiveSelections: [String: String] = [:]
        for (angleKey, options) in ambiguousAnglesByKey {
            if let explicit = candidateSelections[angleKey] {
                // Applied as-is; a stale / unknown value is caught during resolution.
                effectiveSelections[angleKey] = explicit
            } else if let legacyCandidate, !legacyCandidate.isEmpty,
                      let matched = options.first(where: { $0 == legacyCandidate || $0.hasPrefix("\(legacyCandidate)|") }) {
                // Best-effort migration of a legacy single global candidate.
                effectiveSelections[angleKey] = matched
            }
        }

        var resolved: [ThreeOmegaScalingAnglePoint] = []
        for (angleKey, pts) in pointsByAngleKey {
            guard pts.count > 1 else {
                resolved.append(contentsOf: pts)
                continue
            }
            if let selection = effectiveSelections[angleKey] {
                let matching = pts.filter { $0.candidateID == selection }
                if matching.isEmpty {
                    warnings.append("Angle \(Int(pts[0].angleDeg.rounded()))° run selection '\(selection)' is not available — showing all candidates.")
                    resolved.append(contentsOf: pts)
                } else {
                    resolved.append(contentsOf: matching)
                }
            } else {
                // Ambiguous but unresolved: keep every candidate (never average or
                // overwrite); the ambiguity is surfaced via ambiguousAnglesByKey.
                resolved.append(contentsOf: pts)
            }
        }
        points = resolved

        // 10. Numeric angle sort
        points.sort { (p1, p2) -> Bool in
            if p1.angleDeg != p2.angleDeg {
                return p1.angleDeg < p2.angleDeg
            }
            if p1.sampleKey != p2.sampleKey {
                return p1.sampleKey < p2.sampleKey
            }
            if p1.device != p2.device {
                return p1.device < p2.device
            }
            return p1.sourceID < p2.sourceID
        }

        return ThreeOmegaScalingVsAngleResult(
            points: points,
            warnings: warnings,
            availableMethods: availableMethods,
            availableFitRanges: availableFitRanges,
            availableCandidates: availableCandidates,
            selectedCoefficient: selectedCoefficient,
            selectedMethod: effectiveMethod,
            selectedFitRange: effectiveFitRange,
            selectedCandidate: legacyCandidate,
            ambiguousAnglesByKey: ambiguousAnglesByKey,
            candidateSelections: effectiveSelections
        )
    }
}
