import Testing
@testable import SpinLabApp

@Suite("ThreeOmegaDeviceAngleParser")
struct ThreeOmegaDeviceAngleParserTests {

    // MARK: - Valid formats

    @Test("parses '0deg'")
    func zero() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("0deg") == 0)
    }

    @Test("parses '30deg'")
    func thirtyDeg() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("30deg") == 30)
    }

    @Test("parses '-15deg'")
    func negativeDeg() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("-15deg") == -15)
    }

    @Test("parses '+45deg'")
    func plusDeg() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("+45deg") == 45)
    }

    @Test("parses '0 deg' with space")
    func spaceBeforeDeg() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("0 deg") == 0)
    }

    @Test("parses '45°' with degree symbol")
    func degreeSymbol() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("45°") == 45)
    }

    @Test("parses 'device_30deg' embedded token")
    func embeddedToken() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("device_30deg") == 30)
    }

    @Test("parses decimal angle '22.5deg'")
    func decimal() {
        let result = ThreeOmegaDeviceAngleParser.parseDegrees("22.5deg")
        #expect(result == 22.5)
    }

    @Test("parses '-90°'")
    func negativeSymbol() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("-90°") == -90)
    }

    // MARK: - Rejects non-angle strings

    @Test("rejects plain number without unit")
    func rejectsPlainNumber() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("30") == nil)
    }

    @Test("rejects empty string")
    func rejectsEmpty() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("") == nil)
    }

    @Test("rejects 'angle_sweep'")
    func rejectsAngleSweep() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("angle_sweep") == nil)
    }

    @Test("rejects 'device'")
    func rejectsDevice() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("device") == nil)
    }

    @Test("rejects 'sample1'")
    func rejectsSampleLabel() {
        #expect(ThreeOmegaDeviceAngleParser.parseDegrees("sample1") == nil)
    }
}
