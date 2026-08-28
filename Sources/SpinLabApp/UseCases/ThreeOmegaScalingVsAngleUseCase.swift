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
        selectedCandidate: String? = nil
    ) -> ThreeOmegaScalingVsAngleResult {
        // 1. Filter to 3w records
        let threeOmegaRecords = records.filter { $0.workflowID == WorkflowKey.threeOmega.rawValue || $0.workflowID == "3w" }
        guard !threeOmegaRecords.isEmpty else {
            return ThreeOmegaScalingVsAngleResult(
                points: [],
                warnings: ["No 3ω Scaling Law records available."],
                availableMethods: [],
                availableFitRanges: [],
                availableCandidates: [],
                selectedCoefficient: selectedCoefficient,
                selectedMethod: nil,
                selectedFitRange: nil,
                selectedCandidate: nil
            )
        }

        // 2. Group records into logical scaling results
        // Grouping key: sampleKey + runID + device + method + range
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
                candidateID: record.sampleKey
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
                warnings: ["No α/β/R² scaling metrics found in records."],
                availableMethods: [],
                availableFitRanges: [],
                availableCandidates: [],
                selectedCoefficient: selectedCoefficient,
                selectedMethod: nil,
                selectedFitRange: nil,
                selectedCandidate: nil
            )
        }

        // 3. Extract available methods, fit ranges.
        // The method picker is constrained to exactly the HFE / WA choices the
        // Scaling vs Angle workflow supports, never to arbitrary record strings.
        let availableMethods = ThreeOmegaScalingVsAngleResult.applicableMethods
        let availableFitRanges = Array(Set(allGroups.map(\.fitRange).filter { !$0.isEmpty })).sorted()

        // 4. Resolve effective method and fit range. Default coefficient method is HFE.
        let effectiveMethod: String? = {
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

        // 5. Filter by method and fit range
        var candidateGroups = allGroups
        if let effectiveMethod {
            candidateGroups = candidateGroups.filter {
                ThreeOmegaScalingVsAngleResult.normalizedMethod($0.method) == effectiveMethod || $0.method.isEmpty
            }
        }
        if let effectiveFitRange {
            candidateGroups = candidateGroups.filter { $0.fitRange == effectiveFitRange || $0.fitRange.isEmpty }
        }

        var warnings: [String] = []
        var points: [ThreeOmegaScalingAnglePoint] = []

        // 6. Filter by coefficient availability and parse angle
        for item in candidateGroups {
            // Check coefficient availability
            switch selectedCoefficient {
            case .beta:
                guard item.beta != nil else { continue }
            case .alpha:
                guard item.alpha != nil else { continue }
            }

            // Parse device angle
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

        // 7. Determine ambiguous candidates for the current method + fit-range
        // condition. A candidate picker is only meaningful when some angle under
        // this condition resolves to more than one distinct candidate. The set is
        // computed BEFORE applying any candidate filter so candidate identity
        // stays stable across selection changes.
        let pointsByAngle = Dictionary(grouping: points, by: { $0.angleDeg })
        var ambiguousCandidateIDs: Set<String> = []
        for (_, pts) in pointsByAngle {
            let distinctCandidates = Set(pts.map(\.candidateID).filter { !$0.isEmpty })
            if distinctCandidates.count > 1 {
                ambiguousCandidateIDs.formUnion(distinctCandidates)
            }
        }
        let availableCandidates = ambiguousCandidateIDs.sorted()

        // 8. Duplicate angle diagnostics (do NOT overwrite or average). Emitted
        // from the pre-candidate-filter points so the ambiguity is always surfaced.
        for (angle, pts) in pointsByAngle where pts.count > 1 {
            let devNames = pts.map(\.device).joined(separator: ", ")
            warnings.append("Multiple records found for angle \(Int(angle.rounded()))° (\(devNames)).")
        }

        // 9. Filter by candidate if specified
        if let selectedCandidate, !selectedCandidate.isEmpty, selectedCandidate != "All" {
            let matching = points.filter { $0.candidateID == selectedCandidate || $0.sampleKey == selectedCandidate }
            if matching.isEmpty {
                warnings.append("Selected candidate '\(selectedCandidate)' is not available for the current method and fit range.")
            } else {
                points = matching
            }
        }

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
            selectedCandidate: selectedCandidate
        )
    }
}
