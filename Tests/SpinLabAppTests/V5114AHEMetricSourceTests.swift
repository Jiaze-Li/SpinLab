import Testing
import Foundation
@testable import SpinLabApp

@Suite("V5.1.14 AHE Metric Source")
struct V5114AHEMetricSourceTests {

    // INV-4: metric extraction reads sampleID (typed metadata), NOT label
    @Test("INV-4: metric key comes from sampleID, not label")
    func metricKeyFromSampleID() throws {
        let series = WorkbenchPlotSeries(
            label: "LabelX | channel | file",
            x: [-1.0, 0.0, 1.0],
            y: [-0.5, 0.0, 0.5],
            sampleID: "MetaY"
        )
        let result = try ExtractAHEMetricsUseCase.extractAHEMetricsPerSeries(from: [series]).get()
        #expect(result["MetaY"] != nil, "metric must be keyed by sampleID 'MetaY'")
        #expect(result["LabelX"] == nil, "metric must NOT be keyed by parsed label 'LabelX'")
    }

    // INV-4b: series without sampleID produces extraction failure
    @Test("INV-4b: series without sampleID produces unparseable label failure")
    func missingsSampleIDFails() {
        let series = WorkbenchPlotSeries(
            label: "SomeLabel",
            x: [1.0],
            y: [1.0]
            // sampleID not set → nil
        )
        let result = ExtractAHEMetricsUseCase.extractAHEMetricsPerSeries(from: [series])
        if case .failure(.unparseableLabels(let labels)) = result {
            #expect(labels.contains("SomeLabel"))
        } else {
            Issue.record("Expected unparseableLabels failure for series without sampleID")
        }
    }
}
