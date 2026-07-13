import Foundation
import Testing
@testable import SpinLabApp

/// Gate B — consolidates two leaf UI primitives that were byte-for-byte (or
/// algorithmically) duplicated across the CartesianXY and Dual Axis control
/// modules, with identical behavior, no state-ownership change, no persistence
/// change, no renderer change, and no validation change:
///
///  1. Numeric input field with commit/dirty/focus/source-reset semantics —
///     `DualAxisCompressibleNumericField` (DualAxis-local) duplicated
///     `CompactNumericField` (Common) exactly except for its width strategy
///     (fixed vs. compressible min/ideal/max). `CompactNumericField` now
///     accepts an optional `flexibleWidth` to cover both, and the DualAxis
///     duplicate is deleted.
///  2. Weighted-row `Layout` — `DualAxisControlWeightedRowLayout` (DualAxis)
///     and the private `PlotControlWeightedRowLayout` backing
///     `SharedPlotTextControls` (Common) were algorithmically identical,
///     differing only in which `LayoutValueKey` type tagged the weight. Both
///     now delegate to a single generic `WeightedRowLayout<Key>` (Common).
///
/// Source-inspection checks only — layout weights/fields and numeric-field
/// widths are unchanged at every call site.
@Suite("Gate B — control primitive consolidation")
struct V557GateBControlPrimitiveConsolidationTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test("DualAxis's duplicate numeric field is gone; it now drives range fields through the shared CompactNumericField")
    func dualAxisNumericFieldConsolidated() throws {
        let dualAxisSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift"
        )
        #expect(!dualAxisSrc.contains("DualAxisCompressibleNumericField"),
                "the DualAxis-local numeric field duplicate must be fully removed")
        #expect(dualAxisSrc.contains("CompactNumericField(") && dualAxisSrc.contains("flexibleWidth:"),
                "DualAxis's range fields must use CompactNumericField's flexible-width mode")
    }

    @Test("CompactNumericField supports a flexible (min/ideal/max) width alongside its original fixed width, defaulting to unchanged behavior")
    func compactNumericFieldSupportsFlexibleWidth() throws {
        let src = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/CompactNumericField.swift"
        )
        #expect(src.contains("var width: CGFloat = 64"),
                "the original fixed-width parameter and default must be unchanged")
        #expect(src.contains("var flexibleWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat)? = nil"),
                "flexibleWidth must default to nil, so any existing caller of the fixed-width path is unaffected")
    }

    @Test("Both DualAxis and SharedPlotTextControls drive their weighted row through the shared generic WeightedRowLayout, not a local duplicate")
    func weightedRowLayoutConsolidated() throws {
        let dualAxisSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift"
        )
        let sharedTextSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SharedPlotTextControls.swift"
        )
        let weightedLayoutSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/WeightedRowLayout.swift"
        )

        #expect(!dualAxisSrc.contains("struct DualAxisControlWeightedRowLayout"),
                "DualAxis's local Layout duplicate must be removed")
        #expect(dualAxisSrc.contains("WeightedRowLayout<DualAxisControlWeightKey>(spacing: 12)"),
                "DualAxis must drive its label-override row through the shared generic layout")
        #expect(dualAxisSrc.contains("struct DualAxisControlWeightKey: LayoutValueKey"),
                "DualAxis keeps ownership of its own weight-key tag — only the algorithm moved to Common")

        #expect(!sharedTextSrc.contains("struct PlotControlWeightedRowLayout"),
                "SharedPlotTextControls's local Layout duplicate must be removed")
        #expect(sharedTextSrc.contains("WeightedRowLayout<PlotControlWeightKey>(spacing: 12)"),
                "SharedPlotTextControls must drive its Title/X/Y row through the shared generic layout")

        #expect(weightedLayoutSrc.contains("struct WeightedRowLayout<Key: LayoutValueKey>: Layout"),
                "the shared primitive must be generic over the caller-supplied weight key")
    }

    @Test("Weight values at each call site are unchanged by the consolidation")
    func weightValuesUnchanged() throws {
        let dualAxisSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift"
        )
        #expect(dualAxisSrc.contains(".dualAxisControlWeight(2.2)"))
        #expect(dualAxisSrc.contains(".dualAxisControlWeight(1.0)"))
        #expect(dualAxisSrc.contains(".dualAxisControlWeight(1.1)"))

        let sharedTextSrc = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/SharedPlotTextControls.swift"
        )
        #expect(sharedTextSrc.contains(".plotControlWeight(3)"))
        #expect(sharedTextSrc.contains(".plotControlWeight(1)"))
    }
}
