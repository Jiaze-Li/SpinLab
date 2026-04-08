import Foundation
import Testing
@testable import SpinLabApp

@Suite("V4.1.11 RT Selection Restore")
struct V4111RTRestoreTests {

    private func writeSidecar(at path: String, workflow: String = "3w") {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sidecar = """
        {
          "version": 1,
          "workflow": "\(workflow)",
          "workflowDisplayName": "\(workflow)",
          "conditions": {"temperature": "5K"},
          "channels": [],
          "sourceFilePath": "/tmp/source.lvm",
          "appliedAt": "2026-04-08T00:00:00Z"
        }
        """
        try? sidecar.write(toFile: path, atomically: true, encoding: .utf8)
    }

    @Test("restore succeeds when sidecar and measurement file exist")
    func restoreSuccess() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "rt_restore_\(UUID().uuidString)")
        let measurementPath = tmp.appending(path: "test.lvm").path
        let sidecarPath = measurementPath + ".spinlab.json"

        // Create both files
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: measurementPath, contents: Data("data".utf8))
        writeSidecar(at: sidecarPath, workflow: "3w")

        let hit = ThreeOmegaWorkspaceStore.rebuildRTHit(fromSidecarPath: sidecarPath)
        #expect(hit != nil)
        #expect(hit?.measurementFilePath == measurementPath)
        #expect(hit?.workflowCanonicalID == "3w")
        #expect(hit?.conditions["temperature"] == "5K")

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test("restore fails silently when sidecar is missing")
    func restoreFailsMissingSidecar() {
        let hit = ThreeOmegaWorkspaceStore.rebuildRTHit(fromSidecarPath: "/nonexistent/path.spinlab.json")
        #expect(hit == nil)
    }

    @Test("restore fails silently when workflow does not match")
    func restoreFailsWrongWorkflow() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "rt_restore_wf_\(UUID().uuidString)")
        let measurementPath = tmp.appending(path: "test.lvm").path
        let sidecarPath = measurementPath + ".spinlab.json"

        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: measurementPath, contents: Data("data".utf8))
        writeSidecar(at: sidecarPath, workflow: "ahe")

        let hit = ThreeOmegaWorkspaceStore.rebuildRTHit(fromSidecarPath: sidecarPath)
        #expect(hit == nil)

        try? FileManager.default.removeItem(at: tmp)
    }

    @Test("restore fails silently when measurement file is missing")
    func restoreFailsMissingMeasurement() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "rt_restore_nofile_\(UUID().uuidString)")
        let measurementPath = tmp.appending(path: "test.lvm").path
        let sidecarPath = measurementPath + ".spinlab.json"

        // Only create sidecar, not measurement file
        writeSidecar(at: sidecarPath, workflow: "3w")

        let hit = ThreeOmegaWorkspaceStore.rebuildRTHit(fromSidecarPath: sidecarPath)
        #expect(hit == nil)

        try? FileManager.default.removeItem(at: tmp)
    }
}
