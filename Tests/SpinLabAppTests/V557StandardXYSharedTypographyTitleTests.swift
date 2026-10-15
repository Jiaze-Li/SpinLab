import Foundation
import SwiftUI
import Testing
@testable import SpinLabApp

/// v5.5.7 — Standard XY's Title checkbox now sits on the Draw row right after Grid
/// (superseding the earlier Font-row placement; Dual Axis still uses `CompactTypographyRow`), consuming the same
/// `showTitle` capability Dual Axis already threads into that row. Source-inspection
/// checks only — layout/behavior is otherwise unchanged (Grid stays on the Draw row,
/// `showTitle` remains caller-owned state, `.equatable()`/onChange semantics preserved).
@Suite("V5.5.7 Standard XY shared Typography + Title integration")
struct V557StandardXYSharedTypographyTitleTests {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpinLabAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private func loadSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

}
