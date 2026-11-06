import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SpinLabApp

@Suite("Sample Plots Overview Service and Presentation Tests (P2)")
struct SamplePlotsOverviewTests {

    @MainActor
    @discardableResult
    static func waitUntil(timeout: TimeInterval = 3.0, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    final class IsolatedFixture {
        let rootURL: URL
        let fm = FileManager.default

        init() {
            let tempDir = fm.temporaryDirectory.appending(path: "spinlab-sample-plots-overview-\(UUID().uuidString)")
            try! fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            self.rootURL = tempDir
        }

        deinit {
            try? fm.removeItem(at: rootURL)
        }

        func createSample(
            sampleKey: String,
            results: WorkbenchResultsIndex? = nil,
            plotIndex: MeasurementPlotIndex? = nil,
            isCorruptIndex: Bool = false
        ) {
            let sampleDir = rootURL.appending(path: "samples/\(sampleKey)")
            let spinlabDir = sampleDir.appending(path: "_spinlab")
            let chartsDir = sampleDir.appending(path: "charts")
            try! fm.createDirectory(at: spinlabDir, withIntermediateDirectories: true)
            try! fm.createDirectory(at: chartsDir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if isCorruptIndex {
                let corruptData = "Not valid JSON {{{".data(using: .utf8)!
                try! corruptData.write(to: spinlabDir.appending(path: "results_index.json"))
            } else if let results {
                let data = try! encoder.encode(results)
                try! data.write(to: spinlabDir.appending(path: "results_index.json"))
            }

            if let plotIndex {
                let data = try! encoder.encode(plotIndex)
                try! data.write(to: spinlabDir.appending(path: "measurement_plot_index.json"))
            }
        }

        func createChartFiles(
            relImagePath: String,
            relManifestPath: String,
            createImage: Bool = true,
            createManifest: Bool = true,
            inputFiles: [String] = ["data.lvm"],
            lineColor: NSColor = .systemBlue
        ) {
            let imgURL = rootURL.appending(path: relImagePath)
            let manURL = rootURL.appending(path: relManifestPath)
            try? fm.createDirectory(at: imgURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.createDirectory(at: manURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if createImage {
                let pngData = Self.makeValidPNGData(width: 64, height: 64, lineColor: lineColor)
                try! pngData.write(to: imgURL)
            }
            if createManifest {
                let manifest = WorkbenchRunManifest(
                    manifestID: UUID().uuidString,
                    runID: UUID().uuidString,
                    workflowID: "3w",
                    inputFiles: inputFiles,
                    filters: [:],
                    axisMapping: WorkbenchAxisMapping(xField: "Field", yField: "Resistance"),
                    semanticParams: ["tabKey": "fieldSweep3omega"],
                    outputImagePath: relImagePath,
                    generatedAt: Date(),
                    appVersion: "5.11.0"
                )
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try! encoder.encode(manifest)
                try! data.write(to: manURL)
            }
        }

        static func makeValidPNGData(
            width: Int = 64,
            height: Int = 64,
            lineColor: NSColor = .systemBlue
        ) -> Data {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )!

            NSGraphicsContext.saveGraphicsState()
            if let context = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = context

                // Background
                NSColor.windowBackgroundColor.setFill()
                NSRect(x: 0, y: 0, width: width, height: height).fill()

                // Plot frame
                let frameRect = NSRect(x: 4, y: 4, width: width - 8, height: height - 8)
                NSColor.controlBackgroundColor.setFill()
                frameRect.fill()
                NSColor.separatorColor.setStroke()
                let framePath = NSBezierPath(rect: frameRect)
                framePath.lineWidth = 1
                framePath.stroke()

                // Plot curve
                lineColor.setStroke()
                let curve = NSBezierPath()
                curve.lineWidth = 1.5
                curve.move(to: NSPoint(x: 6, y: 8))
                for x in stride(from: 8.0, through: Double(width - 8), by: 4.0) {
                    let normX = (x - 6) / Double(max(width - 14, 1))
                    let y = 8.0 + sin(normX * .pi) * Double(height - 18)
                    curve.line(to: NSPoint(x: x, y: y))
                }
                curve.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()

            return rep.representation(using: .png, properties: [:])!
        }

        func takeFileContentSnapshot() -> [String: Data] {
            var contents: [String: Data] = [:]
            guard let files = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
                return contents
            }
            for case let url as URL in files {
                if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                    contents[url.path] = try! Data(contentsOf: url)
                }
            }
            return contents
        }
    }

    private func defaultDefinitions() -> [WorkflowDefinition] {
        [
            WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
            WorkflowDefinition(id: "RT", displayName: "RT", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: [])
        ]
    }

    // MARK: - Test Cases

    @Test("Case 0: 0 plots returns empty array and causes no crash or disk write")
    func testZeroPlots() {
        let fix = IsolatedFixture()
        fix.createSample(sampleKey: "S_EMPTY")
        let snapshotBefore = fix.takeFileContentSnapshot()

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_EMPTY")

        #expect(plots.isEmpty)
        #expect(fix.takeFileContentSnapshot() == snapshotBefore)
    }

    @Test("Performance record: cold vs hot loadPlots (measured, recorded; no complexity claim)")
    func testColdHotLoadPlotsTimings() {
        let fix = IsolatedFixture()
        let now = Date()
        let sampleCount = 30
        let refsPerSample = 40
        // Every sample owns 40 local charts and also references 20 shared multi-sample charts.
        var sharedRefs: [WorkbenchResultReference] = []
        for i in 0..<20 {
            sharedRefs.append(WorkbenchResultReference(
                chartIdentityKey: "shared_\(i)", chartImagePath: "multi-sample/charts/shared_\(i).png",
                manifestPath: "multi-sample/charts/shared_\(i).manifest.json", workflowID: "3w",
                generatedAt: now, tabKey: "fieldSweep3omega"))
        }
        for sIdx in 0..<sampleCount {
            let key = "S\(sIdx)"
            var refs: [WorkbenchResultReference] = []
            for i in 0..<refsPerSample {
                refs.append(WorkbenchResultReference(
                    chartIdentityKey: "\(key)_c\(i)", chartImagePath: "samples/\(key)/charts/c\(i).png",
                    manifestPath: "samples/\(key)/charts/c\(i).manifest.json", workflowID: "3w",
                    generatedAt: now.addingTimeInterval(Double(i)), tabKey: "fieldSweep3omega"))
            }
            refs += sharedRefs
            fix.createSample(sampleKey: key, results: WorkbenchResultsIndex(sampleKey: key, updatedAt: now, references: refs))
        }
        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        func ms(_ block: () -> Void) -> Double {
            let t0 = DispatchTime.now().uptimeNanoseconds
            block()
            return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        }
        SamplePlotsOverviewService.invalidateMultiSampleCache(for: fix.rootURL)
        var count = 0
        let cold = ms { count = service.loadPlots(for: "S0").count }
        let hotSame = (0..<20).map { _ in ms { _ = service.loadPlots(for: "S0") } }.sorted()
        let hotOther = (1..<sampleCount).map { i in ms { _ = service.loadPlots(for: "S\(i)") } }.sorted()
        print("PERF loadPlots items=\(count) samples=\(sampleCount) cold(first, builds shared index)=\(String(format: "%.2f", cold))ms hotSameSample median=\(String(format: "%.2f", hotSame[hotSame.count / 2]))ms hotOtherSamples median=\(String(format: "%.2f", hotOther[hotOther.count / 2]))ms max=\(String(format: "%.2f", hotOther.last!))ms")
        #expect(count == refsPerSample + 20)
    }

    @Test("Case 1: 1 plot is correctly parsed and classified")
    func testSinglePlot() {
        let fix = IsolatedFixture()
        let now = Date()
        let ref = WorkbenchResultReference(
            chartIdentityKey: "chart_1",
            chartImagePath: "samples/S1/charts/R3w_field_sweep.png",
            manifestPath: "samples/S1/charts/R3w_field_sweep.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        fix.createSample(
            sampleKey: "S1",
            results: WorkbenchResultsIndex(sampleKey: "S1", updatedAt: now, references: [ref]),
            plotIndex: MeasurementPlotIndex(sampleKey: "S1", updatedAt: now, entries: ["raw.lvm": ["chart_1"]])
        )
        fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S1")

        #expect(plots.count == 1)
        let plot = plots[0]
        #expect(plot.chartIdentityKey == "chart_1")
        #expect(plot.canonicalWorkflowID == "3w")
        #expect(plot.imageStatus == .available)
        #expect(plot.manifestStatus == .available)
        #expect(plot.hasMeasurementAssociation == true)
        #expect(plot.isMultiSample == false)
        #expect(plot.associatedSampleKeys == ["S1"])
    }

    @Test("Case 2: Multiple plots are ordered by canonical tab rank")
    func testMultiplePlotsTabRankOrdering() {
        let fix = IsolatedFixture()
        let now = Date()

        // Tab ranking in SpinLab: fieldSweep1omega -> fieldSweep3omega -> rahe -> hc -> rt -> scaling
        let refRT = WorkbenchResultReference(
            chartIdentityKey: "c_rt",
            chartImagePath: "samples/S_MULTI/charts/RT_curve.png",
            manifestPath: "samples/S_MULTI/charts/RT_curve.manifest.json",
            workflowID: "RT",
            generatedAt: now.addingTimeInterval(10),
            tabKey: "rtCurve"
        )
        let ref3w = WorkbenchResultReference(
            chartIdentityKey: "c_3w",
            chartImagePath: "samples/S_MULTI/charts/R3w_sweep.png",
            manifestPath: "samples/S_MULTI/charts/R3w_sweep.manifest.json",
            workflowID: "3w",
            generatedAt: now.addingTimeInterval(5),
            tabKey: "fieldSweep3omega"
        )
        let ref1w = WorkbenchResultReference(
            chartIdentityKey: "c_1w",
            chartImagePath: "samples/S_MULTI/charts/R1w_sweep.png",
            manifestPath: "samples/S_MULTI/charts/R1w_sweep.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep1omega"
        )

        // Insert in reverse order in results_index.json
        fix.createSample(
            sampleKey: "S_MULTI",
            results: WorkbenchResultsIndex(sampleKey: "S_MULTI", updatedAt: now, references: [refRT, ref3w, ref1w])
        )
        fix.createChartFiles(relImagePath: refRT.chartImagePath, relManifestPath: refRT.manifestPath)
        fix.createChartFiles(relImagePath: ref3w.chartImagePath, relManifestPath: ref3w.manifestPath)
        fix.createChartFiles(relImagePath: ref1w.chartImagePath, relManifestPath: ref1w.manifestPath)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_MULTI")

        #expect(plots.count == 3)
        // Tab rank order: 1w first, then 3w, then RT
        #expect(plots[0].chartIdentityKey == "c_1w")
        #expect(plots[1].chartIdentityKey == "c_3w")
        #expect(plots[2].chartIdentityKey == "c_rt")
    }

    @Test("Historical 7 unlinked charts are surfaced with hasMeasurementAssociation == false")
    func testHistoricalUnlinkedPlotsSurfaced() {
        let fix = IsolatedFixture()
        let now = Date()
        let refLinked = WorkbenchResultReference(
            chartIdentityKey: "c_linked",
            chartImagePath: "samples/S_UNLINKED/charts/linked.png",
            manifestPath: "samples/S_UNLINKED/charts/linked.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        let refUnlinked = WorkbenchResultReference(
            chartIdentityKey: "c_historical_unlinked",
            chartImagePath: "samples/S_UNLINKED/charts/unlinked.png",
            manifestPath: "samples/S_UNLINKED/charts/unlinked.manifest.json",
            workflowID: "3w",
            generatedAt: now.addingTimeInterval(1),
            tabKey: "fieldSweep3omega"
        )

        // Only c_linked is present in measurement_plot_index.json
        fix.createSample(
            sampleKey: "S_UNLINKED",
            results: WorkbenchResultsIndex(sampleKey: "S_UNLINKED", updatedAt: now, references: [refLinked, refUnlinked]),
            plotIndex: MeasurementPlotIndex(sampleKey: "S_UNLINKED", updatedAt: now, entries: ["data.lvm": ["c_linked"]])
        )
        fix.createChartFiles(relImagePath: refLinked.chartImagePath, relManifestPath: refLinked.manifestPath)
        fix.createChartFiles(relImagePath: refUnlinked.chartImagePath, relManifestPath: refUnlinked.manifestPath)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_UNLINKED")

        #expect(plots.count == 2)
        let unlinkedPlot = plots.first { $0.chartIdentityKey == "c_historical_unlinked" }
        #expect(unlinkedPlot != nil)
        #expect(unlinkedPlot?.hasMeasurementAssociation == false)
        #expect(unlinkedPlot?.imageStatus == .available)

        let linkedPlot = plots.first { $0.chartIdentityKey == "c_linked" }
        #expect(linkedPlot != nil)
        #expect(linkedPlot?.hasMeasurementAssociation == true)
    }

    @Test("Missing PNG files are classified as .missingFile while preserving manifest provenance")
    func testMissingPNGStatusAndProvenance() {
        let fix = IsolatedFixture()
        let now = Date()
        let refMissing = WorkbenchResultReference(
            chartIdentityKey: "c_missing_png",
            chartImagePath: "samples/S_MISSING/charts/missing.png",
            manifestPath: "samples/S_MISSING/charts/missing.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        fix.createSample(
            sampleKey: "S_MISSING",
            results: WorkbenchResultsIndex(sampleKey: "S_MISSING", updatedAt: now, references: [refMissing])
        )
        // Create manifest on disk, but DO NOT create image file
        fix.createChartFiles(
            relImagePath: refMissing.chartImagePath,
            relManifestPath: refMissing.manifestPath,
            createImage: false,
            createManifest: true
        )

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_MISSING")

        #expect(plots.count == 1)
        let plot = plots[0]
        #expect(plot.imageStatus == .missingFile)
        #expect(plot.manifestStatus == .available)
        #expect(plot.displayTitle.contains("missing"))
    }

    @Test("Nested sample keys with slashes (e.g. PN107/SRO2|o|STO|110) are resolved accurately")
    func testNestedSampleKeyWithSlash() {
        let fix = IsolatedFixture()
        let now = Date()
        let nestedKey = "PN107/SRO2|o|STO|110"
        let ref = WorkbenchResultReference(
            chartIdentityKey: "c_nested",
            chartImagePath: "samples/\(nestedKey)/charts/nested_chart.png",
            manifestPath: "samples/\(nestedKey)/charts/nested_chart.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        fix.createSample(
            sampleKey: nestedKey,
            results: WorkbenchResultsIndex(sampleKey: nestedKey, updatedAt: now, references: [ref])
        )
        fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: nestedKey)

        #expect(plots.count == 1)
        let plot = plots[0]
        #expect(plot.chartIdentityKey == "c_nested")
        #expect(plot.associatedSampleKeys == [nestedKey])
        #expect(plot.imageStatus == .available)
        #expect(plot.manifestStatus == .available)
    }

    @Test("Multi-sample charts referenced by multiple samples are flagged isMultiSample")
    func testMultiSampleComparisonChart() {
        let fix = IsolatedFixture()
        let now = Date()
        let refMulti = WorkbenchResultReference(
            chartIdentityKey: "c_comparison",
            chartImagePath: "_spinlab/multi-sample/charts/cross_sample_rt.png",
            manifestPath: "_spinlab/multi-sample/charts/cross_sample_rt.manifest.json",
            workflowID: "RT",
            generatedAt: now,
            tabKey: "rtCurve"
        )
        // Two samples reference the comparison chart
        fix.createSample(
            sampleKey: "S_COMP",
            results: WorkbenchResultsIndex(sampleKey: "S_COMP", updatedAt: now, references: [refMulti])
        )
        fix.createSample(
            sampleKey: "S_COMP2",
            results: WorkbenchResultsIndex(sampleKey: "S_COMP2", updatedAt: now, references: [refMulti])
        )
        fix.createChartFiles(relImagePath: refMulti.chartImagePath, relManifestPath: refMulti.manifestPath)

        SamplePlotsOverviewService.clearMultiSampleCache()
        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_COMP")

        #expect(plots.count == 1)
        let plot = plots[0]
        #expect(plot.chartIdentityKey == "c_comparison")
        #expect(plot.isMultiSample == true)
        #expect(plot.associatedSampleKeys.contains("S_COMP"))
        #expect(plot.associatedSampleKeys.contains("S_COMP2"))
        #expect(plot.imageStatus == .available)
    }

    @Test("P0 Semantic: Single sample chart located in shared multi-sample directory retains isMultiSample == false (PN90 historical IV)")
    func testP0SingleSampleSemanticsPreservedInSharedDirectory() {
        let fix = IsolatedFixture()
        let now = Date()
        let refSingleShared = WorkbenchResultReference(
            chartIdentityKey: "pn90_iv",
            chartImagePath: "_spinlab/multi-sample/charts/pn90_historical_iv.png",
            manifestPath: "_spinlab/multi-sample/charts/pn90_historical_iv.manifest.json",
            workflowID: "IV",
            generatedAt: now,
            tabKey: "ivCurve"
        )
        // Only PN90 references this chart, even though it physically resides in _spinlab/multi-sample/charts/
        fix.createSample(
            sampleKey: "PN90",
            results: WorkbenchResultsIndex(sampleKey: "PN90", updatedAt: now, references: [refSingleShared])
        )
        fix.createChartFiles(relImagePath: refSingleShared.chartImagePath, relManifestPath: refSingleShared.manifestPath)

        SamplePlotsOverviewService.clearMultiSampleCache()
        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "PN90")

        #expect(plots.count == 1)
        let plot = plots[0]
        #expect(plot.chartIdentityKey == "pn90_iv")
        #expect(plot.isMultiSample == false, "Single sample chart must NEVER be flagged multi-sample purely by directory path")
        #expect(plot.associatedSampleKeys == ["PN90"])
        #expect(plot.imageStatus == .available)
    }

    @Test("MultiSampleChartDirectoryCache lifecycle: hasIndex tracks indexing state and invalidate clears cache")
    func testMultiSampleCacheLifecycleAndInvalidation() {
        let fix = IsolatedFixture()
        let now = Date()
        let refMulti = WorkbenchResultReference(
            chartIdentityKey: "c_shared",
            chartImagePath: "_spinlab/multi-sample/charts/shared.png",
            manifestPath: "_spinlab/multi-sample/charts/shared.manifest.json",
            workflowID: "RT",
            generatedAt: now,
            tabKey: "rtCurve"
        )
        fix.createSample(sampleKey: "S_M1", results: WorkbenchResultsIndex(sampleKey: "S_M1", updatedAt: now, references: [refMulti]))
        fix.createSample(sampleKey: "S_M2", results: WorkbenchResultsIndex(sampleKey: "S_M2", updatedAt: now, references: [refMulti]))
        fix.createChartFiles(relImagePath: refMulti.chartImagePath, relManifestPath: refMulti.manifestPath)

        let isolatedCache = MultiSampleChartDirectoryCache()
        #expect(isolatedCache.hasIndex(for: fix.rootURL) == false)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions(), cache: isolatedCache)
        _ = service.loadPlots(for: "S_M1")
        #expect(isolatedCache.hasIndex(for: fix.rootURL) == true)

        // Querying second sample reuses cached index without re-indexing
        let plots2 = service.loadPlots(for: "S_M2")
        #expect(plots2.count == 1)
        #expect(plots2[0].isMultiSample == true)

        // Explicit invalidation clears cached root
        isolatedCache.invalidate(for: fix.rootURL)
        #expect(isolatedCache.hasIndex(for: fix.rootURL) == false)
    }

    @Test("Fail-soft behavior: corrupt results_index.json returns empty array without throwing")
    func testFailSoftOnCorruptedResultsIndex() {
        let fix = IsolatedFixture()
        fix.createSample(sampleKey: "S_CORRUPT", isCorruptIndex: true)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_CORRUPT")

        #expect(plots.isEmpty)
    }

    @Test("Preloaded results and plot index are utilized without disk re-read")
    func testPreloadedIndexesUsage() {
        let fix = IsolatedFixture()
        let now = Date()
        let ref = WorkbenchResultReference(
            chartIdentityKey: "c_preloaded",
            chartImagePath: "samples/S_PRE/charts/pre.png",
            manifestPath: "samples/S_PRE/charts/pre.manifest.json",
            workflowID: "ahe",
            generatedAt: now,
            tabKey: "rahe3omegaVsT"
        )
        fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)

        let preloadedResults = WorkbenchResultsIndex(sampleKey: "S_PRE", updatedAt: now, references: [ref])
        let preloadedPlot = MeasurementPlotIndex(sampleKey: "S_PRE", updatedAt: now, entries: ["m.lvm": ["c_preloaded"]])

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        // Even though results_index.json is NOT written to disk, preloaded index provides the references!
        let plots = service.loadPlots(
            for: "S_PRE",
            preloadedResults: preloadedResults,
            preloadedPlotIndex: preloadedPlot
        )

        #expect(plots.count == 1)
        #expect(plots[0].chartIdentityKey == "c_preloaded")
        #expect(plots[0].canonicalWorkflowID == "ahe")
        #expect(plots[0].hasMeasurementAssociation == true)
    }

    @Test("Zero mutation invariant: scanning never writes or alters any file")
    func testZeroMutationsDuringScan() {
        let fix = IsolatedFixture()
        let now = Date()
        let ref = WorkbenchResultReference(
            chartIdentityKey: "c_immut",
            chartImagePath: "samples/S_IMMUT/charts/test.png",
            manifestPath: "samples/S_IMMUT/charts/test.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        fix.createSample(
            sampleKey: "S_IMMUT",
            results: WorkbenchResultsIndex(sampleKey: "S_IMMUT", updatedAt: now, references: [ref])
        )
        fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)

        let snapshotBefore = fix.takeFileContentSnapshot()

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        _ = service.loadPlots(for: "S_IMMUT")

        let snapshotAfter = fix.takeFileContentSnapshot()
        #expect(snapshotBefore == snapshotAfter)
    }

    @Test("Deleting a chart reference refreshes the loaded plots list and removes the chart")
    func testDeletionRefreshesOverviewList() {
        let fix = IsolatedFixture()
        let now = Date()
        let ref1 = WorkbenchResultReference(
            chartIdentityKey: "c_keep",
            chartImagePath: "samples/S_DEL/charts/keep.png",
            manifestPath: "samples/S_DEL/charts/keep.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep1omega"
        )
        let ref2 = WorkbenchResultReference(
            chartIdentityKey: "c_delete",
            chartImagePath: "samples/S_DEL/charts/delete.png",
            manifestPath: "samples/S_DEL/charts/delete.manifest.json",
            workflowID: "3w",
            generatedAt: now.addingTimeInterval(10),
            tabKey: "fieldSweep3omega"
        )
        fix.createSample(
            sampleKey: "S_DEL",
            results: WorkbenchResultsIndex(sampleKey: "S_DEL", updatedAt: now, references: [ref1, ref2])
        )
        fix.createChartFiles(relImagePath: ref1.chartImagePath, relManifestPath: ref1.manifestPath)
        fix.createChartFiles(relImagePath: ref2.chartImagePath, relManifestPath: ref2.manifestPath)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())

        // Initial query: 2 plots
        let initialPlots = service.loadPlots(for: "S_DEL")
        #expect(initialPlots.count == 2)

        // Simulate deleting c_delete: update results_index.json to omit ref2
        fix.createSample(
            sampleKey: "S_DEL",
            results: WorkbenchResultsIndex(sampleKey: "S_DEL", updatedAt: now.addingTimeInterval(20), references: [ref1])
        )

        // Re-query: only 1 plot remains
        let refreshedPlots = service.loadPlots(for: "S_DEL")
        #expect(refreshedPlots.count == 1)
        #expect(refreshedPlots[0].chartIdentityKey == "c_keep")
        #expect(!refreshedPlots.contains(where: { $0.chartIdentityKey == "c_delete" }))
    }

    @Test("Adding or updating a chart reference immediately appears in query")
    func testUpdatingChartRefreshesOverviewList() {
        let fix = IsolatedFixture()
        let now = Date()
        let ref1 = WorkbenchResultReference(
            chartIdentityKey: "c_v1",
            chartImagePath: "samples/S_UPDATE/charts/chart_v1.png",
            manifestPath: "samples/S_UPDATE/charts/chart_v1.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        fix.createSample(
            sampleKey: "S_UPDATE",
            results: WorkbenchResultsIndex(sampleKey: "S_UPDATE", updatedAt: now, references: [ref1])
        )
        fix.createChartFiles(relImagePath: ref1.chartImagePath, relManifestPath: ref1.manifestPath)

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        #expect(service.loadPlots(for: "S_UPDATE").count == 1)

        // Simulate new chart saved
        let ref2 = WorkbenchResultReference(
            chartIdentityKey: "c_v2",
            chartImagePath: "samples/S_UPDATE/charts/chart_v2.png",
            manifestPath: "samples/S_UPDATE/charts/chart_v2.manifest.json",
            workflowID: "RT",
            generatedAt: now.addingTimeInterval(30),
            tabKey: "rtCurve"
        )
        fix.createSample(
            sampleKey: "S_UPDATE",
            results: WorkbenchResultsIndex(sampleKey: "S_UPDATE", updatedAt: now.addingTimeInterval(30), references: [ref1, ref2])
        )
        fix.createChartFiles(relImagePath: ref2.chartImagePath, relManifestPath: ref2.manifestPath)

        let updatedPlots = service.loadPlots(for: "S_UPDATE")
        #expect(updatedPlots.count == 2)
        #expect(updatedPlots.contains(where: { $0.chartIdentityKey == "c_v2" }))
    }

    @Test("Real Library reconciliation verification (opt-in read-only verification for P2)")
    @MainActor
    func testRealLibrarySamplePlotsReconciliationOptIn() {
        // Explicit opt-in only: default unit tests run ONLY isolated fixtures and must never depend on local developer/CI library state.
        guard let optIn = ProcessInfo.processInfo.environment["SPINLAB_VERIFY_REAL_LIBRARY_RECONCILIATION"],
              optIn == "1" || optIn.lowercased() == "true" else {
            return
        }

        let configuredPath = ProcessInfo.processInfo.environment["SPINLAB_LIBRARY_ROOT"]
            ?? LibrarySettingsStore().load().rootPath
        guard let path = configuredPath, !path.isEmpty else {
            Issue.record("Opt-in real Library verification requires a configured Library Root path via SPINLAB_LIBRARY_ROOT or saved settings.")
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            Issue.record("Opt-in real Library root does not exist on disk: \(path)")
            return
        }

        let libraryURL = URL(fileURLWithPath: path)
        let defs = defaultDefinitions()
        let service = SamplePlotsOverviewService(libraryRootURL: libraryURL, workflowDefinitions: defs)

        // 1. Verify real nested sample key: PN107/SRO2|o|STO|110
        let nestedKey = "PN107/SRO2|o|STO|110"
        let nestedPlots = service.loadPlots(for: nestedKey)
        #expect(nestedPlots.count == 1)
        #expect(nestedPlots[0].associatedSampleKeys == [nestedKey])

        // 2. Scan all samples in the real library and verify historical edge cases
        let galleryResult = WorkflowGalleryQueryService(libraryRootURL: libraryURL, workflowDefinitions: defs).execute()
        #expect(galleryResult.totalReferenceCount == 212)
        #expect(galleryResult.uniqueChartCount == 204)
        #expect(galleryResult.missingImageCount == 16)

        // 3. Verify that the 7 historical unlinked charts are all discovered via SamplePlotsOverviewService
        var totalSurfacedPlotsAcrossSamples = 0
        var unlinkedPlotsCount = 0
        let samplesDir = libraryURL.appending(path: "samples")
        if let enumerator = FileManager.default.enumerator(at: samplesDir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == "results_index.json" {
                    let spinlabDir = fileURL.deletingLastPathComponent()
                    let sampleDir = spinlabDir.deletingLastPathComponent()
                    let relativeKey = String(sampleDir.standardizedFileURL.path.dropFirst(samplesDir.standardizedFileURL.path.count + 1))
                    let plots = service.loadPlots(for: relativeKey)
                    totalSurfacedPlotsAcrossSamples += plots.count
                    unlinkedPlotsCount += plots.filter { !$0.hasMeasurementAssociation }.count
                }
            }
        }

        // All 212 references across 51 samples are surfaced
        #expect(totalSurfacedPlotsAcrossSamples == 212)
        // All 7 unlinked charts are surfaced with hasMeasurementAssociation == false
        #expect(unlinkedPlotsCount >= 7)

        // 4. Mount real nested sample in SamplePlotsOverviewSection and verify UI rendering
        let nestedSection = SamplePlotsOverviewSection(
            sampleKey: nestedKey,
            sampleDisplayName: nestedKey,
            libraryRootURL: libraryURL,
            workbenchResults: nil,
            measurementPlotIndex: nil,
            workflowDefinitions: defs,
            canDeleteChart: false,
            onDeleteChart: nil
        )
        let hostingView = NSHostingView(rootView: nestedSection)
        hostingView.frame = NSRect(x: 0, y: 0, width: 450, height: 300)
        hostingView.layoutSubtreeIfNeeded()
        #expect(hostingView.fittingSize.height > 100)
    }

    // MARK: - Runtime UI & Layout Acceptance (Geometries & Isolation)

    @Test("Runtime Acceptance: First plot preview is visible without vertical scrolling inside LibraryDetailView at common window sizes")
    @MainActor
    func testRuntimePreviewVisibleWithoutScrolling() throws {
        let fix = IsolatedFixture()
        let now = Date()
        let ref1 = WorkbenchResultReference(
            chartIdentityKey: "c_first_plot",
            chartImagePath: "samples/S_UI/charts/plot1.png",
            manifestPath: "samples/S_UI/charts/plot1.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep1omega"
        )
        let ref2 = WorkbenchResultReference(
            chartIdentityKey: "c_second_plot",
            chartImagePath: "samples/S_UI/charts/plot2.png",
            manifestPath: "samples/S_UI/charts/plot2.manifest.json",
            workflowID: "3w",
            generatedAt: now.addingTimeInterval(10),
            tabKey: "fieldSweep3omega"
        )
        let results = WorkbenchResultsIndex(sampleKey: "S_UI", updatedAt: now, references: [ref1, ref2])
        let plotIndex = MeasurementPlotIndex(sampleKey: "S_UI", updatedAt: now, entries: ["m.lvm": ["c_first_plot"]])
        fix.createSample(sampleKey: "S_UI", results: results, plotIndex: plotIndex)
        // Draw distinct vibrant red curve in plot1
        fix.createChartFiles(relImagePath: ref1.chartImagePath, relManifestPath: ref1.manifestPath, lineColor: .systemRed)
        fix.createChartFiles(relImagePath: ref2.chartImagePath, relManifestPath: ref2.manifestPath, lineColor: .systemBlue)

        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = fix.rootURL.path
        appState.library.workbenchResults = results
        appState.library.measurementPlotIndex = plotIndex

        let sample = LibrarySample(
            id: "S_UI",
            displayName: "PN-UI-Test",
            batchId: "B1",
            substrateRaw: "STO (001)",
            substrateDisplay: "SrTiO3 (001)",
            substrateTokens: ["STO"],
            substrateTags: ["clean"],
            metadata: ["Temperature": "300 K"],
            orderedMetadata: [LibraryMetadataItem(key: "Temperature", value: "300 K")],
            numericTags: ["temp_k": 300.0],
            numericDisplay: ["temp_k": "300.0 K"],
            sourceSheetName: "Batch_01",
            sourceRowNumber: 1,
            updatedAt: now
        )
        let group = LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])
        appState.library.libraryExistingGroups["B"] = [group]
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.librarySelectedSampleId = "S_UI"
        appState.library.libraryActiveSelectionSource = .drawer

        let state = LibraryWorkspaceState()
        appState.library.currentRoute = .sampleWorkspace(prefix: appState.library.librarySelectedPrefix ?? "", batchId: appState.library.librarySelectedBatchId ?? "")
        let detailView = LibrarySampleWorkspacePrimaryView(state: state).environment(appState)

        // Pre-warm thumbnail cache so synchronous rendering is guaranteed during UI tests
        let img1URL = fix.rootURL.appending(path: ref1.chartImagePath)
        let cacheKey1 = WorkflowThumbnailCache.cacheKey(rootURL: fix.rootURL, relativePath: ref1.chartImagePath, maxPixelSize: 480)
        _ = WorkflowThumbnailCache.shared.loadThumbnail(url: img1URL, key: cacheKey1, maxPixelSize: 480)

        let testSizes: [(name: String, width: CGFloat, height: CGFloat)] = [
            ("standard_1200x800", 600, 800),
            ("compact_1000x700", 500, 700),
            ("narrow_column_350", 350, 650)
        ]

        for size in testSizes {
            let hostingView = NSHostingView(rootView: detailView)
            hostingView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)

            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            hostingView.layoutSubtreeIfNeeded()
            for _ in 0..<5 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }

            // Verify the preview sits within un-scrolled viewport height (< size.height)
            let captureHeight = min(size.height, 550)
            guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: NSRect(x: 0, y: 0, width: size.width, height: captureHeight)) else {
                Issue.record("Failed to create bitmap rep for \(size.name)")
                window.orderOut(nil)
                continue
            }
            hostingView.cacheDisplay(in: NSRect(x: 0, y: 0, width: size.width, height: captureHeight), to: rep)
            window.orderOut(nil)

            // Look for red pixel color from the decoded thumbnail in the overview strip area
            var foundRedPlotPixel = false
            for y in 80..<min(Int(size.height), 520) {
                for x in 10..<min(Int(size.width) - 10, 220) {
                    if let color = rep.colorAt(x: x, y: y) {
                        if color.redComponent > 0.7 && color.greenComponent < 0.3 && color.blueComponent < 0.3 {
                            foundRedPlotPixel = true
                            break
                        }
                    }
                }
                if foundRedPlotPixel { break }
            }
            #expect(foundRedPlotPixel, "Vibrant red curve from decoded plot thumbnail must be rendered within un-scrolled viewport for \(size.name)")
        }
    }

    @Test("Runtime Acceptance: Missing PNG placeholder and Unlinked badges render correctly inside LibraryDetailView")
    @MainActor
    func testRuntimeMissingAndUnlinkedBadges() throws {
        let fix = IsolatedFixture()
        let now = Date()
        let refMissing = WorkbenchResultReference(
            chartIdentityKey: "c_missing",
            chartImagePath: "samples/S_EDGE/charts/missing.png",
            manifestPath: "samples/S_EDGE/charts/missing.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep1omega"
        )
        let refUnlinked = WorkbenchResultReference(
            chartIdentityKey: "c_unlinked",
            chartImagePath: "samples/S_EDGE/charts/unlinked.png",
            manifestPath: "samples/S_EDGE/charts/unlinked.manifest.json",
            workflowID: "RT",
            generatedAt: now.addingTimeInterval(10),
            tabKey: "rtCurve"
        )
        let results = WorkbenchResultsIndex(sampleKey: "S_EDGE", updatedAt: now, references: [refMissing, refUnlinked])
        fix.createSample(sampleKey: "S_EDGE", results: results)
        // Missing PNG: create manifest only
        fix.createChartFiles(relImagePath: refMissing.chartImagePath, relManifestPath: refMissing.manifestPath, createImage: false, createManifest: true)
        // Unlinked: create both image and manifest
        fix.createChartFiles(relImagePath: refUnlinked.chartImagePath, relManifestPath: refUnlinked.manifestPath, createImage: true, createManifest: true, lineColor: .systemIndigo)

        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = fix.rootURL.path
        appState.library.workbenchResults = results

        let sample = LibrarySample(
            id: "S_EDGE",
            displayName: "PN-Edge-Cases",
            batchId: "B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: ["STO"],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: now
        )
        let group = LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])
        appState.library.libraryExistingGroups["B"] = [group]
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.librarySelectedSampleId = "S_EDGE"
        appState.library.libraryActiveSelectionSource = .drawer

        let state = LibraryWorkspaceState()
        appState.library.currentRoute = .sampleWorkspace(prefix: appState.library.librarySelectedPrefix ?? "", batchId: appState.library.librarySelectedBatchId ?? "")
        let detailView = LibrarySampleWorkspacePrimaryView(state: state).environment(appState)

        let hostingView = NSHostingView(rootView: detailView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 600)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        #expect(Self.waitUntil(timeout: 3.0) { appState.library.plotsOverviewItems.count == 2 })

        // Verify loaded items in overview
        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_EDGE")
        #expect(plots.count == 2)
        #expect(plots[0].imageStatus == .missingFile)
        #expect(plots[1].hasMeasurementAssociation == false)

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: NSRect(x: 0, y: 0, width: 500, height: 400)) else {
            Issue.record("Failed to create bitmap rep")
            window.orderOut(nil)
            return
        }
        hostingView.cacheDisplay(in: NSRect(x: 0, y: 0, width: 500, height: 400), to: rep)
        window.orderOut(nil)
        #expect(rep.pixelsWide % 500 == 0, "bitmap width must be a whole backing-scale multiple of 500pt")

        // Verify the mounted LibraryDetailView's plots overview loaded items
        #expect(appState.library.plotsOverviewItems.count == 2)
        #expect(appState.library.plotsOverviewItems[0].imageStatus == .missingFile, "Missing PNG must be classified as .missingFile")
        #expect(appState.library.plotsOverviewItems[1].hasMeasurementAssociation == false, "Unlinked chart must have hasMeasurementAssociation == false")

        // Also verify orange pixels from the rendered badge and warning icon in the bitmap representation
        var foundOrangeBadgePixel = false
        // The Primary grid sits below the Batch/Sample header, so scan the whole bitmap.
        for y in 0..<Int(rep.pixelsHigh) {
            for x in 0..<rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y) {
                    if color.redComponent > 0.8 && color.greenComponent > 0.4 && color.greenComponent < 0.7 && color.blueComponent < 0.45 {
                        foundOrangeBadgePixel = true
                        break
                    }
                }
            }
            if foundOrangeBadgePixel { break }
        }
        #expect(foundOrangeBadgePixel, "Orange Unlinked badge must be rendered inside mounted LibraryDetailView")
    }

    @Test("End-to-End: Live chart update on disk and deletion via appState reflects in LibraryDetailView")
    @MainActor
    func testLiveChartUpdateAndDeletionInLibraryDetailView() throws {
        let fix = IsolatedFixture()
        let now = Date()
        let ref1 = WorkbenchResultReference(
            chartIdentityKey: "c1",
            chartImagePath: "samples/S_LIVE/charts/c1.png",
            manifestPath: "samples/S_LIVE/charts/c1.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep1omega"
        )
        let ref2 = WorkbenchResultReference(
            chartIdentityKey: "c2",
            chartImagePath: "samples/S_LIVE/charts/c2.png",
            manifestPath: "samples/S_LIVE/charts/c2.manifest.json",
            workflowID: "3w",
            generatedAt: now.addingTimeInterval(10),
            tabKey: "fieldSweep3omega"
        )
        let initialResults = WorkbenchResultsIndex(sampleKey: "S_LIVE", updatedAt: now, references: [ref1, ref2])
        fix.createSample(sampleKey: "S_LIVE", results: initialResults)
        fix.createChartFiles(relImagePath: ref1.chartImagePath, relManifestPath: ref1.manifestPath, lineColor: .systemBlue)
        fix.createChartFiles(relImagePath: ref2.chartImagePath, relManifestPath: ref2.manifestPath, lineColor: .systemTeal)

        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = fix.rootURL.path
        appState.library.workbenchResults = initialResults

        let sample = LibrarySample(
            id: "S_LIVE",
            displayName: "Live-Sample",
            batchId: "B1",
            substrateRaw: "STO",
            substrateDisplay: "STO",
            substrateTokens: ["STO"],
            substrateTags: [],
            metadata: [:],
            orderedMetadata: [],
            numericTags: [:],
            numericDisplay: [:],
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: now
        )
        let group = LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])
        appState.library.libraryExistingGroups["B"] = [group]
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.librarySelectedSampleId = "S_LIVE"
        appState.library.libraryActiveSelectionSource = .drawer

        let state = LibraryWorkspaceState()
        appState.library.currentRoute = .sampleWorkspace(prefix: appState.library.librarySelectedPrefix ?? "", batchId: appState.library.librarySelectedBatchId ?? "")
        let detailView = LibrarySampleWorkspacePrimaryView(state: state).environment(appState)
        let hostingView = NSHostingView(rootView: detailView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 700)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        // 1. Initial count in state & mounted UI is 2
        #expect(Self.waitUntil(timeout: 3.0) { appState.library.plotsOverviewItems.count == 2 }, "Mounted UI must initialize with 2 plots")
        #expect(appState.library.workbenchResults?.references.count == 2)
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "c1" })
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "c2" })

        // 2. Add chart c3 directly to disk in results_index.json (do NOT manually assign appState.library.workbenchResults)
        let ref3 = WorkbenchResultReference(
            chartIdentityKey: "c3",
            chartImagePath: "samples/S_LIVE/charts/c3.png",
            manifestPath: "samples/S_LIVE/charts/c3.manifest.json",
            workflowID: "RT",
            generatedAt: now.addingTimeInterval(30),
            tabKey: "rtCurve"
        )
        fix.createChartFiles(relImagePath: ref3.chartImagePath, relManifestPath: ref3.manifestPath, lineColor: .systemOrange)
        let updatedResults = WorkbenchResultsIndex(sampleKey: "S_LIVE", updatedAt: now.addingTimeInterval(30), references: [ref1, ref2, ref3])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let updatedData = try encoder.encode(updatedResults)
        let indexURL = fix.rootURL.appending(path: "samples/S_LIVE/_spinlab/results_index.json")
        try updatedData.write(to: indexURL)
        // Ensure disk modification timestamp advances past the initial write timestamp
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: indexURL.path)

        // Exercise the disk mod-date poller: wait for background poll cycle and pump RunLoop for mounted view
        #expect(Self.waitUntil(timeout: 4.0) { appState.library.plotsOverviewItems.count == 3 }, "Mounted UI must update to 3 plots via disk mod-date poller")
        hostingView.layoutSubtreeIfNeeded()

        // Verify the mounted LibraryDetailView reactively updated from disk poller
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "c3" }, "Chart c3 must appear in mounted UI after disk update")

        // 3. Delete chart c1 via appState
        appState.library.workbenchResults = updatedResults
        appState.library.deleteWorkbenchResult(ref1)
        #expect(Self.waitUntil(timeout: 3.0) {
            appState.library.plotsOverviewItems.count == 2 &&
            !appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "c1" }
        }, "Mounted UI must update to 2 plots after delete")
        hostingView.layoutSubtreeIfNeeded()

        #expect(appState.library.workbenchResults?.references.count == 2)
        #expect(appState.library.workbenchResults?.references.contains { $0.chartIdentityKey == "c1" } == false)
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "c2" })
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "c3" })

        window.orderOut(nil)
    }

    @Test("End-to-End: Sample switching updates LibraryDetailView plots overview reactively")
    @MainActor
    func testEndToEndSampleSwitchingInLibraryDetailView() throws {
        let fix = IsolatedFixture()
        let now = Date()

        // Sample A: 2 plots
        let refA1 = WorkbenchResultReference(chartIdentityKey: "cA1", chartImagePath: "samples/SA/charts/1.png", manifestPath: "samples/SA/charts/1.manifest.json", workflowID: "3w", generatedAt: now, tabKey: "fieldSweep1omega")
        let refA2 = WorkbenchResultReference(chartIdentityKey: "cA2", chartImagePath: "samples/SA/charts/2.png", manifestPath: "samples/SA/charts/2.manifest.json", workflowID: "3w", generatedAt: now, tabKey: "fieldSweep3omega")
        let resultsA = WorkbenchResultsIndex(sampleKey: "SA", updatedAt: now, references: [refA1, refA2])
        fix.createSample(sampleKey: "SA", results: resultsA)
        fix.createChartFiles(relImagePath: refA1.chartImagePath, relManifestPath: refA1.manifestPath, lineColor: .systemBlue)
        fix.createChartFiles(relImagePath: refA2.chartImagePath, relManifestPath: refA2.manifestPath, lineColor: .systemIndigo)

        // Sample B: 1 plot
        let refB1 = WorkbenchResultReference(chartIdentityKey: "cB1", chartImagePath: "samples/SB/charts/b.png", manifestPath: "samples/SB/charts/b.manifest.json", workflowID: "RT", generatedAt: now, tabKey: "rtCurve")
        let resultsB = WorkbenchResultsIndex(sampleKey: "SB", updatedAt: now, references: [refB1])
        fix.createSample(sampleKey: "SB", results: resultsB)
        fix.createChartFiles(relImagePath: refB1.chartImagePath, relManifestPath: refB1.manifestPath, lineColor: .systemGreen)

        // Sample C: 0 plots
        let resultsC = WorkbenchResultsIndex(sampleKey: "SC", updatedAt: now, references: [])
        fix.createSample(sampleKey: "SC", results: resultsC)

        let sampleA = LibrarySample(id: "SA", displayName: "Sample-A", batchId: "B1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: now)
        let sampleB = LibrarySample(id: "SB", displayName: "Sample-B", batchId: "B1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: now)
        let sampleC = LibrarySample(id: "SC", displayName: "Sample-C", batchId: "B1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: now)

        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = fix.rootURL.path
        let group = LibraryPreviewBatchGroup(batchId: "B1", samples: [sampleA, sampleB, sampleC])
        appState.library.libraryExistingGroups["B"] = [group]
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.libraryActiveSelectionSource = .drawer

        let state = LibraryWorkspaceState()
        appState.library.currentRoute = .sampleWorkspace(prefix: appState.library.librarySelectedPrefix ?? "", batchId: appState.library.librarySelectedBatchId ?? "")
        let detailView = LibrarySampleWorkspacePrimaryView(state: state).environment(appState)
        let hostingView = NSHostingView(rootView: detailView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 700)

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)

        // 1. Select SA -> 2 charts
        _ = appState.library.selectExistingDrawer(prefix: "B", batchId: "B1", sampleId: "SA")
        #expect(Self.waitUntil(timeout: 3.0) {
            state.selectedSample(appState)?.id == "SA" &&
            appState.library.plotsOverviewItems.count == 2
        }, "Mounted UI must show 2 plots for SA")
        hostingView.layoutSubtreeIfNeeded()
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "cA1" })
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "cA2" })

        // 2. Switch to SB -> 1 chart
        _ = appState.library.selectExistingDrawer(prefix: "B", batchId: "B1", sampleId: "SB")
        #expect(Self.waitUntil(timeout: 3.0) {
            state.selectedSample(appState)?.id == "SB" &&
            appState.library.plotsOverviewItems.count == 1
        }, "Mounted UI must show 1 plot for SB")
        hostingView.layoutSubtreeIfNeeded()
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "cB1" })
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "cA1" } == false)

        // 3. Switch to SC -> 0 charts (empty state)
        _ = appState.library.selectExistingDrawer(prefix: "B", batchId: "B1", sampleId: "SC")
        #expect(Self.waitUntil(timeout: 3.0) {
            state.selectedSample(appState)?.id == "SC" &&
            appState.library.plotsOverviewItems.isEmpty
        }, "Mounted UI must show 0 plots for SC (empty state)")
        hostingView.layoutSubtreeIfNeeded()

        // 4. Switch back to SA -> 2 charts restored
        _ = appState.library.selectExistingDrawer(prefix: "B", batchId: "B1", sampleId: "SA")
        #expect(Self.waitUntil(timeout: 3.0) {
            state.selectedSample(appState)?.id == "SA" &&
            appState.library.plotsOverviewItems.count == 2
        }, "Mounted UI must restore 2 plots for SA")
        hostingView.layoutSubtreeIfNeeded()
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "cA1" })
        #expect(appState.library.plotsOverviewItems.contains { $0.chartIdentityKey == "cA2" })

        window.orderOut(nil)
    }

    @Test("End-to-End: Multi-sample comparison chart resolves all participating samples with slashes in provenance inspector")
    @MainActor
    func testMultiSampleProvenanceInspectorResolvesAllSamples() throws {
        let fix = IsolatedFixture()
        let now = Date()

        // Nested sample key containing '/'
        let nestedKey = "PN107/SRO2|o|STO|110"
        let otherKey = "PN108"
        let compImg = "_spinlab/multi-sample/charts/comp_nested.png"
        let compManifest = "_spinlab/multi-sample/charts/comp_nested.manifest.json"
        fix.createChartFiles(
            relImagePath: compImg,
            relManifestPath: compManifest,
            inputFiles: ["samples/\(nestedKey)/data.lvm", "samples/\(otherKey)/data.lvm"]
        )

        let refComp = WorkbenchResultReference(
            chartIdentityKey: "comp_nested",
            chartImagePath: compImg,
            manifestPath: compManifest,
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )

        // Seed both nestedKey and otherKey results_index referencing the same multi-sample chart
        fix.createSample(sampleKey: nestedKey, results: WorkbenchResultsIndex(sampleKey: nestedKey, updatedAt: now, references: [refComp]))
        fix.createSample(sampleKey: otherKey, results: WorkbenchResultsIndex(sampleKey: otherKey, updatedAt: now, references: [refComp]))

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: nestedKey)
        #expect(plots.count == 1)

        let plot = plots[0]
        #expect(plot.isMultiSample == true)
        // Resolves BOTH samples accurately without corrupting nested slashes!
        #expect(plot.associatedSampleKeys.contains(nestedKey))
        #expect(plot.associatedSampleKeys.contains(otherKey))
        #expect(plot.associatedSampleKeys.count == 2)

        // Mount WorkflowGalleryDetailView with this item to verify UI rendering of multi-sample provenance
        let galleryState = WorkflowGalleryState()
        galleryState.configureForSample(items: [plot], libraryRootURL: fix.rootURL, preselectedItem: plot)
        let appState = SpinLabAppState()
        let detailView = WorkflowGalleryDetailView(galleryState: galleryState).environment(appState)
        let hostingView = NSHostingView(rootView: detailView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        hostingView.layoutSubtreeIfNeeded()
        #expect(hostingView.fittingSize.height > 100)
    }

    @Test("End-to-End: SamplePlotsGallerySheet automatically dismisses when user jumps to a different sample (drawer & browser)")
    @MainActor
    func testSamplePlotsGallerySheetDismissesOnSampleNavigation() throws {
        let appState = SpinLabAppState()
        appState.library.libraryActiveSelectionSource = .drawer
        appState.library.librarySelectedSampleId = "S1"

        var dismissed = false
        let item = WorkflowGalleryItem(
            chartIdentityKey: "c1",
            chartImagePath: "samples/S1/charts/1.png",
            manifestPath: "samples/S1/charts/1.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: "fieldSweep3omega",
            associatedSampleKeys: ["S1", "S2"],
            isMultiSample: true,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Plot 1"
        )

        let sheet = SamplePlotsGallerySheet(
            sampleKey: "S1",
            sampleDisplayName: "Sample 1",
            items: [item],
            initialSelectedItem: item,
            libraryRootURL: URL(fileURLWithPath: "/tmp"),
            canDeleteChart: false,
            onDeleteChart: nil,
            onDismiss: { dismissed = true }
        ).environment(appState)

        let hostingView = NSHostingView(rootView: sheet)
        hostingView.frame = NSRect(x: 0, y: 0, width: 880, height: 620)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 880, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        // 1. Drawer navigation: Switch to S2
        appState.library.librarySelectedSampleId = "S2"
        let dismissedOnDrawer = Self.waitUntil(timeout: 2.0) { dismissed }
        #expect(dismissedOnDrawer == true)
        window.orderOut(nil)

        // 2. Browser navigation: Test browser selection source dismiss
        dismissed = false
        appState.library.libraryActiveSelectionSource = .browser
        appState.library.libraryBrowserSelectedSampleId = "S1"

        let sheetBrowser = SamplePlotsGallerySheet(
            sampleKey: "S1",
            sampleDisplayName: "Sample 1",
            items: [item],
            initialSelectedItem: item,
            libraryRootURL: URL(fileURLWithPath: "/tmp"),
            canDeleteChart: false,
            onDeleteChart: nil,
            onDismiss: { dismissed = true }
        ).environment(appState)

        let hostingView2 = NSHostingView(rootView: sheetBrowser)
        hostingView2.frame = NSRect(x: 0, y: 0, width: 880, height: 620)
        let window2 = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 880, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window2.contentView = hostingView2
        window2.makeKeyAndOrderFront(nil)
        hostingView2.layoutSubtreeIfNeeded()

        // Switch browser selection to S2
        appState.library.libraryBrowserSelectedSampleId = "S2"
        let dismissedOnBrowser = Self.waitUntil(timeout: 2.0) { dismissed }
        #expect(dismissedOnBrowser == true)
        window2.orderOut(nil)
    }

    @Test("End-to-End: Dirty draft protection active in LibraryDetailView preserves editing without plot interference")
    @MainActor
    func testDirtyDraftProtectionNonInterference() throws {
        let fix = IsolatedFixture()
        let now = Date()

        let ref = WorkbenchResultReference(
            chartIdentityKey: "c1",
            chartImagePath: "samples/S_DRAFT/charts/c1.png",
            manifestPath: "samples/S_DRAFT/charts/c1.manifest.json",
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        let results = WorkbenchResultsIndex(sampleKey: "S_DRAFT", updatedAt: now, references: [ref])
        fix.createSample(sampleKey: "S_DRAFT", results: results)
        fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)

        let sample = LibrarySample(
            id: "S_DRAFT",
            displayName: "Draft-Sample",
            batchId: "B1",
            substrateRaw: "Initial Substrate",
            substrateDisplay: "Initial Substrate",
            substrateTokens: ["STO"],
            substrateTags: ["clean"],
            metadata: ["Key1": "Val1"],
            orderedMetadata: [LibraryMetadataItem(key: "Key1", value: "Val1")],
            numericTags: ["thickness_nm": 45.0],
            numericDisplay: ["thickness_nm": "45.0 nm"],
            sourceSheetName: nil,
            sourceRowNumber: nil,
            updatedAt: now
        )

        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = fix.rootURL.path
        appState.library.workbenchResults = results
        let group = LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])
        appState.library.libraryExistingGroups["B"] = [group]
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.librarySelectedSampleId = "S_DRAFT"
        appState.library.libraryActiveSelectionSource = .drawer

        // Create an uncommitted dirty draft with modifications
        var draft = appState.library.librarySampleEditService.makeDraft(from: sample)
        draft.substrateTagsText = "clean, tag2, tag3"
        appState.library.librarySampleEditDraft = draft

        #expect(appState.library.librarySampleEditDraft?.sampleId == "S_DRAFT")

        let state = LibraryWorkspaceState()
        appState.library.currentRoute = .sampleWorkspace(prefix: appState.library.librarySelectedPrefix ?? "", batchId: appState.library.librarySelectedBatchId ?? "")
        let detailView = LibrarySampleWorkspacePrimaryView(state: state).environment(appState)
        let hostingView = NSHostingView(rootView: detailView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        hostingView.layoutSubtreeIfNeeded()

        // Draft state is untouched and preserved
        #expect(appState.library.librarySampleEditDraft?.substrateTagsText == "clean, tag2, tag3")

        // The underlying sample's plots are still intact on disk
        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_DRAFT")
        #expect(plots.count == 1)
    }

    @Test("On-demand thumbnail loading: ImageIO downsamples at decode time and bounds memory")
    func testWorkflowThumbnailCacheBoundedDecode() throws {
        let fix = IsolatedFixture()
        let largeImageURL = fix.rootURL.appending(path: "large_test.png")
        // Create a large 600x600 bitmap
        let largeData = IsolatedFixture.makeValidPNGData(width: 600, height: 600)
        try largeData.write(to: largeImageURL)

        let cache = WorkflowThumbnailCache(countLimit: 10, totalCostLimit: 1024 * 1024)
        let key = WorkflowThumbnailCache.cacheKey(rootURL: fix.rootURL, relativePath: "large_test.png", maxPixelSize: 120)

        // Load thumbnail with maxPixelSize = 120
        let thumb = cache.loadThumbnail(url: largeImageURL, key: key, maxPixelSize: 120)
        let decoded = try #require(thumb)

        // Verifies that ImageIO downsampled during decode — image is bounded to maxPixelSize:
        #expect(decoded.size.width <= 120)
        #expect(decoded.size.height <= 120)

        // Cached object exists
        #expect(cache.cachedThumbnail(for: key) != nil)
    }

    @Test("WorkflowGalleryState configureForSample reactive updates on chart deletion")
    @MainActor
    func testWorkflowGalleryStateConfigureForSampleReactiveUpdate() throws {
        let state = WorkflowGalleryState()
        let item1 = WorkflowGalleryItem(
            chartIdentityKey: "c1",
            chartImagePath: "samples/S/charts/1.png",
            manifestPath: "samples/S/charts/1.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: "fieldSweep1omega",
            associatedSampleKeys: ["S"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Plot 1"
        )
        let item2 = WorkflowGalleryItem(
            chartIdentityKey: "c2",
            chartImagePath: "samples/S/charts/2.png",
            manifestPath: "samples/S/charts/2.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date().addingTimeInterval(10),
            tabKey: "fieldSweep3omega",
            associatedSampleKeys: ["S"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Plot 2"
        )

        let dummyRoot = URL(fileURLWithPath: "/tmp")
        // Configure with both items, preselect item2
        state.configureForSample(items: [item1, item2], libraryRootURL: dummyRoot, preselectedItem: item2)
        #expect(state.items.count == 2)
        #expect(state.selectedItem?.chartIdentityKey == "c2")

        // Simulate deletion of item2: sheet receives updated items [item1]
        state.configureForSample(items: [item1], libraryRootURL: dummyRoot, preselectedItem: nil)
        #expect(state.items.count == 1)
        #expect(state.items[0].chartIdentityKey == "c1")
        // Selection automatically resets away from deleted item
        #expect(state.selectedItem?.chartIdentityKey == "c1")
    }

    @Test("SamplePlotsGallerySheet: Deleting a chart with empty identity key preserves other empty-key charts")
    @MainActor
    func testGallerySheetDeletePreservesOtherEmptyKeyCharts() throws {
        let dummyRoot = URL(fileURLWithPath: "/tmp")

        // Two unlinked/legacy charts both with empty chartIdentityKey
        let unlinked1 = WorkflowGalleryItem(
            chartIdentityKey: "",
            chartImagePath: "samples/S/charts/unlinked1.png",
            manifestPath: "samples/S/charts/unlinked1.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: "tab1",
            associatedSampleKeys: ["S"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: false,
            displayTitle: "Unlinked 1"
        )
        let unlinked2 = WorkflowGalleryItem(
            chartIdentityKey: "",
            chartImagePath: "samples/S/charts/unlinked2.png",
            manifestPath: "samples/S/charts/unlinked2.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: "tab2",
            associatedSampleKeys: ["S"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: false,
            displayTitle: "Unlinked 2"
        )

        let galleryState = WorkflowGalleryState()
        galleryState.configureForSample(items: [unlinked1, unlinked2], libraryRootURL: dummyRoot, preselectedItem: unlinked1)
        #expect(galleryState.items.count == 2)

        // Simulate deleting unlinked1 using the sheet's filter logic
        let ref1 = WorkbenchResultReference(
            chartIdentityKey: "",
            chartImagePath: "samples/S/charts/unlinked1.png",
            manifestPath: "samples/S/charts/unlinked1.manifest.json",
            workflowID: "3w",
            generatedAt: Date(),
            tabKey: "tab1"
        )
        let updated = galleryState.items.filter { item in
            if !ref1.chartIdentityKey.isEmpty {
                return item.chartIdentityKey != ref1.chartIdentityKey
            } else {
                return item.chartImagePath != ref1.chartImagePath
            }
        }
        galleryState.configureForSample(items: updated, libraryRootURL: dummyRoot, preselectedItem: updated.first)

        // unlinked2 is preserved!
        #expect(galleryState.items.count == 1)
        #expect(galleryState.items[0].chartImagePath == "samples/S/charts/unlinked2.png")
    }

    @Test("Manifest Provenance: Production ISO8601 date encoding decodes successfully into inspector payload")
    @MainActor
    func testManifestProvenanceDecodesIso8601Date() async throws {
        let fix = IsolatedFixture()
        let now = Date()
        let relImage = "samples/S_ISO/charts/iso.png"
        let relManifest = "samples/S_ISO/charts/iso.manifest.json"

        fix.createChartFiles(relImagePath: relImage, relManifestPath: relManifest, createImage: true, createManifest: true)
        let ref = WorkbenchResultReference(
            chartIdentityKey: "c_iso",
            chartImagePath: relImage,
            manifestPath: relManifest,
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        fix.createSample(sampleKey: "S_ISO", results: WorkbenchResultsIndex(sampleKey: "S_ISO", updatedAt: now, references: [ref]))

        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let plots = service.loadPlots(for: "S_ISO")
        #expect(plots.count == 1)
        #expect(plots[0].manifestStatus == .available)

        let galleryState = WorkflowGalleryState()
        galleryState.configureForSample(items: plots, libraryRootURL: fix.rootURL, preselectedItem: plots.first)
        await galleryState.loadSelectedDetail(item: plots.first, libraryRootURL: fix.rootURL)
        #expect(galleryState.manifest != nil, "Manifest must decode without error")
        #expect(galleryState.manifestLoadingError == nil)
        #expect(galleryState.manifest?.appVersion == "5.11.0")
        #expect(galleryState.manifest?.workflowID == "3w")
    }

    @Test("State Lifecycle: plotsOverviewItems is cleared when entering edit mode or clearing selection")
    @MainActor
    func testPlotsOverviewItemsClearedOnDeselectAndEdit() throws {
        let fix = IsolatedFixture()
        let now = Date()
        let ref = WorkbenchResultReference(chartIdentityKey: "c1", chartImagePath: "samples/S_EDIT/charts/1.png", manifestPath: "samples/S_EDIT/charts/1.manifest.json", workflowID: "3w", generatedAt: now, tabKey: "fieldSweep3omega")
        fix.createSample(sampleKey: "S_EDIT", results: WorkbenchResultsIndex(sampleKey: "S_EDIT", updatedAt: now, references: [ref]))
        fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)

        let sample = LibrarySample(id: "S_EDIT", displayName: "Sample-Edit", batchId: "B1", substrateRaw: "", substrateDisplay: "", substrateTokens: [], substrateTags: [], metadata: [:], orderedMetadata: [], numericTags: [:], numericDisplay: [:], sourceSheetName: nil, sourceRowNumber: nil, updatedAt: now)
        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = fix.rootURL.path
        let group = LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])
        appState.library.libraryExistingGroups["B"] = [group]
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.libraryActiveSelectionSource = .drawer
        appState.library.librarySelectedSampleId = "S_EDIT"

        let state = LibraryWorkspaceState()
        appState.library.currentRoute = .sampleWorkspace(prefix: appState.library.librarySelectedPrefix ?? "", batchId: appState.library.librarySelectedBatchId ?? "")
        let detailView = LibrarySampleWorkspacePrimaryView(state: state).environment(appState)
        let hostingView = NSHostingView(rootView: detailView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()

        #expect(Self.waitUntil(timeout: 3.0) { appState.library.plotsOverviewItems.count == 1 })

        // 1. Enter edit mode -> the Primary grid stays browsable (PR 3); only deletion is disabled
        appState.library.librarySampleEditDraft = appState.library.librarySampleEditService.makeDraft(from: sample)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        #expect(appState.library.plotsOverviewItems.count == 1, "plots stay visible while the Detail pane is editing")

        // 2. Exit edit mode -> overview items must restore
        appState.library.librarySampleEditDraft = nil
        #expect(Self.waitUntil(timeout: 3.0) { appState.library.plotsOverviewItems.count == 1 }, "plotsOverviewItems must restore when exiting edit mode")

        // 3. Clear sample selection -> overview items must be cleared
        appState.library.librarySelectedSampleId = nil
        #expect(Self.waitUntil(timeout: 2.0) { appState.library.plotsOverviewItems.isEmpty }, "plotsOverviewItems must clear when selection is nil")

        window.orderOut(nil)
    }

    @Test("WorkflowGalleryState: configureForSample updates preselectedItem with refreshed item status")
    @MainActor
    func testConfigureForSampleUpdatesSelectedItemState() {
        let dummyRoot = URL(fileURLWithPath: "/tmp")
        let staleItem = WorkflowGalleryItem(
            chartIdentityKey: "c1",
            chartImagePath: "samples/S1/charts/1.png",
            manifestPath: "samples/S1/charts/1.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: "fieldSweep3omega",
            associatedSampleKeys: ["S1"],
            isMultiSample: false,
            imageStatus: .missingFile,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Plot 1"
        )
        let freshItem = WorkflowGalleryItem(
            chartIdentityKey: "c1",
            chartImagePath: "samples/S1/charts/1.png",
            manifestPath: "samples/S1/charts/1.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: "fieldSweep3omega",
            associatedSampleKeys: ["S1"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Plot 1"
        )

        let state = WorkflowGalleryState()
        // Re-configure with fresh items while passing old staleItem as preselectedItem
        state.configureForSample(items: [freshItem], libraryRootURL: dummyRoot, preselectedItem: staleItem)

        // Selected item must be updated to the fresh item reflecting .available status, not stale .missingFile
        #expect(state.selectedItem?.imageStatus == .available)
    }

    @MainActor
    private static func renderViewToPNG<V: View>(view: V, size: CGSize, targetURL: URL) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            window.orderOut(nil)
            return
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        window.orderOut(nil)

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? pngData.write(to: targetURL)
    }

    @Test("Opt-in evidence screenshot generation for P2 PR deliverable")
    @MainActor
    func testGenerateEvidenceScreenshotsOptIn() throws {
        guard ProcessInfo.processInfo.environment["SPINLAB_GENERATE_EVIDENCE_SCREENSHOTS"] == "1" else {
            return
        }

        let fix = IsolatedFixture()
        let manifest1 = "samples/S1/charts/field_sweep_3w.manifest.json"
        let img1 = "samples/S1/charts/field_sweep_3w.png"
        let manifest2 = "samples/S1/charts/field_sweep_1w.manifest.json"
        let img2 = "samples/S1/charts/field_sweep_1w.png"
        let manifestMissing = "samples/S1/charts/missing_plot.manifest.json"
        let imgMissing = "samples/S1/charts/missing_plot.png"

        fix.createChartFiles(relImagePath: img1, relManifestPath: manifest1, createImage: true, createManifest: true, lineColor: .systemBlue)
        fix.createChartFiles(relImagePath: img2, relManifestPath: manifest2, createImage: true, createManifest: true, lineColor: .systemIndigo)
        fix.createChartFiles(relImagePath: imgMissing, relManifestPath: manifestMissing, createImage: false, createManifest: true)

        let now = Date()
        let ref1 = WorkbenchResultReference(
            chartIdentityKey: "c1",
            chartImagePath: img1,
            manifestPath: manifest1,
            workflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep3omega"
        )
        let ref2 = WorkbenchResultReference(
            chartIdentityKey: "c2",
            chartImagePath: img2,
            manifestPath: manifest2,
            workflowID: "3w",
            generatedAt: now.addingTimeInterval(60),
            tabKey: "fieldSweep1omega"
        )
        let ref3 = WorkbenchResultReference(
            chartIdentityKey: "c3",
            chartImagePath: imgMissing,
            manifestPath: manifestMissing,
            workflowID: "3w",
            generatedAt: now.addingTimeInterval(120),
            tabKey: "temperatureSweep"
        )

        let results = WorkbenchResultsIndex(
            sampleKey: "S1",
            updatedAt: now,
            references: [ref1, ref2, ref3]
        )
        fix.createSample(sampleKey: "S1", results: results)

        let appState = SpinLabAppState()
        appState.library.librarySettings.rootPath = fix.rootURL.path
        appState.library.workbenchResults = results

        let sample = LibrarySample(
            id: "S1",
            displayName: "SRO_ThinFilm_001",
            batchId: "B1",
            substrateRaw: "STO (001)",
            substrateDisplay: "SrTiO3 (001)",
            substrateTokens: ["STO"],
            substrateTags: ["clean"],
            metadata: ["Growth Temperature": "750 °C", "Oxygen Pressure": "100 mTorr"],
            orderedMetadata: [
                LibraryMetadataItem(key: "Growth Temperature", value: "750 °C"),
                LibraryMetadataItem(key: "Oxygen Pressure", value: "100 mTorr")
            ],
            numericTags: ["thickness_nm": 42.5],
            numericDisplay: ["thickness_nm": "42.5 nm"],
            sourceSheetName: "SRO_Batch",
            sourceRowNumber: 2,
            updatedAt: Date()
        )

        let group = LibraryPreviewBatchGroup(batchId: "B1", samples: [sample])
        appState.library.libraryExistingGroups["B"] = [group]
        appState.library.librarySelectedPrefix = "B"
        appState.library.librarySelectedBatchId = "B1"
        appState.library.librarySelectedSampleId = "S1"
        appState.library.libraryActiveSelectionSource = .drawer

        let state = LibraryWorkspaceState()

        let evidenceDir: URL
        if let envPath = ProcessInfo.processInfo.environment["SPINLAB_EVIDENCE_OUTPUT_DIR"] {
            evidenceDir = URL(fileURLWithPath: envPath)
        } else {
            evidenceDir = fix.rootURL.appending(path: "evidence")
        }
        try? FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)

        // Real Library check: if real library root is configured, render real sample PN107/SRO2|o|STO|110
        let realLibPath = ProcessInfo.processInfo.environment["SPINLAB_LIBRARY_ROOT"]
            ?? LibrarySettingsStore().load().rootPath
        if let realPath = realLibPath, FileManager.default.fileExists(atPath: realPath) {
            let libraryURL = URL(fileURLWithPath: realPath)
            let nestedKey = "PN107/SRO2|o|STO|110"
            let realSample = LibrarySample(
                id: nestedKey,
                displayName: nestedKey,
                batchId: "PN107",
                substrateRaw: "STO (110)",
                substrateDisplay: "SrTiO3 (110)",
                substrateTokens: ["STO"],
                substrateTags: ["clean"],
                metadata: ["Substrate": "STO (110)"],
                orderedMetadata: [LibraryMetadataItem(key: "Substrate", value: "STO (110)")],
                numericTags: [:],
                numericDisplay: [:],
                sourceSheetName: nil,
                sourceRowNumber: nil,
                updatedAt: Date()
            )
            let realGroup = LibraryPreviewBatchGroup(batchId: "PN107", samples: [realSample])
            let realAppState = SpinLabAppState()
            realAppState.library.librarySettings.rootPath = libraryURL.path
            realAppState.library.libraryExistingGroups["P"] = [realGroup]
            realAppState.library.librarySelectedPrefix = "P"
            realAppState.library.librarySelectedBatchId = "PN107"
            realAppState.library.librarySelectedSampleId = nestedKey
            realAppState.library.libraryActiveSelectionSource = .drawer

            let realState = LibraryWorkspaceState()
            realAppState.library.currentRoute = .sampleWorkspace(prefix: realAppState.library.librarySelectedPrefix ?? "", batchId: realAppState.library.librarySelectedBatchId ?? "")
            let realDetail = LibrarySampleWorkspacePrimaryView(state: realState).environment(realAppState)
            Self.renderViewToPNG(view: realDetail, size: CGSize(width: 650, height: 750), targetURL: evidenceDir.appending(path: "p2_01_detail_view_plots_overview.png"))
            Self.renderViewToPNG(view: realDetail, size: CGSize(width: 340, height: 600), targetURL: evidenceDir.appending(path: "p2_03_narrow_column_responsive.png"))
        } else {
            appState.library.currentRoute = .sampleWorkspace(prefix: appState.library.librarySelectedPrefix ?? "", batchId: appState.library.librarySelectedBatchId ?? "")
            let detailView = LibrarySampleWorkspacePrimaryView(state: state).environment(appState)
            Self.renderViewToPNG(view: detailView, size: CGSize(width: 650, height: 750), targetURL: evidenceDir.appending(path: "p2_01_detail_view_plots_overview.png"))
            Self.renderViewToPNG(view: detailView, size: CGSize(width: 340, height: 600), targetURL: evidenceDir.appending(path: "p2_03_narrow_column_responsive.png"))
        }

        // 2. p2_02_view_all_gallery_sheet.png
        let service = SamplePlotsOverviewService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let items = service.loadPlots(for: "S1")
        let sheetView = SamplePlotsGallerySheet(
            sampleKey: "S1",
            sampleDisplayName: "SRO_ThinFilm_001",
            items: items,
            initialSelectedItem: items.first,
            libraryRootURL: fix.rootURL,
            canDeleteChart: true,
            onDeleteChart: nil,
            onDismiss: {}
        ).environment(appState)
        Self.renderViewToPNG(view: sheetView, size: CGSize(width: 900, height: 600), targetURL: evidenceDir.appending(path: "p2_02_view_all_gallery_sheet.png"))

        // 4. p2_04_missing_png_placeholder.png
        if let missingItem = items.first(where: { $0.imageStatus == .missingFile }) {
            let card = WorkflowGalleryThumbnailCard(
                item: missingItem,
                isSelected: false,
                libraryRootURL: fix.rootURL,
                onSelect: {},
                onDoubleClick: {}
            ).frame(width: 200, height: 220).padding(20)
            Self.renderViewToPNG(view: card, size: CGSize(width: 240, height: 260), targetURL: evidenceDir.appending(path: "p2_04_missing_png_placeholder.png"))
        }

        // 5. p2_05_sample_editing_draft_protection.png
        let draft = appState.library.librarySampleEditService.makeDraft(from: sample)
        appState.library.librarySampleEditDraft = draft
        let editingDetailView = LibraryDetailView(state: state).environment(appState)
        Self.renderViewToPNG(view: editingDetailView, size: CGSize(width: 650, height: 750), targetURL: evidenceDir.appending(path: "p2_05_sample_editing_draft_protection.png"))
    }
}
