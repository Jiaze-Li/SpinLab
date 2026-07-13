import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.6 — AHE label/data-key boundary regression.
///
/// Locks down the AHE key/label boundaries identified in
/// docs/architecture/workbench/AHE_LABEL_KEY_AUDIT.md: persisted metric keys ("Hc"/"R_AHE"),
/// AHEAxisDetector's raw-column lookups, and the legacy generic display constants. The actual
/// visible-axis-label migration (BuildAHEPlotPayloadUseCase -> magnetic-field magnitude policy)
/// is covered separately in V558AHEMagneticFieldDisplayMigrationTests.
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

        // AHEIngestionResult.defaultAxisMapping is a vestigial field — the actually-rendered
        // chart's axis label comes from BuildAHEPlotPayloadUseCase (migrated to the magnitude
        // policy, v5.5.6 Phase B — see V558AHEMagneticFieldDisplayMigrationTests), not from this
        // field. This ingestion-level constant intentionally stays the legacy generic label.
        #expect(result.defaultAxisMapping.xField != "μ₀H (T)")
    }

    @Test("AHEAxisDetector.displayXField/YField constants stay the legacy generic labels")
    func detectorConstantsRemainLegacy() {
        // BuildAHEPlotPayloadUseCase no longer sources its xField from these constants directly
        // (see V558AHEMagneticFieldDisplayMigrationTests) — but the constants themselves, and
        // AHEIngestionResult.defaultAxisMapping which still uses them, are unchanged.
        let series = WorkbenchPlotSeries(
            label: "300 K", x: [-1.0, 0.0, 1.0], y: [0.5, 0.0, -0.5],
            sourceRef: "/tmp/ahe.csv", sampleID: "sample-ahe"
        )
        let ingestion = AHEIngestionResult(
            defaultAxisMapping: WorkbenchAxisMapping(
                xField: AHEAxisDetector.displayXField,
                yField: AHEAxisDetector.displayYField
            ),
            series: [series],
            sourceFiles: ["/tmp/ahe.csv"],
            warnings: []
        )
        #expect(ingestion.defaultAxisMapping.xField == "H (T)")
        #expect(ingestion.defaultAxisMapping.yField == "R_H (\u{03A9})")
    }

    @Test("AHEAxisDetector display constants source from WorkbenchPlotDisplayVocabulary and match current output exactly")
    func displayConstantsSourceFromVocabularyExactly() {
        #expect(AHEAxisDetector.displayXField == WorkbenchPlotDisplayVocabulary.label(for: .externalMagneticField, context: .manifestPlainText))
        #expect(AHEAxisDetector.displayYField == WorkbenchPlotDisplayVocabulary.label(for: .hallResistance, context: .manifestPlainText))
        #expect(AHEAxisDetector.displayXField == "H (T)")
        #expect(AHEAxisDetector.displayYField == "R_H (\u{03A9})")
        #expect(WorkbenchPlotDisplayVocabulary.plotLabel(for: .hallResistance) == #"math:R_{H} (Ω)"#)
        #expect(WorkbenchPlotDisplayVocabulary.plainTextLabel(for: .hallResistance) == "R_H (\u{03A9})")
    }

    // MARK: - 2 & 3. Persisted metric-key guard (must stay literal — not vocabulary output,
    // not renamed to a future target such as "μ0Hc" or a math-style R_AHE label)

    @Test("AHEDataFieldKey raw values are exactly 'Hc' and 'R_AHE'")
    func dataFieldKeyRawValuesAreLiteral() {
        #expect(AHEDataFieldKey.hc.rawValue == "Hc")
        #expect(AHEDataFieldKey.rAHE.rawValue == "R_AHE")
    }

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
        #expect(metricNames == [AHEDataFieldKey.hc.rawValue, AHEDataFieldKey.rAHE.rawValue],
                "persisted metric-identity keys must remain exactly 'Hc' and 'R_AHE'")

        // These are persisted per-sample metric-identity keys (WorkbenchMetricIdentity), not
        // display labels. Migrating them to WorkbenchPlotDisplayVocabulary output would change
        // identity for every already-saved library metric entry. See AHE_LABEL_KEY_AUDIT.md §4.
        for entry in entries where entry.metric == AHEDataFieldKey.hc.rawValue {
            #expect(entry.canonicalUnit == "T")
        }
        for entry in entries where entry.metric == AHEDataFieldKey.rAHE.rawValue {
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
        let displayXField = AHEAxisDetector.displayXField
        let displayYField = AHEAxisDetector.displayYField

        // Persisted/lookup keys (blocked, see AHE_LABEL_KEY_AUDIT.md §4):
        let persistedHcKey = "Hc"
        let persistedRAHEKey = "R_AHE"

        #expect(displayXField == "H (T)")
        #expect(displayYField == "R_H (\u{03A9})")
        #expect(displayXField != persistedHcKey)
        #expect(displayYField != persistedRAHEKey)
    }

    @Test("AHEAxisDetector raw-file column lookups are independent of display vocabulary output")
    func rawColumnLookupsAreIndependentOfDisplayVocabulary() {
        // Real data-lookup keys: raw PPMS column names, never routed through the vocabulary.
        #expect(AHEAxisDetector.rawMagneticFieldColumn == "Magnetic Field (Oe)")
        #expect(AHEAxisDetector.rawMagneticFieldColumn != AHEAxisDetector.displayXField,
                "the x-axis data column key must not equal the x-axis display label")

        let detector = AHEAxisDetector()
        let file = PPMSParsedFile(
            columnNames: ["Magnetic Field (Oe)", "Bridge 1 Resistance (Ohms)"],
            rows: [["1000.0", "0.5"], ["2000.0", "0.6"]],
            sourceRef: "/tmp/ahe-fixture.dat"
        )
        let yColumn = detector.yColumnName(from: file, bridgeIndex: 1)
        #expect(yColumn == "Bridge 1 Resistance (Ohms)")
        #expect(yColumn != AHEAxisDetector.displayYField,
                "the y-axis data column key must not equal the y-axis display label")

        // If WorkbenchPlotDisplayVocabulary's externalMagneticField/hallResistance labels ever
        // changed, these raw column lookups (used to actually locate data in the file) would be
        // unaffected — they are independent literal strings, not derived from the vocabulary.
        let (xs, ys) = detector.pairedValues(from: file, xColumn: AHEAxisDetector.rawMagneticFieldColumn, yColumn: yColumn!)
        #expect(xs == [1000.0, 2000.0])
        #expect(ys == [0.5, 0.6])
    }

    @Test("magneticFieldLabel(.coerciveField, millitesla) does not alter AHE persisted/lookup keys")
    func magneticFieldLabelDoesNotAlterAHEKeys() {
        let futureCoerciveFieldLabel = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(
            for: .coerciveField, context: .manifestPlainText, unit: .millitesla
        )
        let futureExternalFieldLabel = WorkbenchPlotDisplayVocabulary.magneticFieldLabel(
            for: .externalMagneticField, context: .manifestPlainText, unit: .tesla
        )

        // These future-target labels (used by the already-migrated 3ω workflow) must remain
        // textually distinct from AHE's persisted metric keys and its current display label —
        // AHE does not call magneticFieldLabel today, and must not start doing so implicitly.
        #expect(futureCoerciveFieldLabel == "\u{3bc}\u{2080}Hc (mT)")
        #expect(futureCoerciveFieldLabel != "Hc")
        #expect(futureCoerciveFieldLabel != "R_AHE")
        #expect(futureExternalFieldLabel != "Hc")
        #expect(futureExternalFieldLabel != "R_AHE")
        #expect(futureExternalFieldLabel != AHEAxisDetector.displayXField,
                "AHE's current field label ('H (T)') must stay distinct from the future μ0H-style label")
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
