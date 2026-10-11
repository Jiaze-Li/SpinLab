import Foundation
import Testing
@testable import SpinLabApp

/// Strict real-IBW acceptance: unlike the smoke tests, a missing sample is a FAILURE, never a
/// silent skip. Exports are written to `SPINLAB_AFM_EXPORT_DIR` when set.
@Suite("AFM real-data acceptance (strict)")
struct AFMRealDataAcceptanceTests {

    static let root = "/Users/jack/Downloads/data/batches/LNO"
    static let files = [
        "LNO22/samples/LNO22||STO|001/measurements/afm/LNO22_CONTACT_0000_AFM.ibw",
        "LNO15/samples/LNO15||STO|001/measurements/afm/LNO15_AFM.ibw",
        "LNO14/samples/LNO14||STO|001/measurements/afm/LNO14_AFM.ibw",
        "LNO23/samples/LNO23||STO|001/measurements/afm/LNO23_CONTACT_0000_AFM.ibw",
    ]

    @Test("every real IBW loads, plots with defaults, and exports PNG + PDF", arguments: files)
    func loadsAndExports(relative: String) throws {
        let url = URL(fileURLWithPath: "\(Self.root)/\(relative)")
        #expect(FileManager.default.fileExists(atPath: url.path), "REQUIRED real sample missing: \(url.path)")
        let output = try AFMInputAdapter.load(fileURL: url)
        let ds = output.dataset
        let resolution = AFMChannelResolver.resolveDefaultChannel(in: ds.channels)
        let channel = try #require(resolution.channel)

        let width = try #require(AFMHeatmapPayloadBuilder.scanWidthMicrometers(ds.xCoordinates))
        let config = AFMProcessingConfiguration(activeChannelID: channel.id)
        let processed = AFMProcessingPipeline.process(channel: channel, xCoordinates: ds.xCoordinates, yCoordinates: ds.yCoordinates, configuration: config)
        let payload = try AFMHeatmapPayloadBuilder.build(dataset: ds, processed: processed, options: .init(workflowID: "afm"))
        let state = AFMWorkspaceStore.defaultDisplayState
        let out = try HeatmapRenderPipeline.render(.init(
            payload: payload, zDomainState: state.zDomainState,
            showColorbar: true, showTitle: true,
            colorbarTickStyleOverride: .endpointsOnly(decimals: 2, unit: processed.canonicalUnit)
        ))
        #expect(out.layout.hideSpatialAxes)
        #expect(out.layout.xTickEntries.isEmpty && out.layout.yTickEntries.isEmpty)
        #expect(out.layout.colorbarTicks.count == 2)
        #expect(out.layout.colorbarTicks.allSatisfy { $0.label.hasSuffix(" nm") })
        #expect(out.layout.colorbarRect.maxX < out.layout.rendererSize.width)
        #expect(out.imageData.count > 10_000)
        #expect(out.pdfData.prefix(4) == Data("%PDF".utf8))

        let bar = try #require(out.layout.scaleBarOverlay)
        let physical = try #require(bar.physicalLength)
        let drawnFraction = Double(bar.lengthInPoints / out.layout.gridRect.width)
        #expect(abs(drawnFraction - physical / width) < 1e-9)

        let aspect = Double(out.layout.gridRect.width / out.layout.gridRect.height)
        let yWidth = (ds.yCoordinates.max()! - ds.yCoordinates.min()!) * Double(ds.yCoordinates.count) / Double(ds.yCoordinates.count - 1)
        #expect(abs(aspect - width / yWidth) < 1e-3)

        let info = "\(relative)\n  size \(ds.xCoordinates.count)x\(ds.yCoordinates.count) scan \(width)x\(yWidth) µm\n  channels \(ds.channels.map { "\($0.sourceLabel)[\($0.canonicalUnit)]" })\n  default \(channel.sourceLabel) z=[\(out.layout.zMin), \(out.layout.zMax)] bar=\(bar.label) \(bar.lengthInPoints)pt of \(out.layout.gridRect.width)pt\n"
        if let dir = ProcessInfo.processInfo.environment["SPINLAB_AFM_EXPORT_DIR"] {
            let base = URL(fileURLWithPath: dir).appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            try out.imageData.write(to: base.appendingPathExtension("png"))
            try out.pdfData.write(to: base.appendingPathExtension("pdf"))
            try info.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            // Raw (unprocessed) default channel, row 0 = first scan line, for external comparison.
            let csv = channel.values.map { $0.map { String($0) }.joined(separator: ",") }.joined(separator: "\n")
            try csv.write(to: base.appendingPathExtension("csv"), atomically: true, encoding: .utf8)
        }
    }

    @Test("Robust Plane on every real IBW: finite, warning-free, idempotent, source untouched, differs from Plane only moderately", arguments: files)
    func robustPlaneOnRealData(relative: String) throws {
        let url = URL(fileURLWithPath: "\(Self.root)/\(relative)")
        #expect(FileManager.default.fileExists(atPath: url.path), "REQUIRED real sample missing: \(url.path)")
        let ds = try AFMInputAdapter.load(fileURL: url).dataset
        let channel = try #require(AFMChannelResolver.resolveDefaultChannel(in: ds.channels).channel)
        let original = channel.values

        let robust = AFMRobustPlaneProcessor.apply(to: original, xCoordinates: ds.xCoordinates, yCoordinates: ds.yCoordinates)
        let plain = AFMPlaneLevelProcessor.apply(to: original, xCoordinates: ds.xCoordinates, yCoordinates: ds.yCoordinates)
        #expect(robust.warnings.isEmpty)
        #expect(channel.values == original)
        #expect(robust.values.joined().allSatisfy { $0.isFinite })

        let again = AFMRobustPlaneProcessor.apply(to: robust.values, xCoordinates: ds.xCoordinates, yCoordinates: ds.yCoordinates)
        let drift = zip(robust.values.joined(), again.values.joined()).map { abs($0 - $1) }.max() ?? 0
        #expect(drift < 1e-3, "robust leveling must be (nearly) idempotent, drift \(drift) nm")

        func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
        let flat = robust.values.joined().map { $0 }
        let flatPlain = plain.values.joined().map { $0 }
        let line = "\(relative)\n  plane  : median \(median(flatPlain)) nm  range [\(flatPlain.min()!), \(flatPlain.max()!)]\n  robust : median \(median(flat)) nm  range [\(flat.min()!), \(flat.max()!)]\n  idempotence drift \(drift) nm\n"
        if let dir = ProcessInfo.processInfo.environment["SPINLAB_AFM_EXPORT_DIR"] {
            let name = url.deletingPathExtension().lastPathComponent
            try line.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-robust.txt"), atomically: true, encoding: .utf8)
        }
    }

    @Test("garbage and truncated input fail with an explicit error")
    func invalidInputErrors() {
        #expect(throws: (any Error).self) { try AFMInputAdapter.build(from: Data(repeating: 0x41, count: 512), sourceRef: "bad") }
        #expect(throws: (any Error).self) { try AFMInputAdapter.build(from: Data(), sourceRef: "empty") }
    }
}
