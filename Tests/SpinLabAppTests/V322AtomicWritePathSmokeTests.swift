import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.2.2 Atomic Write-Path Smoke")
struct V322AtomicWritePathSmokeTests {

    @Test("rendered PNG can be written atomically via AtomicFileWriter")
    func atomicWriteOfRenderedPNGSucceeds() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-v322-smoke-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Build a minimal 1-series payload
        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Smoke Test",
            axisMapping: WorkbenchAxisMapping(
                xField: "Magnetic Field (Oe)",
                yField: "Bridge 1 Resistance (Ohms)"
            ),
            series: [WorkbenchPlotSeries(
                label: "PN31|o|STO|111 | ch1 | 80K",
                x: [-10000.0, 0.0, 10000.0],
                y: [1.1, 1.0, 0.9]
            )]
        )

        // Render
        let pngData = try WorkbenchChartRenderer().renderPNG(payload: payload)
        #expect(!pngData.isEmpty)

        // Write atomically
        let destURL = tmpDir.appending(path: "smoke_ahe_plot.png")
        try AtomicFileWriter().write(pngData, to: destURL)

        // File must exist and match
        #expect(FileManager.default.fileExists(atPath: destURL.path))
        let written = try Data(contentsOf: destURL)
        #expect(written == pngData)
    }

    @Test("atomic write creates parent directories when they do not exist")
    func atomicWriteCreatesParentDirectories() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-v322-smoke-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        // Note: tmpDir itself is NOT created — AtomicFileWriter should create it

        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Dir Creation Test",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [0.0, 1.0], y: [0.0, 1.0])]
        )

        let pngData = try WorkbenchChartRenderer().renderPNG(payload: payload)
        let destURL = tmpDir.appending(path: "subdir/output.png")
        try AtomicFileWriter().write(pngData, to: destURL)

        #expect(FileManager.default.fileExists(atPath: destURL.path))
    }

    @Test("atomic overwrite replaces existing file")
    func atomicWriteOverwritesExistingFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-v322-smoke-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let destURL = tmpDir.appending(path: "overwrite.png")
        let initialData = Data("placeholder".utf8)
        try initialData.write(to: destURL)

        let payload = WorkbenchPlotPayload(
            workflowID: "AHE",
            workflowDisplayName: "AHE",
            title: "Overwrite",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [WorkbenchPlotSeries(label: "S", x: [0.0, 1.0], y: [0.0, 1.0])]
        )
        let pngData = try WorkbenchChartRenderer().renderPNG(payload: payload)
        try AtomicFileWriter().write(pngData, to: destURL)

        let written = try Data(contentsOf: destURL)
        #expect(written == pngData)
        #expect(written != initialData)
    }
}
