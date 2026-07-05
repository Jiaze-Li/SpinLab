import Testing
@testable import SpinLabApp

/// v5.5.6 — magnetic-field display unit architecture (H / Hc).
///
/// Locks the conversion factors, the new display labels, and the persisted-key/AHE boundaries
/// this migration must not cross. See docs/architecture/workbench/PLOT_DISPLAY_SPEC.md §4 and
/// UNIT_LABEL_AUDIT.md §5 item 7 for the approved target this test enforces.
@Suite("v5.5.6 - Magnetic field unit conversion")
struct V556MagneticFieldUnitConversionTests {

    // MARK: - Conversion factors

    @Test("Oe -> T is ×1e-4")
    func oeToTesla() {
        #expect(WorkbenchMagneticFieldUnitConverter.convert(10000, from: .oersted, to: .tesla) == 1.0)
        #expect(WorkbenchMagneticFieldUnitConverter.convert(1, from: .oersted, to: .tesla) == 1e-4)
    }

    @Test("Oe -> mT is ×0.1")
    func oeToMillitesla() {
        #expect(WorkbenchMagneticFieldUnitConverter.convert(10, from: .oersted, to: .millitesla) == 1.0)
        #expect(WorkbenchMagneticFieldUnitConverter.convert(1, from: .oersted, to: .millitesla) == 0.1)
    }

    @Test("T -> mT is ×1000")
    func teslaToMillitesla() {
        #expect(WorkbenchMagneticFieldUnitConverter.convert(1, from: .tesla, to: .millitesla) == 1000)
    }

    @Test("mT -> T is ×1e-3")
    func milliteslaToTesla() {
        #expect(WorkbenchMagneticFieldUnitConverter.convert(1000, from: .millitesla, to: .tesla) == 1.0)
        #expect(WorkbenchMagneticFieldUnitConverter.convert(1, from: .millitesla, to: .tesla) == 1e-3)
    }

    @Test("same-unit conversion is a no-op")
    func sameUnitNoOp() {
        #expect(WorkbenchMagneticFieldUnitConverter.convert(42, from: .tesla, to: .tesla) == 42)
        #expect(WorkbenchMagneticFieldUnitConverter.convert(42, from: .oersted, to: .oersted) == 42)
        #expect(WorkbenchMagneticFieldUnitConverter.convert(42, from: .millitesla, to: .millitesla) == 42)
    }

    // MARK: - Display labels

    @Test("externalMagneticField + T => μ₀H (T)")
    func externalFieldTeslaLabel() {
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .externalMagneticField, context: .plotAxis, unit: .tesla) == "μ₀H (T)")
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .externalMagneticField, context: .manifestPlainText, unit: .tesla) == "μ₀H (T)")
    }

    @Test("externalMagneticField + mT => μ₀H (mT)")
    func externalFieldMilliteslaLabel() {
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .externalMagneticField, context: .plotAxis, unit: .millitesla) == "μ₀H (mT)")
    }

    @Test("coerciveField + T => μ₀Hc (T)")
    func coerciveFieldTeslaLabel() {
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .plotAxis, unit: .tesla) == "μ₀Hc (T)")
    }

    @Test("coerciveField + mT => μ₀Hc (mT)")
    func coerciveFieldMilliteslaLabel() {
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .plotAxis, unit: .millitesla) == "μ₀Hc (mT)")
        #expect(WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .manifestPlainText, unit: .millitesla) == "μ₀Hc (mT)")
    }

    // MARK: - 3ω renderer applies the phase-5 policy (H in T, Hc in mT)

    @Test("ThreeOmegaPlotRenderer field axis label is μ₀H (T)")
    func rendererFieldAxisLabel() {
        #expect(ThreeOmegaPlotRenderer.fieldAxisLabel == "μ₀H (T)")
    }

    @Test("ThreeOmegaPlotRenderer Hc axis label is μ₀Hc (mT)")
    func rendererHcAxisLabel() {
        #expect(ThreeOmegaPlotRenderer.hcAxisLabel == "μ₀Hc (mT)")
    }

    @Test("makeHcPayload converts raw Oe hc1omega/hc3omega values to mT")
    func hcPayloadValuesConvertedToMillitesla() throws {
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: nil,
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: nil,
            rahe1omegaWA: nil,
            hc1omega: 500,   // Oe
            hc3omega: 250,   // Oe
            v3omegaWindow: 0.0,
            v3omegaFit: nil
        )
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeHcPayload(sweeps: [sweep], device: "0deg"))

        let hc1Series = try #require(payload.series.first { $0.label == ThreeOmegaPlotRenderer.hc1LegendLabel })
        let hc3Series = try #require(payload.series.first { $0.label == ThreeOmegaPlotRenderer.hc3LegendLabel })
        #expect(hc1Series.y == [50.0])   // 500 Oe * 0.1 = 50 mT
        #expect(hc3Series.y == [25.0])   // 250 Oe * 0.1 = 25 mT
    }

    @Test("makeR1omegaPayload converts raw Oe hField values to T")
    func fieldSweepValuesConvertedToTesla() throws {
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 100,
            device: "0deg",
            sampleMetadata: nil,
            hField: [-10000, 0, 10000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: nil,
            rahe1omegaWA: nil,
            hc1omega: nil,
            hc3omega: nil,
            v3omegaWindow: 0.0,
            v3omegaFit: nil
        )
        let renderer = ThreeOmegaPlotRenderer()
        let payload = try #require(renderer.makeR1omegaPayload(sweeps: [sweep], device: "0deg"))
        let series = try #require(payload.series.first)
        #expect(series.x == [-1.0, 0.0, 1.0])   // Oe / 10000 = T
    }

    // MARK: - Persisted-key / AHE boundary (must not be touched by this migration)

    @Test("AHE semantic field label stays 'H (T)', not migrated to μ₀H (T)")
    func aheFieldLabelUnaffected() {
        #expect(AHEAxisDetector.displayXField == "H (T)")
        #expect(AHEAxisDetector.displayXField != "μ₀H (T)")
    }

    @Test("WorkbenchPlotDisplayVocabulary.label (generic, non-unit-aware) stays legacy for AHE consumers")
    func genericLabelStaysLegacy() {
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .manifestPlainText) == "H (T)")
        #expect(WorkbenchPlotDisplayVocabulary.label(for: .coerciveField, context: .manifestPlainText) == "Hc (Oe)")
    }
}
