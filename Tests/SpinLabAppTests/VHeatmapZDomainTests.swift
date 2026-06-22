import Foundation
import Testing
@testable import SpinLabApp

@Suite("HeatmapZDomain")
struct HeatmapZDomainTests {

    private func makePayload(values: [[Double]]) -> HeatmapPlotPayload {
        let xValues = values.first?.indices.map(Double.init) ?? []
        let yValues = values.indices.map(Double.init)
        return HeatmapPlotPayload(
            workflowID: "heatmap",
            title: "Domain",
            xLabel: "X",
            yLabel: "Y",
            zLabel: "Z",
            grid: HeatmapGrid(
                xValues: xValues,
                yValues: yValues,
                zMatrix: values
            )
        )
    }

    @Test("Auto preserves existing data min/max behavior")
    func autoPreservesExistingDataRange() {
        let values = [[1.0, 2.0], [3.0, 10.0]]
        let resolution = HeatmapZDomainState(mode: .auto).resolve(rawValues: values.flatMap { $0 })
        #expect(resolution == .resolved(lowerBound: 1.0, upperBound: 10.0))
    }

    @Test("Manual valid min/max resolves domain")
    func manualValidMinMaxResolvesDomain() {
        let state = HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "2.5", maxText: "9.5")
        )
        let resolution = state.resolve(rawValues: [1, 2, 3])
        #expect(resolution == .resolved(lowerBound: 2.5, upperBound: 9.5))
    }

    @Test("Manual empty min falls back safely")
    func manualEmptyMinFallsBackSafely() {
        let state = HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "", maxText: "9.5")
        )
        #expect(state.resolve(rawValues: [1, 2, 3]) == .fallbackToAuto(reason: HeatmapZDomainValidationIssue.manualMinMissing.message))
    }

    @Test("Manual empty max falls back safely")
    func manualEmptyMaxFallsBackSafely() {
        let state = HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "2.5", maxText: "")
        )
        #expect(state.resolve(rawValues: [1, 2, 3]) == .fallbackToAuto(reason: HeatmapZDomainValidationIssue.manualMaxMissing.message))
    }

    @Test("Manual non-numeric input falls back safely")
    func manualNonNumericFallsBackSafely() {
        let state = HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "abc", maxText: "9.5")
        )
        #expect(state.resolve(rawValues: [1, 2, 3]) == .fallbackToAuto(reason: HeatmapZDomainValidationIssue.manualMinInvalid.message))
    }

    @Test("Manual NaN and Inf fall back safely")
    func manualNaNAndInfFallBackSafely() {
        let nanState = HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "nan", maxText: "9.5")
        )
        let infState = HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "2.5", maxText: "inf")
        )
        #expect(nanState.resolve(rawValues: [1, 2, 3]) == .fallbackToAuto(reason: HeatmapZDomainValidationIssue.manualMinInvalid.message))
        #expect(infState.resolve(rawValues: [1, 2, 3]) == .fallbackToAuto(reason: HeatmapZDomainValidationIssue.manualMaxInvalid.message))
    }

    @Test("Manual min >= max falls back safely")
    func manualMinGreaterThanMaxFallsBackSafely() {
        let state = HeatmapZDomainState(
            mode: .manual,
            manualRange: HeatmapZRangeDraft(minText: "9", maxText: "2")
        )
        #expect(state.resolve(rawValues: [1, 2, 3]) == .fallbackToAuto(reason: HeatmapZDomainValidationIssue.manualRangeInverted.message))
    }

    @Test("Percentile preset computes expected domain")
    func percentilePresetComputesExpectedDomain() {
        let values = Array(stride(from: 0.0, through: 100.0, by: 10.0))
        let state = HeatmapZDomainState(
            mode: .percentile,
            percentilePreset: .p5_95
        )
        #expect(state.resolve(rawValues: values) == .resolved(lowerBound: 5.0, upperBound: 95.0))
    }

    @Test("Supported percentile presets remain visible and custom stays hidden")
    func visiblePercentilePresetsExcludeCustom() {
        #expect(HeatmapPercentilePreset.visiblePresets == [
            .p0_5_99_5,
            .p1_99,
            .p2_98,
            .p5_95
        ])
        #expect(!HeatmapPercentilePreset.visiblePresets.contains(.custom))
    }

    @Test("Percentile invalid or collapsed domain falls back safely")
    func percentileInvalidOrCollapsedDomainFallsBackSafely() {
        let invalidClamp = HeatmapZDomainState(
            mode: .percentile,
            percentilePreset: .custom,
            percentileClamp: .init(lowerPercent: 80, upperPercent: 20)
        )
        let collapsed = HeatmapZDomainState(
            mode: .percentile,
            percentilePreset: .p5_95
        )
        #expect(invalidClamp.validationIssue() == .percentileInvalidClamp)
        #expect(collapsed.resolve(rawValues: [5, 5, 5]) == .fallbackToAuto(reason: HeatmapZDomainValidationIssue.percentileCollapsedDomain.message))
    }

    @Test("Restored custom percentile state still resolves using stored clamp")
    func customPercentileStateResolvesUsingStoredClamp() throws {
        let state = HeatmapZDomainState(
            mode: .percentile,
            percentilePreset: .custom,
            percentileClamp: .init(lowerPercent: 2, upperPercent: 98)
        )
        let output = try HeatmapRenderPipeline.render(.init(
            payload: makePayload(values: [
                [0.0, 10.0, 20.0],
                [30.0, 40.0, 100.0]
            ]),
            colorScaleMode: .linear,
            zDomainState: state
        ))
        #expect(output.layout.zMin > 0.0)
        #expect(output.layout.zMax < 100.0)
    }

    @Test("Linear plus percentile works")
    func linearPlusPercentileWorks() throws {
        let payload = makePayload(values: [
            [1.0, 2.0, 3.0, 100.0],
            [4.0, 5.0, 6.0, 200.0]
        ])
        let output = try HeatmapRenderPipeline.render(.init(
            payload: payload,
            colorScaleMode: .linear,
            zDomainState: HeatmapZDomainState(mode: .percentile, percentilePreset: .p5_95)
        ))
        #expect(output.layout.zMin > 1.0)
        #expect(output.layout.zMax < 200.0)
    }

    @Test("Log plus percentile works")
    func logPlusPercentileWorks() throws {
        let payload = makePayload(values: [
            [1.0, 10.0, 100.0],
            [2.0, 20.0, 200.0]
        ])
        let output = try HeatmapRenderPipeline.render(.init(
            payload: payload,
            colorScaleMode: .log10,
            zDomainState: HeatmapZDomainState(mode: .percentile, percentilePreset: .p5_95)
        ))
        #expect(output.layout.colorbarTicks.contains { $0.label.contains("1e") })
        #expect(output.layout.zMin > 0)
        #expect(output.layout.zMax > output.layout.zMin)
    }

    @Test("Zero and negative values under log remain safe")
    func zeroAndNegativeValuesUnderLogRemainSafe() throws {
        let payload = makePayload(values: [
            [-10.0, 0.0, 1.0],
            [2.0, 10.0, 100.0]
        ])
        let data = try HeatmapRenderPipeline.render(.init(
            payload: payload,
            colorScaleMode: .log10,
            zDomainState: HeatmapZDomainState(mode: .auto)
        ))
        #expect(!data.imageData.isEmpty)
        #expect(data.layout.zMin.isFinite)
        #expect(data.layout.zMax.isFinite)
    }

    @Test("Auto with all-identical non-zero values resolves to valid non-zero span")
    func autoFlatNonZeroValuesExpandsSpan() throws {
        let resolution = HeatmapZDomainState(mode: .auto).resolve(rawValues: [5, 5, 5])
        guard case .resolved(let lo, let hi) = resolution else {
            Issue.record("Expected .resolved, got \(resolution)")
            return
        }
        #expect(lo < hi)
        #expect(lo.isFinite)
        #expect(hi.isFinite)
        // Render pipeline must not throw
        let payload = makePayload(values: [[5.0, 5.0], [5.0, 5.0]])
        let output = try HeatmapRenderPipeline.render(.init(
            payload: payload,
            zDomainState: HeatmapZDomainState(mode: .auto)
        ))
        #expect(!output.imageData.isEmpty)
    }

    @Test("Auto with all-zero values resolves to valid non-zero span")
    func autoFlatZeroValuesExpandsSpan() throws {
        let resolution = HeatmapZDomainState(mode: .auto).resolve(rawValues: [0, 0])
        guard case .resolved(let lo, let hi) = resolution else {
            Issue.record("Expected .resolved, got \(resolution)")
            return
        }
        #expect(lo < hi)
        #expect(lo.isFinite)
        #expect(hi.isFinite)
        // Render pipeline must not throw
        let payload = makePayload(values: [[0.0, 0.0], [0.0, 0.0]])
        let output = try HeatmapRenderPipeline.render(.init(
            payload: payload,
            zDomainState: HeatmapZDomainState(mode: .auto)
        ))
        #expect(!output.imageData.isEmpty)
    }

    @Test("Resolution never produces NaN or Inf")
    func resolutionNeverProducesNaNOrInf() {
        let states: [HeatmapZDomainState] = [
            .init(mode: .auto),
            .init(mode: .manual, manualRange: .init(minText: "0", maxText: "1")),
            .init(mode: .percentile, percentilePreset: .p1_99)
        ]
        for state in states {
            let resolution = state.resolve(rawValues: [0, 1, 2, 3, 4, 5])
            if case .resolved(let lowerBound, let upperBound) = resolution {
                #expect(lowerBound.isFinite)
                #expect(upperBound.isFinite)
            }
        }
    }
}
