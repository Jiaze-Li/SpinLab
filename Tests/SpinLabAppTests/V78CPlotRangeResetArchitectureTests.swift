import Foundation
import Testing
@testable import SpinLabApp

/// Gate 7.8C — architecture regression guard for the shared plot-range reset
/// capability introduced alongside the AHE migration (see
/// V557PlotRangeResetTests.swift for the behavioral/wiring tests).
///
/// This suite exists to stop a future plot-controls change from quietly
/// reintroducing what the reset-ranges work deliberately removed:
///   - a second, independently-defined "reset all ranges" button living
///     somewhere other than the one shared `PlotRangeResetControl`;
///   - reset-all behavior creeping into the shared per-bound numeric leaf
///     (`PlotAxisBoundField`), which must stay ignorant of anything beyond
///     its own single bound;
///   - visibility gated by a workflow-name/type check instead of the
///     injected `onResetRanges: (() -> Void)?` capability.
///
/// Source-inspection only, consistent with this repo's existing V78C
/// architecture-boundary tests. Assertions target types/capabilities rather
/// than exact button copy or line numbers wherever a stable alternative exists.
@Suite("V7.8C Plot range reset — architecture guard")
struct V78CPlotRangeResetArchitectureTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func allProductionSwiftFiles() throws -> [String] {
        try FileManager.default
            .subpathsOfDirectory(atPath: repoRoot().appendingPathComponent("Sources/SpinLabApp").path)
            .filter { $0.hasSuffix(".swift") }
    }

    private let plotRangeResetControlPath =
        "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/PlotRangeResetControl.swift"
    private let workbenchPlotControlsPanelPath =
        "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/CartesianXY/WorkbenchPlotControlsPanel.swift"
    private let dualAxisPlotControlsPanelPath =
        "Sources/SpinLabApp/Workbench/Modules/PlotSystem/DualAxis/DualAxisPlotControlsPanel.swift"
    /// v5.5.7: the Cartesian-only `AxisBoundField` and Dual Axis-only
    /// `CompactNumericField` were unified into one shared leaf.
    private let sharedAxisBoundFieldPath =
        "Sources/SpinLabApp/Workbench/Modules/PlotSystem/Controls/Common/PlotAxisBoundField.swift"

    // MARK: 1. Exactly one production definition of PlotRangeResetControl

    @Test("PlotRangeResetControl has exactly one production struct definition")
    func exactlyOneDefinition() throws {
        let allFiles = try allProductionSwiftFiles()
        var definingFiles: [String] = []
        for relativePath in allFiles {
            let src = try loadSource("Sources/SpinLabApp/\(relativePath)")
            if src.contains("struct PlotRangeResetControl") {
                definingFiles.append(relativePath)
            }
        }
        #expect(definingFiles == ["Workbench/Modules/PlotSystem/Controls/Common/PlotRangeResetControl.swift"],
                "PlotRangeResetControl must be defined exactly once; found: \(definingFiles)")
    }

    // MARK: 2 & 3. Both panel families reference the shared component

    @Test("Cartesian XY's WorkbenchPlotControlsPanel references PlotRangeResetControl")
    func cartesianPanelReferencesSharedControl() throws {
        let src = try loadSource(workbenchPlotControlsPanelPath)
        #expect(src.contains("PlotRangeResetControl("),
                "Cartesian XY range controls must compose the shared reset component, not a local one")
    }

    @Test("DualAxisPlotControlsPanel references PlotRangeResetControl")
    func dualAxisPanelReferencesSharedControl() throws {
        let src = try loadSource(dualAxisPlotControlsPanelPath)
        #expect(src.contains("PlotRangeResetControl("),
                "Dual Axis controls must compose the shared reset component, not a local one")
    }

    // MARK: 4. No other production plot-control source builds its own reset-all UI

    @Test("No production source other than PlotRangeResetControl.swift defines a reset-all-ranges component")
    func noSecondResetComponent() throws {
        let allFiles = try allProductionSwiftFiles()
        // Structural signature of PlotRangeResetControl's own capability shape —
        // its *property declarations*, not the argument labels a caller uses to
        // construct it (both real call sites legitimately pass
        // `hasActiveOverride: ...` and `onReset: ...` as arguments, which must
        // not trip this check). A second file independently *declaring* this
        // property shape — under any type name — is exactly the regression
        // this test exists to catch, without pinning the check to the button's
        // exact user-facing copy.
        var filesWithResetCapabilityShape: [String] = []
        for relativePath in allFiles {
            guard relativePath != "Workbench/Modules/PlotSystem/Controls/Common/PlotRangeResetControl.swift" else { continue }
            let src = try loadSource("Sources/SpinLabApp/\(relativePath)")
            if src.contains("let hasActiveOverride: Bool") && src.contains("let onReset: () -> Void") {
                filesWithResetCapabilityShape.append(relativePath)
            }
        }
        #expect(filesWithResetCapabilityShape.isEmpty,
                "found a second reset-all-ranges component shape outside PlotRangeResetControl.swift: \(filesWithResetCapabilityShape)")
    }

    // MARK: 5. Per-bound numeric leaves stay ignorant of reset-all

    @Test("PlotAxisBoundField (shared Cartesian XY + Dual Axis per-bound leaf) does not reference PlotRangeResetControl or own reset-all behavior")
    func sharedLeafDoesNotOwnReset() throws {
        let src = try loadSource(sharedAxisBoundFieldPath)
        #expect(!src.contains("PlotRangeResetControl"),
                "the per-bound leaf must not know about the panel-level reset component")
        #expect(!src.contains("hasActiveOverride"),
                "the per-bound leaf must not carry the reset-all capability shape")
        #expect(!src.contains("resetAxisRangeOverride"),
                "the per-bound leaf must not call the atomic all-bounds reset directly")
        #expect(!src.contains("axisRangeOverride = nil"),
                "the per-bound leaf must not clear the whole override itself; only the panel-level reset does")
    }

    // MARK: 6. Visibility is capability-driven, never a workflow-name check

    @Test("Reset visibility is gated by the injected onResetRanges capability, not a workflow-name/type check")
    func visibilityIsCapabilityDrivenNotWorkflowNamed() throws {
        let cartesianSrc = try loadSource(workbenchPlotControlsPanelPath)
        #expect(cartesianSrc.contains("var onResetRanges: (() -> Void)? = nil"),
                "Cartesian XY must expose reset as a typed optional capability")
        #expect(cartesianSrc.contains("if let onResetRanges {"),
                "Cartesian XY must gate the shared control on capability presence, not a Bool flag")

        let dualAxisSrc = try loadSource(dualAxisPlotControlsPanelPath)
        #expect(dualAxisSrc.contains("var onResetRanges: (() -> Void)? = nil"),
                "Dual Axis must expose reset as the same typed optional capability")
        #expect(dualAxisSrc.contains("if let onResetRanges {"),
                "Dual Axis must gate the shared control on capability presence, not a Bool flag")

        // No workflow-identity branching anywhere near either panel's reset wiring.
        for (name, src) in [("Cartesian XY panel", cartesianSrc), ("Dual Axis panel", dualAxisSrc)] {
            #expect(!src.contains("workflowID ==") && !src.contains("workflowName =="),
                    "\(name) must not gate reset visibility by workflow identity")
            #expect(!src.contains("is AHEWorkspaceStore") && !src.contains("is RTWorkspaceStore")
                    && !src.contains("is IVWorkspaceStore") && !src.contains("is XYRotationWorkspaceStore")
                    && !src.contains("is ThreeOmegaWorkspaceStore"),
                    "\(name) must not gate reset visibility by workflow store type")
        }

        // The shared control itself must stay a pure capability/state view — no
        // workflow enum, store type, or identity string in its own signature.
        let controlSrc = try loadSource(plotRangeResetControlPath)
        #expect(!controlSrc.contains("Workspace") && !controlSrc.contains("workflowID"),
                "PlotRangeResetControl must stay workflow-agnostic")
    }
}
