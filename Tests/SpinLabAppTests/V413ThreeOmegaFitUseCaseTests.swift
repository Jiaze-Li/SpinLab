import Foundation
import Testing
@testable import SpinLabApp

/// V4.1.3 — 3ω field-sweep physics extraction and ingestion pipeline.
///
/// Coverage:
///   - V3ω window-average extraction (primary AHE signal)
///   - V3ω high-field extrapolation cross-check
///   - RAHE extraction from background-subtracted resistance
///   - Hc zero-crossing extraction
///   - Edge cases: insufficient data → nil/NaN
///   - PlotRenderer Tab 3–5 non-nil output
///   - RT file selection: multiple RT files → pick longest
@Suite("V4.1.3 ThreeOmega Fit, Render & Ingestion")
struct V413ThreeOmegaFitUseCaseTests {

    // MARK: - Synthetic data helpers

    /// Builds a synthetic field-sweep LVM file with a clean step-function hysteresis.
    ///
    /// Scan order: H descends from +hMax → −hMax, then ascends from −hMax → +hMax.
    /// R¹ω = step function with amplitude `rahe` and coercivity `hc`.
    /// R³ω = step function with amplitude `rahe3` and coercivity `hc3`.
    /// col5 (raw V³ω_X) has a known offset between branches to test window extraction.
    private func makeFieldSweepFile(
        temperatureK: Double = 200,
        device: String = "0deg",
        iRms: Double = 1e-4,
        hMax: Double = 10_000,
        rahe: Double = 0.5,
        hc: Double = 5000,
        rahe3: Double = 0.1,
        hc3: Double = 3000,
        v3wDescBias: Double = -2e-6,
        v3wAscBias: Double = 2e-6,
        nHalf: Int = 50
    ) -> ThreeOmegaLVMFile {
        let step = 2.0 * hMax / Double(nHalf)

        // Descending: +hMax → −hMax
        let descH = (0...nHalf).map { hMax - step * Double($0) }
        // Ascending: −hMax → +hMax (skip duplicate at −hMax)
        let ascH = (1...nHalf).map { -hMax + step * Double($0) }
        let H = descH + ascH
        let N = H.count
        let descCount = descH.count  // indices 0..<descCount are descending

        // Square hysteresis loop:
        // Descending (H from +max→−max): R = +amplitude for H > −hc, −amplitude for H < −hc
        // Ascending (H from −max→+max):  R = −amplitude for H < +hc, +amplitude for H > +hc
        // This produces a clean midpoint crossing at exactly ±hc.
        func stepR(_ h: Double, _ amplitude: Double, _ coercivity: Double, isDescending: Bool) -> Double {
            if isDescending {
                return h > -coercivity ? amplitude : -amplitude
            } else {
                return h > coercivity ? amplitude : -amplitude
            }
        }

        // Build col1 and col5 as voltages (R × iRms)
        var col1 = [Double](repeating: 0, count: N)
        var col5 = [Double](repeating: 0, count: N)
        var col9 = [Double](repeating: 0, count: N)

        for i in 0..<N {
            let isDesc = i < descCount
            let r1 = stepR(H[i], rahe, hc, isDescending: isDesc)
            let r3 = stepR(H[i], rahe3, hc3, isDescending: isDesc)
            col1[i] = r1 * iRms
            // V³ω raw voltage: R³ω × iRms + branch-dependent bias for window test
            let bias = isDesc ? v3wDescBias : v3wAscBias
            col5[i] = r3 * iRms + bias
            col9[i] = r1  // pre-calculated R (not used for field-sweep fitting)
        }

        return ThreeOmegaLVMFile(
            iRms: iRms,
            iAmpFromFilename: iRms * sqrt(2),
            temperatureK: temperatureK,
            device: device,
            fileKind: .fieldSweep,
            stem: "test_3w_\(Int(temperatureK))K",
            col0: H,
            col1: col1,
            col5: col5,
            col9: col9
        )
    }

    /// Builds a synthetic RT sweep file.
    private func makeRTFile(
        device: String = "0deg",
        temperatures: [Double],
        rxx: [Double],
        stem: String = "test_RT"
    ) -> ThreeOmegaLVMFile {
        ThreeOmegaLVMFile(
            iRms: 1e-4,
            temperatureK: .nan,
            device: device,
            fileKind: .rtSweep,
            stem: stem,
            col0: temperatures,
            col1: [Double](repeating: 0, count: temperatures.count),
            col5: [Double](repeating: 0, count: temperatures.count),
            col9: rxx
        )
    }

    /// Builds a minimal `WorkflowMeasurementSearchHit` for ingestion tests.
    private func makeHit(path: String, canonicalID: String = "3w", temperature: String? = nil) -> WorkflowMeasurementSearchHit {
        var conditions: [String: String] = [:]
        if let t = temperature { conditions["temperature"] = t }
        return WorkflowMeasurementSearchHit(
            sidecarPath: path + ".sidecar",
            measurementFilePath: path,
            sourceFilePath: path,
            workflowID: "3w",
            workflowDisplayName: "3w",
            workflowCanonicalID: canonicalID,
            batchID: "B1",
            sampleKey: "TestSample",
            sampleSubstrate: "",
            conditions: conditions,
            channels: [],
            appliedAt: Date()
        )
    }

    // MARK: - V3ω window-average extraction

    @Test("process produces non-NaN v3omegaWindow for clean hysteresis")
    func v3omegaWindowBasic() {
        let file = makeFieldSweepFile()
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(!result.v3omegaWindow.isNaN)
    }

    @Test("v3omegaWindow equals (V_desc − V_asc) / 2 near H=0")
    func v3omegaWindowValue() {
        // Set rahe3=0 so col5 = pure bias (no R³ω step contribution in the window).
        // Bias: desc = −2e-6, asc = +2e-6
        // _windowV3w returns (V_desc − V_asc) / 2 = (−2e-6 − 2e-6) / 2 = −2e-6 V
        let file = makeFieldSweepFile(rahe3: 0, hc3: 1, v3wDescBias: -2e-6, v3wAscBias: 2e-6)
        let result = ThreeOmegaFitUseCase().process(file: file)
        let expected = -2e-6
        #expect(abs(result.v3omegaWindow - expected) < 1e-7,
                "v3omegaWindow \(result.v3omegaWindow) should be close to \(expected)")
    }

    @Test("v3omegaWindow is NaN when data has fewer than 4 points")
    func v3omegaWindowTooFewPoints() {
        var file = makeFieldSweepFile(nHalf: 1)  // only 3 points total
        file.col0 = [10000, 0, -10000]
        file.col1 = [1e-8, 0, -1e-8]
        file.col5 = [1e-9, 0, -1e-9]
        file.col9 = [100, 100, 100]
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.v3omegaWindow.isNaN)
    }

    // MARK: - V3ω high-field extrapolation cross-check

    @Test("v3omegaFit is non-nil for clean hysteresis with sufficient high-field points")
    func v3omegaFitNonNil() {
        let file = makeFieldSweepFile(nHalf: 50)
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.v3omegaFit != nil)
    }

    @Test("v3omegaFit is nil when high-field region has too few points")
    func v3omegaFitInsufficientPoints() {
        // nHalf=3 → only ~7 total points; high-field (>70% of 10000) has very few
        var fitter = ThreeOmegaFitUseCase()
        fitter.minHighFieldPoints = 10  // raise threshold to force nil
        let file = makeFieldSweepFile(nHalf: 5)
        let result = fitter.process(file: file)
        #expect(result.v3omegaFit == nil)
    }

    // MARK: - RAHE extraction

    @Test("rahe1omega is extracted for clean step-function hysteresis")
    func rahe1omegaNonNil() {
        let file = makeFieldSweepFile(rahe: 0.5, hc: 5000)
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.rahe1omega != nil)
    }

    @Test("rahe1omega value is close to input amplitude")
    func rahe1omegaValue() {
        let amplitude = 0.5
        let file = makeFieldSweepFile(rahe: amplitude, hc: 5000)
        let result = ThreeOmegaFitUseCase().process(file: file)
        // After centering + background subtraction, RAHE should recover ≈ amplitude
        guard let rahe = result.rahe1omega else {
            Issue.record("rahe1omega should not be nil"); return
        }
        #expect(abs(rahe - amplitude) < 0.05,
                "rahe1omega \(rahe) should be close to \(amplitude)")
    }

    @Test("rahe(3ω, HFE) derived from v3omegaFit / iRms")
    func rahe3omegaHFEDerived() {
        let file = makeFieldSweepFile(rahe3: 0.1, hc3: 3000)
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.rahe(harmonic: 3, method: .highField) != nil)
    }

    @Test("rahe1omegaWA is extracted via window average on col9")
    func rahe1omegaWANonNil() {
        let file = makeFieldSweepFile()
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.rahe1omegaWA != nil)
    }

    // MARK: - Hc zero-crossing extraction

    @Test("hc1omega is extracted for clean hysteresis")
    func hc1omegaNonNil() {
        let file = makeFieldSweepFile(hc: 5000)
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.hc1omega != nil)
    }

    @Test("hc1omega is positive and within field range")
    func hc1omegaValue() {
        let file = makeFieldSweepFile(rahe: 0.5, hc: 5000, nHalf: 200)
        let result = ThreeOmegaFitUseCase().process(file: file)
        guard let hc = result.hc1omega else {
            Issue.record("hc1omega should not be nil"); return
        }
        #expect(hc > 0, "hc1omega should be positive")
        #expect(hc < 10000, "hc1omega should be within field range")
    }

    @Test("hc3omega is extracted for R³ω signal")
    func hc3omegaNonNil() {
        let file = makeFieldSweepFile(hc3: 3000)
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.hc3omega != nil)
    }

    @Test("hc3omega is positive and within field range")
    func hc3omegaValue() {
        let file = makeFieldSweepFile(rahe3: 0.1, hc3: 3000, nHalf: 200)
        let result = ThreeOmegaFitUseCase().process(file: file)
        guard let hc = result.hc3omega else {
            Issue.record("hc3omega should not be nil"); return
        }
        #expect(hc > 0, "hc3omega should be positive")
        #expect(hc < 10000, "hc3omega should be within field range")
    }

    // MARK: - Edge cases

    @Test("process handles empty file gracefully")
    func emptyFile() {
        let file = ThreeOmegaLVMFile(
            iRms: 1e-4,
            temperatureK: 300,
            device: "0deg",
            fileKind: .fieldSweep,
            stem: "empty",
            col0: [], col1: [], col5: [], col9: []
        )
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.hField.isEmpty)
        #expect(result.rahe1omega == nil)
        #expect(result.hc1omega == nil)
        #expect(result.v3omegaWindow.isNaN)
        #expect(result.v3omegaFit == nil)
    }

    @Test("temperature and device pass through from file to result")
    func metadataPassthrough() {
        let file = makeFieldSweepFile(temperatureK: 77, device: "30deg")
        let result = ThreeOmegaFitUseCase().process(file: file)
        #expect(result.temperatureK == 77)
        #expect(result.device == "30deg")
    }

    @Test("renderHcVsT produces non-nil PNG for valid sweeps")
    func renderHcVsTNonNil() {
        let sweeps = [100.0, 200.0, 300.0].map { t in
            ThreeOmegaFitUseCase().process(file: makeFieldSweepFile(temperatureK: t))
        }
        var renderer = ThreeOmegaPlotRenderer()
        let (data, _, _, _) = renderer.renderHcVsT(sweeps: sweeps, device: "0deg")
        #expect(data != nil)
    }

    @Test("renderHcVsT returns nil for empty sweeps")
    func renderHcVsTEmpty() {
        var renderer = ThreeOmegaPlotRenderer()
        let (data, _, _, _) = renderer.renderHcVsT(sweeps: [], device: "0deg")
        #expect(data == nil)
    }

    @Test("renderRT produces non-nil PNG for valid RT result")
    func renderRTNonNil() {
        let rt = ThreeOmegaRTResult(
            device: "0deg",
            temperatureK: [10, 50, 100, 200, 300],
            rxx: [500, 450, 400, 350, 300]
        )
        var renderer = ThreeOmegaPlotRenderer()
        let (data, _, _, _) = renderer.renderRT(rt: rt)
        #expect(data != nil)
    }

    @Test("renderRT returns nil for empty RT data")
    func renderRTEmpty() {
        let rt = ThreeOmegaRTResult(device: "0deg", temperatureK: [], rxx: [])
        var renderer = ThreeOmegaPlotRenderer()
        let (data, _, _, _) = renderer.renderRT(rt: rt)
        #expect(data == nil)
    }

    // MARK: - RT file selection (via IngestThreeOmegaSelectionsUseCase)

    @Test("Ingestion selects RT file with most data rows when multiple exist")
    func rtFileSelectionPicksLongest() {
        let rtShort = makeRTFile(temperatures: [300], rxx: [100], stem: "RT_short")
        let rtLong = makeRTFile(
            temperatures: [10, 50, 100, 200, 300],
            rxx: [500, 450, 400, 350, 300],
            stem: "RT_long"
        )

        let hits = [
            makeHit(path: "/fake/RT_short.lvm", canonicalID: "rt"),
            makeHit(path: "/fake/RT_long.lvm", canonicalID: "rt"),
        ]

        let fileMap: [String: ThreeOmegaLVMFile] = [
            "/fake/RT_short.lvm": rtShort,
            "/fake/RT_long.lvm": rtLong,
        ]

        let uc = IngestThreeOmegaSelectionsUseCase()
        let result = uc.execute(hits: hits) { url in
            guard let file = fileMap[url.path] else {
                throw NSError(domain: "test", code: 1)
            }
            return file
        }

        #expect(result.rtResult != nil)
        #expect(result.rtResult?.temperatureK.count == 5)
    }

    @Test("Ingestion emits warning for multiple RT files")
    func rtFileSelectionWarning() {
        let rt1 = makeRTFile(temperatures: [300], rxx: [100], stem: "RT_1")
        let rt2 = makeRTFile(temperatures: [10, 300], rxx: [500, 100], stem: "RT_2")

        let hits = [
            makeHit(path: "/fake/RT_1.lvm", canonicalID: "rt"),
            makeHit(path: "/fake/RT_2.lvm", canonicalID: "rt"),
        ]
        let fileMap: [String: ThreeOmegaLVMFile] = [
            "/fake/RT_1.lvm": rt1,
            "/fake/RT_2.lvm": rt2,
        ]

        let uc = IngestThreeOmegaSelectionsUseCase()
        let result = uc.execute(hits: hits) { url in
            guard let file = fileMap[url.path] else {
                throw NSError(domain: "test", code: 1)
            }
            return file
        }

        let hasWarning = result.warnings.contains { $0.contains("Multiple RT files") }
        #expect(hasWarning)
    }

    @Test("Ingestion sorts field sweeps by temperature ascending")
    func fieldSweepsSortedByTemperature() {
        let f300 = makeFieldSweepFile(temperatureK: 300)
        let f100 = makeFieldSweepFile(temperatureK: 100)
        let f200 = makeFieldSweepFile(temperatureK: 200)

        let hits = [
            makeHit(path: "/fake/3w_300K.lvm"),
            makeHit(path: "/fake/3w_100K.lvm"),
            makeHit(path: "/fake/3w_200K.lvm"),
        ]
        let fileMap: [String: ThreeOmegaLVMFile] = [
            "/fake/3w_300K.lvm": f300,
            "/fake/3w_100K.lvm": f100,
            "/fake/3w_200K.lvm": f200,
        ]

        let uc = IngestThreeOmegaSelectionsUseCase()
        let result = uc.execute(hits: hits) { url in
            guard let file = fileMap[url.path] else {
                throw NSError(domain: "test", code: 1)
            }
            return file
        }

        let temps = result.fieldSweeps.map(\.temperatureK)
        #expect(temps == [100, 200, 300])
    }

    @Test("Ingestion deduplicates by measurementFilePath")
    func ingestionDeduplicates() {
        let file = makeFieldSweepFile(temperatureK: 200)
        let hits = [
            makeHit(path: "/fake/same.lvm"),
            makeHit(path: "/fake/same.lvm"),
        ]

        let uc = IngestThreeOmegaSelectionsUseCase()
        let result = uc.execute(hits: hits) { _ in file }

        #expect(result.fieldSweeps.count == 1)
    }

    @Test("Ingestion returns empty result for no hits")
    func ingestionEmptyHits() {
        let uc = IngestThreeOmegaSelectionsUseCase()
        let result = uc.execute(hits: [])
        #expect(result.fieldSweeps.isEmpty)
        #expect(result.rtResult == nil)
    }

    @Test("RT result temperature array is sorted ascending")
    func rtResultSortedByTemperature() {
        // Provide unsorted temperatures
        let rt = makeRTFile(
            temperatures: [300, 10, 200, 50, 100],
            rxx: [300, 500, 350, 450, 400],
            stem: "RT_unsorted"
        )
        let hits = [makeHit(path: "/fake/RT.lvm", canonicalID: "rt")]
        let uc = IngestThreeOmegaSelectionsUseCase()
        let result = uc.execute(hits: hits) { _ in rt }

        #expect(result.rtResult != nil)
        #expect(result.rtResult?.temperatureK == [10, 50, 100, 200, 300])
        // Rxx should follow the same sort order
        #expect(result.rtResult?.rxx == [500, 450, 400, 350, 300])
    }
}
