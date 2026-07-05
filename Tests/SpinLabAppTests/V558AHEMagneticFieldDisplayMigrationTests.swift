import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.6 — AHE magnetic-field visible-label migration.
///
/// AHE's data/display decoupling (AHEDataFieldKey, AHEAxisDetector.displayXField/YField) is
/// already in place (see AHE_LABEL_KEY_AUDIT.md). This suite locks the follow-on migration:
/// AHE's rendered field-sweep axis now routes through `WorkbenchMagneticFieldDisplayPolicy` /
/// `WorkbenchPlotDisplayVocabulary.magneticFieldLabel`, same as 3ω.
///
/// Key architectural invariant this suite protects: `AHEIngestionResult.series.x` (persisted in
/// the pack) is always canonical Tesla — `IngestAHESelectionsUseCase` is untouched by this
/// migration. `BuildAHEPlotPayloadUseCase` derives a *fresh, display-only* re-scaled series and
/// label on every render (including pack restore), so old and new packs both render correctly
/// with no schema change and no restore ambiguity. Extraction (`ExtractAHEMetricsUseCase`,
/// persisted "Hc"/"R_AHE" metrics) reads the untouched Tesla-scale ingestion series directly and
/// is fully unaffected — canonicalUnit stays "T" regardless of what the chart displays.
@Suite("v5.5.6 - AHE magnetic field display migration")
struct V558AHEMagneticFieldDisplayMigrationTests {

    // MARK: - Field-sweep axis: small range -> mT, large range -> T

    @Test("AHE field-sweep small range (±0.05 T) displays in mT with converted values")
    func fieldSweepSmallRangeUsesMillitesla() {
        let ingestion = makeIngestion(xTesla: [-0.05, 0, 0.05])
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE Test")

        #expect(payload.axisMapping.xField == "μ₀H (mT)")
        #expect(payload.series.first?.x == [-50.0, 0.0, 50.0])
    }

    @Test("AHE field-sweep large range (±7 T) displays in T with converted values")
    func fieldSweepLargeRangeUsesTesla() {
        let ingestion = makeIngestion(xTesla: [-7, 0, 7])
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE Test")

        #expect(payload.axisMapping.xField == "μ₀H (T)")
        #expect(payload.series.first?.x == [-7.0, 0.0, 7.0])
    }

    @Test("empty ingestion series defaults to T (no data to measure magnitude from)")
    func emptySeriesDefaultsToTesla() {
        let ingestion = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: AHEAxisDetector.displayXField, yField: AHEAxisDetector.displayYField),
            series: [], sourceFiles: [], warnings: []
        )
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE Test")
        #expect(payload.axisMapping.xField == "μ₀H (T)")
    }

    // MARK: - Hc display (derived from the same H-axis data — same selected unit as the chart)

    @Test("AHE Hc small values: same-magnitude selection yields mT with converted values")
    func hcSmallValuesUsesMillitesla() {
        // Hc is extracted from the H-axis series (already Tesla) — the UI's read-only
        // auto-detected text (AHEWorkspaceView) shares the chart's selected unit, computed the
        // same way `AHEWorkspaceStore.fieldDisplayUnit` does.
        let hcTesla = 0.05
        let unit = WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: [-0.05, 0, 0.05])
        let converted = WorkbenchMagneticFieldUnitConverter.convert(hcTesla, from: .tesla, to: unit)
        let label = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .uiText, unit: unit)

        #expect(unit == .millitesla)
        #expect(converted == 50.0)
        #expect(label == "μ₀Hc (mT)")
    }

    @Test("AHE Hc large values: same-magnitude selection yields T with converted values")
    func hcLargeValuesUsesTesla() {
        let hcTesla = 7.0
        let unit = WorkbenchMagneticFieldDisplayPolicy.preferredUnit(canonicalTeslaValues: [-7, 0, 7])
        let converted = WorkbenchMagneticFieldUnitConverter.convert(hcTesla, from: .tesla, to: unit)
        let label = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(for: .coerciveField, context: .uiText, unit: unit)

        #expect(unit == .tesla)
        #expect(converted == 7.0)
        #expect(label == "μ₀Hc (T)")
    }

    // MARK: - Persisted keys / extraction pipeline unaffected by the display-only re-scaling

    @MainActor
    @Test("persisted 'Hc'/'R_AHE' keys and canonicalUnit 'T' are unaffected even when the chart displays mT")
    func persistedKeysUnaffectedByDisplayUnit() async throws {
        let fixture = try AHEMigrationFixture()
        defer { fixture.cleanup() }
        // Small raw Oe range -> chart will display mT, but persisted Hc must still be Tesla-scale
        // under canonicalUnit "T" (extraction reads the untouched ingestion series directly).
        let url = try fixture.write(name: "f.dat", content: AHEMigrationFixtureContent.smallFieldRange)

        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.cachedSearchResults = [makeHit(sourceFilePath: url.path)]
        store.runAnalysis()

        var attempts = 0
        while store.isPlotRendering && attempts < 60 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        #expect(store.fieldDisplayUnit == .millitesla, "small raw-Oe range should select mT for display")

        let entries = store.buildActiveChartMetrics()
        #expect(!entries.isEmpty)
        let metricNames = Set(entries.map(\.metric))
        #expect(metricNames == ["Hc", "R_AHE"])
        for entry in entries where entry.metric == "Hc" {
            #expect(entry.canonicalUnit == "T", "persisted Hc must stay Tesla-scale regardless of the chart's display unit")
        }
    }

    // MARK: - Pack restore: old/default packs render the current label; explicit overrides still win

    @Test("no stored override renders the current μ₀H display default")
    func noOverrideUsesVocabularyDefault() throws {
        let ingestion = makeIngestion(xTesla: [-0.05, 0, 0.05])
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE Test")
        let input = WorkbenchRenderPipeline.Input(payload: payload)
        let output = try WorkbenchRenderPipeline.render(input)

        #expect(output.layout.xAxisLabel == "μ₀H (mT)")
        #expect(output.manifestPayload.axisMapping.xField == "μ₀H (mT)")
    }

    @Test("an explicit xLabelOverride still wins over the μ₀H display default")
    func explicitOverrideWins() throws {
        let ingestion = makeIngestion(xTesla: [-0.05, 0, 0.05])
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE Test")
        let input = WorkbenchRenderPipeline.Input(payload: payload, xLabelOverride: "My Custom Field Axis")
        let output = try WorkbenchRenderPipeline.render(input)

        #expect(output.layout.xAxisLabel == "My Custom Field Axis")
        #expect(output.manifestPayload.axisMapping.xField == "μ₀H (mT)",
                "manifest must retain the canonical display label regardless of the layout override")
    }

    @MainActor
    @Test("restoring an old pack (Tesla-scale ingestion, no override) re-renders with the current μ₀H default")
    func restoreOldPackUsesCurrentDefault() throws {
        // Simulates a pack saved before this migration: ingestionResult.series.x already Tesla
        // (as it always has been), no stored label override.
        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        let ingestion = makeIngestion(xTesla: [-7, 0, 7])
        let config = AHEPackConfig(titleTemplate: "#tab #sample", showPlotGrid: false)
        let result = AHEPackResult(ingestionResult: ingestion)
        let pack = try AnalysisPack(
            label: "AHE Old Pack", workflowID: "ahe", filePaths: [], sampleKeys: [],
            config: config, result: result
        )

        store.restoreFromPack(config: config, result: result, pack: pack,
            restoreSearchState: { _, _ in }, seedSelection: { _, _ in })

        #expect(store.ingestionResult != nil)
        #expect(store.fieldDisplayUnit == .tesla)
    }

    // MARK: - AHEAxisDetector lookup independence still holds after this migration

    @Test("AHEAxisDetector raw-column lookup keys remain independent of the new μ₀H display label")
    func rawColumnLookupsIndependentOfNewLabel() {
        let ingestion = makeIngestion(xTesla: [-0.05, 0, 0.05])
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE Test")
        #expect(payload.axisMapping.xField == "μ₀H (mT)")
        #expect(AHEAxisDetector.rawMagneticFieldColumn == "Magnetic Field (Oe)")
        #expect(AHEAxisDetector.rawMagneticFieldColumn != payload.axisMapping.xField)
    }

    // MARK: - Fixtures

    private func makeIngestion(xTesla: [Double]) -> AHEIngestionResult {
        let series = WorkbenchPlotSeries(
            label: "300 K", x: xTesla, y: xTesla.map { _ in 0.5 },
            sourceRef: "/tmp/ahe.csv", sampleID: "sample-ahe"
        )
        return AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(xField: AHEAxisDetector.displayXField, yField: AHEAxisDetector.displayYField),
            series: [series],
            sourceFiles: ["/tmp/ahe.csv"],
            warnings: []
        )
    }

    private func makeHit(sourceFilePath: String, sampleKey: String = "PN31|o|STO|111") -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: "/tmp/\(sampleKey).spinlab.json",
            measurementFilePath: sourceFilePath,
            sourceFilePath: sourceFilePath,
            workflowID: "ahe",
            workflowDisplayName: "AHE",
            workflowCanonicalID: "ahe",
            batchID: "PN31",
            sampleKey: sampleKey,
            sampleSubstrate: "STO111",
            conditions: ["temperature": "80K"],
            channels: ["ch1"],
            appliedAt: .distantPast
        )
    }
}

// MARK: - Local fixture helpers

private struct AHEMigrationFixture {
    let rootURL: URL
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v558-ahe-migration-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func write(name: String, content: String) throws -> URL {
        let url = rootURL.appending(path: name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func cleanup() {
        try? fm.removeItem(at: rootURL)
    }
}

private enum AHEMigrationFixtureContent {
    static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

    // ±500 Oe = ±0.05 T -> small range, chart should select mT
    static let row1 = ",0,4449,80.0,500.0,0,1.0,500,,,,,,,,,,,25,1.0,,,"
    static let row2 = ",1,4449,80.0,0.0,0,0.0,500,,,,,,,,,,,25,0.0,,,"
    static let row3 = ",2,4449,80.0,-500.0,0,-1.0,500,,,,,,,,,,,25,-1.0,,,"

    static let smallFieldRange = """
    [Header]
    TITLE, test
    BYAPP, Resistivity, 2.1, 1.0
    INFO, Ohm, Sample1 Units
    [Data]
    \(colHeader)
    \(row1)
    \(row2)
    \(row3)
    """
}
