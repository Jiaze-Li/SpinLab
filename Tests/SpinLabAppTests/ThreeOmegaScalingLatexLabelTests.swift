import Foundation
import Testing
@testable import SpinLabApp

@Suite("ThreeOmega scaling-law LaTeX labels")
struct ThreeOmegaScalingLatexLabelTests {

    private let expectedScalingXFormula = #"\sigma_{xx}^{2};(10^{7},\mathrm{S}^{2}/\mathrm{cm}^{2})"#
    private let expectedScalingYFormula = #"\frac{E_{\mathrm{AHE}}^{(3\omega)}}{E_{xx}^{3}\cdot\sigma_{xx}}\times10^{2};(\Omega\cdot\mu\mathrm{m}^{3}\cdot\mathrm{V}^{-2})"#

    @Test("Scaling-law X label preserves raw LaTeX commands exactly")
    func scalingLawXLabelPreservesCommands() {
        let fullLabel = ThreeOmegaPlotRenderer.scalingXAxisLabel
        #expect(LatexAxisLabelRenderer.isLatexLabel(fullLabel))

        let latex = LatexAxisLabelRenderer.extractLatex(fullLabel)
        #expect(latex == expectedScalingXFormula)
        #expect(latex.contains("\\sigma"))
        #expect(latex.contains("\\mathrm"))
        #expect(!latex.contains("\\;"))
        #expect(!latex.contains("σ"))
    }

    @Test("Scaling-law Y label preserves raw LaTeX commands exactly")
    func scalingLawYLabelPreservesCommands() {
        let fullLabel = ThreeOmegaPlotRenderer.scalingYAxisLabel
        #expect(LatexAxisLabelRenderer.isLatexLabel(fullLabel))

        let latex = LatexAxisLabelRenderer.extractLatex(fullLabel)
        #expect(latex == expectedScalingYFormula)
        #expect(latex.contains("\\frac"))
        #expect(latex.contains("\\mathrm"))
        #expect(latex.contains("\\cdot"))
        #expect(latex.contains("\\sigma"))
        #expect(latex.contains("\\Omega"))
        #expect(latex.contains("\\mu"))
        #expect(!latex.contains("ω"))
        #expect(!latex.contains("σ"))
        #expect(!latex.contains("Ω"))
        #expect(!latex.contains("μ"))
        #expect(!latex.contains("\u{000C}"))
        #expect(!latex.contains("\t"))
    }

    @Test("Scaling-law Y label compiles through LatexRenderService when backend is available")
    func scalingLawYLabelCompilesWithRealBackend() throws {
        let latex = LatexAxisLabelRenderer.extractLatex(ThreeOmegaPlotRenderer.scalingYAxisLabel)
        guard LatexRenderService.shared.isAvailable else { return }

        if let asset = LatexRenderService.shared.render(latex: latex) {
            #expect(asset.naturalSize.width > 0)
            #expect(asset.naturalSize.height > 0)
            return
        }

        let diagnostics = try compileFormulaWithLogs(latex: latex)
        print(diagnostics)
        #expect(Bool(false), "Exact scaling-law formula failed to compile with the real LaTeX backend.")
    }

    private func compileFormulaWithLogs(latex: String) throws -> String {
        let backend = LocalLatexBackend(status: LocalLatexBackend.detect())
        guard backend.isAvailable, let execPath = backend.status.executablePath else {
            return "Latex backend unavailable on this machine."
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpinLab_LatexDebug_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let texFile = tempDir.appendingPathComponent("formula.tex")
        let pdfFile = tempDir.appendingPathComponent("formula.pdf")
        let logFile = tempDir.appendingPathComponent("formula.log")
        let tex = backend.makeTexDocument(latex: latex, colorHex: "000000")
        try tex.write(to: texFile, atomically: true, encoding: .utf8)

        let args: [String]
        switch backend.status {
        case .latexmk:
            args = ["-pdf", "-interaction=nonstopmode", "-output-directory=\(tempDir.path)", texFile.path]
        case .pdflatex:
            args = ["-interaction=nonstopmode", "-output-directory=\(tempDir.path)", texFile.path]
        case .unavailable:
            return "Latex backend became unavailable while preparing diagnostics."
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: execPath)
        proc.arguments = args
        proc.currentDirectoryURL = tempDir

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        try proc.run()
        proc.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let logContents = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""

        if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: pdfFile.path) {
            return [
                "latex command: \(execPath) \(args.joined(separator: " "))",
                "stdout:\n\(stdout)",
                "stderr:\n\(stderr)",
                "formula.log:\n\(logContents)"
            ].joined(separator: "\n")
        }

        let tail = logContents
            .split(whereSeparator: \.isNewline)
            .filter {
                $0.contains("!") ||
                $0.localizedCaseInsensitiveContains("error") ||
                $0.localizedCaseInsensitiveContains("undefined") ||
                $0.localizedCaseInsensitiveContains("emergency stop")
            }
            .joined(separator: "\n")

        return [
            "latex command: \(execPath) \(args.joined(separator: " "))",
            "terminationStatus: \(proc.terminationStatus)",
            "stdout:\n\(stdout)",
            "stderr:\n\(stderr)",
            "formula.log tail:\n\(tail.isEmpty ? logContents : tail)"
        ].joined(separator: "\n")
    }
}
