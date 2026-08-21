import Foundation
import Testing
@testable import SpinLabApp

/// v5.5.2 UI standards pass: guards `RegistryGrowthImportSheet.swift` against
/// reintroducing forbidden typography/color tokens on readable text
/// (specs/04_UI_RULES.md — Font Readability, Readable Text Color, Font
/// Family Consistency). Scans source text rather than rendering SwiftUI,
/// since there is no snapshot framework in this project.
@Suite("V5.5.2 RegistryGrowthImportSheet typography compliance")
struct V552RegistryGrowthImportTypographyComplianceTests {
    private var sourceText: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/SpinLabAppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Sources/SpinLabApp/Features/Library/RegistryGrowthImportSheet.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    @Test("No forbidden sub-12pt font tokens")
    func noForbiddenFontTokens() {
        let text = sourceText
        #expect(!text.isEmpty)
        for token in [".caption", ".caption2", ".footnote", ".subheadline"] {
            #expect(!text.contains(token), "found forbidden font token \(token)")
        }
    }

    @Test("No monospaced font family override")
    func noMonospaced() {
        #expect(!sourceText.contains(".monospaced"))
    }

    @Test("No gray foreground on readable text (icon exemptions documented)")
    func noGrayForegroundOutsideExemptions() {
        let text = sourceText
        // The only permitted `.secondary`/`Color.secondary` uses are the two
        // decorative leading-indicator SF Symbol icons in `leadingIndicator`,
        // not user-readable text.
        let lines = text.components(separatedBy: "\n")
        let occurrences = lines.enumerated().filter { $0.element.contains(".secondary") }
        #expect(occurrences.count == 2, "expected exactly the two documented icon exemptions, found \(occurrences.count)")
        for (index, line) in occurrences {
            let context = (index > 0 ? lines[index - 1] : "") + line
            #expect(context.contains("Image") || context.contains("Color.accentColor"), "unexpected .secondary usage outside leadingIndicator icons: \(line)")
        }
        #expect(!text.contains("Color.gray"))
        #expect(!text.contains(".foregroundStyle(.gray)"))
    }

    // MARK: - Phase 5B UI info-design compliance (specs/04_UI_RULES.md — Human-Readable Information / Information Non-Redundancy)

    @Test("Does not render raw provenance internals (raw key / raw value)")
    func doesNotRenderRawProvenanceStrings() {
        let text = sourceText
        #expect(!text.contains("raw key:"))
        #expect(!text.contains("raw value:"))
    }

    @Test("Does not use a raw DisclosureGroup — CollapsibleSectionHeader is the only sanctioned collapsible")
    func doesNotUseRawDisclosureGroup() {
        #expect(!sourceText.contains("DisclosureGroup("))
    }

    @Test("Expected Sample renders through the human sample label projection, not the raw canonical key")
    func usesHumanSampleProjection() {
        let text = sourceText
        #expect(text.contains("RegistryGrowthImportPresentation.humanSampleLabel(for:"))
        #expect(!text.contains("Text(key)"))
    }
}
