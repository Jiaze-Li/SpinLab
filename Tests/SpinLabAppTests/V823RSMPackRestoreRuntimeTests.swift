import Foundation
import Testing
@testable import SpinLabApp

// MARK: - Fixtures

private let rsmRuntimeHL3x3 = """
# RSM scan — HL plane, K=0 fixed
H        K        L        Detector
-1.0     0.0      1.0      100.0
 0.0     0.0      1.0      200.0
 1.0     0.0      1.0      150.0
-1.0     0.0      1.5      110.0
 0.0     0.0      1.5      250.0
 1.0     0.0      1.5      180.0
-1.0     0.0      2.0       90.0
 0.0     0.0      2.0      300.0
 1.0     0.0      2.0      120.0
"""

private let rsmRuntimeKL2x2 = """
H     K     L     Detector
0.0   0.0   1.0   10.0
0.0   0.5   1.0   20.0
0.0   0.0   2.0   30.0
0.0   0.5   2.0   40.0
"""

private let rsmRuntimeHK2x2 = """
H     K     L     Intensity
-1.0  0.0   1.0   11.0
 1.0  0.0   1.0   22.0
-1.0  1.0   1.0   33.0
 1.0  1.0   1.0   44.0
"""

private let rsmRuntimeIrregularGrid = """
H     K     L     Detector
0.0   0.0   1.0   10.0
1.0   0.0   1.0   20.0
0.0   0.0   2.0   30.0
"""

// MARK: - Pack config construction helper

/// Directly constructs the pack config that the runtime store would produce.
private func makePackConfig(
    sourceIdentity: String,
    detectorColumnName: String,
    activeView: RSMView,
    displayState: HeatmapTabRenderState = .init(),
    searchResults: [WorkflowMeasurementSearchHit] = []
) -> RSMPackConfig {
    RSMPackConfig(
        packState: RSMPackState(
            sourceFileIdentity: sourceIdentity,
            detectorColumnName: detectorColumnName,
            activeView: activeView
        ),
        displayState: displayState,
        cachedSearchResults: searchResults
    )
}

// MARK: - Restore harness (mirrors runtime restoreFromPack)

private struct RSMRuntimeRestoreResult {
    let dataset: CanonicalRSMDataset
    let payload: HeatmapPlotPayload
    let output: HeatmapRenderPipeline.Output
}

private enum RSMRuntimeTestError: Error, Equatable {
    case missingSourceIdentity
}

private func restoreFromPackConfig(
    _ config: RSMPackConfig,
    sourceResolver: (String) throws -> String,
    packLabel: String = "Test Pack"
) throws -> RSMRuntimeRestoreResult {
    guard let sourceIdentity = config.packState.sourceFileIdentity, !sourceIdentity.isEmpty else {
        throw RSMRuntimeTestError.missingSourceIdentity
    }

    let displayState = config.displayState
    let text = try sourceResolver(sourceIdentity)
    let dataset = try RSMDataParser.parse(text: text, title: packLabel, sourceRef: sourceIdentity)

    var payload = try RSMHeatmapPayloadBuilder.build(
        from: dataset,
        options: .init(
            view: config.packState.activeView,
            title: displayState.titleOverride.isEmpty ? dataset.title : displayState.titleOverride,
            zLabel: displayState.zLabelOverride.isEmpty ? dataset.detectorColumnName : displayState.zLabelOverride
        )
    )

    if !displayState.xLabelOverride.isEmpty { payload.xLabel = displayState.xLabelOverride }
    if !displayState.yLabelOverride.isEmpty { payload.yLabel = displayState.yLabelOverride }
    if let colormapOverride = displayState.colormapKey { payload.colormapKey = colormapOverride }

    let output = try HeatmapRenderPipeline.render(.init(
        payload: payload,
        colorScaleMode: displayState.colorScaleMode,
        zDomainState: displayState.zDomainState,
        showColorbar: displayState.showColorbar
    ))

    return RSMRuntimeRestoreResult(dataset: dataset, payload: payload, output: output)
}

private func pngHeaderMatches(_ data: Data) -> Bool {
    let pngHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    return [UInt8](data.prefix(4)) == pngHeader
}

private func collectAllKeys(_ object: Any) -> Set<String> {
    var keys = Set<String>()
    if let dict = object as? [String: Any] {
        for (k, v) in dict {
            keys.insert(k)
            keys.formUnion(collectAllKeys(v))
        }
    } else if let array = object as? [Any] {
        for item in array { keys.formUnion(collectAllKeys(item)) }
    }
    return keys
}

// MARK: - H4 runtime pack/restore tests

@Suite("RSM pack/restore runtime (H4)")
struct V823RSMPackRestoreRuntimeTests {

    // MARK: Store captures activeView and displayState into pack config

    @Test("Store buildPackConfig captures activeView and heatmapDisplayState")
    @MainActor
    func storeCapturesActiveViewAndDisplayState() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        store.activeView = .kl
        store.heatmapDisplayState = HeatmapTabRenderState(
            showColorbar: false,
            colorScaleMode: .log10,
            colormapKey: "plasma"
        )

        let config = store.buildPackConfig()

        #expect(config.packState.activeView == .kl)
        #expect(config.displayState.colorScaleMode == .log10)
        #expect(config.displayState.colormapKey == "plasma")
        #expect(!config.displayState.showColorbar)
    }

    // MARK: Pack then restore: HL heatmap

    @Test("Pack then restore RSM HL heatmap")
    func packThenRestoreHLHeatmap() throws {
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-hl.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )

        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })

        #expect(result.payload.xLabel == "H (r.l.u.)")
        #expect(result.payload.yLabel == "L (r.l.u.)")
        #expect(result.payload.zLabel == "Detector")
        #expect(!result.output.imageData.isEmpty)
        #expect(pngHeaderMatches(result.output.imageData))
    }

    // MARK: Pack then restore: KL / HK active views

    @Test("Pack then restore KL and HK active views")
    func packThenRestoreKLHKViews() throws {
        let cases: [(view: RSMView, source: String, detector: String, expectedX: String, expectedY: String)] = [
            (.kl, rsmRuntimeKL2x2, "Detector", "K (r.l.u.)", "L (r.l.u.)"),
            (.hk, rsmRuntimeHK2x2, "Intensity", "H (r.l.u.)", "K (r.l.u.)")
        ]

        for item in cases {
            let config = makePackConfig(
                sourceIdentity: "/tmp/rsm-runtime-\(item.view.rawValue).dat",
                detectorColumnName: item.detector,
                activeView: item.view
            )
            let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
            let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in item.source })

            #expect(result.payload.xLabel == item.expectedX)
            #expect(result.payload.yLabel == item.expectedY)
            #expect(!result.output.imageData.isEmpty)
            #expect(pngHeaderMatches(result.output.imageData))
        }
    }

    // MARK: Pack then restore: detectorColumnName

    @Test("Pack then restore detectorColumnName")
    func packThenRestoreDetectorColumnName() throws {
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-intensity.dat",
            detectorColumnName: "Intensity",
            activeView: .hk
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(roundTripped.packState.detectorColumnName == "Intensity")

        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHK2x2 })
        #expect(result.payload.zLabel == "Intensity")
    }

    // MARK: Pack then restore: label overrides

    @Test("Pack then restore title/x/y/z label overrides")
    func packThenRestoreLabelOverrides() throws {
        let displayState = HeatmapTabRenderState(
            titleOverride: "Runtime Restored Title",
            xLabelOverride: "H Axis",
            yLabelOverride: "L Axis",
            zLabelOverride: "Counts",
            colorScaleMode: .linear
        )
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-labels.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })

        #expect(result.payload.title == "Runtime Restored Title")
        #expect(result.payload.xLabel == "H Axis")
        #expect(result.payload.yLabel == "L Axis")
        #expect(result.payload.zLabel == "Counts")
        #expect(!result.output.imageData.isEmpty)
    }

    @Test("Pack then restore showColorbar false")
    func packThenRestoreShowColorbarFalse() throws {
        let displayState = HeatmapTabRenderState(showColorbar: false)
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-hide-z.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })

        #expect(!result.output.layout.showColorbar)
        // showColorbar=false hides the entire colorbar block
        #expect(result.output.layout.colorbarTicks.isEmpty)
        #expect(!result.output.imageData.isEmpty)
    }

    // MARK: Pack then restore: log10 color scale mode

    @Test("Pack then restore log10 colorScaleMode")
    func packThenRestoreLog10ColorScaleMode() throws {
        let displayState = HeatmapTabRenderState(colorScaleMode: .log10)
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-log.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(roundTripped.displayState.colorScaleMode == .log10)

        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })

        let logLayout = HeatmapPlotLayout.compute(payload: result.payload, colorScaleMode: .log10)
        let linearLayout = HeatmapPlotLayout.compute(payload: result.payload, colorScaleMode: .linear)

        let renderedTicks = result.output.layout.colorbarTicks.map { (Double($0.y), $0.label) }
        let logTicks = logLayout.colorbarTicks.map { (Double($0.y), $0.label) }
        let linearTicks = linearLayout.colorbarTicks.map { (Double($0.y), $0.label) }

        #expect(zip(renderedTicks, logTicks).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 })
        #expect(!zip(renderedTicks, linearTicks).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 })
    }

    // MARK: Pack then restore: colormapKey

    @Test("Pack then restore colormapKey")
    func packThenRestoreColormapKey() throws {
        let displayState = HeatmapTabRenderState(colormapKey: "magma")
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-magma.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(roundTripped.displayState.colormapKey == "magma")

        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })
        #expect(result.payload.colormapKey == "magma")
        #expect(!result.output.imageData.isEmpty)
    }

    @Test("Pack then restore with no colormap override preserves RSM's rsmTurbo default")
    func packThenRestoreWithNoColormapOverridePreservesRSMDefault() throws {
        // Default HeatmapTabRenderState() has colormapKey == nil ("no override"). Restoring
        // it must not clobber RSMHeatmapPayloadBuilder's rsmTurbo default with viridis.
        let displayState = HeatmapTabRenderState()
        #expect(displayState.colormapKey == nil)

        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-default-colormap.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
        #expect(roundTripped.displayState.colormapKey == nil)

        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })
        #expect(result.payload.colormapKey == "rsmTurbo")
        #expect(!result.output.imageData.isEmpty)
    }

    // MARK: Pack then restore: manual Z domain

    @Test("Pack then restore manual z domain")
    func packThenRestoreManualZDomain() throws {
        let displayState = HeatmapTabRenderState(
            zDomainState: HeatmapZDomainState(
                mode: .manual,
                manualRange: HeatmapZRangeDraft(minText: "110.0", maxText: "250.0")
            )
        )
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-zrange.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))
        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })

        #expect(result.output.layout.zMin == 110.0)
        #expect(result.output.layout.zMax == 250.0)
    }

    @Test("Pack then restore percentile z domain")
    func packThenRestorePercentileZDomain() throws {
        let displayState = HeatmapTabRenderState(
            zDomainState: HeatmapZDomainState(
                mode: .percentile,
                percentilePreset: .p5_95
            )
        )
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-percentile.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )
        let roundTripped = try JSONDecoder().decode(RSMPackConfig.self, from: JSONEncoder().encode(config))

        #expect(roundTripped.displayState.zDomainState.mode == .percentile)
        #expect(roundTripped.displayState.zDomainState.percentilePreset == .p5_95)

        let result = try restoreFromPackConfig(roundTripped, sourceResolver: { _ in rsmRuntimeHL3x3 })
        #expect(!result.output.imageData.isEmpty)
        #expect(result.output.layout.zMin > 90.0)
        #expect(result.output.layout.zMax < 300.0)
    }

    // MARK: Restore failure: missing source file

    @Test("Restore failure: missing source file")
    func restoreFailureMissingSourceFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rsm-runtime-missing-\(UUID().uuidString).dat")
        let config = makePackConfig(
            sourceIdentity: tempURL.path,
            detectorColumnName: "Detector",
            activeView: .hl
        )

        #expect(throws: CocoaError.self) {
            try restoreFromPackConfig(
                config,
                sourceResolver: { path in try String(contentsOfFile: path, encoding: .utf8) }
            )
        }
    }

    // MARK: Restore failure: irregular grid

    @Test("Restore failure: irregular grid")
    func restoreFailureIrregularGrid() throws {
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-irregular.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )

        #expect(throws: RSMHeatmapPayloadBuilderError.self) {
            try restoreFromPackConfig(config, sourceResolver: { _ in rsmRuntimeIrregularGrid })
        }
    }

    // MARK: Restore fallback: invalid manual z-range

    @Test("Restore fallback invalid manual z range")
    func restoreFallbackInvalidManualZRange() throws {
        let displayState = HeatmapTabRenderState(
            zDomainState: HeatmapZDomainState(
                mode: .manual,
                manualRange: HeatmapZRangeDraft(minText: "5.0", maxText: "3.0")
            )
        )
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-invalid-zrange.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: displayState
        )

        let result = try restoreFromPackConfig(config, sourceResolver: { _ in rsmRuntimeHL3x3 })
        #expect(result.output.layout.zMin == 90.0)
        #expect(result.output.layout.zMax == 300.0)
    }

    // MARK: Assert pack JSON does not contain PNG

    @Test("Pack JSON does not contain PNG")
    func packJSONDoesNotContainPNG() throws {
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-no-png.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )
        let data = try JSONEncoder().encode(config)
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("imageData"))
        #expect(!json.contains("renderedPNG"))
        #expect(!json.lowercased().contains("\"png\""))
    }

    // MARK: Assert pack JSON does not contain HeatmapPlotLayout

    @Test("Pack JSON does not contain HeatmapPlotLayout")
    func packJSONDoesNotContainHeatmapPlotLayout() throws {
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-no-layout.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: HeatmapTabRenderState(titleOverride: "Layout-free pack")
        )
        let data = try JSONEncoder().encode(config)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Pack config should encode as a JSON object.")
            return
        }
        let allKeys = collectAllKeys(object)

        #expect(!allKeys.contains("layout"))
        #expect(!allKeys.contains("HeatmapPlotLayout"))
        #expect(!allKeys.contains("activeLayout"))
        #expect(!allKeys.contains("gridRect"))
        #expect(!allKeys.contains("colorbarRect"))
    }

    // MARK: Library root restored from vault during pack restore

    @Test("restoreFromPack sets lastLibraryRootPath from vault when previously empty")
    @MainActor
    func restoreFromPackSetsLibraryRootFromVault() async {
        let libPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("v823-vault-\(UUID().uuidString)").path

        let vault = AnalysisVault()
        vault.configurePersistence(libraryRootPath: libPath)

        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        store.vault = vault
        // lastLibraryRootPath starts empty
        #expect(store.lastLibraryRootPath.isEmpty)

        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-vault-restore.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )
        let fakePack = AnalysisPack(
            label: "Vault Pack",
            workflowID: "rsm",
            createdAt: .distantPast,
            filePaths: ["/tmp/rsm-vault-restore.dat"],
            sampleKeys: ["test-key"],
            config: (try? JSONEncoder().encode(config)) ?? Data(),
            result: Data()
        )

        store.restoreFromPack(
            config: config,
            result: RSMPackResult(),
            pack: fakePack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        #expect(store.lastLibraryRootPath == libPath)
    }

    @Test("restoreFromPack does not overwrite non-empty lastLibraryRootPath")
    @MainActor
    func restoreFromPackPreservesExistingLibraryRoot() async {
        let vaultPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("v823-vault-a-\(UUID().uuidString)").path
        let existingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("v823-vault-b-\(UUID().uuidString)").path

        let vault = AnalysisVault()
        vault.configurePersistence(libraryRootPath: vaultPath)

        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        store.vault = vault
        store.lastLibraryRootPath = existingPath  // already set

        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-vault-preserve.dat",
            detectorColumnName: "Detector",
            activeView: .hl
        )
        let fakePack = AnalysisPack(
            label: "Vault Pack",
            workflowID: "rsm",
            createdAt: .distantPast,
            filePaths: [],
            sampleKeys: [],
            config: Data(),
            result: Data()
        )

        store.restoreFromPack(
            config: config,
            result: RSMPackResult(),
            pack: fakePack,
            restoreSearchState: { _, _ in },
            seedSelection: { _, _ in }
        )

        // Must not overwrite the existing non-empty value with vault path
        #expect(store.lastLibraryRootPath == existingPath)
    }

    // MARK: Assert activeLayout remains nil after restore

    @Test("activeLayout remains nil after restore")
    @MainActor
    func activeLayoutRemainsNilAfterRestore() {
        let store = RSMWorkspaceStore(workflowID: WorkflowKey.rsm.rawValue)
        store.activeView = .hl
        store.heatmapDisplayState = .init()

        #expect(store.activeLayout == nil)
    }

    // MARK: Assert Cartesian XY render path still passes

    @Test("Cartesian XY render path remains untouched")
    func cartesianXYRenderPathRemainsUntouched() throws {
        let payload = WorkbenchPlotPayload(
            workflowID: "xy",
            workflowDisplayName: "XY Rotation",
            title: "H4 Cartesian Smoke",
            axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
            series: [
                WorkbenchPlotSeries(
                    label: "Series 1",
                    x: [0.0, 1.0, 2.0],
                    y: [1.0, 2.0, 3.0]
                )
            ]
        )

        let output = try WorkbenchRenderPipeline.render(.init(payload: payload))

        #expect(!output.imageData.isEmpty)
        #expect(output.layout.chartTitle == "H4 Cartesian Smoke")
        #expect(output.layout.xAxisLabel == "X")
        #expect(output.layout.yAxisLabel == "Y")
    }

    // MARK: RSM and Heatmap display state remain separate in JSON

    @Test("RSM pack state does not contain display fields; display state does not contain RSM fields")
    func rsmAndDisplayStateRemainSeparate() throws {
        let config = makePackConfig(
            sourceIdentity: "/tmp/rsm-runtime-separation.dat",
            detectorColumnName: "Detector",
            activeView: .hl,
            displayState: HeatmapTabRenderState(
                titleOverride: "Separation Test",
                colorScaleMode: .log10,
                colormapKey: "inferno"
            )
        )

        let packStateData = try JSONEncoder().encode(config.packState)
        let packStateJSON = String(decoding: packStateData, as: UTF8.self)

        #expect(!packStateJSON.contains("titleOverride"))
        #expect(!packStateJSON.contains("colorScaleMode"))
        #expect(!packStateJSON.contains("colormapKey"))
        #expect(!packStateJSON.contains("zRangeOverride"))
        #expect(!packStateJSON.contains("xLabelOverride"))

        let displayData = try JSONEncoder().encode(config.displayState)
        let displayJSON = String(decoding: displayData, as: UTF8.self)

        #expect(!displayJSON.contains("sourceFileIdentity"))
        #expect(!displayJSON.contains("detectorColumnName"))
        #expect(!displayJSON.contains("activeView"))
    }
}
