import Foundation
import Testing
@testable import SpinLabApp

/// Regression coverage for the 3ω magnetic-field storage-unit metadata added ahead of a future
/// Oe→T canonical-storage migration (docs/architecture/workbench/MAGNETIC_FIELD_STORAGE_AUDIT.md).
/// This phase adds an explicit `magneticFieldStorageUnit` marker only — no numeric value changes.
@Suite("V5.6.4 ThreeOmega Magnetic Field Storage Unit")
struct V564ThreeOmegaMagneticFieldStorageUnitTests {

    private func makeFieldSweep() -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: 5.0,
            device: "0deg",
            sampleMetadata: ["device": "0deg"],
            sampleID: "sample",
            sourceFilePath: "/tmp/sample-5K.csv",
            hField: [-1000, 0, 1000],
            r1omega: [-1, 0, 1],
            r3omega: [-2, 0, 2],
            iRms: 1e-3,
            rahe1omega: 1.0,
            rahe1omegaWA: 1.0,
            hc1omega: 123.4,
            hc3omega: 56.7,
            v3omegaWindow: 2e-5,
            v3omegaFit: 2e-5
        )
    }

    // MARK: - New pack writes explicit "Oe" metadata

    @Test("New ingestion result defaults to explicit Oe storage-unit marker")
    func newIngestionResultDefaultsToOe() {
        let result = ThreeOmegaIngestionResult(fieldSweeps: [makeFieldSweep()], device: "0deg")
        #expect(result.magneticFieldStorageUnit == "Oe")
        #expect(result.magneticFieldStorageUnit == ThreeOmegaIngestionResult.oerstedStorageUnit)
    }

    @Test("New pack round-trips the Oe storage-unit marker through encode/decode")
    func newPackRoundTripsMarker() throws {
        let sweep = makeFieldSweep()
        let ingestion = ThreeOmegaIngestionResult(fieldSweeps: [sweep], device: "0deg")
        let packResult = ThreeOmegaPackResult(ingestionResult: ingestion, scalingResult: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(packResult)

        // Metadata is actually present in the serialized JSON, not just the in-memory struct.
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"magneticFieldStorageUnit\":\"Oe\""))

        let decoded = try JSONDecoder().decode(ThreeOmegaPackResult.self, from: data)
        #expect(decoded.ingestionResult.magneticFieldStorageUnit == "Oe")
        #expect(decoded.ingestionResult.fieldSweeps == ingestion.fieldSweeps)
    }

    // MARK: - Old pack (no metadata key at all) restores as legacy Oe

    @Test("Old pack JSON with no magneticFieldStorageUnit key decodes as legacy Oe")
    func oldPackWithMissingKeyDecodesAsOe() throws {
        let legacyJSON = """
        {
          "fieldSweeps": [
            {
              "temperatureK": 5.0,
              "device": "0deg",
              "hField": [-1000, 0, 1000],
              "r1omega": [-1, 0, 1],
              "r3omega": [-2, 0, 2],
              "iRms": 0.001,
              "rahe1omega": 1.0,
              "rahe1omegaWA": 1.0,
              "hc1omega": 123.4,
              "hc3omega": 56.7,
              "v3omegaWindow": 0.00002,
              "v3omegaFit": 0.00002
            }
          ],
          "device": "0deg",
          "deviceMode": "single",
          "devices": [],
          "iRmsValues": [],
          "warnings": []
        }
        """
        let data = try #require(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ThreeOmegaIngestionResult.self, from: data)

        #expect(decoded.magneticFieldStorageUnit == "Oe")
        // Byte-for-byte unchanged numeric values — no conversion applied on legacy decode.
        #expect(decoded.fieldSweeps.first?.hField == [-1000, 0, 1000])
        #expect(decoded.fieldSweeps.first?.hc1omega == 123.4)
        #expect(decoded.fieldSweeps.first?.hc3omega == 56.7)
    }

    // MARK: - Explicit "Oe" metadata decodes as Oe (no-op, but confirms the marker is read back)

    @Test("Pack JSON explicitly marked Oe decodes as Oe")
    func explicitOeMarkerDecodesAsOe() throws {
        let json = """
        {
          "fieldSweeps": [],
          "device": "0deg",
          "deviceMode": "single",
          "devices": [],
          "iRmsValues": [],
          "warnings": [],
          "magneticFieldStorageUnit": "Oe"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ThreeOmegaIngestionResult.self, from: data)
        #expect(decoded.magneticFieldStorageUnit == "Oe")
    }

    // MARK: - Numeric values are byte-for-byte unchanged by this phase

    @Test("hField/hc1omega/hc3omega numeric values are unaffected by the storage-unit marker")
    func numericValuesUnchanged() {
        let sweep = makeFieldSweep()
        #expect(sweep.hField == [-1000, 0, 1000])
        #expect(sweep.hc1omega == 123.4)
        #expect(sweep.hc3omega == 56.7)
    }
}
