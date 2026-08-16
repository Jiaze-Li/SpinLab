import Foundation
import Testing
@testable import SpinLabApp

/// Regression guard for the Library Detail Metadata 1-column/2-column
/// breakpoint. Column count must be a pure function of available width
/// (`LibraryViewComputationService.twoColumnRequiredWidth`), never of
/// measured field content — a single long metadata value must not force a
/// collapse to 1 column when the pane otherwise has room for two.
@Suite("Library metadata column layout policy")
struct LibraryMetadataColumnLayoutPolicyTests {
    private let service = LibraryViewComputationService()

    private func pairRow(shortValue: String = "value", longValue: String? = nil) -> [DetailField] {
        [
            DetailField(label: "Label A", value: shortValue),
            DetailField(label: "Label B", value: longValue ?? shortValue)
        ]
    }

    @Test("below the semantic threshold collapses to 1 column")
    func belowThresholdCollapses() {
        let rows = [pairRow()]
        let width = LibraryViewComputationService.twoColumnRequiredWidth - 1
        #expect(service.sectionFirstColumnWidth(rows: rows, availableWidth: width) == nil)
    }

    @Test("at or above the semantic threshold uses 2 columns")
    func atThresholdUsesTwoColumns() {
        let rows = [pairRow()]
        let width = LibraryViewComputationService.twoColumnRequiredWidth
        #expect(service.sectionFirstColumnWidth(rows: rows, availableWidth: width) != nil)
    }

    @Test("a long metadata value no longer forces a premature 1-column collapse")
    func longValueDoesNotForceCollapse() {
        let longValue = String(repeating: "very long metadata value ", count: 12)
        let rows = [pairRow(longValue: longValue)]
        let width = LibraryViewComputationService.twoColumnRequiredWidth + 40
        #expect(service.sectionFirstColumnWidth(rows: rows, availableWidth: width) != nil)
    }

    @Test("returned column widths never fall below the minimum usable width")
    func columnWidthsRespectMinimum() {
        let longValue = String(repeating: "very long metadata value ", count: 12)
        let rows = [pairRow(longValue: longValue)]
        let width = LibraryViewComputationService.twoColumnRequiredWidth + 40
        let first = service.sectionFirstColumnWidth(rows: rows, availableWidth: width)
        #expect(first != nil)
        if let first {
            #expect(first >= LibraryViewComputationService.metadataColumnMinWidth)
            let second = width - first - LibraryViewComputationService.metadataColumnSpacing
            #expect(second >= LibraryViewComputationService.metadataColumnMinWidth)
        }
    }
}
