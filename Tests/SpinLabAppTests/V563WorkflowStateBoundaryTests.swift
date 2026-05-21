import Foundation
import Testing
@testable import SpinLabApp

@Suite("Workflow State Boundaries")
struct V563WorkflowStateBoundaryTests {

    @MainActor
    @Test("TabRenderManager owns plot outputs; activeImageData is a projection")
    func tabRenderManagerActiveImageDataIsProjection() {
        enum TestTab: Hashable, Sendable { case first }

        let manager = TabRenderManager<TestTab>(defaultTab: .first)
        #expect(manager.activeImageData == nil)
        #expect(manager.activeLayout == nil)

        manager.setOutput(
            TabRenderOutput(
                imageData: Data([0x01, 0x02]),
                layout: nil,
                manifestPayload: nil
            ),
            for: .first
        )

        #expect(manager.activeImageData == Data([0x01, 0x02]))
        #expect(manager.output(for: .first).imageData == Data([0x01, 0x02]))

        manager.clearOutputs()
        #expect(manager.activeImageData == nil)
        #expect(manager.output(for: .first).imageData == nil)
    }

    @Test("Reorderable payloads use stable sampleID values")
    func reorderablePayloadUsesStableSampleID() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "test",
            workflowDisplayName: "test",
            title: "T",
            axisMapping: WorkbenchAxisMapping(xField: "x", yField: "y"),
            series: [
                WorkbenchPlotSeries(label: "A", x: [0, 1], y: [0, 1], sampleID: "sample-a"),
                WorkbenchPlotSeries(label: "B", x: [0, 1], y: [1, 2], sampleID: "sample-b")
            ],
            seriesReorderable: true
        )

        #expect(payload.series.allSatisfy { $0.sampleID != nil })

        var input = WorkbenchRenderPipeline.Input(payload: payload)
        input.seriesOrder = ["sample-a", "sample-b"]
        let output = try WorkbenchRenderPipeline.render(input)
        #expect(output.warnings.isEmpty)
    }

    @Test("LibraryRootAccess requires bookmark-backed discovery in sandboxed mode")
    func libraryRootAccessRequiresBookmarkForSandboxedDiscovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "spinlab-boundary-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let settings = LibrarySettings(
            rootPath: root.path,
            rootBookmarkData: nil,
            registryInternalPath: nil,
            registrySourcePath: nil,
            backupPath: nil,
            backupLastSyncedAt: nil,
            allowedBatchPrefixes: [],
            lastRefreshAt: nil
        )

        let status = LibraryRootAccess().resolveRootURL(settings: settings, sandboxed: true)
        #expect(status == .missingBookmark)
    }

    @MainActor
    @Test("Canvas-facing reads project canonical tab output")
    func canvasFacingReadsProjectCanonicalTabOutput() {
        let store = AHEWorkspaceStore()
        let adapterEmpty = WorkbenchReadAdapter(store: store)
        #expect(adapterEmpty.activeImageData == nil)

        store.tabs.setOutput(
            TabRenderOutput(
                imageData: Data([0xAA]),
                layout: nil,
                manifestPayload: nil
            ),
            for: .ahe
        )

        let adapter = WorkbenchReadAdapter(store: store)
        #expect(adapter.activeImageData == Data([0xAA]))
        #expect(store.tabs.activeImageData == Data([0xAA]))

        store.tabs.clearOutputs()
        let afterClear = WorkbenchReadAdapter(store: store)
        #expect(afterClear.activeImageData == nil)
    }
}

