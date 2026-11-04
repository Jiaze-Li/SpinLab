import Foundation
import Testing
@testable import SpinLabApp

@Suite("Workflow Gallery Query Tests")
struct WorkflowGalleryQueryTests {

    private final class TempFixture {
        let rootURL: URL
        let fm = FileManager.default

        init() {
            rootURL = fm.temporaryDirectory.appending(path: "WorkflowGalleryTest_\(UUID().uuidString)")
            try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
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
            inputFiles: [String] = ["file1.lvm"]
        ) {
            let imgURL = rootURL.appending(path: relImagePath)
            let manURL = rootURL.appending(path: relManifestPath)
            try? fm.createDirectory(at: imgURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.createDirectory(at: manURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if createImage {
                try! "PNGDATA".data(using: .utf8)!.write(to: imgURL)
            }
            if createManifest {
                let manifest = WorkbenchRunManifest(
                    manifestID: UUID().uuidString,
                    runID: UUID().uuidString,
                    workflowID: "3w",
                    inputFiles: inputFiles,
                    filters: [:],
                    axisMapping: WorkbenchAxisMapping(xField: "H", yField: "R"),
                    semanticParams: ["tabKey": "fieldSweep3omega"],
                    outputImagePath: relImagePath,
                    generatedAt: Date(),
                    appVersion: "1.0"
                )
                let data = try! JSONEncoder().encode(manifest)
                try! data.write(to: manURL)
            }
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

        func takeDirectorySnapshot() -> [String: (size: Int, modDate: Date)] {
            var snapshot: [String: (size: Int, modDate: Date)] = [:]
            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { return snapshot }

            for case let fileURL as URL in enumerator {
                if let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                   let mod = vals.contentModificationDate,
                   let size = vals.fileSize {
                    snapshot[fileURL.path] = (size, mod)
                }
            }
            return snapshot
        }
    }

    private func defaultDefinitions() -> [WorkflowDefinition] {
        [
            WorkflowDefinition(id: "3w", displayName: "3w", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: []),
            WorkflowDefinition(id: "RT", displayName: "RT", conditionFields: []),
            WorkflowDefinition(id: "XY", displayName: "XY Rotation", conditionFields: []),
            WorkflowDefinition(id: "IV", displayName: "IV", conditionFields: []),
            WorkflowDefinition(id: "afm", displayName: "AFM", conditionFields: []),
            WorkflowDefinition(id: "rsm", displayName: "RSM", conditionFields: []),
            WorkflowDefinition(id: "MR", displayName: "MR", conditionFields: [])
        ]
    }

    @Test("Cross-sample collection and multi-sample deduplication")
    func testCrossSampleCollectionAndDeduplication() {
        let fix = TempFixture()
        let now = Date()

        let chart1 = WorkbenchResultReference(
            chartIdentityKey: "chart_1",
            chartImagePath: "samples/S1/charts/R3w_1.png",
            manifestPath: "samples/S1/charts/R3w_1.manifest.json",
            workflowID: "3w",
            generatedAt: now
        )
        let chartShared = WorkbenchResultReference(
            chartIdentityKey: "chart_shared",
            chartImagePath: "_spinlab/multi-sample/charts/R3w_shared.png",
            manifestPath: "_spinlab/multi-sample/charts/R3w_shared.manifest.json",
            workflowID: "3w",
            generatedAt: now
        )
        let chart2 = WorkbenchResultReference(
            chartIdentityKey: "chart_2",
            chartImagePath: "samples/S2/charts/AHE_2.png",
            manifestPath: "samples/S2/charts/AHE_2.manifest.json",
            workflowID: "AHE",
            generatedAt: now
        )

        // S1 has chart1 and chartShared
        fix.createSample(
            sampleKey: "S1",
            results: WorkbenchResultsIndex(sampleKey: "S1", updatedAt: now, references: [chart1, chartShared]),
            plotIndex: MeasurementPlotIndex(sampleKey: "S1", updatedAt: now, entries: ["data1.dat": ["chart_1"]])
        )
        // S2 has chart2 and chartShared
        fix.createSample(
            sampleKey: "S2",
            results: WorkbenchResultsIndex(sampleKey: "S2", updatedAt: now, references: [chart2, chartShared]),
            plotIndex: MeasurementPlotIndex(sampleKey: "S2", updatedAt: now, entries: [:])
        )

        fix.createChartFiles(relImagePath: chart1.chartImagePath, relManifestPath: chart1.manifestPath)
        fix.createChartFiles(relImagePath: chartShared.chartImagePath, relManifestPath: chartShared.manifestPath)
        fix.createChartFiles(relImagePath: chart2.chartImagePath, relManifestPath: chart2.manifestPath)

        let service = WorkflowGalleryQueryService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions())
        let result = service.execute()

        #expect(result.totalReferenceCount == 4) // S1: 2, S2: 2
        #expect(result.uniqueChartCount == 3)   // chart1, chartShared, chart2
        #expect(result.items.count == 3)

        // Check shared chart deduplication
        let sharedItem = result.items.first { $0.chartIdentityKey == "chart_shared" }
        #expect(sharedItem != nil)
        #expect(sharedItem?.isMultiSample == true)
        #expect(sharedItem?.associatedSampleKeys == ["S1", "S2"])

        // Check single-sample chart
        let s1Item = result.items.first { $0.chartIdentityKey == "chart_1" }
        #expect(s1Item?.isMultiSample == false)
        #expect(s1Item?.associatedSampleKeys == ["S1"])
    }

    @Test("Workflow ID normalization and case-insensitive filtering with Rule Book definitions")
    func testWorkflowClassificationAndFiltering() {
        let fix = TempFixture()
        let now = Date()

        let ref3w = WorkbenchResultReference(
            chartIdentityKey: "c_3w",
            chartImagePath: "samples/S1/charts/3w.png",
            manifestPath: "samples/S1/charts/3w.manifest.json",
            workflowID: "3W", // uppercase variant
            generatedAt: now
        )
        let refAHE = WorkbenchResultReference(
            chartIdentityKey: "c_ahe",
            chartImagePath: "samples/S1/charts/ahe.png",
            manifestPath: "samples/S1/charts/ahe.manifest.json",
            workflowID: "AHE", // uppercase variant
            generatedAt: now
        )
        let refRT = WorkbenchResultReference(
            chartIdentityKey: "c_rt",
            chartImagePath: "samples/S1/charts/rt.png",
            manifestPath: "samples/S1/charts/rt.manifest.json",
            workflowID: "rt", // lowercase variant
            generatedAt: now
        )

        fix.createSample(
            sampleKey: "S1",
            results: WorkbenchResultsIndex(sampleKey: "S1", updatedAt: now, references: [ref3w, refAHE, refRT])
        )
        fix.createChartFiles(relImagePath: ref3w.chartImagePath, relManifestPath: ref3w.manifestPath)
        fix.createChartFiles(relImagePath: refAHE.chartImagePath, relManifestPath: refAHE.manifestPath)
        fix.createChartFiles(relImagePath: refRT.chartImagePath, relManifestPath: refRT.manifestPath)

        let defs = defaultDefinitions()
        let service = WorkflowGalleryQueryService(libraryRootURL: fix.rootURL, workflowDefinitions: defs)

        // Query all
        let allResult = service.execute()
        #expect(allResult.workflowCounts["3w"] == 1)
        #expect(allResult.workflowCounts["ahe"] == 1)
        #expect(allResult.workflowCounts["RT"] == 1)

        // Filter 3w
        let result3w = service.execute(workflowID: "3w")
        #expect(result3w.items.count == 1)
        #expect(result3w.items[0].chartIdentityKey == "c_3w")
        #expect(WorkflowClassifier.displayName(for: "3w", definitions: defs) == "3ω")

        // Filter AHE case-insensitively
        let resultAHE = service.execute(workflowID: "AHE")
        #expect(resultAHE.items.count == 1)
        #expect(resultAHE.items[0].chartIdentityKey == "c_ahe")
        #expect(WorkflowClassifier.displayName(for: "ahe", definitions: defs) == "AHE")
    }

    @Test("Deterministic Reconciliation Audit Invariants Fixture (Zero writes, exact edge cases)")
    func testDeterministicReconciliationAuditInvariants() {
        let fix = TempFixture()
        let now = Date()

        // 1. Model 3 truly cross-sample charts:
        // Chart A: across 6 samples (e.g. LNO RT)
        let chartLNO = WorkbenchResultReference(
            chartIdentityKey: "chart_lno_rt",
            chartImagePath: "_spinlab/multi-sample/charts/RT_lno.png",
            manifestPath: "_spinlab/multi-sample/charts/RT_lno.manifest.json",
            workflowID: "RT",
            generatedAt: now
        )
        // Chart B: across 3 samples (e.g. SRO XY)
        let chartSRO = WorkbenchResultReference(
            chartIdentityKey: "chart_sro_xy",
            chartImagePath: "_spinlab/multi-sample/charts/XY_sro.png",
            manifestPath: "_spinlab/multi-sample/charts/XY_sro.manifest.json",
            workflowID: "XY",
            generatedAt: now
        )
        // Chart C: across 2 samples (e.g. PN AHE)
        let chartPNAHE = WorkbenchResultReference(
            chartIdentityKey: "chart_pn_ahe",
            chartImagePath: "_spinlab/multi-sample/charts/AHE_pn.png",
            manifestPath: "_spinlab/multi-sample/charts/AHE_pn.manifest.json",
            workflowID: "AHE",
            generatedAt: now
        )

        // 2. Model 4 charts in multi-sample directory belonging to only 1 sample (e.g. PN90 IV)
        let chartPN90_1 = WorkbenchResultReference(
            chartIdentityKey: "chart_pn90_iv1",
            chartImagePath: "_spinlab/multi-sample/charts/IV_1.png",
            manifestPath: "_spinlab/multi-sample/charts/IV_1.manifest.json",
            workflowID: "IV",
            generatedAt: now
        )

        // 3. Model 14 missing PNG records (manifest exists, image missing)
        var missingPNGRefs: [WorkbenchResultReference] = []
        for i in 1...14 {
            let ref = WorkbenchResultReference(
                chartIdentityKey: "chart_missing_png_\(i)",
                chartImagePath: "samples/SampleMissing/charts/missing_\(i).png",
                manifestPath: "samples/SampleMissing/charts/missing_\(i).manifest.json",
                workflowID: "3w",
                generatedAt: now
            )
            missingPNGRefs.append(ref)
            // Create manifest only
            fix.createChartFiles(
                relImagePath: ref.chartImagePath,
                relManifestPath: ref.manifestPath,
                createImage: false,
                createManifest: true
            )
        }

        // 4. Model 7 unlinked measurement charts (in results_index but NOT in measurement_plot_index)
        var unlinkedRefs: [WorkbenchResultReference] = []
        for i in 1...7 {
            let ref = WorkbenchResultReference(
                chartIdentityKey: "chart_unlinked_\(i)",
                chartImagePath: "samples/SampleUnlinked/charts/unlinked_\(i).png",
                manifestPath: "samples/SampleUnlinked/charts/unlinked_\(i).manifest.json",
                workflowID: "3w",
                generatedAt: now
            )
            unlinkedRefs.append(ref)
            fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)
        }

        // 5. Model legacy semicolon-delimited inputFiles in manifest (v4.1.17)
        let legacyManifestPath = "samples/SampleLegacy/charts/legacy.manifest.json"
        let legacyImagePath = "samples/SampleLegacy/charts/legacy.png"
        let legacyRef = WorkbenchResultReference(
            chartIdentityKey: "chart_legacy_semicolon",
            chartImagePath: legacyImagePath,
            manifestPath: legacyManifestPath,
            workflowID: "3w",
            generatedAt: now
        )
        fix.createChartFiles(
            relImagePath: legacyImagePath,
            relManifestPath: legacyManifestPath,
            createImage: true,
            createManifest: true,
            inputFiles: ["/tmp/file1.lvm;/tmp/file2.lvm;/tmp/file3.lvm"]
        )

        // Setup sample directories
        // 6 samples for chartLNO
        for i in 1...6 {
            fix.createSample(
                sampleKey: "LNO_\(i)",
                results: WorkbenchResultsIndex(sampleKey: "LNO_\(i)", updatedAt: now, references: [chartLNO])
            )
        }
        fix.createChartFiles(relImagePath: chartLNO.chartImagePath, relManifestPath: chartLNO.manifestPath)

        // 3 samples for chartSRO
        for i in 1...3 {
            fix.createSample(
                sampleKey: "SRO_\(i)",
                results: WorkbenchResultsIndex(sampleKey: "SRO_\(i)", updatedAt: now, references: [chartSRO])
            )
        }
        fix.createChartFiles(relImagePath: chartSRO.chartImagePath, relManifestPath: chartSRO.manifestPath)

        // 2 samples for chartPNAHE
        for i in 1...2 {
            fix.createSample(
                sampleKey: "PN_\(i)",
                results: WorkbenchResultsIndex(sampleKey: "PN_\(i)", updatedAt: now, references: [chartPNAHE])
            )
        }
        fix.createChartFiles(relImagePath: chartPNAHE.chartImagePath, relManifestPath: chartPNAHE.manifestPath)

        // 1 sample for PN90
        fix.createSample(
            sampleKey: "PN90",
            results: WorkbenchResultsIndex(sampleKey: "PN90", updatedAt: now, references: [chartPN90_1])
        )
        fix.createChartFiles(relImagePath: chartPN90_1.chartImagePath, relManifestPath: chartPN90_1.manifestPath)

        // Missing PNG sample
        fix.createSample(
            sampleKey: "SampleMissing",
            results: WorkbenchResultsIndex(sampleKey: "SampleMissing", updatedAt: now, references: missingPNGRefs)
        )

        // Unlinked sample: has measurement_plot_index that references only OTHER keys
        fix.createSample(
            sampleKey: "SampleUnlinked",
            results: WorkbenchResultsIndex(sampleKey: "SampleUnlinked", updatedAt: now, references: unlinkedRefs),
            plotIndex: MeasurementPlotIndex(sampleKey: "SampleUnlinked", updatedAt: now, entries: [
                "run.lvm": ["some_other_key"] // unlinkedRefs are NOT in this index
            ])
        )

        // Legacy sample
        fix.createSample(
            sampleKey: "SampleLegacy",
            results: WorkbenchResultsIndex(sampleKey: "SampleLegacy", updatedAt: now, references: [legacyRef])
        )

        // Snapshot directory before query to prove strict immutability
        let beforeSnapshot = fix.takeDirectorySnapshot()
        let beforeFileContents = fix.takeFileContentSnapshot()
        #expect(!beforeFileContents.isEmpty)

        let defs = defaultDefinitions()
        let service = WorkflowGalleryQueryService(libraryRootURL: fix.rootURL, workflowDefinitions: defs)
        let result = service.execute()

        // Verify immutability down to exact file bytes, not just metadata.
        let afterSnapshot = fix.takeDirectorySnapshot()
        #expect(beforeFileContents == fix.takeFileContentSnapshot())
        #expect(beforeSnapshot.count == afterSnapshot.count)
        for (path, beforeMeta) in beforeSnapshot {
            guard let afterMeta = afterSnapshot[path] else {
                Issue.record("File missing after query: \(path)")
                continue
            }
            #expect(beforeMeta.size == afterMeta.size)
            #expect(beforeMeta.modDate == afterMeta.modDate)
        }

        // Verify Invariants:
        // 1. Cross-sample deduplication:
        let lnoItem = result.items.first { $0.chartIdentityKey == "chart_lno_rt" }
        #expect(lnoItem != nil)
        #expect(lnoItem?.isMultiSample == true)
        #expect(lnoItem?.associatedSampleKeys.count == 6)
        #expect(lnoItem?.associatedSampleKeys == ["LNO_1", "LNO_2", "LNO_3", "LNO_4", "LNO_5", "LNO_6"])

        let sroItem = result.items.first { $0.chartIdentityKey == "chart_sro_xy" }
        #expect(sroItem?.isMultiSample == true)
        #expect(sroItem?.associatedSampleKeys.count == 3)

        let aheItem = result.items.first { $0.chartIdentityKey == "chart_pn_ahe" }
        #expect(aheItem?.isMultiSample == true)
        #expect(aheItem?.associatedSampleKeys.count == 2)

        // 2. Multi-sample folder single sample item:
        let pn90Item = result.items.first { $0.chartIdentityKey == "chart_pn90_iv1" }
        #expect(pn90Item?.isMultiSample == false) // PN90 has single sample associated despite being in multi-sample dir
        #expect(pn90Item?.associatedSampleKeys == ["PN90"])

        // 3. 14 missing PNG records:
        #expect(result.missingImageCount == 14)
        #expect(result.missingManifestCount == 0)
        let missingItems = result.items.filter { $0.imageStatus == .missingFile }
        #expect(missingItems.count == 14)
        for item in missingItems {
            #expect(item.manifestStatus == .available)
            #expect(item.associatedSampleKeys == ["SampleMissing"])
        }

        // 4. 7 unlinked measurement records:
        let unlinkedItems = result.items.filter { $0.associatedSampleKeys.contains("SampleUnlinked") }
        #expect(unlinkedItems.count == 7)
        for item in unlinkedItems {
            #expect(item.hasMeasurementAssociation == false)
            #expect(item.imageStatus == .available)
            #expect(item.manifestStatus == .available)
        }

        // 5. Total counts consistency:
        // Total refs: 6 (LNO) + 3 (SRO) + 2 (AHE) + 1 (PN90) + 14 (Missing) + 7 (Unlinked) + 1 (Legacy) = 34
        #expect(result.totalReferenceCount == 34)
        // Unique charts: 1 (LNO) + 1 (SRO) + 1 (AHE) + 1 (PN90) + 14 (Missing) + 7 (Unlinked) + 1 (Legacy) = 26
        #expect(result.uniqueChartCount == 26)
        #expect(result.items.count == 26)
    }

    @Test("Empty legacy chart identities remain distinct and cannot falsely link measurements")
    func testEmptyChartIdentityFallback() {
        let fix = TempFixture()
        let now = Date()
        let first = WorkbenchResultReference(
            chartIdentityKey: "", chartImagePath: "samples/S1/charts/legacyA.png",
            manifestPath: "samples/S1/charts/legacyA.manifest.json",
            workflowID: "3w", generatedAt: now
        )
        let second = WorkbenchResultReference(
            chartIdentityKey: "", chartImagePath: "samples/S1/charts/legacyB.png",
            manifestPath: "samples/S1/charts/legacyB.manifest.json",
            workflowID: "3w", generatedAt: now
        )
        fix.createSample(
            sampleKey: "S1",
            results: WorkbenchResultsIndex(sampleKey: "S1", updatedAt: now, references: [first, second]),
            plotIndex: MeasurementPlotIndex(sampleKey: "S1", updatedAt: now, entries: ["raw.lvm": [""]])
        )
        fix.createChartFiles(relImagePath: first.chartImagePath, relManifestPath: first.manifestPath)
        fix.createChartFiles(relImagePath: second.chartImagePath, relManifestPath: second.manifestPath)
        let result = WorkflowGalleryQueryService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions()).execute()
        #expect(result.uniqueChartCount == 2)
        let ids = result.items.map(\.id)
        #expect(Set(ids).count == 2)
        #expect(ids.allSatisfy { !$0.isEmpty })
        #expect(ids.allSatisfy { $0.hasPrefix("path:") })
        #expect(result.items.allSatisfy { !$0.hasMeasurementAssociation })
    }

    @Test("Reconciliation mathematical invariant: references minus redundant links equals unique charts")
    func testReconciliationMathematicalInvariants() {
        let fix = TempFixture()
        let now = Date()

        // 3 multi-sample charts:
        // Chart 1: 6 samples
        let c6 = WorkbenchResultReference(
            chartIdentityKey: "c_multi_6", chartImagePath: "_spinlab/multi-sample/charts/rt.png",
            manifestPath: "_spinlab/multi-sample/charts/rt.manifest.json", workflowID: "RT", generatedAt: now
        )
        // Chart 2: 3 samples
        let c3 = WorkbenchResultReference(
            chartIdentityKey: "c_multi_3", chartImagePath: "_spinlab/multi-sample/charts/xy.png",
            manifestPath: "_spinlab/multi-sample/charts/xy.manifest.json", workflowID: "xy", generatedAt: now
        )
        // Chart 3: 2 samples
        let c2 = WorkbenchResultReference(
            chartIdentityKey: "c_multi_2", chartImagePath: "_spinlab/multi-sample/charts/ahe.png",
            manifestPath: "_spinlab/multi-sample/charts/ahe.manifest.json", workflowID: "AHE", generatedAt: now
        )
        // 4 charts in multi-sample directory belonging to only 1 sample (e.g. PN90)
        var pn90Refs: [WorkbenchResultReference] = []
        for i in 1...4 {
            let ref = WorkbenchResultReference(
                chartIdentityKey: "c_pn90_\(i)", chartImagePath: "_spinlab/multi-sample/charts/iv_\(i).png",
                manifestPath: "_spinlab/multi-sample/charts/iv_\(i).manifest.json", workflowID: "IV", generatedAt: now
            )
            pn90Refs.append(ref)
            fix.createChartFiles(relImagePath: ref.chartImagePath, relManifestPath: ref.manifestPath)
        }
        fix.createChartFiles(relImagePath: c6.chartImagePath, relManifestPath: c6.manifestPath)
        fix.createChartFiles(relImagePath: c3.chartImagePath, relManifestPath: c3.manifestPath)
        fix.createChartFiles(relImagePath: c2.chartImagePath, relManifestPath: c2.manifestPath)

        for i in 1...6 {
            fix.createSample(sampleKey: "LNO_\(i)", results: WorkbenchResultsIndex(sampleKey: "LNO_\(i)", updatedAt: now, references: [c6]))
        }
        for i in 1...3 {
            fix.createSample(sampleKey: "SRO_\(i)", results: WorkbenchResultsIndex(sampleKey: "SRO_\(i)", updatedAt: now, references: [c3]))
        }
        for i in 1...2 {
            fix.createSample(sampleKey: "PN_\(i)", results: WorkbenchResultsIndex(sampleKey: "PN_\(i)", updatedAt: now, references: [c2]))
        }
        fix.createSample(sampleKey: "PN90", results: WorkbenchResultsIndex(sampleKey: "PN90", updatedAt: now, references: pn90Refs))

        let result = WorkflowGalleryQueryService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions()).execute()

        // Total references = 6 + 3 + 2 + 4 = 15
        #expect(result.totalReferenceCount == 15)
        // Redundant references = (6-1) + (3-1) + (2-1) + (4 * 0) = 5 + 2 + 1 = 8
        let redundantCount = result.items.reduce(0) { acc, item in
            item.isMultiSample ? acc + (item.associatedSampleKeys.count - 1) : acc
        }
        #expect(redundantCount == 8)
        // Unique charts = 15 - 8 = 7
        #expect(result.uniqueChartCount == 7)
        #expect(result.items.count == 7)

        // Exactly 3 charts are multi-sample
        let multiSampleItems = result.items.filter(\.isMultiSample)
        #expect(multiSampleItems.count == 3)

        // The 4 PN90 charts are single-sample despite being in _spinlab/multi-sample/charts
        let pn90Items = result.items.filter { $0.chartIdentityKey.hasPrefix("c_pn90_") }
        #expect(pn90Items.count == 4)
        #expect(pn90Items.allSatisfy { !$0.isMultiSample && $0.associatedSampleKeys == ["PN90"] })
    }

    /// Characterization baseline test for P0 closeout:
    /// Documents the exact discovery boundary of the shallow scanner before the Stage B nested-sample enhancement.
    @Test("Nested sample directories with slash in key document shallow scanning boundary")
    func testNestedSampleDirectoryDiscoveryCharacterization() {
        let fix = TempFixture()
        let now = Date()

        // Regular sample
        let refNormal = WorkbenchResultReference(
            chartIdentityKey: "c_normal", chartImagePath: "samples/S1/charts/normal.png",
            manifestPath: "samples/S1/charts/normal.manifest.json", workflowID: "3w", generatedAt: now
        )
        fix.createSample(sampleKey: "S1", results: WorkbenchResultsIndex(sampleKey: "S1", updatedAt: now, references: [refNormal]))
        fix.createChartFiles(relImagePath: refNormal.chartImagePath, relManifestPath: refNormal.manifestPath)

        // Nested sample: key contains slash, e.g. "PN107/SRO2|o|STO|110"
        let nestedKey = "PN107/SRO2"
        let refNested = WorkbenchResultReference(
            chartIdentityKey: "c_nested", chartImagePath: "samples/\(nestedKey)/charts/nested.png",
            manifestPath: "samples/\(nestedKey)/charts/nested.manifest.json", workflowID: "3w", generatedAt: now
        )
        fix.createSample(sampleKey: nestedKey, results: WorkbenchResultsIndex(sampleKey: nestedKey, updatedAt: now, references: [refNested]))
        fix.createChartFiles(relImagePath: refNested.chartImagePath, relManifestPath: refNested.manifestPath)

        let result = WorkflowGalleryQueryService(libraryRootURL: fix.rootURL, workflowDefinitions: defaultDefinitions()).execute()

        // S1 is discovered at depth=1.
        // Nested samples/PN107/SRO2 is not discovered by shallow findSampleDirectories (addressed in Stage B).
        #expect(result.uniqueChartCount == 1)
        #expect(result.items.first?.chartIdentityKey == "c_normal")
    }
}
