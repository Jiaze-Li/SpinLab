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

    func testRunAnalysisCommitsTraceOnlyAfterSuccessfulIngestion() throws {
        let source = try workspaceSource
        let runAnalysis = try extractFunction("_runAnalysis(selectedHits:", from: source)

        XCTAssertTrue(runAnalysis.contains("self.ingestionResult = result"))
        XCTAssertTrue(runAnalysis.contains("self._snapshotAndCacheManifestPayloads(from: selectedHits)"))
        XCTAssertTrue(runAnalysis.contains("self.commitRunTrace()"))
        XCTAssertLessThan(
            try XCTUnwrap(runAnalysis.range(of: "self.ingestionResult = result")?.lowerBound),
            try XCTUnwrap(runAnalysis.range(of: "self.commitRunTrace()")?.lowerBound)
        )
    }

    func testRunScalingRequiresIngestionResultAndUsesV3Method() throws {
        let runScaling = try extractFunction("runScaling", from: try workspaceSource)

        XCTAssertTrue(runScaling.contains("guard let result = ingestionResult, let rt = result.rtResult else"))
        XCTAssertTrue(runScaling.contains("let capturedGlobalSettings = ThreeOmegaRendererGlobalSettings("))
        XCTAssertTrue(runScaling.contains("let capturedScalingSnapshot = tabs.displayStateSnapshot(for: .scaling)"))
        XCTAssertTrue(runScaling.contains("_renderRevision &+= 1"))
        XCTAssertTrue(runScaling.contains("renderThreeOmegaTab("))
        XCTAssertTrue(runScaling.contains("let capturedV3Method = v3Method"))
        XCTAssertTrue(runScaling.contains("v3Method: capturedV3Method"))
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
        let update = try extractFunction("updateRAHEMethod", from: try workspaceSource)

        XCTAssertTrue(update.contains("rahe1omegaMethod = method"))
        XCTAssertTrue(update.contains("rahe3omegaMethod = method"))
        XCTAssertFalse(update.contains("v3Method = method"))
    }

    func testRerenderFieldSweepTabsPropagatesHiddenPointLabelsToR1omega() throws {
        let rerender = try extractFunction("rerenderFieldSweepTabs", from: try workspaceSource)

        XCTAssertTrue(
            rerender.contains("renderer1.hiddenPointLabelsBySeries = toIndexedOverrides(capturedState1.hiddenPointLabelIndicesBySeries, series: labelMapSeries).mapValues { Set($0) }")
        )
    }

    func testRerenderFieldSweepTabsPropagatesHiddenPointLabelsToR3omega() throws {
        let rerender = try extractFunction("rerenderFieldSweepTabs", from: try workspaceSource)

        XCTAssertTrue(
            rerender.contains("renderer3.hiddenPointLabelsBySeries = toIndexedOverrides(capturedState3.hiddenPointLabelIndicesBySeries, series: labelMapSeries).mapValues { Set($0) }")
        )
    }

    func testRenderRAHEWithOverlaysPropagatesHiddenPointLabelsToRAHE1omega() throws {
        let render = try extractFunction("_renderRAHEWithOverlays", from: try workspaceSource)

        XCTAssertTrue(
            render.contains("r1.hiddenPointLabelsBySeries = toIndexedOverrides(state1.hiddenPointLabelIndicesBySeries, series: groups.map")
        )
    }

    func testRenderRAHEWithOverlaysPropagatesHiddenPointLabelsToRAHE3omega() throws {
        let render = try extractFunction("_renderRAHEWithOverlays", from: try workspaceSource)

        XCTAssertTrue(
            render.contains("r3.hiddenPointLabelsBySeries = toIndexedOverrides(state3.hiddenPointLabelIndicesBySeries, series: groups.map")
        )
    }

    func testSpecialRenderPathsStillAssignShowPointTags() throws {
        let rerender = try extractFunction("rerenderFieldSweepTabs", from: try workspaceSource)
        let overlay = try extractFunction("_renderRAHEWithOverlays", from: try workspaceSource)

        XCTAssertTrue(rerender.contains("renderer1.showPointTags         = capturedState1.pointTags.showPointTags"))
        XCTAssertTrue(rerender.contains("renderer3.showPointTags         = capturedState3.pointTags.showPointTags"))
        XCTAssertTrue(overlay.contains("r1.showPointTags = capturedShowPointTags1"))
        XCTAssertTrue(overlay.contains("r3.showPointTags = capturedShowPointTags3"))
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
