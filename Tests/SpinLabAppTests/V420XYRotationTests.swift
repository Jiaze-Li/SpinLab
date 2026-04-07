import Testing
@testable import SpinLabApp

/// Test skeleton for the XY Rotation workflow (v4.2.0+).
///
/// Tests are added incrementally as each iteration lands.
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
        #expect(XYRotationWorkbenchTab.rVsPhi.displayName == "R vs φ")
    }
}
