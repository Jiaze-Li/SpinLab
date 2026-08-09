import Testing
import Foundation
@testable import SpinLabApp

/// v5.5.8 Phase 3b — connects built-in Sidecar conditions to the PhysicalQuantity domain
/// registry without redesigning Sidecar storage. See the 2026-08-08 registry audit and Phase 3b
/// implementation report for the design this locks.
@Suite("v5.5.8 - Sidecar PhysicalQuantity bridge")
struct V558SidecarPhysicalQuantityTests {

    private func makeSidecar(conditions: [String: String], overrides: [String: String] = [:]) -> SpinLabFileSidecar {
        let ruleConditions = conditions.mapValues { SourcedValue(value: $0, source: "rule:test#0") }
        let overrideConditions = overrides.mapValues {
            ManualValueOverride(value: $0, reason: "test", at: .distantPast)
        }
        return SpinLabFileSidecar(
            workflow: "RT",
            workflowDisplayName: "RT",
            channels: [],
            sourceFilePath: "/tmp/test.dat",
            appliedAt: .distantPast,
            ruleSnapshot: SidecarRuleSnapshot(
                ruleSetVersion: 1,
                ruleSetFingerprint: "test",
                appliedAt: .distantPast,
                fields: SidecarRuleFields(sampleID: nil, conditions: ruleConditions, substrateTags: [])
            ),
            userOverrides: SidecarUserOverrides(conditions: overrideConditions)
        )
    }

    // MARK: A-C — built-in condition -> PhysicalQuantityID mapping

    @Test("A: temperature -> PhysicalQuantityID.temperature")
    func temperatureMapping() {
        #expect(SidecarPhysicalQuantityMapping.physicalQuantity(forConditionID: "temperature") == .temperature)
    }

    @Test("B: field -> PhysicalQuantityID.externalMagneticField")
    func fieldMapping() {
        #expect(SidecarPhysicalQuantityMapping.physicalQuantity(forConditionID: "field") == .externalMagneticField)
    }

    @Test("C: current -> PhysicalQuantityID.current")
    func currentMapping() {
        #expect(SidecarPhysicalQuantityMapping.physicalQuantity(forConditionID: "current") == .current)
    }

    // MARK: D — custom conditions have no mapping

    @Test("D: custom/non-mapped condition IDs have no PhysicalQuantity mapping")
    func customConditionsUnmapped() {
        #expect(SidecarPhysicalQuantityMapping.physicalQuantity(forConditionID: "shift") == nil)
        #expect(SidecarPhysicalQuantityMapping.physicalQuantity(forConditionID: "device") == nil)
        #expect(SidecarPhysicalQuantityMapping.physicalQuantity(forConditionID: "my_custom_condition") == nil)
    }

    // MARK: E — existing Sidecar JSON still decodes unchanged

    @Test("E: pre-Phase-3b Sidecar JSON decodes unchanged")
    func existingSidecarJSONDecodesUnchanged() throws {
        let json = """
        {
          "version": 2,
          "workflow": "RT",
          "autoDetectedWorkflow": "RT",
          "workflowSource": "auto",
          "workflowDisplayName": "RT",
          "channels": [],
          "sourceFilePath": "/tmp/test.dat",
          "appliedAt": 0,
          "ruleSnapshot": {
            "ruleSetVersion": 1,
            "ruleSetFingerprint": "test",
            "appliedAt": 0,
            "fields": {
              "conditions": {
                "temperature": { "value": "300K", "source": "rule:test#0" },
                "current": { "value": "10mA", "source": "rule:test#1" },
                "shift": { "value": "shift", "source": "rule:test#2" }
              },
              "substrateTags": []
            }
          },
          "userOverrides": { "conditions": {} }
        }
        """
        let decoded = try JSONDecoder().decode(SpinLabFileSidecar.self, from: Data(json.utf8))
        #expect(decoded.ruleSnapshot.fields.conditions["temperature"]?.value == "300K")
        #expect(decoded.ruleSnapshot.fields.conditions["current"]?.value == "10mA")
        #expect(decoded.ruleSnapshot.fields.conditions["shift"]?.value == "shift")
        #expect(decoded.effectiveConditions["temperature"] == "300K")
    }

    // MARK: F — effectiveConditions output remains unchanged

    @Test("F: effectiveConditions is unaffected by the PhysicalQuantity bridge")
    func effectiveConditionsUnchanged() {
        let sidecar = makeSidecar(
            conditions: ["temperature": "300K", "current": "10mA", "shift": "shift"],
            overrides: ["temperature": "295K"]
        )
        #expect(sidecar.effectiveConditions["temperature"] == "295K")
        #expect(sidecar.effectiveConditions["current"] == "10mA")
        #expect(sidecar.effectiveConditions["shift"] == "shift")
        #expect(sidecar.effectiveConditions.count == 3)
    }

    // MARK: Typed access (item 3)

    @Test("Typed access: conditionValue(for:) reads through to effectiveConditions")
    func typedConditionValueAccess() {
        let sidecar = makeSidecar(conditions: ["temperature": "300K", "field": "0.5T"])
        #expect(sidecar.conditionValue(for: .temperature) == "300K")
        #expect(sidecar.conditionValue(for: .externalMagneticField) == "0.5T")
        #expect(sidecar.conditionValue(for: .rxx) == nil)  // no built-in condition mapping
    }

    // MARK: G — temperature normalization handles equivalent Kelvin spellings

    @Test("G: temperature normalization handles equivalent Kelvin spellings")
    func temperatureNormalizationEquivalentSpellings() {
        let a = SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .temperature, rawValue: "300K")
        let b = SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .temperature, rawValue: "300.0K")
        #expect(a == 300.0)
        #expect(b == 300.0)
    }

    // MARK: H — Celsius<->Kelvin uses 273.15

    @Test("H: Celsius condition value normalizes using the 273.15 offset")
    func celsiusNormalizationUsesExactOffset() {
        let normalized = SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .temperature, rawValue: "0C")
        #expect(normalized == 273.15)
        #expect(normalized != 273.0)
    }

    // MARK: I — magnetic-field normalization recognizes equivalent Oe/T values

    @Test("I: magnetic-field normalization recognizes equivalent Oe/T values")
    func magneticFieldNormalizationEquivalentUnits() {
        let fromOe = SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .externalMagneticField, rawValue: "10000Oe")
        let fromTesla = SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .externalMagneticField, rawValue: "1T")
        #expect(fromOe == 1.0)
        #expect(fromTesla == 1.0)
        #expect(fromOe == fromTesla)
    }

    // MARK: J — current normalization is independent of peak/RMS basis

    @Test("J: current normalization is unit-only, independent of peak/RMS basis")
    func currentNormalizationIndependentOfBasis() {
        // SidecarConditionNormalizer has no basis parameter at all — normalization is purely a
        // unit conversion. A raw "10mA" condition value normalizes identically regardless of
        // whatever basis a consuming workflow later interprets it under.
        let normalized = SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .current, rawValue: "10mA")
        #expect(normalized == 10.0)
        // Same raw condition value normalizes identically no matter which basis a downstream
        // workflow later interprets it under — normalization never reads IVCurrentBasis/
        // WorkbenchCurrentBasis, confirmed by there being no basis parameter on this API at all.
        let normalizedAgain = SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .current, rawValue: "10mA")
        #expect(normalized == normalizedAgain)
        // CurrentUnit and the (unrelated) measurement-basis enum remain fully distinct types.
        #expect(CurrentUnit.milliampere != CurrentUnit.microampere)
        #expect(IVCurrentBasis.peak != IVCurrentBasis.rms)
    }

    // MARK: Unrecognized / unparseable values fall back safely

    @Test("Unparseable or unrecognized-unit values normalize to nil, not a crash or wrong number")
    func unparseableValuesFallBackToNil() {
        #expect(SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .temperature, rawValue: "shift") == nil)
        #expect(SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .temperature, rawValue: "300F") == nil)
        #expect(SidecarConditionNormalizer.normalizedCanonicalValue(quantity: .rxx, rawValue: "300K") == nil)
    }

    @Test("sidecar.normalizedConditionValue(for:) composes lookup + normalization")
    func sidecarNormalizedConditionValueConvenience() {
        let sidecar = makeSidecar(conditions: ["temperature": "0C"])
        #expect(sidecar.normalizedConditionValue(for: .temperature) == 273.15)
        #expect(sidecar.normalizedConditionValue(for: .rxx) == nil)
    }
}
