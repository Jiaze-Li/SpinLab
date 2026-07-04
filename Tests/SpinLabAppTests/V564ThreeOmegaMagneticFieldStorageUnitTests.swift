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

    // MARK: - Restore-time storage-unit compatibility boundary (normalizedToStorageOersted)

    private func makeIngestionResult(
        hField: [Double], hc1omega: Double?, hc3omega: Double?,
        magneticFieldStorageUnit: String?
    ) throws -> ThreeOmegaIngestionResult {
        let sweep = ThreeOmegaFieldSweepResult(
            temperatureK: 5.0, device: "0deg", sampleID: "sample", sourceFilePath: "/tmp/s-5K.csv",
            hField: hField, r1omega: [0], r3omega: [0], iRms: 1e-3,
            rahe1omega: 1.0, rahe1omegaWA: 1.0, hc1omega: hc1omega, hc3omega: hc3omega,
            v3omegaWindow: 2e-5, v3omegaFit: 2e-5
        )
        if let unit = magneticFieldStorageUnit {
            return ThreeOmegaIngestionResult(fieldSweeps: [sweep], device: "0deg", magneticFieldStorageUnit: unit)
        }
        // Simulate a truly legacy pack: decode JSON with no key at all, rather than passing "Oe"
        // explicitly, so the decode-time default path (not the memberwise init) is exercised.
        let hFieldJSON = hField.map { "\($0)" }.joined(separator: ",")
        let hc1JSON = hc1omega.map { "\($0)" } ?? "null"
        let hc3JSON = hc3omega.map { "\($0)" } ?? "null"
        let json = """
        {
          "fieldSweeps": [
            {
              "temperatureK": 5.0, "device": "0deg",
              "hField": [\(hFieldJSON)], "r1omega": [0], "r3omega": [0], "iRms": 0.001,
              "rahe1omega": 1.0, "rahe1omegaWA": 1.0,
              "hc1omega": \(hc1JSON), "hc3omega": \(hc3JSON),
              "v3omegaWindow": 0.00002, "v3omegaFit": 0.00002
            }
          ],
          "device": "0deg", "deviceMode": "single", "devices": [], "iRmsValues": [], "warnings": []
        }
        """
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(ThreeOmegaIngestionResult.self, from: data)
    }

    @Test("Missing unit metadata + 70000 Oe field restores/displays as 7 T, not 70000 T")
    func missingUnitFieldRestoresAsSevenTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [70000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: nil
        )
        let normalized = ingestion.normalizedToStorageOersted()
        #expect(normalized.magneticFieldStorageUnit == "Oe")
        #expect(normalized.fieldSweeps.first?.hField == [70000])
        let displayTesla = normalized.fieldSweeps.first!.hField
            .map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .oersted, to: .tesla) }
        #expect(displayTesla == [7.0])
    }

    @Test("Explicit Oe + 70000 field restores/displays as 7 T")
    func explicitOeFieldRestoresAsSevenTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [70000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "Oe"
        )
        let normalized = ingestion.normalizedToStorageOersted()
        #expect(normalized.magneticFieldStorageUnit == "Oe")
        #expect(normalized.fieldSweeps.first?.hField == [70000])
        let displayTesla = normalized.fieldSweeps.first!.hField
            .map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .oersted, to: .tesla) }
        #expect(displayTesla == [7.0])
    }

    @Test("Explicit T + 7 field restores/displays as 7 T, without a 10000x error")
    func explicitTeslaFieldRestoresAsSevenTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [7], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "T"
        )
        let normalized = ingestion.normalizedToStorageOersted()
        // Internal representation is normalized back to canonical Oe after restore.
        #expect(normalized.magneticFieldStorageUnit == "Oe")
        #expect(normalized.fieldSweeps.first?.hField == [70000])
        let displayTesla = normalized.fieldSweeps.first!.hField
            .map { WorkbenchMagneticFieldUnitConverter.convert($0, from: .oersted, to: .tesla) }
        #expect(displayTesla == [7.0])
    }

    @Test("Hc missing/Oe/T markers all normalize to the same Oe value and display magnitude")
    func hcMissingOeTeslaAllNormalizeConsistently() throws {
        let missing = try makeIngestionResult(
            hField: [0], hc1omega: 700, hc3omega: 350, magneticFieldStorageUnit: nil
        ).normalizedToStorageOersted()
        let explicitOe = try makeIngestionResult(
            hField: [0], hc1omega: 700, hc3omega: 350, magneticFieldStorageUnit: "Oe"
        ).normalizedToStorageOersted()
        let explicitTesla = try makeIngestionResult(
            hField: [0], hc1omega: 0.07, hc3omega: 0.035, magneticFieldStorageUnit: "T"
        ).normalizedToStorageOersted()

        for result in [missing, explicitOe, explicitTesla] {
            #expect(result.magneticFieldStorageUnit == "Oe")
            #expect(result.fieldSweeps.first?.hc1omega == 700)
            #expect(result.fieldSweeps.first?.hc3omega == 350)
        }
    }

    @Test("An unrecognized storage-unit marker is treated as a defensive Oe pass-through")
    func unrecognizedMarkerPassesThroughAsOe() throws {
        let ingestion = try makeIngestionResult(
            hField: [1000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "bogus"
        )
        let normalized = ingestion.normalizedToStorageOersted()
        #expect(normalized.fieldSweeps.first?.hField == [1000])
    }
}
