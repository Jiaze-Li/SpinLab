import Testing
import Foundation
@testable import SpinLabApp

@Suite("ThreeOmega — Scaling vs Angle Workflow Tests")
struct ThreeOmegaScalingVsAngleTests {

    private func makeMetricRecord(
        sampleKey: String = "sample-1",
        runID: String = "run-1",
        device: String,
        method: String = "HFE",
        range: String = "30K–110K",
        alpha: Double? = nil,
        beta: Double? = nil,
        rSquared: Double? = nil,
        date: Date = Date(timeIntervalSince1970: 1000)
    ) -> [WorkbenchMetricRecord] {
        var records: [WorkbenchMetricRecord] = []
        let conditions: [String: String] = [
            "device": device,
            "v3method": method,
            "range": range
        ]
        if let alpha {
            records.append(WorkbenchMetricRecord(
                recordID: UUID().uuidString,
                sampleKey: sampleKey,
                displayKey: sampleKey,
                workflowID: "3w",
                metric: "alpha",
                value: alpha,
                canonicalUnit: "Ω·μm³·cm²·V⁻²·S⁻²",
                conditions: conditions,
                generatedAt: date,
                runID: runID
            ))
        }
        if let beta {
            records.append(WorkbenchMetricRecord(
                recordID: UUID().uuidString,
                sampleKey: sampleKey,
                displayKey: sampleKey,
                workflowID: "3w",
                metric: "beta",
                value: beta,
                canonicalUnit: "Ω·μm³·V⁻²",
                conditions: conditions,
                generatedAt: date,
                runID: runID
            ))
        }
        if let rSquared {
            records.append(WorkbenchMetricRecord(
                recordID: UUID().uuidString,
                sampleKey: sampleKey,
                displayKey: sampleKey,
                workflowID: "3w",
                metric: "r_squared",
                value: rSquared,
                canonicalUnit: "",
                conditions: conditions,
                generatedAt: date,
                runID: runID
            ))
        }
        return records
    }

    @Test("Basic β angle aggregation: 0°, 30°, 60° ordered numerically")
    func basicBetaAngleAggregation() {
        let recs = makeMetricRecord(runID: "r1", device: "device_0deg", beta: 1.0)
            + makeMetricRecord(runID: "r2", device: "device_30deg", beta: 2.0)
            + makeMetricRecord(runID: "r3", device: "device_60deg", beta: 3.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)

        #expect(result.points.count == 3)
        #expect(result.points.map(\.angleDeg) == [0.0, 30.0, 60.0])
        #expect(result.points.compactMap(\.beta) == [1.0, 2.0, 3.0])
    }

    @Test("Negative angle sorting preserves physical signed order: -30°, 0°, 30°")
    func negativeAngleSorting() {
        let recs = makeMetricRecord(runID: "r1", device: "device_+30deg", beta: 30.0)
            + makeMetricRecord(runID: "r2", device: "device_-30deg", beta: -30.0)
            + makeMetricRecord(runID: "r3", device: "device_0deg", beta: 0.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)

        #expect(result.points.count == 3)
        #expect(result.points.map(\.angleDeg) == [-30.0, 0.0, 30.0])
    }

    @Test("Signed β preserves negative and positive values without abs")
    func signedBetaPreservation() {
        let recs = makeMetricRecord(runID: "r1", device: "-30deg", beta: -2.5e3)
            + makeMetricRecord(runID: "r2", device: "0deg", beta: 1.2e3)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)

        #expect(result.points.count == 2)
        #expect(result.points[0].beta == -2.5e3)
        #expect(result.points[1].beta == 1.2e3)
    }

    @Test("α selector queries alpha(angle) for same source results")
    func alphaSelectorAggregation() {
        let recs = makeMetricRecord(runID: "r1", device: "0deg", alpha: 4.5e5, beta: 1.0)
            + makeMetricRecord(runID: "r2", device: "45deg", alpha: 8.9e5, beta: 2.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .alpha)

        #expect(result.points.count == 2)
        #expect(result.points.map(\.angleDeg) == [0.0, 45.0])
        #expect(result.points.compactMap(\.alpha) == [4.5e5, 8.9e5])
    }

    @Test("Duplicate angle does not silently overwrite or average")
    func duplicateAngleHandling() {
        let recs = makeMetricRecord(sampleKey: "s1", runID: "r1", device: "device_A_30deg", beta: 1.0)
            + makeMetricRecord(sampleKey: "s2", runID: "r2", device: "device_B_30deg", beta: 2.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)

        #expect(result.points.count == 2)
        #expect(result.points.map(\.angleDeg) == [30.0, 30.0])
        #expect(result.points.compactMap(\.beta).sorted() == [1.0, 2.0])
        #expect(result.warnings.contains { $0.contains("30°") })
    }

    @Test("Missing angle in device string is safely skipped with diagnostic warning")
    func missingAngleSkipped() {
        let recs = makeMetricRecord(runID: "r1", device: "unparseable_device", beta: 1.0)
            + makeMetricRecord(runID: "r2", device: "device_15deg", beta: 2.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)

        #expect(result.points.count == 1)
        #expect(result.points[0].angleDeg == 15.0)
        #expect(result.warnings.contains { $0.contains("unparseable_device") })
    }

    @Test("Missing coefficient safely skips point without crash")
    func missingCoefficientSkipped() {
        // Record 1 has alpha only, record 2 has beta only
        let recs = makeMetricRecord(runID: "r1", device: "0deg", alpha: 10.0, beta: nil)
            + makeMetricRecord(runID: "r2", device: "30deg", alpha: nil, beta: 20.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let resultBeta = useCase.execute(records: recs, selectedCoefficient: .beta)
        #expect(resultBeta.points.count == 1)
        #expect(resultBeta.points[0].angleDeg == 30.0)

        let resultAlpha = useCase.execute(records: recs, selectedCoefficient: .alpha)
        #expect(resultAlpha.points.count == 1)
        #expect(resultAlpha.points[0].angleDeg == 0.0)
    }

    @Test("Empty state handles zero records safely")
    func emptyStateHandling() {
        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: [], selectedCoefficient: .beta)

        #expect(result.points.isEmpty)
        #expect(!result.warnings.isEmpty)
    }

    @Test("Single angle yields exactly 1 point without error")
    func singleAngleHandling() {
        let recs = makeMetricRecord(runID: "r1", device: "45°", beta: 5.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)

        #expect(result.points.count == 1)
        #expect(result.points[0].angleDeg == 45.0)
        #expect(result.points[0].beta == 5.0)
    }

    @Test("Method filtering discriminates HFE and WA results")
    func methodFiltering() {
        let recs = makeMetricRecord(runID: "r1", device: "0deg", method: "HFE", beta: 100.0)
            + makeMetricRecord(runID: "r2", device: "0deg", method: "WA", beta: 200.0)
            + makeMetricRecord(runID: "r3", device: "30deg", method: "HFE", beta: 150.0)
            + makeMetricRecord(runID: "r4", device: "30deg", method: "WA", beta: 250.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let resultHFE = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "HFE")
        #expect(resultHFE.points.count == 2)
        #expect(resultHFE.points.compactMap(\.beta) == [100.0, 150.0])

        let resultWA = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "WA")
        #expect(resultWA.points.count == 2)
        #expect(resultWA.points.compactMap(\.beta) == [200.0, 250.0])
    }

    @Test("Fit range filtering prevents mixing different temperature conditions")
    func fitRangeFiltering() {
        let recs = makeMetricRecord(runID: "r1", device: "0deg", range: "30K–110K", beta: 11.0)
            + makeMetricRecord(runID: "r2", device: "0deg", range: "50K–120K", beta: 12.0)
            + makeMetricRecord(runID: "r3", device: "30deg", range: "30K–110K", beta: 31.0)
            + makeMetricRecord(runID: "r4", device: "30deg", range: "50K–120K", beta: 32.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result1 = useCase.execute(records: recs, selectedCoefficient: .beta, selectedFitRange: "30K–110K")
        #expect(result1.points.compactMap(\.beta) == [11.0, 31.0])

        let result2 = useCase.execute(records: recs, selectedCoefficient: .beta, selectedFitRange: "50K–120K")
        #expect(result2.points.compactMap(\.beta) == [12.0, 32.0])
    }

    @Test("Coefficient selection defaults to β and offers α as the alternative")
    func coefficientDefaultsAndAlternative() {
        #expect(ThreeOmegaScalingCoefficientKind.allCases == [.beta, .alpha])
        let result = ThreeOmegaScalingVsAngleResult()
        #expect(result.selectedCoefficient == .beta)

        let recs = makeMetricRecord(runID: "r1", device: "0deg", alpha: 1.0, beta: 2.0)
        let useCase = ThreeOmegaScalingVsAngleUseCase()
        #expect(useCase.execute(records: recs).selectedCoefficient == .beta)
    }

    @Test("Method picker is restricted to exactly HFE and WA regardless of record content")
    func methodPickerRestrictedToApplicable() {
        #expect(ThreeOmegaScalingVsAngleResult.applicableMethods == ["HFE", "WA"])

        // Records carry junk / legacy method strings.
        let recs = makeMetricRecord(runID: "r1", device: "0deg", method: "highField", beta: 1.0)
            + makeMetricRecord(runID: "r2", device: "30deg", method: "bogusMethod", beta: 2.0)
            + makeMetricRecord(runID: "r3", device: "60deg", method: "WA", beta: 3.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)
        #expect(result.availableMethods == ["HFE", "WA"])

        // "highField" normalizes to HFE (default), "bogusMethod" is excluded.
        let hfe = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "HFE")
        #expect(hfe.points.map(\.angleDeg) == [0.0])

        let wa = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "WA")
        #expect(wa.points.map(\.angleDeg) == [60.0])

        // An unsupported selected method falls back to HFE deterministically.
        let junkSelected = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "bogusMethod")
        #expect(junkSelected.selectedMethod == "HFE")
        #expect(junkSelected.points.map(\.angleDeg) == [0.0])
    }

    @Test("Candidate picker hidden when no angle+condition has multiple candidates")
    func candidatePickerHiddenWithoutPerAngleAmbiguity() {
        // Distinct candidates exist globally but never collide on the same angle.
        let recs = makeMetricRecord(sampleKey: "s1", runID: "r1", device: "0deg", beta: 1.0)
            + makeMetricRecord(sampleKey: "s2", runID: "r2", device: "30deg", beta: 2.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)
        #expect(result.availableCandidates.isEmpty)
    }

    @Test("Candidate picker visibility is scoped to the selected method+fit-range condition")
    func candidatePickerScopedToCondition() {
        // Angle 30 collides for two candidates only under the HFE condition.
        let recs = makeMetricRecord(sampleKey: "s1", runID: "r1", device: "dev_A_30deg", method: "HFE", beta: 1.0)
            + makeMetricRecord(sampleKey: "s2", runID: "r2", device: "dev_B_30deg", method: "HFE", beta: 2.0)
            + makeMetricRecord(sampleKey: "s3", runID: "r3", device: "dev_C_30deg", method: "WA", beta: 3.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let hfe = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "HFE")
        #expect(hfe.availableCandidates == ["s1|r1", "s2|r2"])
        #expect(hfe.ambiguousAnglesByKey["30"] == ["s1|r1", "s2|r2"])

        let wa = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "WA")
        #expect(wa.availableCandidates.isEmpty)
        #expect(wa.ambiguousAnglesByKey.isEmpty)
    }

    @Test("Candidate identity stays stable across per-angle candidate selection changes")
    func candidateIdentityStableAcrossSelection() {
        let recs = makeMetricRecord(sampleKey: "s1", runID: "r1", device: "dev_A_30deg", beta: 1.0)
            + makeMetricRecord(sampleKey: "s2", runID: "r2", device: "dev_B_30deg", beta: 2.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let all = useCase.execute(records: recs, selectedCoefficient: .beta)
        #expect(all.availableCandidates == ["s1|r1", "s2|r2"])

        let pickS1 = useCase.execute(records: recs, selectedCoefficient: .beta, candidateSelections: ["30": "s1|r1"])
        #expect(pickS1.availableCandidates == ["s1|r1", "s2|r2"])
        #expect(pickS1.points.compactMap(\.beta) == [1.0])

        let pickS2 = useCase.execute(records: recs, selectedCoefficient: .beta, candidateSelections: ["30": "s2|r2"])
        #expect(pickS2.availableCandidates == ["s1|r1", "s2|r2"])
        #expect(pickS2.points.compactMap(\.beta) == [2.0])
    }

    @Test("Unresolved / unavailable per-angle selection keeps all candidates rather than an arbitrary pick")
    func unavailableCandidateDiagnostic() {
        let recs = makeMetricRecord(sampleKey: "s1", runID: "r1", device: "dev_A_30deg", beta: 1.0)
            + makeMetricRecord(sampleKey: "s2", runID: "r2", device: "dev_B_30deg", beta: 2.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        // No selection: both candidates kept, ambiguity surfaced.
        let result = useCase.execute(records: recs, selectedCoefficient: .beta)
        #expect(result.points.compactMap(\.beta).sorted() == [1.0, 2.0])
        #expect(result.ambiguousAnglesByKey["30"] == ["s1|r1", "s2|r2"])
        #expect(result.warnings.contains { $0.contains("30°") })
    }

    @Test("ThreeOmegaWorkbenchTab handles scalingVsAngle correctly")
    func tabProperties() {
        let tab = ThreeOmegaWorkbenchTab.scalingVsAngle
        #expect(tab.rawValue == "Scaling vs Angle")
        #expect(tab.stableKey == "scalingVsAngle")
        #expect(tab.packStableKey == "scalingVsAngle")
        #expect(ThreeOmegaWorkbenchTab.visibleTabs.contains(.scalingVsAngle))
        #expect(ThreeOmegaWorkbenchTab.tab(forStableKey: "scalingVsAngle") == .scalingVsAngle)
    }

    @Test("Plot renderer creates valid scalingVsAngle payload — one device series per angle")
    func plotRendererScalingVsAnglePayload() {
        let pt1 = ThreeOmegaScalingAnglePoint(device: "0deg", angleDeg: 0.0, alpha: 1.0, beta: 2.0)
        let pt2 = ThreeOmegaScalingAnglePoint(device: "30deg", angleDeg: 30.0, alpha: 3.0, beta: 4.0)
        let result = ThreeOmegaScalingVsAngleResult(points: [pt1, pt2], selectedCoefficient: .beta)

        let renderer = ThreeOmegaPlotRenderer()
        let payload = renderer.makeScalingVsAnglePayload(
            result: result,
            device: "angle_sweep",
            coefficient: .beta,
            method: "HFE",
            fitRange: "30K–110K"
        )

        #expect(payload != nil)
        #expect(payload?.series.count == 2)
        #expect(payload?.series.map { $0.x } == [[0.0], [30.0]])
        #expect(payload?.series.flatMap(\.y) == [2.0, 4.0])
        // Canonical device metadata drives the legend — no candidate/identity token.
        #expect(payload?.series.compactMap { $0.metadata["device"] } == ["0deg", "30deg"])
        #expect(payload?.axisMapping.yField == ThreeOmegaPlotRenderer.betaAxisLabel)
    }

    @Test("Payload: numeric angle order keeps negative angles ordered and signed β values")
    func payloadSignedNegativeAngleOrdering() {
        let pts = [
            ThreeOmegaScalingAnglePoint(device: "30deg", angleDeg: 30.0, beta: 2.0),
            ThreeOmegaScalingAnglePoint(device: "-30deg", angleDeg: -30.0, beta: -5.0),
            ThreeOmegaScalingAnglePoint(device: "0deg", angleDeg: 0.0, beta: 0.0)
        ]
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .beta)
        let payload = ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .beta)

        #expect(payload?.series.count == 3)
        #expect(payload?.series.flatMap(\.x) == [-30.0, 0.0, 30.0])
        #expect(payload?.series.flatMap(\.y) == [-5.0, 0.0, 2.0])
        #expect(payload?.series.compactMap { $0.metadata["device"] } == ["-30deg", "0deg", "30deg"])
        #expect(payload?.axisMapping.xField == ThreeOmegaPlotRenderer.deviceAngleAxisLabel)
    }

    @Test("Payload: α coefficient uses α axis label and retains negative α values")
    func payloadAlphaAxisAndNegativeValues() {
        let pts = [
            ThreeOmegaScalingAnglePoint(device: "0deg", angleDeg: 0.0, alpha: -1.5e5, beta: 1.0),
            ThreeOmegaScalingAnglePoint(device: "45deg", angleDeg: 45.0, alpha: 2.0e5, beta: 2.0)
        ]
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .alpha)
        let payload = ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .alpha)

        #expect(payload?.axisMapping.yField == ThreeOmegaPlotRenderer.alphaAxisLabel)
        #expect(payload?.series.flatMap(\.y) == [-1.5e5, 2.0e5])
    }

    @Test("Payload: duplicate-angle candidates render as distinct series with distinct identities, not merged")
    func payloadDuplicateAngleDistinctSeries() {
        let pts = [
            ThreeOmegaScalingAnglePoint(device: "A_30deg", angleDeg: 30.0, beta: 1.0, candidateID: "s1"),
            ThreeOmegaScalingAnglePoint(device: "B_30deg", angleDeg: 30.0, beta: 2.0, candidateID: "s2")
        ]
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .beta)
        let payload = ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .beta)

        #expect(payload?.series.count == 2)
        // Legend semantics come from the device dimension, never the candidate token.
        #expect(Set(payload?.series.compactMap { $0.metadata["device"] } ?? []) == ["A_30deg", "B_30deg"])
        #expect(Set(payload?.series.map(\.label) ?? []) == ["A_30deg", "B_30deg"])
        // Distinct internal identities so reorder/rename never collides.
        let identityKeys = payload?.series.compactMap { $0.metadata["seriesIdentityKey"] } ?? []
        #expect(Set(identityKeys).count == 2)
        #expect(payload?.series.flatMap(\.y).sorted() == [1.0, 2.0])
    }

    @Test("Cache identity: coefficient, method, fit range, and candidate each yield a distinct semantic identity")
    func cacheIdentitySeparatesEverySelectionDimension() {
        let pts = [
            ThreeOmegaScalingAnglePoint(device: "0deg", angleDeg: 0.0, alpha: 1.0, beta: 2.0),
            ThreeOmegaScalingAnglePoint(device: "30deg", angleDeg: 30.0, alpha: 3.0, beta: 4.0)
        ]
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .beta)
        let renderer = ThreeOmegaPlotRenderer()

        func params(_ coeff: ThreeOmegaScalingCoefficientKind, _ method: String, _ range: String, _ candidate: String?) -> [String: String] {
            renderer.makeScalingVsAnglePayload(
                result: result, coefficient: coeff, method: method, fitRange: range, candidate: candidate
            )?.semanticParams ?? [:]
        }

        let base = params(.beta, "HFE", "30K–110K", nil)
        #expect(base != params(.alpha, "HFE", "30K–110K", nil))
        #expect(base != params(.beta, "WA", "30K–110K", nil))
        #expect(base != params(.beta, "HFE", "50K–120K", nil))
        #expect(base != params(.beta, "HFE", "30K–110K", "s1"))
        #expect(params(.beta, "HFE", "30K–110K", "s1") != params(.beta, "HFE", "30K–110K", "s2"))
    }

    @Test("PackConfig round trip preserves every Scaling vs Angle selection field including candidate")
    func packConfigRoundTripPreservesSelection() throws {
        let json = """
        {
            "device": "0deg",
            "geometry": { "lxx": 100.0, "lxy": 50.0, "dNm": 10.0 },
            "fitRanges": [],
            "v3Method": "highField",
            "sampleBatchAndSubstrate": "sample-batch",
            "activeTab": "scalingVsAngle",
            "stackOffsetMultiplier": 1.2,
            "showPlotGrid": true,
            "scalingAngleCoefficient": "α",
            "scalingAngleMethod": "WA",
            "scalingAngleFitRange": "50K–120K",
            "scalingAngleCandidate": "s2"
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: json)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ThreeOmegaPackConfig.self, from: data)
        #expect(decoded.scalingAngleCoefficient == "α")
        #expect(decoded.scalingAngleMethod == "WA")
        #expect(decoded.scalingAngleFitRange == "50K–120K")
        #expect(decoded.scalingAngleCandidate == "s2")
    }

    // MARK: - Result-table projection (step 6)

    @Test("Table rows expose Angle, Device, β/α, R², Range, Method columns")
    func tableRowColumns() {
        #expect(ThreeOmegaScalingAngleTableColumn.allCases.map(\.rawValue)
            == ["Angle", "Device", "β/α", "R²", "Range", "Method"])

        let recs = makeMetricRecord(runID: "r1", device: "device_30deg", method: "HFE",
                                    range: "30K–110K", beta: 2.0, rSquared: 0.987)
        let result = ThreeOmegaScalingVsAngleUseCase().execute(records: recs, selectedCoefficient: .beta)
        let rows = result.tableRows()

        #expect(rows.count == 1)
        let row = rows[0]
        #expect(row.angleDeg == 30.0)
        #expect(row.device == "device_30deg")
        #expect(row.coefficientValue == 2.0)
        #expect(row.coefficientKind == .beta)
        #expect(row.rSquared == 0.987)
        #expect(row.fitRange == "30K–110K")
        #expect(row.method == "HFE")
    }

    @Test("Table projection preserves numeric angle ordering and negative angles")
    func tableRowOrderingAndNegativeAngles() {
        let recs = makeMetricRecord(runID: "r1", device: "device_+30deg", beta: 3.0)
            + makeMetricRecord(runID: "r2", device: "device_-30deg", beta: -1.0)
            + makeMetricRecord(runID: "r3", device: "device_0deg", beta: 0.0)
        let result = ThreeOmegaScalingVsAngleUseCase().execute(records: recs, selectedCoefficient: .beta)
        let rows = result.tableRows()

        #expect(rows.map(\.angleDeg) == [-30.0, 0.0, 30.0])
        #expect(rows.map(\.coefficientValue) == [-1.0, 0.0, 3.0])
    }

    @Test("Table projection retains signed α/β without folding and switches coefficient cleanly")
    func tableRowSignedCoefficientSwitch() {
        let recs = makeMetricRecord(runID: "r1", device: "0deg", alpha: -4.5e5, beta: -2.5e3)
            + makeMetricRecord(runID: "r2", device: "45deg", alpha: 8.9e5, beta: 1.2e3)
        let result = ThreeOmegaScalingVsAngleUseCase().execute(records: recs, selectedCoefficient: .beta)

        #expect(result.tableRows(coefficient: .beta).map(\.coefficientValue) == [-2.5e3, 1.2e3])
        #expect(result.tableRows(coefficient: .alpha).map(\.coefficientValue) == [-4.5e5, 8.9e5])
        #expect(result.tableRows(coefficient: .alpha).allSatisfy { $0.coefficientKind == .alpha })
    }

    @Test("Table projection keeps candidate identity stable for duplicate angles")
    func tableRowStableCandidateIdentity() {
        let recs = makeMetricRecord(sampleKey: "s1", runID: "r1", device: "dev_A_30deg", beta: 1.0)
            + makeMetricRecord(sampleKey: "s2", runID: "r2", device: "dev_B_30deg", beta: 2.0)
        let result = ThreeOmegaScalingVsAngleUseCase().execute(records: recs, selectedCoefficient: .beta)
        let rows = result.tableRows()

        #expect(rows.count == 2)
        #expect(Set(rows.map(\.candidateID)) == ["s1|r1", "s2|r2"])
        // Distinct stable row identities — no merge/overwrite.
        #expect(Set(rows.map(\.id)).count == 2)
    }

    @Test("Diagnostics partition missing, conflicting, and ambiguous warnings")
    func diagnosticsPartitioning() {
        let recs = makeMetricRecord(sampleKey: "s1", runID: "r1", device: "dev_A_30deg", beta: 1.0)
            + makeMetricRecord(sampleKey: "s2", runID: "r2", device: "dev_B_30deg", beta: 2.0)
            + makeMetricRecord(runID: "r3", device: "unparseable_device", beta: 5.0)
        let result = ThreeOmegaScalingVsAngleUseCase().execute(
            records: recs, selectedCoefficient: .beta, candidateSelections: ["30": "ghost"])
        let diagnostics = result.diagnostics

        #expect(!diagnostics.isEmpty)
        #expect(diagnostics.conflicting.contains { $0.contains("30°") })
        #expect(diagnostics.missing.contains { $0.contains("unparseable_device") })
        #expect(diagnostics.ambiguous.contains { $0.contains("not available") })
        #expect(Set(diagnostics.all) == Set(result.warnings))
    }

    @Test("Empty result surfaces a missing-data diagnostic")
    func diagnosticsEmptyState() {
        let result = ThreeOmegaScalingVsAngleUseCase().execute(records: [], selectedCoefficient: .beta)
        #expect(!result.diagnostics.missing.isEmpty)
    }

    // MARK: - Data-lifecycle: measurement-store ingestion (step 6)

    private func makeLibraryFixture() throws -> (resolver: LibraryPathResolver, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "svangle-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (LibraryPathResolver(libraryRootURL: root), root)
    }

    @Test("Measurement-store ingestion feeds already-computed scaling artifacts without refitting across devices")
    func measurementStoreIngestionNoRecomputation() throws {
        let (resolver, root) = try makeLibraryFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        // Pre-computed per-device scaling artifacts, distinct signed values per device.
        let persisted: [(device: String, angle: Double, beta: Double, alpha: Double, r2: Double)] = [
            ("dev_+30deg", 30.0, 1.234567e3, -9.87654e5, 0.9911),
            ("dev_-30deg", -30.0, -4.44444e3, 3.33333e5, 0.9822),
            ("dev_0deg", 0.0, 7.0e2, 1.0e5, 0.9733)
        ]
        let persistUseCase = PersistMeasurementDataUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
        for row in persisted {
            for rec in makeMetricRecord(sampleKey: "SK", device: row.device,
                                        alpha: row.alpha, beta: row.beta, rSquared: row.r2) {
                try persistUseCase.execute(sampleKey: "SK", record: rec)
            }
        }

        // Read the artifacts straight back from the store — the ingestion path.
        let loaded = LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK")
        let records = try #require(loaded).records.filter { $0.workflowID == "3w" }
        #expect(records.count == persisted.count * 3)

        let result = ThreeOmegaScalingVsAngleUseCase().execute(records: records, selectedCoefficient: .beta)

        // Numeric-angle order preserved, signs intact.
        #expect(result.points.map(\.angleDeg) == [-30.0, 0.0, 30.0])
        // Values are the stored artifacts verbatim — not refit, averaged, or normalized.
        let byAngle = Dictionary(uniqueKeysWithValues: result.points.map { ($0.angleDeg, $0) })
        for row in persisted {
            let pt = try #require(byAngle[row.angle])
            #expect(pt.beta == row.beta)
            #expect(pt.alpha == row.alpha)
            #expect(pt.rSquared == row.r2)
            #expect(pt.device == row.device)
            #expect(pt.sampleKey == "SK")
        }
    }

    // MARK: - Data-lifecycle: session / analysis-pack round trip (step 6)

    /// Rich aggregate: negative angles, signed α/β, full provenance, a per-angle
    /// duplicate-candidate collision, diagnostics, and every selection field set.
    private func makeRichAngleResult() -> ThreeOmegaScalingVsAngleResult {
        let genA = Date(timeIntervalSince1970: 111_111)
        let genB = Date(timeIntervalSince1970: 222_222)
        let points = [
            ThreeOmegaScalingAnglePoint(id: "p-neg", sourceID: "run-neg", sampleKey: "s1",
                                        device: "dev_-30deg", angleDeg: -30.0,
                                        alpha: -8.8e5, beta: -2.5e3, rSquared: 0.95,
                                        method: "HFE", fitRange: "30K–110K",
                                        generatedAt: genA, candidateID: "s1"),
            ThreeOmegaScalingAnglePoint(id: "p-30a", sourceID: "run-30a", sampleKey: "s1",
                                        device: "dev_A_30deg", angleDeg: 30.0,
                                        alpha: 4.5e5, beta: 1.2e3, rSquared: 0.97,
                                        method: "HFE", fitRange: "30K–110K",
                                        generatedAt: genA, candidateID: "s1"),
            ThreeOmegaScalingAnglePoint(id: "p-30b", sourceID: "run-30b", sampleKey: "s2",
                                        device: "dev_B_30deg", angleDeg: 30.0,
                                        alpha: 6.6e5, beta: 2.4e3, rSquared: 0.93,
                                        method: "HFE", fitRange: "30K–110K",
                                        generatedAt: genB, candidateID: "s2")
        ]
        return ThreeOmegaScalingVsAngleResult(
            points: points,
            warnings: ["Multiple records found for angle 30° (dev_A_30deg, dev_B_30deg)."],
            availableMethods: ["HFE", "WA"],
            availableFitRanges: ["30K–110K"],
            availableCandidates: ["s1", "s2"],
            selectedCoefficient: .alpha,
            selectedMethod: "HFE",
            selectedFitRange: "30K–110K",
            selectedCandidate: "s2"
        )
    }

    @Test("Analysis-pack export/import restores the displayed aggregate verbatim — no overwrite, averaging, or recomputation")
    func analysisPackRoundTripPreservesAggregate() throws {
        let original = makeRichAngleResult()
        let packResult = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "angle_sweep"),
            scalingResult: nil,
            scalingVsAngleResult: original
        )
        let config = ThreeOmegaPackConfig(
            device: "angle_sweep",
            geometry: ThreeOmegaGeometry(lxx: 100, lxy: 50, dNm: 10),
            fitRanges: [], v3Method: "highField", rahe1Method: "highField", rahe3Method: "highField",
            rtFilePath: nil, sampleBatchAndSubstrate: "batch", activeTab: "scalingVsAngle",
            titleTemplate: "", stackOffsetMultiplier: 1.0, minGapFraction: 0.15,
            showPlotGrid: true, plotLegendAnchor: "",
            scalingAngleCoefficient: "α", scalingAngleMethod: "HFE",
            scalingAngleFitRange: "30K–110K", scalingAngleCandidate: "s2"
        )

        let pack = try AnalysisPack(
            label: "AngleSweep", workflowID: "3w",
            filePaths: ["/a.lvm"], sampleKeys: ["s1", "s2"],
            config: config, result: packResult
        )
        let restored = try pack.decodeResult(ThreeOmegaPackResult.self)
        let angle = try #require(restored.scalingVsAngleResult)

        // Whole-aggregate equality: nothing dropped, reordered, or rescaled.
        #expect(angle == original)

        // Explicit field-level guarantees required by the acceptance criteria.
        #expect(angle.selectedCoefficient == .alpha)
        #expect(angle.selectedMethod == "HFE")
        #expect(angle.selectedFitRange == "30K–110K")
        #expect(angle.selectedCandidate == "s2")
        #expect(angle.points.map(\.angleDeg) == [-30.0, 30.0, 30.0])
        #expect(angle.points.map(\.beta) == [-2.5e3, 1.2e3, 2.4e3])
        #expect(angle.points.map(\.alpha) == [-8.8e5, 4.5e5, 6.6e5])
        // Provenance survives.
        #expect(angle.points.map(\.sourceID) == ["run-neg", "run-30a", "run-30b"])
        #expect(angle.points.map(\.generatedAt) == original.points.map(\.generatedAt))
        // Duplicate candidates stay distinct — not merged or averaged.
        #expect(Set(angle.points.filter { $0.angleDeg == 30.0 }.map(\.candidateID)) == ["s1", "s2"])
        #expect(angle.availableCandidates == ["s1", "s2"])
        // Diagnostics survive and still partition.
        #expect(angle.diagnostics.conflicting.contains { $0.contains("30°") })
    }

    @Test("Legacy pack without a persisted aggregate decodes to nil and still loads")
    func legacyPackResultDecodesWithoutAggregate() throws {
        let legacyJSON = """
        { "ingestionResult": { "fieldSweeps": [], "device": "legacy_dev" } }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ThreeOmegaPackResult.self, from: legacyJSON)
        #expect(decoded.scalingVsAngleResult == nil)
        #expect(decoded.ingestionResult.device == "legacy_dev")
    }

    @Test("ThreeOmegaPackResult JSON round trip keeps the aggregate byte-stable")
    func packResultJSONRoundTrip() throws {
        let original = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "d"),
            scalingResult: nil,
            scalingVsAngleResult: makeRichAngleResult()
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ThreeOmegaPackResult.self, from: data)
        #expect(decoded == original)
        #expect(decoded.scalingVsAngleResult?.points == original.scalingVsAngleResult?.points)
    }

    // MARK: - Data-lifecycle: save-to-library metadata (step 6)

    @Test("SaveActiveChartToLibraryUseCase persists the Scaling vs Angle selection metadata and keeps duplicate candidates distinct")
    func saveToLibraryPreservesSelectionAndDuplicateCandidates() throws {
        let (_, root) = try makeLibraryFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let result = makeRichAngleResult()
        let payload = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(
            result: result, device: "angle_sweep", coefficient: .alpha,
            method: "HFE", fitRange: "30K–110K", candidate: "s2"
        ))
        // The displayed chart keeps every final per-angle point as its own device series
        // (here: -30°, plus the two unresolved 30° candidates).
        #expect(payload.series.count == 3)
        #expect(Set(payload.series.compactMap { $0.metadata["device"] }) == ["dev_-30deg", "dev_A_30deg", "dev_B_30deg"])
        #expect(payload.series.flatMap(\.y).contains(-8.8e5))

        let outcome = SaveActiveChartToLibraryUseCase().execute(input: SaveActiveChartInput(
            png: Data([0x89, 0x50, 0x4E, 0x47]),
            payload: payload,
            sampleKeys: ["s1", "s2"],
            libraryRootPath: root.path
        ))
        guard case .success(let trace) = outcome else {
            Issue.record("save failed: \(outcome)"); return
        }

        // Selection configuration is carried in the persisted chart metadata.
        #expect(trace.semanticParams["coefficient"] == "α")
        #expect(trace.semanticParams["method"] == "HFE")
        #expect(trace.semanticParams["fitRange"] == "30K–110K")
        #expect(trace.semanticParams["candidate"] == "s2")

        // And it is actually on disk (not just in the in-memory trace).
        let manifestURL = root.appending(path: trace.manifestPath)
        let manifestDecoder = JSONDecoder()
        manifestDecoder.dateDecodingStrategy = .iso8601
        let manifest = try manifestDecoder.decode(
            WorkbenchRunManifest.self, from: Data(contentsOf: manifestURL))
        #expect(manifest.semanticParams["coefficient"] == "α")
        #expect(manifest.semanticParams["candidate"] == "s2")

        // Saving the other candidate produces a distinct artifact — no overwrite.
        let payloadS1 = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(
            result: result, device: "angle_sweep", coefficient: .alpha,
            method: "HFE", fitRange: "30K–110K", candidate: "s1"
        ))
        let outcomeS1 = SaveActiveChartToLibraryUseCase().execute(input: SaveActiveChartInput(
            png: Data([0x89, 0x50, 0x4E, 0x47]),
            payload: payloadS1,
            sampleKeys: ["s1", "s2"],
            libraryRootPath: root.path
        ))
        guard case .success(let traceS1) = outcomeS1 else {
            Issue.record("second save failed: \(outcomeS1)"); return
        }
        #expect(traceS1.manifestPath != trace.manifestPath)
    }

    // MARK: - Data-lifecycle: WorkbenchMeasurementDataStore active-workflow path (step 6)

    private func makeRichAngleConfig() -> ThreeOmegaPackConfig {
        ThreeOmegaPackConfig(
            device: "angle_sweep",
            geometry: ThreeOmegaGeometry(lxx: 100, lxy: 50, dNm: 10),
            fitRanges: [], v3Method: "highField", rahe1Method: "highField", rahe3Method: "highField",
            rtFilePath: nil, sampleBatchAndSubstrate: "batch", activeTab: "scalingVsAngle",
            titleTemplate: "", stackOffsetMultiplier: 1.0, minGapFraction: 0.15,
            showPlotGrid: true, plotLegendAnchor: "",
            scalingAngleCoefficient: "α", scalingAngleMethod: "HFE",
            scalingAngleFitRange: "30K–110K", scalingAngleCandidate: "s2"
        )
    }

    @MainActor
    @Test("WorkbenchMeasurementDataStore feeds the active Scaling vs Angle workspace workflow with no cross-device refit")
    func measurementStoreActiveWorkflowNoRecomputation() throws {
        let (resolver, root) = try makeLibraryFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        // Pre-computed independent per-device scaling artifacts (distinct signed values).
        let persisted: [(device: String, angle: Double, beta: Double, alpha: Double, r2: Double)] = [
            ("dev_+30deg", 30.0, 1.234567e3, -9.87654e5, 0.9911),
            ("dev_-30deg", -30.0, -4.44444e3, 3.33333e5, 0.9822),
            ("dev_0deg", 0.0, 7.0e2, 1.0e5, 0.9733)
        ]
        let persistUseCase = PersistMeasurementDataUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
        for row in persisted {
            for rec in makeMetricRecord(sampleKey: "SK", device: row.device,
                                        alpha: row.alpha, beta: row.beta, rSquared: row.r2) {
                try persistUseCase.execute(sampleKey: "SK", record: rec)
            }
        }

        // Drive the real workspace ingestion path: library root + cached sample keys, then refresh.
        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.lastLibraryRootPath = root.path
        store.cachedSampleKeys = ["SK"]
        store.scalingAngleCoefficient = .beta
        store._refreshScalingVsAngleResult()

        let result = try #require(store.scalingVsAngleResult)
        #expect(result.points.map(\.angleDeg) == [-30.0, 0.0, 30.0])

        // Values are the stored artifacts verbatim — not refit, averaged, or normalized.
        let byAngle = Dictionary(uniqueKeysWithValues: result.points.map { ($0.angleDeg, $0) })
        for row in persisted {
            let pt = try #require(byAngle[row.angle])
            #expect(pt.beta == row.beta)
            #expect(pt.alpha == row.alpha)
            #expect(pt.rSquared == row.r2)
            #expect(pt.device == row.device)
            #expect(pt.sampleKey == "SK")
        }
    }

    // MARK: - Data-lifecycle: real restoreFromPack path (step 6)

    @MainActor
    @Test("ThreeOmegaWorkspaceStore.restoreFromPack restores the active Scaling vs Angle workflow verbatim")
    func restoreFromPackRestoresActiveScalingVsAngleWorkflow() throws {
        let original = makeRichAngleResult()
        let packResult = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "angle_sweep"),
            scalingResult: nil,
            scalingVsAngleResult: original
        )
        let config = makeRichAngleConfig()
        let pack = try AnalysisPack(
            label: "AngleSweep", workflowID: "3w",
            filePaths: ["/a.lvm"], sampleKeys: ["s1", "s2"],
            config: config, result: packResult
        )

        // Exercise the real decode + restore path.
        let decodedResult = try JSONDecoder().decode(
            ThreeOmegaPackResult.self, from: JSONEncoder().encode(packResult))

        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.restoreFromPack(config: config, result: decodedResult, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        // Scalar selection restored.
        #expect(store.scalingAngleCoefficient == .alpha)
        #expect(store.scalingAngleMethod == "HFE")
        #expect(store.scalingAngleFitRange == "30K–110K")
        #expect(store.scalingAngleCandidate == "s2")

        let restored = try #require(store.scalingVsAngleResult)
        // Whole-aggregate equality: nothing recomputed, reordered, averaged, or normalized.
        #expect(restored == original)
        #expect(restored.selectedCoefficient == .alpha)
        #expect(restored.selectedMethod == "HFE")
        #expect(restored.selectedFitRange == "30K–110K")
        #expect(restored.selectedCandidate == "s2")
        #expect(restored.points.map(\.angleDeg) == [-30.0, 30.0, 30.0])
        #expect(restored.points.map(\.beta) == [-2.5e3, 1.2e3, 2.4e3])
        #expect(restored.points.map(\.alpha) == [-8.8e5, 4.5e5, 6.6e5])
        // Provenance survives.
        #expect(restored.points.map(\.sourceID) == ["run-neg", "run-30a", "run-30b"])
        #expect(restored.points.map(\.generatedAt) == original.points.map(\.generatedAt))
        // Distinct duplicate candidates for the colliding angle.
        #expect(Set(restored.points.filter { $0.angleDeg == 30.0 }.map(\.candidateID)) == ["s1", "s2"])
        #expect(restored.availableCandidates == ["s1", "s2"])
        // Diagnostics survive and still partition.
        #expect(restored.diagnostics.conflicting.contains { $0.contains("30°") })
        // Table projection over the restored aggregate keeps order + signs.
        #expect(restored.tableRows(coefficient: .alpha).map(\.coefficientValue) == [-8.8e5, 4.5e5, 6.6e5])
    }

    @MainActor
    @Test("restoreFromPack falls back to independent-artifact rebuild for a legacy pack without the aggregate")
    func restoreFromPackLegacyFallbackRebuildsFromArtifacts() throws {
        let packResult = ThreeOmegaPackResult(
            ingestionResult: ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "angle_sweep"),
            scalingResult: nil,
            scalingVsAngleResult: nil
        )
        let config = makeRichAngleConfig()
        let pack = try AnalysisPack(
            label: "Legacy", workflowID: "3w",
            filePaths: [], sampleKeys: [],
            config: config, result: packResult
        )

        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.restoreFromPack(config: config, result: packResult, pack: pack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in })

        // Legacy path still restores the scalar selection and produces an (empty) aggregate
        // without crashing or recomputing scaling physics.
        #expect(store.scalingAngleCoefficient == .alpha)
        #expect(store.scalingVsAngleResult != nil)
        #expect(store.scalingVsAngleResult?.points.isEmpty == true)
    }

    // MARK: - Data-lifecycle: save-to-library persisted metadata (step 6)

    // MARK: - Repair A: angle chart save must not self-feed Library metrics

    @MainActor
    @Test("Repair A — Scaling vs Angle active chart save writes NO α/β/R² measurement metrics")
    func angleChartSaveDoesNotWriteScientificMetrics() throws {
        let (resolver, root) = try makeLibraryFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        // Library already holds saved single-device Scaling results at 0° and 30°.
        let persistUseCase = PersistMeasurementDataUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
        for rec in makeMetricRecord(sampleKey: "SK", runID: "runA", device: "dev_0deg", beta: 10.0, rSquared: 0.99)
            + makeMetricRecord(sampleKey: "SK", runID: "runB", device: "dev_30deg", beta: 20.0, rSquared: 0.98) {
            try persistUseCase.execute(sampleKey: "SK", record: rec)
        }

        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.lastLibraryRootPath = root.path
        store.cachedSampleKeys = ["SK"]
        store.tabs.activeTab = .scalingVsAngle
        store.scalingAngleCoefficient = .beta
        store._refreshScalingVsAngleResult()

        let before = try #require(store.scalingVsAngleResult)
        #expect(before.points.map(\.angleDeg) == [0.0, 30.0])

        // The save-facing metric builder contributes nothing scientific.
        #expect(store.buildActiveChartMetrics().isEmpty)

        // Simulate the real save with whatever the store produced.
        let payload = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(
            result: before, device: "angle_sweep", coefficient: .beta, method: "HFE", fitRange: "30K–110K"))
        let outcome = SaveActiveChartToLibraryUseCase().execute(input: SaveActiveChartInput(
            png: Data([0x89, 0x50, 0x4E, 0x47]),
            payload: payload,
            sampleKeys: ["SK"],
            libraryRootPath: root.path,
            metrics: store.buildActiveChartMetrics()
        ))
        guard case .success = outcome else { Issue.record("save failed: \(outcome)"); return }

        // Reload from Library: no new α/β/R² rows, candidate/angle counts unchanged.
        let reloaded = try #require(LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK"))
        let scalingRows = reloaded.records.filter {
            $0.workflowID == "3w" && ["alpha", "beta", "r_squared"].contains($0.metric)
        }
        #expect(scalingRows.count == 4)   // 2 beta + 2 r_squared, exactly what we seeded

        store._refreshScalingVsAngleResult()
        let after = try #require(store.scalingVsAngleResult)
        #expect(after.points.map(\.angleDeg) == [0.0, 30.0])
        #expect(after.points.count == before.points.count)
        #expect(after.availableCandidates == before.availableCandidates)
    }

    // MARK: - Repair B/C: real fit/run identity, per-angle resolution

    @Test("Repair B — same sample/device/method/range, different runID → two distinct fit candidates, no average / overwrite")
    func sameSampleDeviceRepeatedRunsStayDistinct() {
        let recs = makeMetricRecord(sampleKey: "PN80", runID: "run-A", device: "device_30deg",
                                    method: "HFE", range: "30K–110K", beta: -85.4)
            + makeMetricRecord(sampleKey: "PN80", runID: "run-B", device: "device_30deg",
                               method: "HFE", range: "30K–110K", beta: -78.1)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let all = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "HFE", selectedFitRange: "30K–110K")

        // Both fits survive; ambiguity recognised; nothing averaged/overwritten.
        #expect(all.points.count == 2)
        #expect(all.points.compactMap(\.beta).sorted() == [-85.4, -78.1].sorted())
        #expect(all.ambiguousAnglesByKey["30"] == ["PN80|run-A", "PN80|run-B"])

        let pickA = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "HFE",
                                    selectedFitRange: "30K–110K", candidateSelections: ["30": "PN80|run-A"])
        #expect(pickA.points.compactMap(\.beta) == [-85.4])

        let pickB = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "HFE",
                                    selectedFitRange: "30K–110K", candidateSelections: ["30": "PN80|run-B"])
        #expect(pickB.points.compactMap(\.beta) == [-78.1])
    }

    @Test("Repair C — resolving one ambiguous angle never filters out the other angles")
    func perAngleResolutionKeepsOtherAngles() {
        let recs = makeMetricRecord(sampleKey: "PN80", runID: "run-0", device: "device_0deg", beta: 5.0)
            + makeMetricRecord(sampleKey: "PN80", runID: "run-30A", device: "device_30deg", beta: 30.1)
            + makeMetricRecord(sampleKey: "PN80", runID: "run-30B", device: "device_30deg", beta: 30.2)
            + makeMetricRecord(sampleKey: "PN80", runID: "run-60", device: "device_60deg", beta: 6.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let picked = useCase.execute(records: recs, selectedCoefficient: .beta,
                                     candidateSelections: ["30": "PN80|run-30B"])

        #expect(picked.points.map(\.angleDeg) == [0.0, 30.0, 60.0])
        #expect(picked.points.first { $0.angleDeg == 30.0 }?.beta == 30.2)
        #expect(picked.points.first { $0.angleDeg == 0.0 }?.beta == 5.0)
        #expect(picked.points.first { $0.angleDeg == 60.0 }?.beta == 6.0)
        // Only the 30° selection changed.
        #expect(picked.ambiguousAnglesByKey.keys.sorted() == ["30"])
    }

    // MARK: - Repair D: Library-only source

    @MainActor
    @Test("Repair D — an unsaved in-memory scaling result does not enter Scaling vs Angle")
    func libraryOnlySourceExcludesUnsavedResult() throws {
        let (resolver, root) = try makeLibraryFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        // Library: only 0° saved.
        let persistUseCase = PersistMeasurementDataUseCase(writer: AtomicFileWriter(), pathResolver: resolver)
        for rec in makeMetricRecord(sampleKey: "SK", runID: "run0", device: "dev_0deg", beta: 1.0) {
            try persistUseCase.execute(sampleKey: "SK", record: rec)
        }

        let store = ThreeOmegaWorkspaceStore(workflowID: WorkflowKey.threeOmega.rawValue)
        store.lastLibraryRootPath = root.path
        store.cachedSampleKeys = ["SK"]
        store.scalingAngleCoefficient = .beta
        // A 30° result exists only in memory (not yet saved to Library).
        store.scalingResult = ThreeOmegaScalingResult(
            points: [],
            segments: [ThreeOmegaScalingSegment(
                id: UUID(), tLo: 30, tHi: 110, alpha: 1, beta: 2, rSquared: 0.9,
                pointCount: 0, participatingXValues: [])]
        )
        store.ingestionResult = ThreeOmegaIngestionResult(fieldSweeps: [], rtResult: nil, device: "dev_30deg")
        store._refreshScalingVsAngleResult()

        let result = try #require(store.scalingVsAngleResult)
        #expect(result.points.map(\.angleDeg) == [0.0])

        // After the 30° result is actually saved, it appears.
        for rec in makeMetricRecord(sampleKey: "SK", runID: "run30", device: "dev_30deg", beta: 2.0) {
            try persistUseCase.execute(sampleKey: "SK", record: rec)
        }
        store._refreshScalingVsAngleResult()
        #expect(try #require(store.scalingVsAngleResult).points.map(\.angleDeg) == [0.0, 30.0])
    }

    // MARK: - Repair E: missing method must not silently enter HFE / WA

    @Test("Repair E — a record with no method is not silently folded into the HFE plot")
    func missingMethodExcludedFromHFE() {
        let recs = makeMetricRecord(sampleKey: "s1", runID: "rA", device: "device_30deg", method: "", beta: 1.0)
            + makeMetricRecord(sampleKey: "s1", runID: "rB", device: "device_30deg", method: "HFE", beta: 2.0)

        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let hfe = useCase.execute(records: recs, selectedCoefficient: .beta, selectedMethod: "HFE")

        #expect(hfe.points.compactMap(\.beta) == [2.0])
        #expect(hfe.warnings.contains { $0.lowercased().contains("no recognized method") })
        #expect(hfe.diagnostics.missing.contains { $0.lowercased().contains("no recognized method") })
    }

    // MARK: - Legend integration: device is the legend dimension, identity is provenance only

    private func resolveLegend(_ payload: WorkbenchPlotPayload)
        -> (labels: [String], dimension: String?, status: LegendResolutionStatus) {
        let r = LegendResolver.resolveDimension(
            semanticLabels: payload.series.map(\.label),
            seriesMetadata: payload.series.map(\.metadata)
        )
        return (r.labels, r.legendDimensionDisplayName, r.status)
    }

    @Test("Legend test 1 — device is the resolved legend dimension; candidate/runID never appears")
    func legendDeviceIsDimensionNotCandidate() throws {
        let pts = [
            ThreeOmegaScalingAnglePoint(sourceID: "run-\(UUID())", device: "0deg", angleDeg: 0, beta: 1.0, candidateID: "SK|run-\(UUID())"),
            ThreeOmegaScalingAnglePoint(sourceID: "run-\(UUID())", device: "30deg", angleDeg: 30, beta: 2.0, candidateID: "SK|run-\(UUID())"),
            ThreeOmegaScalingAnglePoint(sourceID: "run-\(UUID())", device: "60deg", angleDeg: 60, beta: 3.0, candidateID: "SK|run-\(UUID())"),
            ThreeOmegaScalingAnglePoint(sourceID: "run-\(UUID())", device: "90deg", angleDeg: 90, beta: 4.0, candidateID: "SK|run-\(UUID())")
        ]
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .beta)
        let payload = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .beta))

        let legend = resolveLegend(payload)
        #expect(legend.status == .resolved(dimension: "Device"))
        #expect(legend.dimension == "Device")
        #expect(legend.labels == ["0deg", "30deg", "60deg", "90deg"])

        // No legend label leaks an internal identity token.
        let identityTokens = pts.map(\.candidateID) + pts.map(\.sourceID)
        for label in legend.labels {
            #expect(!identityTokens.contains(label))
            #expect(!label.contains("run-"))
            #expect(!label.contains("|"))
        }
    }

    @Test("Legend test 2 — default series order follows numeric angle, not lexical device strings")
    func legendNumericAngleOrdering() throws {
        let pts = [90.0, 0.0, 180.0, 30.0, 120.0, 60.0].map {
            ThreeOmegaScalingAnglePoint(device: "\(Int($0))deg", angleDeg: $0, beta: $0)
        }
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .beta)
        let payload = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .beta))

        #expect(payload.series.compactMap { $0.metadata["device"] }
            == ["0deg", "30deg", "60deg", "90deg", "120deg", "180deg"])
        #expect(resolveLegend(payload).labels
            == ["0deg", "30deg", "60deg", "90deg", "120deg", "180deg"])
    }

    @Test("Legend test 3 — candidate choice is provenance only; legend still shows device")
    func legendCandidateChoiceIsProvenanceOnly() throws {
        // Angle 30 had run-A and run-B; the store picked run-B. The renderer receives the
        // final 30° point only.
        let recs = makeMetricRecord(sampleKey: "SK", runID: "run-0", device: "device_0deg", beta: 5.0)
            + makeMetricRecord(sampleKey: "SK", runID: "run-A", device: "device_30deg", beta: 30.1)
            + makeMetricRecord(sampleKey: "SK", runID: "run-B", device: "device_30deg", beta: 30.2)

        let result = ThreeOmegaScalingVsAngleUseCase().execute(
            records: recs, selectedCoefficient: .beta, candidateSelections: ["30": "SK|run-B"])
        #expect(result.points.first { $0.angleDeg == 30 }?.beta == 30.2)

        let payload = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .beta))
        let legend = resolveLegend(payload)
        #expect(legend.labels == ["device_0deg", "device_30deg"])
        for label in legend.labels { #expect(!label.contains("run-")) }
    }

    @Test("Legend test 4 — switching candidate at one angle changes only that y value, not the legend")
    func legendStableAcrossCandidateSwitch() throws {
        let recs = makeMetricRecord(sampleKey: "SK", runID: "run-0", device: "device_0deg", beta: 5.0)
            + makeMetricRecord(sampleKey: "SK", runID: "run-A", device: "device_30deg", beta: 30.1)
            + makeMetricRecord(sampleKey: "SK", runID: "run-B", device: "device_30deg", beta: 30.2)
            + makeMetricRecord(sampleKey: "SK", runID: "run-60", device: "device_60deg", beta: 6.0)
        let useCase = ThreeOmegaScalingVsAngleUseCase()
        let renderer = ThreeOmegaPlotRenderer()

        func legendAndY(_ selection: String) throws -> (labels: [String], y30: Double?) {
            let result = useCase.execute(records: recs, selectedCoefficient: .beta,
                                         candidateSelections: ["30": selection])
            let payload = try #require(renderer.makeScalingVsAnglePayload(result: result, coefficient: .beta))
            let idx = payload.series.firstIndex { $0.metadata["device"] == "device_30deg" }
            return (resolveLegend(payload).labels, idx.flatMap { payload.series[$0].y.first })
        }

        let a = try legendAndY("SK|run-A")
        let b = try legendAndY("SK|run-B")
        #expect(a.labels == ["device_0deg", "device_30deg", "device_60deg"])
        #expect(b.labels == a.labels)
        #expect(a.y30 == 30.1)
        #expect(b.y30 == 30.2)
    }

    @Test("Legend test 5 — negative angle sorts numerically and maps to its device label")
    func legendNegativeAngleOrdering() throws {
        let pts = [
            ThreeOmegaScalingAnglePoint(device: "30deg", angleDeg: 30, beta: 3),
            ThreeOmegaScalingAnglePoint(device: "-30deg", angleDeg: -30, beta: -3),
            ThreeOmegaScalingAnglePoint(device: "0deg", angleDeg: 0, beta: 0)
        ]
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .beta)
        let payload = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .beta))
        #expect(payload.series.flatMap(\.x) == [-30.0, 0.0, 30.0])
        #expect(resolveLegend(payload).labels == ["-30deg", "0deg", "30deg"])
    }

    @Test("Legend end-to-end — full render pipeline shows device values in legend rows")
    func legendEndToEndThroughRenderPipeline() throws {
        let pts = [
            ThreeOmegaScalingAnglePoint(device: "0deg", angleDeg: 0, beta: 1.0, candidateID: "SK|run-1"),
            ThreeOmegaScalingAnglePoint(device: "30deg", angleDeg: 30, beta: 2.0, candidateID: "SK|run-2"),
            ThreeOmegaScalingAnglePoint(device: "90deg", angleDeg: 90, beta: 3.0, candidateID: "SK|run-3")
        ]
        let result = ThreeOmegaScalingVsAngleResult(points: pts, selectedCoefficient: .beta)
        let payload = try #require(ThreeOmegaPlotRenderer().makeScalingVsAnglePayload(result: result, coefficient: .beta))

        let output = try WorkbenchRenderPipeline.render(WorkbenchRenderPipeline.Input(payload: payload))
        let rowLabels = output.layout.legendRows.map(\.originalLabel)
        #expect(rowLabels == ["0deg", "30deg", "90deg"])
        for label in rowLabels { #expect(!label.contains("run-") && !label.contains("|")) }

        // Contract guard is satisfied by the real payload.
        #expect(LegendIntegrationContract.diagnostics(for: payload.series).isEmpty)
    }

    @Test("PackConfig backward compatibility: decodes legacy JSON without scalingAngle fields")
    func packConfigBackwardCompatibility() throws {
        let legacyJSON = """
        {
            "device": "0deg",
            "geometry": { "lxx": 100.0, "lxy": 50.0, "dNm": 10.0 },
            "fitRanges": [],
            "v3Method": "highField",
            "sampleBatchAndSubstrate": "sample-batch",
            "activeTab": "scaling",
            "stackOffsetMultiplier": 1.2,
            "showPlotGrid": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let config = try decoder.decode(ThreeOmegaPackConfig.self, from: legacyJSON)
        #expect(config.scalingAngleCoefficient == nil)
        #expect(config.scalingAngleMethod == nil)
        #expect(config.scalingAngleFitRange == nil)
        #expect(config.scalingAngleCandidate == nil)
    }
}
