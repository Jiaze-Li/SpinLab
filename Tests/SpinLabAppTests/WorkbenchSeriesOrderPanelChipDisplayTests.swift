import Testing
@testable import SpinLabApp

@Suite("WorkbenchSeriesOrderPanel chip display text")
struct WorkbenchSeriesOrderPanelChipDisplayTests {

    @Test("Converts math-markup labels into readable chip text")
    func convertsMathMarkupLabels() {
        #expect(WorkbenchSeriesOrderPanel.chipDisplayText(for: "math:H_{c}^{3ω}") == "Hc 3ω")
        #expect(WorkbenchSeriesOrderPanel.chipDisplayText(for: "math:R_{AHE}^{3ω}") == "RAHE 3ω")
        #expect(WorkbenchSeriesOrderPanel.chipDisplayText(for: "math:R^{3ω}") == "R 3ω")
    }

    @Test("Leaves plain labels unchanged")
    func leavesPlainLabelsUnchanged() {
        #expect(WorkbenchSeriesOrderPanel.chipDisplayText(for: "180deg") == "180deg")
        #expect(WorkbenchSeriesOrderPanel.chipDisplayText(for: "Series A") == "Series A")
    }
}
