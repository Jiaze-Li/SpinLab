import Testing
import Foundation
@testable import SpinLabApp

/// v5.5.8 Phase 3a — PhysicalQuantity domain registry. Locks the Tier-A/Tier-B bridge, the new
/// typed unit families (Temperature, Current), and that MagneticFieldUnit's move to
/// Domain/PhysicalQuantity preserved its exact numeric behavior. See the 2026-08-08 registry
/// audit report for the design this implements.
@Suite("v5.5.8 - PhysicalQuantity domain registry")
struct V558PhysicalQuantityRegistryTests {

    // MARK: - WorkbenchPhysicalQuantity -> PhysicalQuantityID bridge

    @Test("Tier-A quantities bridge to their PhysicalQuantityID")
    func tierABridges() {
        #expect(WorkbenchPhysicalQuantity.externalMagneticField.physicalQuantityID == .externalMagneticField)
        #expect(WorkbenchPhysicalQuantity.coerciveField.physicalQuantityID == .coerciveField)
        #expect(WorkbenchPhysicalQuantity.temperature.physicalQuantityID == .temperature)
        #expect(WorkbenchPhysicalQuantity.deviceAngle.physicalQuantityID == .deviceAngle)
        #expect(WorkbenchPhysicalQuantity.angleOffset.physicalQuantityID == .angleOffset)
        #expect(WorkbenchPhysicalQuantity.current.physicalQuantityID == .current)
        #expect(WorkbenchPhysicalQuantity.voltage.physicalQuantityID == .voltage)
        #expect(WorkbenchPhysicalQuantity.resistance1omega.physicalQuantityID == .resistance1omega)
        #expect(WorkbenchPhysicalQuantity.resistance3omega.physicalQuantityID == .resistance3omega)
        #expect(WorkbenchPhysicalQuantity.rxx.physicalQuantityID == .rxx)
        #expect(WorkbenchPhysicalQuantity.rxy.physicalQuantityID == .rxy)
        #expect(WorkbenchPhysicalQuantity.reciprocalH.physicalQuantityID == .reciprocalH)
        #expect(WorkbenchPhysicalQuantity.reciprocalK.physicalQuantityID == .reciprocalK)
        #expect(WorkbenchPhysicalQuantity.reciprocalL.physicalQuantityID == .reciprocalL)
    }

    @Test("Tier-B (analysis/display-only) quantities have no domain mapping")
    func tierBReturnsNil() {
        #expect(WorkbenchPhysicalQuantity.rahe1omega.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.rahe3omega.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.raheCombined.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.hallResistance.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.sigmaXX.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.scalingLawX.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.scalingLawY.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.temperatureDependenceERatio.physicalQuantityID == nil)
        #expect(WorkbenchPhysicalQuantity.diffractionIntensity.physicalQuantityID == nil)
    }

    @Test("Every WorkbenchPhysicalQuantity case is classified (no silent Tier-A/Tier-B gap)")
    func everyCaseIsClassified() {
        // 14 Tier-A + 9 Tier-B == all 23 cases; this fails loudly if a future case is added to
        // WorkbenchPhysicalQuantity without an explicit Tier-A/Tier-B decision in the bridge.
        #expect(WorkbenchPhysicalQuantity.allCases.count == 23)
    }

    // MARK: - PhysicalQuantityRegistry

    @Test("Magnetic-field quantities map to the magnetic-field unit family")
    func magneticFieldFamily() {
        #expect(PhysicalQuantityRegistry.entry(for: .externalMagneticField).unitFamily == .magneticField)
        #expect(PhysicalQuantityRegistry.entry(for: .coerciveField).unitFamily == .magneticField)
    }

    @Test("Temperature and current map to their own unit families")
    func temperatureAndCurrentFamily() {
        #expect(PhysicalQuantityRegistry.entry(for: .temperature).unitFamily == .temperature)
        #expect(PhysicalQuantityRegistry.entry(for: .current).unitFamily == .current)
    }

    @Test("Quantities with no typed unit family are untyped")
    func untypedFamilies() {
        #expect(PhysicalQuantityRegistry.entry(for: .deviceAngle).unitFamily == .untyped)
        #expect(PhysicalQuantityRegistry.entry(for: .voltage).unitFamily == .untyped)
        #expect(PhysicalQuantityRegistry.entry(for: .rxx).unitFamily == .untyped)
        #expect(PhysicalQuantityRegistry.entry(for: .rxy).unitFamily == .untyped)
    }

    @Test("Distinct quantities sharing a unit family remain distinct identities")
    func quantityIdentityIndependentOfUnitFamily() {
        // externalMagneticField and coerciveField share MagneticFieldUnit but are not equal.
        #expect(PhysicalQuantityID.externalMagneticField != .coerciveField)
        #expect(PhysicalQuantityRegistry.entry(for: .externalMagneticField).unitFamily
                == PhysicalQuantityRegistry.entry(for: .coerciveField).unitFamily)
    }

    // MARK: - MagneticFieldUnit (moved, behavior must be unchanged)

    @Test("MagneticFieldUnit is Codable")
    func magneticFieldUnitIsCodable() throws {
        let encoded = try JSONEncoder().encode(MagneticFieldUnit.millitesla)
        let decoded = try JSONDecoder().decode(MagneticFieldUnit.self, from: encoded)
        #expect(decoded == .millitesla)
    }

    @Test("Oe -> T conversion is unchanged after the move (×1e-4)")
    func magneticFieldConversionUnchanged() {
        #expect(WorkbenchMagneticFieldUnitConverter.convert(10000, from: .oersted, to: .tesla) == 1.0)
    }

    // MARK: - TemperatureUnit

    @Test("Temperature round-trips K -> C -> K without drift")
    func temperatureRoundTrip() {
        let original = 300.0
        let celsius = TemperatureUnitConverter.convert(original, from: .kelvin, to: .celsius)
        let backToKelvin = TemperatureUnitConverter.convert(celsius, from: .celsius, to: .kelvin)
        #expect(abs(backToKelvin - original) < 1e-9)
    }

    @Test("Temperature conversion uses the physically correct 273.15 offset")
    func temperatureUsesExactOffset() {
        #expect(TemperatureUnitConverter.convert(0, from: .celsius, to: .kelvin) == 273.15)
        #expect(TemperatureUnitConverter.convert(273.15, from: .kelvin, to: .celsius) == 0)
        // Explicitly not the legacy +273 approximation.
        #expect(TemperatureUnitConverter.convert(0, from: .celsius, to: .kelvin) != 273.0)
    }

    @Test("Temperature same-unit conversion is a no-op")
    func temperatureSameUnitNoOp() {
        #expect(TemperatureUnitConverter.convert(42, from: .kelvin, to: .kelvin) == 42)
    }

    // MARK: - CurrentUnit

    @Test("Current round-trips A -> mA -> uA -> A without drift")
    func currentRoundTrip() {
        let original = 2.5
        let mA = CurrentUnitConverter.convert(original, from: .ampere, to: .milliampere)
        let uA = CurrentUnitConverter.convert(mA, from: .milliampere, to: .microampere)
        let backToAmpere = CurrentUnitConverter.convert(uA, from: .microampere, to: .ampere)
        #expect(abs(backToAmpere - original) < 1e-9)
    }

    @Test("A -> mA is ×1000, uA -> mA is ×0.001 (matches measuring_condition.json transforms)")
    func currentConversionFactors() {
        #expect(CurrentUnitConverter.convert(1, from: .ampere, to: .milliampere) == 1000)
        #expect(CurrentUnitConverter.convert(1, from: .microampere, to: .milliampere) == 0.001)
    }

    @Test("Current same-unit conversion is a no-op")
    func currentSameUnitNoOp() {
        #expect(CurrentUnitConverter.convert(7, from: .milliampere, to: .milliampere) == 7)
    }
}
