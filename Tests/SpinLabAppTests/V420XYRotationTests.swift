import Testing
import Foundation
@testable import SpinLabApp

/// Tests for the XY Rotation workflow (v4.2.0+).
@Suite("V4.2.0 XY Rotation")
struct V420XYRotationTests {

    @Test("Domain enum cases exist")
    func domainEnumsIncludeXYRotation() {
        #expect(SpinLabDomain.WorkflowKind.xyRotation.rawValue == "XY Rotation")
        #expect(SpinLabDomain.MeasurementType.xyRotation.rawValue == "XY Rotation")
    }

    @Test("Ingestion contracts compile and have expected defaults")
    func ingestionContractsDefaults() {
        let result = XYRotationIngestionResult()
        #expect(result.sweeps.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("Workbench tab has display name")
    func tabDisplayName() {
        #expect(XYRotationWorkbenchTab.rxxVsPhi.displayName == "Rxx vs φ")
        #expect(XYRotationWorkbenchTab.rxyVsPhi.displayName == "Rxy vs φ")
    }

    // MARK: - LVM Parser Tests (v4.2.1)

    private func lvmFixtureURL() -> URL? {
        Bundle.module.url(forResource: "xy_rotation_80K_sample", withExtension: "lvm", subdirectory: "TestData/XYRotation")
    }

    @Test("LVM parser: extracts 7 data rows with correct angles")
    func lvmParserBasic() throws {
        guard let url = lvmFixtureURL() else {
            Issue.record("LVM fixture not found")
            return
        }
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        #expect(sweep.angleDeg.count == 7)
        #expect(sweep.resistanceXX.count == 7)
        #expect(sweep.resistanceXY != nil)
        #expect(sweep.resistanceXY?.count == 7)
        #expect(sweep.sourceKind == .lvm)
        // First angle is 360, last is 330
        #expect(abs(sweep.angleDeg[0] - 360.0) < 0.01)
        #expect(abs(sweep.angleDeg[6] - 330.0) < 0.01)
    }

    @Test("LVM parser: Rxx = col9 (1st R_H)")
    func lvmRxxValues() throws {
        guard let url = lvmFixtureURL() else { return }
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        // First row: R_H = -3.6280234729
        #expect(abs(sweep.resistanceXX[0] - (-3.6280234729)) < 1e-6)
    }

    @Test("LVM parser: I_rms derivation and Rxy = col5 / I_rms")
    func lvmRxyDerivation() throws {
        guard let url = lvmFixtureURL() else { return }
        let sweep = try XYRotationLVMParser().parse(fileURL: url, temperatureOverride: 80)
        // Manually compute I_rms from first row: col1/col9 = -0.0010261600 / -3.6280234729
        let expectedIRms = -0.0010261600 / -3.6280234729
        // Rxy[0] = col5[0] / I_rms = 0.2738360000 / expectedIRms
        let expectedRxy0 = 0.2738360000 / expectedIRms
        #expect(sweep.resistanceXY != nil)
        #expect(abs(sweep.resistanceXY![0] - expectedRxy0) < 1.0)
    }

    @Test("LVM parser: temperature from filename")
    func lvmTemperatureFromFilename() throws {
        guard let url = lvmFixtureURL() else { return }
        let sweep = try XYRotationLVMParser().parse(fileURL: url)
        #expect(abs(sweep.temperatureK - 80.0) < 0.01)
    }

    // MARK: - DAT Parser Tests (v4.2.1)

    private func datFixtureURL() -> URL? {
        Bundle.module.url(forResource: "xy_rotation_170K_sample", withExtension: "dat", subdirectory: "TestData/XYRotation")
    }

    @Test("DAT parser: extracts data rows with correct angle and Rxx")
    func datParserBasic() throws {
        guard let url = datFixtureURL() else {
            Issue.record("DAT fixture not found")
            return
        }
        let sweep = try XYRotationDATParser().parse(fileURL: url)
        #expect(sweep.angleDeg.count > 5)
        #expect(sweep.resistanceXX.count == sweep.angleDeg.count)
        #expect(sweep.sourceKind == .dat)
        // First data row: Sample Position ≈ 360
        #expect(abs(sweep.angleDeg[0] - 360.0) < 1.0)
    }

    @Test("DAT parser: temperature from data column")
    func datTemperatureFromData() throws {
        guard let url = datFixtureURL() else { return }
        let sweep = try XYRotationDATParser().parse(fileURL: url)
        // Temperature should be ~170K
        #expect(abs(sweep.temperatureK - 170.0) < 1.0)
    }

    @Test("DAT parser: Rxx is Bridge 2, Rxy is Bridge 3")
    func datColumnMapping() throws {
        guard let url = datFixtureURL() else { return }
        let sweep = try XYRotationDATParser().parse(fileURL: url)
        // First data row: Bridge 2 Resistivity = 150.359689941406
        #expect(abs(sweep.resistanceXX[0] - 150.3597) < 0.01)
        // Bridge 3 Resistivity = -1.83892154693604
        #expect(sweep.resistanceXY != nil)
        #expect(abs(sweep.resistanceXY![0] - (-1.8389)) < 0.01)
    }

    @Test("DAT parser: temperature override takes precedence")
    func datTemperatureOverride() throws {
        guard let url = datFixtureURL() else { return }
        let sweep = try XYRotationDATParser().parse(fileURL: url, temperatureOverride: 42.0)
        #expect(abs(sweep.temperatureK - 42.0) < 0.01)
    }

    // MARK: - v4.2.4 Persistence contracts

    @Test("PackConfig round-trips through Codable")
    func packConfigCodable() throws {
        let config = XYRotationPackConfig(
            phiOffsetOverrides: ["sweep1": 45.0],
            centerBaseline: true,
            activeTab: XYRotationWorkbenchTab.rxxVsPhi.rawValue,
            titleTemplate: "#tab #device",
            stackOffsetMultiplier: 0.5,
            minGapFraction: 0.15,
            showPlotGrid: true,
            tabStates: [
                XYRotationWorkbenchTab.rxxVsPhi.rawValue: TabRenderState(
                    yLabelOverride: "Custom Y",
                    seriesLabelOverrides: [0: "80 K custom"]
                )
            ],
            cachedSearchResults: [],
            selectedSearchResultIDs: ["id1"],
            searchQueryText: "xy test"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(config)
        let decoded = try JSONDecoder().decode(XYRotationPackConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test("PackResult round-trips through Codable")
    func packResultCodable() throws {
        let result = XYRotationPackResult(
            ingestionResult: XYRotationIngestionResult(
                sweeps: [],
                device: "PPMS",
                warnings: ["test warning"]
            )
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(XYRotationPackResult.self, from: data)
        #expect(decoded == result)
    }

    @Test("AngleSweep measurementFilePath defaults to empty")
    func sweepMeasurementFilePath() {
        let sweep = XYRotationAngleSweep(
            temperatureK: 80,
            stem: "test",
            sourceKind: .dat,
            angleDeg: [0, 90],
            resistanceXX: [100, 101],
            defaultPhiOffset: 0
        )
        #expect(sweep.measurementFilePath?.isEmpty != false)
    }

    @Test("InteractionSnapshot XY Rotation fields default to nil")
    func snapshotXYRotationDefaults() {
        let snapshot = SpinLabInteractionSnapshot()
        #expect(snapshot.xyRotationPhiOffsets == nil)
        #expect(snapshot.xyRotationActiveTab == nil)
        #expect(snapshot.xyRotationTitleTemplate == nil)
        #expect(snapshot.xyRotationStackOffset == nil)
        #expect(snapshot.xyRotationCenterBaseline == nil)
        #expect(snapshot.xyRotationPlotLegendPoints == nil)
    }
}
