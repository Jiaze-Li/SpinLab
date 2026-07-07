import XCTest

final class V5115ThreeOmegaWorkspaceStoreCharacterizationTests: XCTestCase {
    private var workspaceSource: String {
        get throws {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let directory = root
                .appendingPathComponent("Sources")
                .appendingPathComponent("SpinLabApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Workbench")
            let names = [
                "ThreeOmegaWorkspaceStore.swift",
                "ThreeOmegaWorkspaceStore+RTSelection.swift",
                "ThreeOmegaWorkspaceStore+Selection.swift",
                "ThreeOmegaWorkspaceStore+FitRanges.swift",
                "ThreeOmegaWorkspaceStore+Analysis.swift",
                "ThreeOmegaWorkspaceStore+Scaling.swift",
                "ThreeOmegaWorkspaceStore+Rendering.swift",
                "ThreeOmegaWorkspaceStore+DualAxisControls.swift",
                "ThreeOmegaWorkspaceStore+ManifestCache.swift",
                "ThreeOmegaWorkspaceStore+Persistence.swift",
                "ThreeOmegaWorkspaceStore+RelatedCharts.swift",
                "ThreeOmegaWorkspaceStore+Pack.swift",
                "ThreeOmegaWorkspaceStore+Plotting.swift",
                "ThreeOmegaRenderedPlots.swift",
                "OverlaySnapshot.swift"
            ]
            return try names.compactMap { name in
                let url = directory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return try String(contentsOf: url, encoding: .utf8)
            }.joined(separator: "\n")
        }
    }

    private var workspaceViewSource: String {
        get throws {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let url = root
                .appendingPathComponent("Sources")
                .appendingPathComponent("SpinLabApp")
                .appendingPathComponent("Features")
                .appendingPathComponent("Workbench")
                .appendingPathComponent("ThreeOmegaWorkspaceView.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testRunAnalysisCommitsTraceOnlyAfterSuccessfulIngestion() throws {
        let source = try workspaceSource
        let runAnalysis = try extractFunction("_runAnalysis(selectedHits:", from: source)

        XCTAssertTrue(runAnalysis.contains("self.ingestionResult = result"))
        XCTAssertTrue(runAnalysis.contains("self._snapshotAndCacheManifestPayloads(from: selectedHits)"))
        XCTAssertTrue(runAnalysis.contains("self.commitRunTrace()"))
        XCTAssertTrue(runAnalysis.contains("self.refreshTransportDerivedPlots(reason: \"analysis completed\")"))
        XCTAssertLessThan(
            try XCTUnwrap(runAnalysis.range(of: "self.ingestionResult = result")?.lowerBound),
            try XCTUnwrap(runAnalysis.range(of: "self.commitRunTrace()")?.lowerBound)
        )
    }

    func testTransportDerivedRefreshUsesIngestionResultAndCurrentV3Method() throws {
        let refresh = try extractFunction("refreshTransportDerivedPlots", from: try workspaceSource)
        let tdHelper = try extractFunction("rerenderTemperatureDependenceForDualAxisControlChange", from: try workspaceSource)

        XCTAssertTrue(refresh.contains("guard let result = ingestionResult else"))
        XCTAssertTrue(refresh.contains("transportDerivedStatus = .missing"))
        XCTAssertTrue(refresh.contains("let capturedGlobalSettings = ThreeOmegaRendererGlobalSettings("))
        XCTAssertTrue(refresh.contains("let capturedScalingSnapshot = tabs.displayStateSnapshot(for: .scaling)"))
        XCTAssertTrue(refresh.contains("let capturedV3Method = v3Method"))
        XCTAssertTrue(refresh.contains("v3Method: capturedV3Method"))
        XCTAssertTrue(refresh.contains("self.rerenderTemperatureDependenceForDualAxisControlChange()"))
        XCTAssertTrue(tdHelper.contains("let displaySnapshot = temperatureDependenceDisplayState.snapshot()"))
        XCTAssertTrue(tdHelper.contains("let (imageData, layout, payload, warnings) = renderer.renderTemperatureDependence("))
    }

    func testTransportGeometryPanelAppearsForScalingAndTemperatureDependence() throws {
        // Architecture change: the Scaling and Temperature Dependence tabs no longer
        // share one combined boolean gate for the geometry fields. Each tab now renders
        // its own dedicated panel — `ThreeOmegaGeometryPanel` (Scaling; geometry + fit
        // ranges) and `ThreeOmegaTemperatureDependencePlotControlsPanel` (TD; geometry
        // only) — and both embed `ThreeOmegaTransportGeometryFields`. This preserves the
        // product behavior (geometry fields visible on both tabs) without one shared
        // condition string.
        let source = try workspaceViewSource
        XCTAssertTrue(source.contains("if store.tabs.activeTab == .temperatureDependence {"))
        XCTAssertTrue(source.contains("ThreeOmegaTemperatureDependencePlotControlsPanel()"))
        XCTAssertTrue(source.contains("if store.tabs.activeTab == .scaling {"))
        XCTAssertTrue(source.contains("ThreeOmegaGeometryPanel()"))
        XCTAssertEqual(
            source.components(separatedBy: "ThreeOmegaTransportGeometryFields(").count - 1,
            2,
            "Expected geometry fields embedded exactly once each in the Scaling and Temperature Dependence panels"
        )
    }

    func testRunScalingCompatibilityWrapperDelegatesToRefresh() throws {
        let runScaling = try extractFunction("runScaling", from: try workspaceSource)

        XCTAssertTrue(runScaling.contains("refreshTransportDerivedPlots(reason: \"manual\")"))
    }

    func testClearPlotAndClearResultsBoundaries() throws {
        let source = try workspaceSource
        let clearPlot = try extractFunction("clearPlot", from: source)
        let clearResults = try extractFunction("clearResults", from: source)

        XCTAssertTrue(clearPlot.contains("ingestionResult"))
        XCTAssertTrue(clearPlot.contains("scalingResult"))
        XCTAssertTrue(clearPlot.contains("currentRunTrace"))
        XCTAssertTrue(clearPlot.contains("tabs.clearAll()"))
        XCTAssertTrue(clearPlot.contains("activePackID"))

        XCTAssertFalse(clearResults.contains("selectedSearchResultIDs"))
        XCTAssertTrue(clearResults.contains("cachedSearchResults"))
        XCTAssertTrue(clearResults.contains("selectedRTHit"))
        XCTAssertFalse(clearResults.contains("ingestionResult"))
        XCTAssertFalse(clearResults.contains("tabs.clearAll()"))
    }

    func testPackSaveRestoreBoundaryDoesNotCommitTraceOnRestore() throws {
        let source = try workspaceSource
        let restoreFromPack = try extractFunction("restoreFromPack", from: source)
        let restoredRender = try extractFunction("_rerenderAllTabsFromRestoredState", from: source)

        XCTAssertTrue(source.contains("var activePackID: AnalysisPack.ID?"))
        XCTAssertFalse(restoreFromPack.contains("commitRunTrace()"))
        XCTAssertTrue(restoreFromPack.contains("_rerenderAllTabsFromRestoredState()"))
        XCTAssertFalse(restoreFromPack.contains("        _snapshotAndCacheManifestPayloads()"))
        XCTAssertTrue(restoredRender.contains("self._titleTokens = tokens"))
        XCTAssertTrue(restoredRender.contains("self._snapshotAndCacheManifestPayloads()"))
        XCTAssertLessThan(
            try XCTUnwrap(restoredRender.range(of: "self._titleTokens = tokens")?.lowerBound),
            try XCTUnwrap(restoredRender.range(of: "self._snapshotAndCacheManifestPayloads()")?.lowerBound)
        )
    }

    func testAlignSeriesOrderPreservesKnownIDsAndAppendsNewIDs() throws {
        let align = try extractFunction("alignSeriesOrder", from: try workspaceSource)

        XCTAssertTrue(align.contains("for id in old where currentSet.contains(id) && seen.insert(id).inserted"))
        XCTAssertTrue(align.contains("for id in defaultIDs where !keptSet.contains(id)"))
        XCTAssertTrue(align.contains("return result == defaultIDs ? nil : result"))
    }

    func testUpdateRAHEMethodDoesNotMutateScalingV3Method() throws {
        // Architecture change: the action-bar/tab-picker split introduced dedicated
        // per-tab method state for the "vs Device" tabs (`rahe1omegaVsDeviceMethod`,
        // `rahe3omegaVsDeviceMethod`), distinct from the combined RAHE tab's
        // `rahe1omegaMethod`/`rahe3omegaMethod`. `updateRAHEMethod` now only drives the
        // vs-Device pair; it still must never mutate the Scaling tab's `v3Method`.
        let update = try extractFunction("updateRAHEMethod", from: try workspaceSource)

        XCTAssertTrue(update.contains("rahe1omegaVsDeviceMethod = method"))
        XCTAssertTrue(update.contains("rahe3omegaVsDeviceMethod = method"))
        XCTAssertFalse(update.contains("v3Method = method"))
    }

    // Architecture change: renderer construction for individual tabs (previously two
    // separate `renderer1`/`renderer3` blocks built inline inside
    // `rerenderFieldSweepTabs`) was consolidated into one shared static helper,
    // `_buildRenderer(for:globalSettings:tabSnap:fieldSweeps:)`, called from within
    // `renderThreeOmegaTab`'s per-tab render closures. `rerenderFieldSweepTabs` itself
    // now only captures per-tab display-state snapshots and delegates to
    // `renderThreeOmegaTab` for both field-sweep tabs. hiddenPointLabelsBySeries
    // propagation now lives once, in `_buildRenderer`, and applies uniformly to every
    // tab that renders through it (including both field-sweep tabs).

    func testRerenderFieldSweepTabsPropagatesHiddenPointLabelsToR1omega() throws {
        let source = try workspaceSource
        let renderTab = try extractFunction("renderThreeOmegaTab", from: source)
        let caseBody = try extractCaseBody(
            "case .fieldSweep1omega:",
            upTo: "case .fieldSweep3omega:",
            from: renderTab
        )
        XCTAssertTrue(caseBody.contains("Self._buildRenderer("))
        XCTAssertTrue(caseBody.contains("r.renderR1omega("))

        let buildRenderer = try extractFunction("_buildRenderer", from: source)
        XCTAssertTrue(
            buildRenderer.contains("r.hiddenPointLabelsBySeries = toIndexedOverrides(tabSnap.hiddenPointLabelsBySeries, series: fakeSeries).mapValues { Set($0) }")
        )
    }

    func testRerenderFieldSweepTabsPropagatesHiddenPointLabelsToR3omega() throws {
        let source = try workspaceSource
        let renderTab = try extractFunction("renderThreeOmegaTab", from: source)
        let caseBody = try extractCaseBody(
            "case .fieldSweep3omega:",
            upTo: "case .rahe1omegaVsT",
            from: renderTab
        )
        XCTAssertTrue(caseBody.contains("Self._buildRenderer("))
        XCTAssertTrue(caseBody.contains("r.renderR3omega("))

        let buildRenderer = try extractFunction("_buildRenderer", from: source)
        XCTAssertTrue(
            buildRenderer.contains("r.hiddenPointLabelsBySeries = toIndexedOverrides(tabSnap.hiddenPointLabelsBySeries, series: fakeSeries).mapValues { Set($0) }")
        )
    }

    func testLegacyOverlayRendererIsRemoved() throws {
        let source = try workspaceSource
        XCTAssertFalse(source.contains("func _renderRAHEWithOverlays()"))
        XCTAssertFalse(source.contains("renderRAHE1omegaVsTMulti"))
        XCTAssertFalse(source.contains("renderRAHE3omegaVsTMulti"))
    }

    func testOverlayEntryPointsNoLongerReferenceLegacyRenderer() throws {
        let source = try workspaceSource
        XCTAssertFalse(source.contains("_renderRAHEWithOverlays()"))
        XCTAssertFalse(source.contains("_renderRAHEWithOverlays"))
    }

    func testSpecialRenderPathsStillAssignShowPointTags() throws {
        // Architecture change: showPointTags propagation moved from two inline
        // renderer1/renderer3 assignments inside `rerenderFieldSweepTabs` into the
        // shared `_buildRenderer` helper (used by both field-sweep tabs, and every
        // other tab that renders through `renderThreeOmegaTab`).
        let source = try workspaceSource
        let renderTab = try extractFunction("renderThreeOmegaTab", from: source)
        let r1CaseBody = try extractCaseBody(
            "case .fieldSweep1omega:",
            upTo: "case .fieldSweep3omega:",
            from: renderTab
        )
        let r3CaseBody = try extractCaseBody(
            "case .fieldSweep3omega:",
            upTo: "case .rahe1omegaVsT",
            from: renderTab
        )
        XCTAssertTrue(r1CaseBody.contains("Self._buildRenderer("))
        XCTAssertTrue(r3CaseBody.contains("Self._buildRenderer("))

        let buildRenderer = try extractFunction("_buildRenderer", from: source)
        XCTAssertTrue(buildRenderer.contains("r.showPointTags         = tabSnap.showPointTags"))
    }

    func testCommitRunTraceCallSitesStayLimited() throws {
        let source = try workspaceSource
        let callCount = source.components(separatedBy: "commitRunTrace()").count - 1
        let runAnalysis = try extractFunction("runAnalysis(searchSnapshot:", from: source)
        let selectedHitsAnalysis = try extractFunction("runAnalysis(selectedHitsSnapshot:", from: source)
        let helper = try extractFunction("_runAnalysis(selectedHits:", from: source)

        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(runAnalysis.contains("commitRunTrace()"))
        XCTAssertFalse(selectedHitsAnalysis.contains("commitRunTrace()"))
        XCTAssertTrue(helper.contains("commitRunTrace()"))
        XCTAssertFalse(try extractFunction("persistToLibrary", from: source).contains("commitRunTrace()"))
    }

    /// Extracts the substring of `source` starting at the first occurrence of `start`
    /// and running up to (but not including) the first occurrence of `end` after it.
    /// Used to isolate a single `switch` case's body within an already-extracted
    /// function body.
    private func extractCaseBody(_ start: String, upTo end: String, from source: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            XCTFail("Missing case marker \(start)")
            return ""
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            XCTFail("Missing case marker \(end) after \(start)")
            return ""
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func extractFunction(_ name: String, from source: String) throws -> String {
        guard let signature = source.range(of: "func \(name)") else {
            XCTFail("Missing function \(name)")
            return ""
        }
        guard let openBrace = source[signature.lowerBound...].firstIndex(of: "{") else {
            XCTFail("Missing opening brace for \(name)")
            return ""
        }
        var depth = 0
        var index = openBrace
        while index < source.endIndex {
            let char = source[index]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[signature.lowerBound...index])
                }
            }
            index = source.index(after: index)
        }
        XCTFail("Missing closing brace for \(name)")
        return ""
    }
}
