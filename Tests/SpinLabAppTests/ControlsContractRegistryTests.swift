import Foundation
import Testing
@testable import SpinLabApp

/// Registry-driven contract: members come from `WorkbenchWorkflowKind.allCases`, so a newly
/// added workflow is checked without editing a test list (spec CS-31, AC7).
@MainActor
@Suite("Controls Contract — registry")
struct ControlsContractRegistryTests {
    private static let grandfathered: Set<String> = ["ahe", "iv", "rt", "xyRotation", "threeOmega", "rsm", "afm"]

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func legacyKinds() throws -> Set<String> {
        let url = repoRoot().appendingPathComponent("scripts/controls_contract_legacy_allowlist.txt")
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return Set(text.split(separator: "\n").compactMap { line -> String? in
            let s = line.trimmingCharacters(in: .whitespaces)
            return s.hasPrefix("kind:") ? s.dropFirst(5).trimmingCharacters(in: .whitespaces) : nil
        })
    }

    @Test("Every workflow kind declares at least one valid Plot Mode")
    func everyKindDeclaresPlotMode() {
        #expect(!WorkbenchWorkflowKind.allCases.isEmpty)
        for kind in WorkbenchWorkflowKind.allCases {
            #expect(!kind.controlsPlotModes.isEmpty, "\(kind) must declare a Plot Mode")
            #expect(kind.controlsPlotModes.isSubset(of: Set(WorkbenchPlotMode.allCases)))
        }
    }

    @Test("Declared Plot Modes match the spec's workflow table")
    func plotModesMatchSpec() {
        #expect(WorkbenchWorkflowKind.ahe.controlsPlotModes == [.cartesianXY])
        #expect(WorkbenchWorkflowKind.iv.controlsPlotModes == [.cartesianXY])
        #expect(WorkbenchWorkflowKind.rt.controlsPlotModes == [.cartesianXY])
        #expect(WorkbenchWorkflowKind.xyRotation.controlsPlotModes == [.cartesianXY])
        #expect(WorkbenchWorkflowKind.threeOmega.controlsPlotModes == [.cartesianXY, .dualAxis])
        #expect(WorkbenchWorkflowKind.rsm.controlsPlotModes == [.heatmap])
        #expect(WorkbenchWorkflowKind.afm.controlsPlotModes == [.heatmap])
    }

    @Test("Only grandfathered kinds may use the legacy mount, and each must be allow-listed")
    func legacyMountIsBounded() throws {
        let allowed = try legacyKinds()
        #expect(allowed.isSubset(of: Self.grandfathered), "allow-list may only shrink")
        for kind in WorkbenchWorkflowKind.allCases where kind.controlsMount == .legacy {
            #expect(allowed.contains("\(kind)"), "\(kind) uses the legacy mount but is not allow-listed")
            #expect(Self.grandfathered.contains("\(kind)"), "\(kind) is new and must mount through the Surface")
        }
    }

    @Test("Every Plot Mode has a Surface section")
    func everyModeHasASection() {
        for mode in WorkbenchPlotMode.allCases {
            let adapter: WorkbenchControlsPlotAdapter
            switch mode {
            case .cartesianXY: adapter = .cartesianXY(ControlsSurfaceFixtures.cartesian())
            case .dualAxis: adapter = .dualAxis(ControlsSurfaceFixtures.dualAxis())
            case .heatmap: adapter = .heatmap(ControlsSurfaceFixtures.heatmap())
            }
            #expect(adapter.mode == mode)
        }
    }
}

@Suite("Controls Contract — AST guard on the real tree")
struct ControlsContractGuardTests {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("The AST guard accepts the real source tree")
    func guardAcceptsRealTree() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repoRoot().appendingPathComponent("scripts/check_controls_contract.sh").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "\(output)")
    }
}
