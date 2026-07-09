import Testing
@testable import SpinLabApp

/// v5.5.6 — magnitude-based magnetic-field display unit selection.
///
/// H and Hc share `WorkbenchMagneticFieldDisplayPolicy`, but remain distinct
/// `WorkbenchPhysicalQuantity` identities (`externalMagneticField` / `coerciveField`). The unit
/// this policy selects must drive both the numeric conversion and the label — never inferred
/// from label text. See docs/architecture/workbench/PLOT_DISPLAY_SPEC.md.
@Suite("v5.5.6 - Magnetic field magnitude-based display unit")
struct V557MagneticFieldMagnitudeDisplayUnitTests {

    // MARK: - Policy: unit selection by magnitude

    @Test("preferred unit is mT when max abs magnitude < 1 T")
    func preferredUnitIsMilliteslaBelowOneTesla() {
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: [-0.05, 0, 0.05]) == .millitesla)
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: [-0.5, 0, 0.5]) == .millitesla)
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: [0.9999]) == .millitesla)
    }

    @Test("preferred unit is T when max abs magnitude >= 1 T")
    func preferredUnitIsTeslaAtOrAboveOneTesla() {
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: [1.0]) == .tesla)
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: [-7, 0, 7]) == .tesla)
    }

    @Test("preferred unit defaults to T when there are no values to measure")
    func preferredUnitDefaultsToTeslaWhenEmpty() {
        // A manifest skeleton built before any field-sweep data is ingested has no values yet —
        // must not silently fall back to mT, matching the pre-existing default (V2A1 purity test).
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: []) == .tesla)
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(values: [], sourceUnit: .oersted) == .tesla)
    }

    @Test("preferredUnit(values:sourceUnit:) converts to Tesla before comparing magnitude")
    func preferredUnitFromSourceUnit() {
        // 500 Oe = 0.05 T -> mT; 20000 Oe = 2 T -> T
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(values: [-500, 500], sourceUnit: .oersted) == .millitesla)
        #expect(WorkbenchMagneticFieldDisplayPolicy.preferredUnit(values: [-20000, 20000], sourceUnit: .oersted) == .tesla)
    }

    // MARK: - Labels match the selected unit (H and Hc are distinct identities, same selector)

    @Test("labels reflect selected unit for both externalMagneticField and coerciveField")
    func labelsMatchSelectedUnit() {
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .externalMagneticField, context: .plotAxis, unit: .millitesla) == "μ₀H (mT)")
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .externalMagneticField, context: .plotAxis, unit: .tesla) == "μ₀H (T)")
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .plotAxis, unit: .millitesla) == "μ₀Hc (mT)")
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .plotAxis, unit: .tesla) == "μ₀Hc (T)")
    }

    // MARK: - 3ω field sweep (H): small range -> mT, large range -> T

    @Test("3ω field sweep with small range (±0.05 T) displays in mT with converted values")
    func fieldSweepSmallRangeUsesMillitesla() throws {
        // hField is canonical internal Tesla (post Oe→Tesla migration); ±500 Oe = ±0.05 T.
        let sweep = makeSweep(hField: [-0.05, 0, 0.05])
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeR1omegaPayload(sweeps: [sweep], device: "0deg"))
        let series = try #require(payload.series.first)

        #expect(payload.axisMapping.xField == "μ₀H (mT)")
        #expect(series.x == [-50.0, 0.0, 50.0])
    }

    @Test("3ω field sweep with large range (±7 T) displays in T with converted values")
    func fieldSweepLargeRangeUsesTesla() throws {
        // hField is canonical internal Tesla; ±70000 Oe = ±7 T.
        let sweep = makeSweep(hField: [-7, 0, 7])
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeR1omegaPayload(sweeps: [sweep], device: "0deg"))
        let series = try #require(payload.series.first)

        #expect(payload.axisMapping.xField == "μ₀H (T)")
        #expect(series.x == [-7.0, 0.0, 7.0])
    }

    // MARK: - Hc-vs-T (coerciveField): small Hc -> mT, large Hc -> T

    @Test("Hc-vs-T with small Hc values displays in mT with converted values")
    func hcVsTSmallValuesUsesMillitesla() throws {
        // hc1omega/hc3omega are canonical internal Tesla; 500 Oe = 0.05 T, 250 Oe = 0.025 T ->
        // both well under 1 T.
        let sweep = makeSweep(hField: [-0.1, 0, 0.1], hc1omega: 0.05, hc3omega: 0.025)
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeHcPayload(sweeps: [sweep], device: "0deg"))
        let hc1Series = try #require(payload.series.first { $0.label == ThreeOmegaPlotRenderer.hc1LegendLabel })
        let hc3Series = try #require(payload.series.first { $0.label == ThreeOmegaPlotRenderer.hc3LegendLabel })

        #expect(payload.axisMapping.yField == "μ₀Hc (mT)")
        #expect(hc1Series.y == [50.0])
        #expect(hc3Series.y == [25.0])
    }

    @Test("Hc-vs-T with large Hc values displays in T with converted values")
    func hcVsTLargeValuesUsesTesla() throws {
        // hc1omega/hc3omega are canonical internal Tesla; 70000 Oe = 7 T -> at/above 1 T threshold.
        let sweep = makeSweep(hField: [-0.1, 0, 0.1], hc1omega: 7.0, hc3omega: 2.0)
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeHcPayload(sweeps: [sweep], device: "0deg"))
        let hc1Series = try #require(payload.series.first { $0.label == ThreeOmegaPlotRenderer.hc1LegendLabel })
        let hc3Series = try #require(payload.series.first { $0.label == ThreeOmegaPlotRenderer.hc3LegendLabel })

        #expect(payload.axisMapping.yField == "μ₀Hc (T)")
        #expect(hc1Series.y == [7.0])
        #expect(hc3Series.y == [2.0])
    }

    // MARK: - AHE remains unaffected by this policy

    @Test("AHE field/Hc identity keys and display label remain unaffected by the magnitude policy")
    func aheUnaffectedByMagnitudePolicy() {
        #expect(AHEDataFieldKey.hc.rawValue == "Hc")
        #expect(AHEDataFieldKey.rAHE.rawValue == "R_AHE")
        #expect(AHEAxisDetector.displayXField == "H (T)")
        #expect(AHEAxisDetector.displayXField != "μ₀H (T)")
        #expect(AHEAxisDetector.displayXField != "μ₀H (mT)")
    }

    // MARK: - Fixtures

    private func makeSweep(
        hField: [Double],
        hc1omega: Double? = nil,
        hc3omega: Double? = nil
    ) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: nil,
            hField: hField,
            r1omega: hField.map { _ in 1.0 },
            r3omega: hField.map { _ in 2.0 },
            iRms: 1e-3,
            rahe1omega: nil,
            rahe1omegaWA: nil,
            hc1omega: hc1omega,
            hc3omega: hc3omega,
            v3omegaWindow: 0.0,
            v3omegaFit: nil
        )
    }
}
