import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.6 — AHE label/data-key boundary regression (pre-migration, tests only).
///
/// Locks down the current AHE behavior identified in
/// docs/architecture/workbench/AHE_LABEL_KEY_AUDIT.md before any AHE label is migrated
/// to WorkbenchPlotDisplayVocabulary. AHE migration itself remains out of scope here.
@Suite("v5.5.6 - AHE label/key boundary regression (pre-migration)")
struct V556AHELabelKeyBoundaryRegressionTests {

    // MARK: - 1. Axis display-label regression (current values only — no future targets)

    @Test("AHE default axis mapping keeps current plain-text labels")
    func defaultAxisMappingKeepsCurrentLabels() throws {
        let fixture = try AHEBoundaryFixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: AHEBoundaryFixtureContent.variantA_ch1Only)

        let result = try IngestAHESelectionsUseCase().execute(
            selections: [
                .init(sampleKey: "PN31|o|STO|111", sourceFilePath: url.path, channel: .ch1, conditions: ["temperature": "80K"])
            ],
            parseFile: { try AHEDataParser().parse(fileURL: $0) }
        )

        #expect(result.defaultAxisMapping.xField == "H (T)")
        #expect(result.defaultAxisMapping.yField == "R_H (\u{03A9})")

        // Phase D (future target) is explicitly out of scope for this migration phase —
        // AHE must not yet display a μ0H-style field label. See AHE_LABEL_KEY_AUDIT.md §6.
        #expect(result.defaultAxisMapping.xField != "μ₀H (T)")
    }

    @Test("BuildAHEPlotPayloadUseCase axis labels match AHEAxisDetector constants exactly")
    func plotPayloadAxisLabelsMatchDetectorConstants() {
        let series = WorkbenchPlotSeries(
            label: "300 K", x: [-1.0, 0.0, 1.0], y: [0.5, 0.0, -0.5],
            sourceRef: "/tmp/ahe.csv", sampleID: "sample-ahe"
        )
        let ingestion = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(
                xField: AHEAxisDetector.semanticXField,
                yField: AHEAxisDetector.semanticYField
            ),
            series: [series],
            sourceFiles: ["/tmp/ahe.csv"],
            warnings: []
        )
        let payload = BuildAHEPlotPayloadUseCase().execute(ingestion: ingestion, title: "AHE Test")

        #expect(payload.axisMapping.xField == "H (T)")
        #expect(payload.axisMapping.yField == "R_H (\u{03A9})")
    }

    @Test("AHEAxisDetector display constants source from WorkbenchPlotDisplayVocabulary and match current output exactly")
    func displayConstantsSourceFromVocabularyExactly() {
        #expect(AHEAxisDetector.semanticXField == WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .manifestPlainText))
        #expect(AHEAxisDetector.semanticYField == WorkbenchPlotDisplayVocabulary.label(for: .hallResistance, context: .manifestPlainText))
        #expect(AHEAxisDetector.semanticXField == "H (T)")
        #expect(AHEAxisDetector.semanticYField == "R_H (\u{03A9})")
    }

    // MARK: - 2 & 3. Persisted metric-key guard (must stay literal — not vocabulary output,
    // not renamed to a future target such as "μ0Hc" or a math-style R_AHE label)

    @MainActor
    @Test("buildActiveChartMetrics persists literal 'Hc'/'R_AHE' keys, not display-vocabulary output")
    func persistedMetricKeysRemainLiteral() async throws {
        let fixture = try AHEBoundaryFixture()
        defer { fixture.cleanup() }
        let url = try fixture.write(name: "f.dat", content: AHEBoundaryFixtureContent.variantA_ch1Only)

        let store = AHEWorkspaceStore(workflowID: WorkflowKey.ahe.rawValue)
        store.cachedSearchResults = [makeHit(sourceFilePath: url.path)]
        store.runAnalysis()

        var attempts = 0
        while store.isPlotRendering && attempts < 60 {
            try await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }

        let entries = store.buildActiveChartMetrics()
        #expect(!entries.isEmpty, "expected at least one persisted metric entry from real AHE analysis")

        let metricNames = Set(entries.map(\.metric))
        #expect(metricNames == ["Hc", "R_AHE"],
                "persisted metric-identity keys must remain exactly 'Hc' and 'R_AHE'")

        // These are persisted per-sample metric-identity keys (WorkbenchMetricIdentity), not
        // display labels. Migrating them to WorkbenchPlotDisplayVocabulary output would change
        // identity for every already-saved library metric entry. See AHE_LABEL_KEY_AUDIT.md §4.
        for entry in entries where entry.metric == "Hc" {
            #expect(entry.canonicalUnit == "T")
        }
        for entry in entries where entry.metric == "R_AHE" {
            #expect(entry.canonicalUnit == "Ω")
            // "R_AHE" the persisted key must stay textually distinct from the vocabulary's
            // raheCombined display label — confirms they are deliberately separate identities.
            #expect(entry.metric != WorkbenchPlotDisplayVocabulary.label(for: .raheCombined, context: .manifestPlainText))
        }
    }

    // MARK: - 4. Lookup/display separation guard (documents which strings are which)

    @Test("AHEAxisDetector semantic fields (display) are textually distinct from the persisted metric keys")
    func displayLabelsAreDistinctFromPersistedMetricKeys() {
        // Display-only (safe future migration candidates, see AHE_LABEL_KEY_AUDIT.md §3):
        let displayXField = AHEAxisDetector.semanticXField
        let displayYField = AHEAxisDetector.semanticYField

        // Persisted/lookup keys (blocked, see AHE_LABEL_KEY_AUDIT.md §4):
        let persistedHcKey = "Hc"
        let persistedRAHEKey = "R_AHE"

        #expect(displayXField == "H (T)")
        #expect(displayYField == "R_H (\u{03A9})")
        #expect(displayXField != persistedHcKey)
        #expect(displayYField != persistedRAHEKey)
    }

    // MARK: - Fixtures

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

// MARK: - Local fixture helpers (mirrors V321AHEIngestionAxisDetectionTests' fixture shape;
// duplicated locally since that file's fixtures are file-private)

private struct AHEBoundaryFixture {
    let rootURL: URL
    private let fm = FileManager.default

    init() throws {
        rootURL = fm.temporaryDirectory.appending(
            path: "spinlab-v556-ahe-boundary-\(UUID().uuidString)", directoryHint: .isDirectory
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

private enum AHEBoundaryFixtureContent {
    static let colHeader = "Comment,Time Stamp (sec),Status (code),Temperature (K),Magnetic Field (Oe),Sample Position (deg),Bridge 1 Resistivity (Ohm),Bridge 1 Excitation (uA),Bridge 2 Resistivity (Ohm),Bridge 2 Excitation (uA),Bridge 3 Resistivity (Ohm),Bridge 3 Excitation (uA),Bridge 4 Resistivity (Ohm),Bridge 4 Excitation (uA),Bridge 1 Std. Dev. (Ohm),Bridge 2 Std. Dev. (Ohm),Bridge 3 Std. Dev. (Ohm),Bridge 4 Std. Dev. (Ohm),Number of Readings,Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms),Bridge 3 Resistance (Ohms),Bridge 4 Resistance (Ohms)"

    static let row1 = ",0,4449,80.0,10000.0,0,1.0,500,,,,,,,,,,,25,1.0,,,"
    static let row2 = ",1,4449,80.0,5000.0,0,0.9,500,,,,,,,,,,,25,0.9,,,"
    static let row3 = ",2,4449,80.0,-5000.0,0,0.8,500,,,,,,,,,,,25,0.8,,,"

    static let variantA_ch1Only = """
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
