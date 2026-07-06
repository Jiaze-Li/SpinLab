import Testing
@testable import SpinLabApp

@Suite("v5.5.9 - RSM labels route through WorkbenchPlotDisplayVocabulary")
struct V559RSMVocabularyLabelMigrationTests {

    @Test("RSMView H/K/L axis labels match the vocabulary output")
    func rsmViewAxisLabelsMatchVocabulary() {
        let expectedH = WorkbenchPlotDisplayVocabulary.label(for: .reciprocalH, context: .plotAxis)
        let expectedK = WorkbenchPlotDisplayVocabulary.label(for: .reciprocalK, context: .plotAxis)
        let expectedL = WorkbenchPlotDisplayVocabulary.label(for: .reciprocalL, context: .plotAxis)

        #expect(RSMView.hl.xLabel == expectedH)
        #expect(RSMView.hl.yLabel == expectedL)
        #expect(RSMView.kl.xLabel == expectedK)
        #expect(RSMView.kl.yLabel == expectedL)
        #expect(RSMView.hk.xLabel == expectedH)
        #expect(RSMView.hk.yLabel == expectedK)
    }

    @Test("RSM default intensity label matches the vocabulary output")
    func rsmDefaultIntensityLabelMatchesVocabulary() {
        let expected = WorkbenchPlotDisplayVocabulary.label(for: .diffractionIntensity, context: .plotAxis)

        #expect(RSMWorkspaceStore.publicationZLabel(for: "Detector") == expected)
        #expect(RSMWorkspaceStore.publicationZLabel(for: "detector") == expected)
        #expect(RSMWorkspaceStore.publicationZLabel(for: "") == expected)
    }

    @Test("Non-standard raw column names still pass through unchanged (not forced into vocabulary)")
    func rsmCustomColumnNamesStillPassThrough() {
        #expect(RSMWorkspaceStore.publicationZLabel(for: "Intensity") == "Intensity")
        #expect(RSMWorkspaceStore.publicationZLabel(for: "κ (W/m·K)") == "κ (W/m·K)")
    }

    @Test("Parser's raw column identification is unaffected by display vocabulary routing")
    func rsmParserRawColumnNamesUnaffected() throws {
        let text = """
        H K L Intensity
        0.0 0.0 1.0 10.0
        """
        let dataset = try RSMDataParser.parse(text: text)
        #expect(dataset.detectorColumnName == "Intensity")
    }
}
