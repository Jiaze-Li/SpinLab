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

    @Test("PlotAxisBoundField supports a flexible (min/ideal/max) width alongside its original fixed width, defaulting to unchanged behavior")
    func plotAxisBoundFieldSupportsFlexibleWidth() throws {
        let src = try loadSource(
            "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/PlotAxisBoundField.swift"
        )
        #expect(src.contains("case fixed(CGFloat)"),
                "the original fixed-width strategy must still exist")
        #expect(src.contains("case flexible(min: CGFloat, ideal: CGFloat, max: CGFloat)"),
                "flexibleWidth must still be available as an explicit width policy case")
        #expect(src.contains("var width: PlotAxisBoundFieldWidth = .fixed(60)"),
                "fixed-width must remain the default, so any existing caller of the fixed-width path is unaffected")
    }

}
