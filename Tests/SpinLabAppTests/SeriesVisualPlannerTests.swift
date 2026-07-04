import Foundation
import Testing
@testable import SpinLabApp

@Suite("SeriesVisualPlanner")
struct SeriesVisualPlannerTests {
    private func makeSeries(
        identityKey: String,
        sourceRef: String,
        sampleID: String,
        label: String,
        y: [Double]
    ) -> WorkbenchPlotSeries {
        WorkbenchPlotSeries(
            label: label,
            x: [0, 1, 2],
            y: y,
            sourceRef: sourceRef,
            sampleID: sampleID
        )
        .withSeriesIdentityKey(identityKey)
    }

    private func makeStackedSeries(
        identityKey: String,
        sourceRef: String,
        sampleID: String,
        temperatureK: Double,
        meanY: Double
    ) -> WorkbenchPlotSeries {
        makeSeries(
            identityKey: identityKey,
            sourceRef: sourceRef,
            sampleID: sampleID,
            label: "\(Int(temperatureK)) K",
            y: [meanY - 1.0, meanY, meanY + 1.0]
        )
    }

    private func identityOrder(_ series: [WorkbenchPlotSeries]) -> [String] {
        WorkbenchSeriesOrderKeyResolver.resolveIdentities(for: series).map(\.identityKey)
    }

    private func meanYDescendingOrder(_ series: [WorkbenchPlotSeries]) -> [String] {
        series.enumerated()
            .map { index, series in
                (
                    identity: WorkbenchSeriesOrderKeyResolver.resolve(for: series, originalIndex: index),
                    mean: series.y.reduce(0.0, +) / Double(series.y.count)
                )
            }
            .sorted { $0.mean > $1.mean }
            .map(\.identity)
    }

    @Test(".none consumes full identity keys")
    func noneConsumesFullIdentityKeys() {
        let series = [
            makeSeries(identityKey: "id-a", sourceRef: "/tmp/a.csv", sampleID: "sample-a", label: "A", y: [1, 2, 3]),
            makeSeries(identityKey: "id-b", sourceRef: "/tmp/b.csv", sampleID: "sample-b", label: "B", y: [4, 5, 6]),
            makeSeries(identityKey: "id-c", sourceRef: "/tmp/c.csv", sampleID: "sample-c", label: "C", y: [7, 8, 9])
        ]
        let order = ["id-c", "id-a", "id-b"]

        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: series,
                visualSeriesOrder: order,
                hiddenSeriesKeys: [],
                stackingPolicy: .none
            )
        )

        #expect(identityOrder(plan.visualSeries) == order)
        #expect(identityOrder(plan.displaySeries) == order)
        #expect(plan.warnings.isEmpty)
    }

    @Test(".none hidden filtering preserves order")
    func noneHiddenFilteringPreservesOrder() {
        let series = [
            makeSeries(identityKey: "id-a", sourceRef: "/tmp/a.csv", sampleID: "sample-a", label: "A", y: [1, 2, 3]),
            makeSeries(identityKey: "id-b", sourceRef: "/tmp/b.csv", sampleID: "sample-b", label: "B", y: [4, 5, 6]),
            makeSeries(identityKey: "id-c", sourceRef: "/tmp/c.csv", sampleID: "sample-c", label: "C", y: [7, 8, 9])
        ]
        let order = ["id-a", "id-b", "id-c"]

        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: series,
                visualSeriesOrder: order,
                hiddenSeriesKeys: ["id-b"],
                stackingPolicy: .none
            )
        )

        #expect(identityOrder(plan.visualSeries) == order)
        #expect(identityOrder(plan.displaySeries) == ["id-a", "id-c"])
        #expect(plan.warnings.isEmpty)
    }

    @Test(".orderEnforcingVertical consumes full identity keys")
    func orderEnforcingVerticalConsumesFullIdentityKeys() {
        let series = [
            makeSeries(identityKey: "id-a", sourceRef: "/tmp/a.csv", sampleID: "sample-a", label: "A", y: [1, 2, 3]),
            makeSeries(identityKey: "id-b", sourceRef: "/tmp/b.csv", sampleID: "sample-b", label: "B", y: [4, 5, 6]),
            makeSeries(identityKey: "id-c", sourceRef: "/tmp/c.csv", sampleID: "sample-c", label: "C", y: [7, 8, 9])
        ]
        let order = ["id-c", "id-a", "id-b"]

        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: series,
                visualSeriesOrder: order,
                hiddenSeriesKeys: [],
                stackingPolicy: .orderEnforcingVertical(multiplier: 1.2, minGapFraction: 0.15)
            )
        )

        #expect(identityOrder(plan.visualSeries) == order)
        #expect(identityOrder(plan.displaySeries) == order)
        #expect(plan.warnings.isEmpty)
    }

    @Test(".orderEnforcingVertical preserves descending mean-y order when raw means conflict")
    func orderEnforcingVerticalPreservesMeanOrderWhenRawMeansConflict() {
        let temperatures: [Double] = [110, 90, 70, 50, 30, 10]
        let series = temperatures.map { temperatureK in
            makeStackedSeries(
                identityKey: "id-\(Int(temperatureK))",
                sourceRef: "/tmp/\(Int(temperatureK)).csv",
                sampleID: "sample-\(Int(temperatureK))",
                temperatureK: temperatureK,
                meanY: -temperatureK
            )
        }
        let order = temperatures.map { "id-\(Int($0))" }

        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: series,
                visualSeriesOrder: order,
                hiddenSeriesKeys: [],
                stackingPolicy: .orderEnforcingVertical(multiplier: 1.2, minGapFraction: 0.15)
            )
        )

        #expect(identityOrder(plan.visualSeries) == order)
        #expect(identityOrder(plan.displaySeries) == order)
        #expect(meanYDescendingOrder(plan.displaySeries) == order)
        #expect(plan.warnings.isEmpty)
    }

    @Test("all-hidden series return a warning and remain visible")
    func allHiddenSeriesReturnWarningAndRemainVisible() {
        let series = [
            makeSeries(identityKey: "id-a", sourceRef: "/tmp/a.csv", sampleID: "sample-a", label: "A", y: [1, 2, 3]),
            makeSeries(identityKey: "id-b", sourceRef: "/tmp/b.csv", sampleID: "sample-b", label: "B", y: [4, 5, 6]),
            makeSeries(identityKey: "id-c", sourceRef: "/tmp/c.csv", sampleID: "sample-c", label: "C", y: [7, 8, 9])
        ]
        let order = ["id-a", "id-b", "id-c"]

        let plan = SeriesVisualPlanner.plan(
            SeriesVisualPlanningInput(
                series: series,
                visualSeriesOrder: order,
                hiddenSeriesKeys: order,
                stackingPolicy: .orderEnforcingVertical(multiplier: 1.2, minGapFraction: 0.15)
            )
        )

        #expect(identityOrder(plan.visualSeries) == order)
        #expect(identityOrder(plan.displaySeries) == order)
        #expect(plan.warnings == ["series visibility ignored: all series were hidden"])
    }
}
