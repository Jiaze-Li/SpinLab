import Testing
import Foundation
@testable import SpinLabApp

@Suite("V4.2.5 Numeric Search")
struct V425NumericSearchTests {

    // MARK: - NumericUnitMap.parse

    @Test("Parse '60mj' → value=60, field=能量")
    func parseEnergyToken() {
        let result = NumericUnitMap.parse("60mj")
        #expect(result != nil)
        #expect(result?.value == 60.0)
        #expect(result?.field == "能量")
    }

    @Test("Parse '50mt' → value=50, field=氧压")
    func parseOxygenToken() {
        let result = NumericUnitMap.parse("50mt")
        #expect(result != nil)
        #expect(result?.value == 50.0)
        #expect(result?.field == "氧压")
    }

    @Test("Parse '700C' → value=700, field=温度 (case insensitive)")
    func parseTemperatureToken() {
        let result = NumericUnitMap.parse("700C")
        #expect(result != nil)
        #expect(result?.value == 700.0)
        #expect(result?.field == "温度")
    }

    @Test("Parse '1000ps' → value=1000, field=厚度")
    func parseThicknessToken() {
        let result = NumericUnitMap.parse("1000ps")
        #expect(result != nil)
        #expect(result?.value == 1000.0)
        #expect(result?.field == "厚度")
    }

    @Test("Parse '30kv' → value=30, field=电压")
    func parseVoltageToken() {
        let result = NumericUnitMap.parse("30kv")
        #expect(result != nil)
        #expect(result?.value == 30.0)
        #expect(result?.field == "电压")
    }

    @Test("Parse decimal '60.5mj' → value=60.5")
    func parseDecimalToken() {
        let result = NumericUnitMap.parse("60.5mj")
        #expect(result != nil)
        #expect(result?.value == 60.5)
        #expect(result?.field == "能量")
    }

    @Test("Non-numeric token returns nil")
    func parseNonNumericToken() {
        #expect(NumericUnitMap.parse("PN67") == nil)
        #expect(NumericUnitMap.parse("xy") == nil)
        #expect(NumericUnitMap.parse("STO111") == nil)
    }

    @Test("Zero value returns nil")
    func parseZeroValue() {
        #expect(NumericUnitMap.parse("0mj") == nil)
    }

    // MARK: - Tolerance

    @Test("Tolerance is ±6% with floor of 1.0")
    func toleranceCalculation() {
        // 60 * 0.06 = 3.6 > 1.0 → 3.6
        #expect(abs(NumericUnitMap.tolerance(for: 60.0) - 3.6) < 1e-9)
        // 10 * 0.06 = 0.6 < 1.0 → floor 1.0
        #expect(abs(NumericUnitMap.tolerance(for: 10.0) - 1.0) < 1e-9)
        // 5 * 0.06 = 0.3 < 1.0 → floor 1.0
        #expect(abs(NumericUnitMap.tolerance(for: 5.0) - 1.0) < 1e-9)
    }

    // MARK: - NumericFieldOrder

    @Test("Preferred order starts with 厚度")
    func fieldOrderFirst() {
        #expect(NumericFieldOrder.preferred.first == "厚度")
    }

    @Test("Preferred order contains all standard fields")
    func fieldOrderContents() {
        let order = NumericFieldOrder.preferred
        #expect(order.contains("厚度"))
        #expect(order.contains("氧压"))
        #expect(order.contains("温度"))
        #expect(order.contains("能量"))
        #expect(order.contains("电压"))
    }

    @Test("Field order matches Library orderedNumericTagKeys")
    func fieldOrderMatchesLibrary() {
        let libraryOrder = ["厚度", "氧压", "温度", "能量", "电压", "磁场", "电阻"]
        #expect(NumericFieldOrder.preferred == libraryOrder)
    }

    // MARK: - Edge cases (Risk 5: coverage)

    @Test("Token with trailing punctuation still parses")
    func parsePunctuationToken() {
        #expect(NumericUnitMap.parse("60mj,") != nil)
        #expect(NumericUnitMap.parse("60mj,")?.value == 60.0)
        #expect(NumericUnitMap.parse("(50mt)") != nil)
        #expect(NumericUnitMap.parse("(50mt)")?.value == 50.0)
    }

    @Test("Unit-only token returns nil")
    func parseUnitOnly() {
        #expect(NumericUnitMap.parse("mj") == nil)
        #expect(NumericUnitMap.parse("mt") == nil)
    }
}
