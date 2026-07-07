import Foundation
import Testing
@testable import SpinLabApp

/// Regression coverage for the 3ω magnetic-field storage-unit migration
/// (docs/architecture/workbench/MAGNETIC_FIELD_STORAGE_AUDIT.md): the `magneticFieldStorageUnit`
/// metadata marker, the restore-time internal-Tesla boundary (`normalizedToInternalTesla`), and
/// the save-time invariant guard (`normalizedForPackSave`). Fresh ingestion and new pack saves now
/// both use Tesla natively; old Oe packs (marked or unmarked) keep restoring/displaying correctly
/// forever.
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

    // MARK: - New ingestion/pack writes explicit "T" metadata

    @Test("New ingestion result defaults to explicit Tesla storage-unit marker")
    func newIngestionResultDefaultsToTesla() {
        let result = ThreeOmegaIngestionResult(fieldSweeps: [makeFieldSweep()], device: "0deg")
        #expect(result.magneticFieldStorageUnit == "T")
        #expect(result.magneticFieldStorageUnit == ThreeOmegaIngestionResult.teslaStorageUnit)
    }

    @Test("New pack round-trips the Tesla storage-unit marker through encode/decode")
    func newPackRoundTripsMarker() throws {
        let sweep = makeFieldSweep()
        let ingestion = ThreeOmegaIngestionResult(fieldSweeps: [sweep], device: "0deg")
        let packResult = ThreeOmegaPackResult(ingestionResult: ingestion, scalingResult: nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(packResult)

        // Metadata is actually present in the serialized JSON, not just the in-memory struct.
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"magneticFieldStorageUnit\":\"T\""))

        let decoded = try JSONDecoder().decode(ThreeOmegaPackResult.self, from: data)
        #expect(decoded.ingestionResult.magneticFieldStorageUnit == "T")
        #expect(decoded.ingestionResult.fieldSweeps == ingestion.fieldSweeps)
    }

    // MARK: - Old pack (no metadata key at all) decodes as legacy Oe

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

        // Decode-time default stays "Oe" regardless of the internal-Tesla migration — a pack
        // saved before the marker existed is only ever Oe. normalizedToInternalTesla() is what
        // later converts these raw-decoded values to canonical Tesla; decode itself must not.
        #expect(decoded.magneticFieldStorageUnit == "Oe")
        // Byte-for-byte unchanged numeric values — no conversion applied on decode itself.
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

    // MARK: - Numeric values are byte-for-byte unchanged by the marker itself

    @Test("hField/hc1omega/hc3omega numeric values are unaffected by the storage-unit marker")
    func numericValuesUnchanged() {
        let sweep = makeFieldSweep()
        #expect(sweep.hField == [-1000, 0, 1000])
        #expect(sweep.hc1omega == 123.4)
        #expect(sweep.hc3omega == 56.7)
    }

    // MARK: - Restore-time internal-Tesla compatibility boundary (normalizedToInternalTesla)

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

    @Test("Missing unit metadata + 70000 Oe field restores to internal 7 T, not 70000 T")
    func missingUnitFieldRestoresAsSevenTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [70000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: nil
        )
        let normalized = ingestion.normalizedToInternalTesla()
        #expect(normalized.magneticFieldStorageUnit == "T")
        #expect(normalized.fieldSweeps.first?.hField == [7.0])
    }

    @Test("Explicit Oe + 70000 field restores to internal 7 T")
    func explicitOeFieldRestoresAsSevenTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [70000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "Oe"
        )
        let normalized = ingestion.normalizedToInternalTesla()
        #expect(normalized.magneticFieldStorageUnit == "T")
        #expect(normalized.fieldSweeps.first?.hField == [7.0])
    }

    @Test("Explicit T + 7 field restores to internal 7 T unchanged, without a 10000x error")
    func explicitTeslaFieldRestoresAsSevenTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [7], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "T"
        )
        let normalized = ingestion.normalizedToInternalTesla()
        // Already canonical Tesla — pass-through, not a reinterpretation.
        #expect(normalized.magneticFieldStorageUnit == "T")
        #expect(normalized.fieldSweeps.first?.hField == [7.0])
    }

    @Test("Hc missing/Oe/T markers all normalize to the same internal Tesla value")
    func hcMissingOeTeslaAllNormalizeConsistently() throws {
        let missing = try makeIngestionResult(
            hField: [0], hc1omega: 700, hc3omega: 350, magneticFieldStorageUnit: nil
        ).normalizedToInternalTesla()
        let explicitOe = try makeIngestionResult(
            hField: [0], hc1omega: 700, hc3omega: 350, magneticFieldStorageUnit: "Oe"
        ).normalizedToInternalTesla()
        let explicitTesla = try makeIngestionResult(
            hField: [0], hc1omega: 0.07, hc3omega: 0.035, magneticFieldStorageUnit: "T"
        ).normalizedToInternalTesla()

        for result in [missing, explicitOe, explicitTesla] {
            #expect(result.magneticFieldStorageUnit == "T")
            #expect(result.fieldSweeps.first?.hc1omega == 0.07)
            #expect(result.fieldSweeps.first?.hc3omega == 0.035)
        }
    }

    @Test("An unrecognized storage-unit marker is treated as a defensive pass-through")
    func unrecognizedMarkerPassesThroughUnconverted() throws {
        let ingestion = try makeIngestionResult(
            hField: [1000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "bogus"
        )
        let normalized = ingestion.normalizedToInternalTesla()
        #expect(normalized.fieldSweeps.first?.hField == [1000])
    }

    // MARK: - Save-time canonical-Tesla invariant guard (normalizedForPackSave)

    @Test("New saved 3ω pack records unit = T")
    func newSavedPackRecordsTeslaUnit() throws {
        let ingestion = try makeIngestionResult(
            hField: [70000], hc1omega: 100, hc3omega: 50, magneticFieldStorageUnit: "Oe"
        )
        let saved = ingestion.normalizedForPackSave()
        #expect(saved.magneticFieldStorageUnit == "T")
        #expect(saved.magneticFieldStorageUnit == ThreeOmegaIngestionResult.teslaStorageUnit)
    }

    @Test("Save-time guard converts a still-Oe result to Tesla (70000 Oe -> 7 T)")
    func newSavedPackStoresHInTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [70000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "Oe"
        )
        let saved = ingestion.normalizedForPackSave()
        #expect(saved.fieldSweeps.first?.hField == [7.0])
    }

    @Test("Save-time guard converts a still-Oe Hc to Tesla (100 Oe -> 0.01 T)")
    func newSavedPackStoresHcInTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [0], hc1omega: 100, hc3omega: 50, magneticFieldStorageUnit: "Oe"
        )
        let saved = ingestion.normalizedForPackSave()
        #expect(saved.fieldSweeps.first?.hc1omega == 0.01)
        #expect(saved.fieldSweeps.first?.hc3omega == 0.005)
    }

    @Test("Old Hc = 100 Oe restores to internal Tesla and displays as 10 mT")
    func oldHcOeRestoresAsTenMilliTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [0], hc1omega: 100, hc3omega: nil, magneticFieldStorageUnit: nil
        )
        let normalized = ingestion.normalizedToInternalTesla()
        let displayMilliTesla = WorkbenchMagneticFieldUnitConverter.convert(
            normalized.fieldSweeps.first!.hc1omega!, from: .tesla, to: .millitesla
        )
        #expect(displayMilliTesla == 10.0)
    }

    @Test("New Hc = 0.01 T restores unchanged and displays as 10 mT")
    func newHcTeslaRestoresAsTenMilliTesla() throws {
        let ingestion = try makeIngestionResult(
            hField: [0], hc1omega: 0.01, hc3omega: nil, magneticFieldStorageUnit: "T"
        )
        let normalized = ingestion.normalizedToInternalTesla()
        #expect(normalized.magneticFieldStorageUnit == "T")
        let displayMilliTesla = WorkbenchMagneticFieldUnitConverter.convert(
            normalized.fieldSweeps.first!.hc1omega!, from: .tesla, to: .millitesla
        )
        #expect(displayMilliTesla == 10.0)
    }

    @Test("Load old pack then save is a no-op (restore already normalized to Tesla)")
    func loadOldPackThenSaveWritesTeslaUnit() throws {
        // Simulates restoreFromPack() consuming a legacy pack, then _buildPackResult() saving it.
        let legacyPack = try makeIngestionResult(
            hField: [70000], hc1omega: 100, hc3omega: 50, magneticFieldStorageUnit: nil
        )
        let restored = legacyPack.normalizedToInternalTesla()   // what restoreFromPack() does
        #expect(restored.magneticFieldStorageUnit == "T")
        #expect(restored.fieldSweeps.first?.hField == [7.0])
        #expect(restored.fieldSweeps.first?.hc1omega == 0.01)
        #expect(restored.fieldSweeps.first?.hc3omega == 0.005)

        // Save-time guard is a no-op here: restore already left the result canonical Tesla,
        // so _buildPackResult() does not reconvert it.
        let resaved = restored.normalizedForPackSave()
        #expect(resaved.magneticFieldStorageUnit == "T")
        #expect(resaved.fieldSweeps.first?.hField == [7.0])
        #expect(resaved.fieldSweeps.first?.hc1omega == 0.01)
        #expect(resaved.fieldSweeps.first?.hc3omega == 0.005)
    }

    @Test("Saving a pack twice does not double-convert an already-Tesla result")
    func doubleSaveDoesNotDoubleConvert() throws {
        let ingestion = try makeIngestionResult(
            hField: [70000], hc1omega: nil, hc3omega: nil, magneticFieldStorageUnit: "Oe"
        )
        let savedOnce = ingestion.normalizedForPackSave()
        let savedTwice = savedOnce.normalizedForPackSave()
        #expect(savedTwice.fieldSweeps.first?.hField == [7.0])
        #expect(savedTwice.magneticFieldStorageUnit == "T")
    }
}
