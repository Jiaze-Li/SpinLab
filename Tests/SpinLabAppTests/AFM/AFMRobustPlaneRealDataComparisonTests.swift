import Foundation
import Testing
@testable import SpinLabApp

/// Characterization on the real IBW samples: Plane vs Robust Plane numbers, repeat-leveling
/// stability, and before/after PNGs written OUTSIDE the repository (printed path).
@Suite("AFM Robust Plane vs Plane: real-data comparison")
struct AFMRobustPlaneRealDataComparisonTests {

    static let outputDirectory: URL = {
        if let dir = ProcessInfo.processInfo.environment["SPINLAB_AFM_LEVELING_DIR"] { return URL(fileURLWithPath: dir) }
        return FileManager.default.temporaryDirectory.appendingPathComponent("spinlab-afm-leveling-characterization", isDirectory: true)
    }()

    @Test("Plane vs Robust Plane on each real IBW: numeric table, repeat-leveling stable, before/after PNGs", arguments: AFMRealDataAcceptanceTests.files)
    func compare(relative: String) throws {
        let url = URL(fileURLWithPath: "\(AFMRealDataAcceptanceTests.root)/\(relative)")
        #expect(FileManager.default.fileExists(atPath: url.path), "REQUIRED real sample missing: \(url.path)")
        let ds = try AFMInputAdapter.load(fileURL: url).dataset
        let channel = try #require(AFMChannelResolver.resolveDefaultChannel(in: ds.channels).channel)
        let xs = ds.xCoordinates, ys = ds.yCoordinates
        let name = url.deletingPathExtension().lastPathComponent

        let raw = AFMLevelingCharacterization.stats(channel.values, xs: xs, ys: ys)
        var table = "[real-data] \(name)\n"
        func f(_ v: Double) -> String { String(format: "%10.4f", v) }
        table += "    raw    : median \(f(raw.median)) max \(f(raw.max)) slopeX \(f(raw.slopeX)) slopeY \(f(raw.slopeY))\n"
        for (label, leveler) in [("Plane ", AFMLevelingCharacterization.plane), ("Robust", AFMLevelingCharacterization.robust)] {
            let once = leveler(channel.values, xs, ys)
            let twice = leveler(once, xs, ys)
            let s = AFMLevelingCharacterization.stats(once, xs: xs, ys: ys)
            let drift = zip(once.joined(), twice.joined()).map { abs($0 - $1) }.max() ?? 0
            table += "    \(label) : median \(f(s.median)) max \(f(s.max)) slopeX \(f(s.slopeX)) slopeY \(f(s.slopeY))  repeat-drift \(String(format: "%.2e", drift)) nm\n"
            #expect(once.joined().allSatisfy { $0.isFinite })
            #expect(drift < 1e-3, "\(label) repeat-leveling drift \(drift) nm on \(name)")
        }
        print(table, terminator: "")

        // Before / after PNGs (default AFM display state; same pipeline as the app).
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for (suffix, level) in [("before", AFMSurfaceLevel.off), ("plane", .plane), ("robust", .robustPlane)] {
            var config = AFMProcessingConfiguration(activeChannelID: channel.id)
            config.surfaceLevel = level
            let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: xs, yCoordinates: ys, configuration: config)
            let payload = try AFMHeatmapPayloadBuilder.build(dataset: ds, processed: processed, options: .init(workflowID: "afm"))
            let state = AFMWorkspaceStore.defaultDisplayState
            let out = try HeatmapRenderPipeline.render(.init(
                payload: payload, zDomainState: state.zDomainState,
                showColorbar: true, showTitle: true,
                colorbarTickStyleOverride: .zHeightTicks(unit: processed.canonicalUnit)
            ))
            let file = Self.outputDirectory.appendingPathComponent("\(name)-\(suffix).png")
            try out.imageData.write(to: file)
            #expect(out.imageData.count > 1_000)
        }
        print("[real-data] PNGs in \(Self.outputDirectory.path)")
    }
}
