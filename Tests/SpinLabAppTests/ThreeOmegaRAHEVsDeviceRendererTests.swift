import Testing
@testable import SpinLabApp

@Suite("ThreeOmegaRAHEVsDevice renderer")
struct ThreeOmegaRAHEVsDeviceRendererTests {

    private func makeSweep(device: String, temperatureK: Double, rahe1: Double, rahe3: Double) -> ThreeOmegaFieldSweepResult {
        ThreeOmegaFieldSweepResult(
            temperatureK: temperatureK,
            device: device,
            hField: [-100, 0, 100],
            r1omega: [0, 0, 0],
            r3omega: [0, 0, 0],
            iRms: 1e-4,
            rahe1omega: rahe1,
            rahe1omegaWA: rahe1 * 0.98,
            hc1omega: nil, hc3omega: nil,
            v3omegaWindow: rahe3 * 1e-4,
            v3omegaFit: rahe3 * 1e-4
        )
    }

    private func makeSweeps() -> [ThreeOmegaFieldSweepResult] {
        [
            makeSweep(device: "30deg",  temperatureK: 200, rahe1: 0.30, rahe3: 0.60),
            makeSweep(device: "0deg",   temperatureK: 200, rahe1: 0.10, rahe3: 0.20),
            makeSweep(device: "60deg",  temperatureK: 200, rahe1: 0.50, rahe3: 1.00),
        ]
    }

    // MARK: - RAHE(1ω) vs Device

    @Test("render produces non-nil data for valid sweeps with HFE method")
    func rahe1DevNonNil() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let (data, _, layout, display, warnings) = r.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        #expect(data != nil)
        #expect(layout != nil)
        #expect(display != nil)
        #expect(warnings.isEmpty)
    }

    @Test("x values are sorted by numeric angle")
    func rahe1DevSortedX() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let (_, _, _, display, _) = r.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        guard let series = display?.series.first else {
            Issue.record("No series in display payload")
            return
        }
        let xs = series.x
        #expect(xs.count == 3)
        #expect(xs[0] < xs[1] && xs[1] < xs[2], "x values must be ascending")
        #expect(xs[0] == 0, "first x should be 0° (from '0deg')")
        #expect(xs[1] == 30, "second x should be 30° (from '30deg')")
        #expect(xs[2] == 60, "third x should be 60° (from '60deg')")
    }

    @Test("y values match rahe(1, .highField)")
    func rahe1DevYValues() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let (_, _, _, display, _) = r.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        guard let series = display?.series.first else {
            Issue.record("No series")
            return
        }
        // After sort by angle: 0deg→0.10, 30deg→0.30, 60deg→0.50
        #expect(abs(series.y[0] - 0.10) < 1e-9)
        #expect(abs(series.y[1] - 0.30) < 1e-9)
        #expect(abs(series.y[2] - 0.50) < 1e-9)
    }

    @Test("axis labels are correct for 1ω HFE")
    func rahe1DevAxisLabels() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let (_, _, _, display, _) = r.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        #expect(display?.axisMapping.xField == "Ψ (deg)")
        #expect(display?.axisMapping.yField == #"math:R_{AHE}^{1ω} (Ω)"#)
    }

    // MARK: - RAHE(3ω) vs Device

    @Test("render 3ω produces non-nil data")
    func rahe3DevNonNil() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let (data, _, _, _, warnings) = r.renderRAHE3omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        #expect(data != nil)
        #expect(warnings.isEmpty)
    }

    @Test("3ω y values come from rahe(3, method)")
    func rahe3DevYValues() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let (_, _, _, display, _) = r.renderRAHE3omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        guard let series = display?.series.first else {
            Issue.record("No series")
            return
        }
        // 3ω HFE: v3omegaFit / iRms. For 0deg: 0.20*1e-4/1e-4 = 0.20
        let expected0deg = 0.20
        #expect(abs(series.y[0] - expected0deg) < 1e-9)
    }

    @Test("window method uses WA values")
    func rahe1DevWAMethod() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = makeSweeps()
        let (_, _, _, display, _) = r.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .window)
        guard let series = display?.series.first else {
            Issue.record("No series")
            return
        }
        // WA: rahe1omegaWA = rahe1 * 0.98. For 0deg: 0.10 * 0.98 = 0.098
        #expect(abs(series.y[0] - 0.098) < 1e-9)
    }

    // MARK: - Temperature policy

    @Test("returns nil and warning when multiple temperatures are present")
    func multiTempReturnsNil() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = [
            makeSweep(device: "0deg",  temperatureK: 200, rahe1: 0.1, rahe3: 0.2),
            makeSweep(device: "30deg", temperatureK: 300, rahe1: 0.3, rahe3: 0.6),
        ]
        let (data, _, layout, display, warnings) = r.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        #expect(data == nil)
        #expect(layout == nil)
        #expect(display == nil)
        #expect(!warnings.isEmpty, "should emit a warning for mixed temperatures")
    }

    // MARK: - Sweeps without parseable device are skipped

    @Test("sweeps with non-angle device strings are excluded")
    func skipsUnparseable() {
        var r = ThreeOmegaPlotRenderer()
        let sweeps = [
            makeSweep(device: "0deg",       temperatureK: 200, rahe1: 0.1, rahe3: 0.2),
            makeSweep(device: "unknown",    temperatureK: 200, rahe1: 0.5, rahe3: 1.0),
            makeSweep(device: "30deg",      temperatureK: 200, rahe1: 0.3, rahe3: 0.6),
        ]
        let (_, _, _, display, warnings) = r.renderRAHE1omegaVsDevice(sweeps: sweeps, device: "angle_sweep", method: .highField)
        #expect(display?.series.first?.x.count == 2, "should have 2 points (0deg and 30deg only)")
        #expect(warnings.isEmpty, "non-parseable device is silently skipped, not a warning")
    }
}
