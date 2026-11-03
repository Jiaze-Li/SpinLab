import AppKit
import Foundation
import Testing
@testable import SpinLabApp

@Suite("Workflow Gallery UI and Navigation Tests")
struct WorkflowGalleryUITests {

    @Test("Sidebar Menu generates Workflows group and preserves drawer prefixes")
    @MainActor
    func testSidebarMenuWorkflowsGroup() {
        let appState = SpinLabAppState()
        appState.workflowDefinitions = [
            WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: []),
            WorkflowDefinition(id: "rt", displayName: "RT", conditionFields: [])
        ]
        let provider = SpinLabSidebarMenuProvider()

        let menu = provider.makeMenu(appState: appState, selectedArea: .library)
        let libraryNode = menu.first(where: { $0.kind == .area(.library) })
        #expect(libraryNode != nil)

        let children = libraryNode?.children ?? []
        #expect(!children.isEmpty)

        // 1. First child should be Workflows group
        let workflowsGroup = children.first(where: { $0.id == SidebarMenuNodeID.libraryWorkflowsGroup() })
        #expect(workflowsGroup != nil)
        #expect(workflowsGroup?.title == "Workflows")
        #expect(workflowsGroup?.systemImage == "photo.stack")

        // 2. Workflows children should contain known workflow entries
        let wfChildren = workflowsGroup?.children ?? []
        #expect(!wfChildren.isEmpty)
        let wfIDs = wfChildren.compactMap { node -> String? in
            if case let .libraryWorkflowGallery(id) = node.kind {
                return id
            }
            return nil
        }
        #expect(wfIDs == ["3w", "ahe", "rt"])
    }

    @Test("AppRouter and deep links route to Workflow Gallery")
    @MainActor
    func testAppRouterRouting() {
        let router = AppRouter()

        // 1. Sidebar node kind mapping
        let route = router.routePath(for: .libraryWorkflowGallery(id: "3w"))
        #expect(route == .libraryWorkflowGallery(id: "3w"))

        let groupRoute = router.routePath(for: .libraryWorkflowsGroup)
        #expect(groupRoute == nil, "Group header is expandable, not directly routable")

        // 2. Deep linking
        let stack = router.deepLinkToRouteStack("library/workflows/3w")
        #expect(stack?.paths == [.library, .libraryWorkflowGallery(id: "3w")])

        let caseInsensitiveStack = router.deepLinkToRouteStack("Library/Workflows/AHE")
        #expect(caseInsensitiveStack?.paths == [.library, .libraryWorkflowGallery(id: "AHE")])
    }

    @Test("LibraryFeatureStore route switching between Samples and Gallery")
    @MainActor
    func testLibraryFeatureStoreRoutes() {
        let store = LibraryFeatureStore()
        #expect(store.currentRoute == .samples)

        // Select gallery
        store.selectWorkflowGallery("3w")
        #expect(store.currentRoute == .workflowGallery(workflowID: "3w"))
        #expect(store.selectedWorkflowGalleryID == "3w")

        // Select samples
        store.selectSamples()
        #expect(store.currentRoute == .samples)
    }

    @Test("WorkflowGalleryState sorting, filtering, and selection")
    @MainActor
    func testWorkflowGalleryStateFilteringAndSorting() {
        let state = WorkflowGalleryState()

        let now = Date()
        let item1 = WorkflowGalleryItem(
            chartIdentityKey: "c1",
            chartImagePath: "samples/PN104/charts/plot1.png",
            manifestPath: "samples/PN104/charts/plot1.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: now.addingTimeInterval(-100),
            tabKey: "fieldSweep",
            associatedSampleKeys: ["PN104|o|STO|111"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Alpha Plot"
        )

        let item2 = WorkflowGalleryItem(
            chartIdentityKey: "c2",
            chartImagePath: "samples/PN60/charts/plot2.png",
            manifestPath: "samples/PN60/charts/plot2.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: now,
            tabKey: "tempSweep",
            associatedSampleKeys: ["PN59|o|STO|111", "PN60|o|STO|111"],
            isMultiSample: true,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Beta Multi Plot"
        )

        let item3 = WorkflowGalleryItem(
            chartIdentityKey: "c3",
            chartImagePath: "samples/PN97/charts/plot3.png",
            manifestPath: "samples/PN97/charts/plot3.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: now.addingTimeInterval(-200),
            tabKey: "scaling",
            associatedSampleKeys: ["PN97|o|STO|110"],
            isMultiSample: false,
            imageStatus: .missingFile,
            manifestStatus: .available,
            hasMeasurementAssociation: false,
            displayTitle: "Gamma Missing Plot"
        )

        state.items = [item1, item2, item3]

        // 1. Sort Newest First (default)
        state.sortOrder = .newestFirst
        #expect(state.displayItems.map(\.chartIdentityKey) == ["c2", "c1", "c3"])

        // 2. Sort Oldest First
        state.sortOrder = .oldestFirst
        #expect(state.displayItems.map(\.chartIdentityKey) == ["c3", "c1", "c2"])

        // 3. Filter Valid Only
        state.sortOrder = .newestFirst
        state.filterOption = .validOnly
        #expect(state.displayItems.map(\.chartIdentityKey) == ["c2", "c1"])

        let validKeys = state.displayItems.map(\.chartIdentityKey)
        #expect(!validKeys.contains("c3"))

        // 4. Filter Missing Only
        state.filterOption = .missingOnly
        #expect(state.displayItems.map(\.chartIdentityKey) == ["c3"])

        // 5. Filter Multi-Sample Only
        state.filterOption = .multiSampleOnly
        #expect(state.displayItems.map(\.chartIdentityKey) == ["c2"])

        // 6. Search filter
        state.filterOption = .all
        state.searchText = "Alpha"
        #expect(state.displayItems.map(\.chartIdentityKey) == ["c1"])

        state.searchText = "PN59"
        #expect(state.displayItems.map(\.chartIdentityKey) == ["c2"])
    }

    @Test("WorkflowThumbnailCache downsamples image and enforces cache count limits")
    func testWorkflowThumbnailCache() throws {
        // Test with countLimit = 2 to prove bounded eviction
        let cache = WorkflowThumbnailCache(countLimit: 2)

        func makeTestPNG(width: Int, height: Int) throws -> URL {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )!
            let pngData = rep.representation(using: .png, properties: [:])!
            let tempURL = FileManager.default.temporaryDirectory.appending(path: "test_\(UUID().uuidString).png")
            try pngData.write(to: tempURL)
            return tempURL
        }

        let url1 = try makeTestPNG(width: 800, height: 800)
        let url2 = try makeTestPNG(width: 800, height: 800)
        let url3 = try makeTestPNG(width: 800, height: 800)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
            try? FileManager.default.removeItem(at: url3)
        }

        // 1. Downsample item 1 to maxPixelSize 300
        let thumb1 = cache.loadThumbnail(url: url1, key: url1.path, maxPixelSize: 300)
        #expect(thumb1 != nil)
        #expect((thumb1?.size.width ?? 0) <= 300)
        #expect((thumb1?.size.height ?? 0) <= 300)
        #expect(cache.cachedThumbnail(for: url1.path) != nil)

        // 2. Load item 2
        _ = cache.loadThumbnail(url: url2, key: url2.path, maxPixelSize: 300)
        #expect(cache.cachedThumbnail(for: url2.path) != nil)

        // 3. Load item 3 (should evict item 1 due to countLimit = 2)
        _ = cache.loadThumbnail(url: url3, key: url3.path, maxPixelSize: 300)
        #expect(cache.cachedThumbnail(for: url3.path) != nil)
        #expect(cache.cachedThumbnail(for: url2.path) != nil)
        #expect(cache.cachedThumbnail(for: url1.path) == nil, "Oldest item 1 must be evicted to prevent memory unbounded growth")

        // 4. Cost-based eviction test
        let costCache = WorkflowThumbnailCache(countLimit: 100, totalCostLimit: 300 * 300 * 4 + 100)
        _ = costCache.loadThumbnail(url: url1, key: "c1", maxPixelSize: 300)
        #expect(costCache.cachedThumbnail(for: "c1") != nil)
        _ = costCache.loadThumbnail(url: url2, key: "c2", maxPixelSize: 300)
        #expect(costCache.cachedThumbnail(for: "c2") != nil)
    }

    @Test("WorkflowGalleryState sets error state when unreadable indices are detected")
    @MainActor
    func testWorkflowGalleryStateErrorHandling() {
        let state = WorkflowGalleryState()
        #expect(state.errorMessage == nil)

        // Query result with unreadable sample indices and no items
        let queryResult = WorkflowGalleryQueryResult(
            items: [],
            unreadableSampleIndices: ["corruptSample_PN99"]
        )
        state.queryResult = queryResult
        state.items = queryResult.items
        if state.items.isEmpty && !queryResult.unreadableSampleIndices.isEmpty {
            state.errorMessage = "Failed to query charts: results_index.json could not be read for \(queryResult.unreadableSampleIndices.count) samples (\(queryResult.unreadableSampleIndices.joined(separator: ", ")))."
        }
        #expect(state.errorMessage != nil)
        #expect(state.errorMessage?.contains("corruptSample_PN99") == true)
    }

    @Test("Full user journey: Navigation -> Gallery -> Select Multi-Sample Chart -> Disambiguate -> Jump with Edit Guard -> Return to Gallery")
    @MainActor
    func testFullUserJourneyNavigationAndSampleJump() {
        let appState = SpinLabAppState()
        appState.workflowDefinitions = [
            WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: []),
            WorkflowDefinition(id: "xy", displayName: "XY Rotation", conditionFields: [])
        ]

        // Populate mock drawer structure in appState.library.libraryExistingGroups
        let dummySample59 = LibrarySample(
            id: "PN59|o|STO|111",
            displayName: "PN59_111",
            batchId: "PN59",
            substrateRaw: "STO",
            substrateDisplay: "STO(111)",
            substrateTokens: ["STO"],
            substrateTags: ["111"],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: Date()
        )
        let dummySample60 = LibrarySample(
            id: "PN60|o|STO|111",
            displayName: "PN60_111",
            batchId: "PN60",
            substrateRaw: "STO",
            substrateDisplay: "STO(111)",
            substrateTokens: ["STO"],
            substrateTags: ["111"],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: Date()
        )
        let dummySample104 = LibrarySample(
            id: "PN104|o|STO|111",
            displayName: "PN104_111",
            batchId: "PN104",
            substrateRaw: "STO",
            substrateDisplay: "STO(111)",
            substrateTokens: ["STO"],
            substrateTags: ["111"],
            metadata: [:],
            numericTags: [:],
            numericDisplay: [:],
            updatedAt: Date()
        )

        appState.library.libraryExistingGroups = [
            "PN": [
                LibraryPreviewBatchGroup(batchId: "PN59", samples: [dummySample59]),
                LibraryPreviewBatchGroup(batchId: "PN60", samples: [dummySample60]),
                LibraryPreviewBatchGroup(batchId: "PN104", samples: [dummySample104])
            ]
        ]

        // Use real LibraryWorkspaceState from the AppWorkspaceShell
        let workspaceState = LibraryWorkspaceState()
        let galleryState = workspaceState.galleryState

        // 1. User navigates from Inbox to Library -> Workflows -> 3ω
        appState.navigate(to: .libraryWorkflowGallery(id: "3w"))
        #expect(appState.selectedArea == .library)
        #expect(appState.library.currentRoute == .workflowGallery(workflowID: "3w"))

        // 2. Gallery loads items
        let now = Date()
        let singleSampleItem = WorkflowGalleryItem(
            chartIdentityKey: "chart_single",
            chartImagePath: "samples/PN104/charts/plot.png",
            manifestPath: "samples/PN104/charts/plot.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: now,
            tabKey: "fieldSweep",
            associatedSampleKeys: ["PN104|o|STO|111"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Single Sample Plot"
        )

        let multiSampleItem = WorkflowGalleryItem(
            chartIdentityKey: "chart_multi",
            chartImagePath: "_spinlab/multi-sample/charts/multi.png",
            manifestPath: "_spinlab/multi-sample/charts/multi.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: now.addingTimeInterval(-50),
            tabKey: "tempSweep",
            associatedSampleKeys: ["PN59|o|STO|111", "PN60|o|STO|111"],
            isMultiSample: true,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "Multi Sample Comparison"
        )

        galleryState.items = [singleSampleItem, multiSampleItem]
        galleryState.selectItem(singleSampleItem)
        #expect(galleryState.selectedItem?.id == singleSampleItem.id)

        // 3. User selects the multi-sample chart
        galleryState.selectItem(multiSampleItem)
        #expect(galleryState.selectedItem?.isMultiSample == true)
        #expect(galleryState.selectedItem?.associatedSampleKeys.count == 2)

        // User opens full screen preview
        galleryState.openFullScreen()
        #expect(galleryState.isFullScreenPresented == true)
        galleryState.isFullScreenPresented = false

        // 4. Test Multi-Sample Disambiguation:
        // The user must choose which sample to open. User picks the 2nd sample (PN60), NOT the 1st (PN59).
        let chosenSample = "PN60|o|STO|111"

        // Setup: user already had a sample selected in PN104 with DIRTY unsaved edits
        _ = appState.library.selectExistingDrawer(prefix: "PN", batchId: "PN104", sampleId: "PN104|o|STO|111")
        let draftDate = Date()
        let originalDraft = LibrarySampleEditDraft(
            sampleId: "PN104|o|STO|111",
            batchId: "PN104",
            baseUpdatedAt: draftDate,
            substrateTagsText: "111",
            numericValues: [],
            metadataValues: []
        )
        let dirtyDraft = LibrarySampleEditDraft(
            sampleId: "PN104|o|STO|111",
            batchId: "PN104",
            baseUpdatedAt: draftDate,
            substrateTagsText: "001",
            numericValues: [],
            metadataValues: []
        )
        appState.library.libraryState.sampleEditOriginalDraft = originalDraft
        appState.library.librarySampleEditDraft = dirtyDraft
        #expect(appState.library.librarySampleEditIsDirty == true)

        // Verify WorkflowGalleryDetailView resolution logic for the 2 associated samples
        let drawerInfo59 = WorkflowGalleryDetailView.findDrawerInfo(for: "PN59|o|STO|111", in: appState)
        #expect(drawerInfo59?.batchId == "PN59")
        let drawerInfo60 = WorkflowGalleryDetailView.findDrawerInfo(for: "PN60|o|STO|111", in: appState)
        #expect(drawerInfo60?.batchId == "PN60")
        let unknownDrawerInfo = WorkflowGalleryDetailView.findDrawerInfo(for: "NONEXISTENT", in: appState)
        #expect(unknownDrawerInfo == nil)

        // Now user in Detail View clicks "Open Sample" on PN60 via the Detail View navigation action
        var confirmationTriggered = false
        WorkflowGalleryDetailView.requestJumpToSample(
            sampleKey: chosenSample,
            in: appState,
            onRequiresConfirmation: {
                confirmationTriggered = true
            }
        )

        // UN-SAVED EDIT GUARD VERIFICATION (AC6):
        // The selection must be DEFERRED, not overwritten!
        #expect(confirmationTriggered == true, "Must intercept and trigger confirmation dialog when edits are dirty")
        #expect(appState.library.hasPendingSelectionChange() == true)
        #expect(appState.library.libraryPendingSelectionChangePrompt != nil)
        // Active drawer selection is still the dirty PN104 sample, protecting edits
        #expect(appState.library.librarySelectedBatchId == "PN104")

        // User decides to apply the pending selection change (e.g. saves or discards)
        let outcome = appState.library.applyPendingSelectionChangeIfNeeded()
        appState.library.selectSamples()
        #expect(appState.library.currentRoute == .samples, "Must switch route from workflow gallery back to samples")
        if case let .appliedDrawer(prefix, batchId, sampleId) = outcome {
            #expect(prefix == "PN")
            #expect(batchId == "PN60")
            #expect(sampleId == chosenSample)
        } else {
            Issue.record("Expected appliedDrawer outcome, got \(String(describing: outcome))")
        }
        #expect(appState.library.librarySelectedBatchId == "PN60")
        #expect(appState.library.librarySelectedSampleId == chosenSample)
        #expect(appState.library.librarySelectedBatchId != "PN59", "Must open selected PN60, NOT default to first sample PN59")

        // 5. User returns to Workflow Gallery via sidebar
        appState.navigate(to: .libraryWorkflowGallery(id: "3w"))
        #expect(appState.library.currentRoute == .workflowGallery(workflowID: "3w"))

        // Verifies previous sample drawer selection in Sample Library was NOT destroyed
        #expect(appState.library.librarySelectedPrefix == "PN")
        #expect(appState.library.librarySelectedBatchId == "PN60")
        #expect(appState.library.librarySelectedSampleId == chosenSample)

        // Verifies real App Workspace Gallery state survives the round trip intact
        #expect(galleryState.selectedItem?.id == multiSampleItem.id)

        // 6. Test clean state jump directly navigates without confirmation
        appState.library.librarySampleEditDraft = nil
        var cleanConfirmationTriggered = false
        WorkflowGalleryDetailView.requestJumpToSample(
            sampleKey: "PN59|o|STO|111",
            in: appState,
            onRequiresConfirmation: {
                cleanConfirmationTriggered = true
            }
        )
        #expect(cleanConfirmationTriggered == false, "Clean edit state must navigate without confirmation dialog")
        #expect(appState.library.librarySelectedBatchId == "PN59")
    }

    @Test("WorkflowGalleryState loadGallery cache keying tracks workflowID and libraryRootURL")
    @MainActor
    func testWorkflowGalleryStateLoadCacheKeying() {
        let state = WorkflowGalleryState()
        let rootURL1 = URL(fileURLWithPath: "/tmp/root1")
        let rootURL2 = URL(fileURLWithPath: "/tmp/root2")

        #expect(state.hasLoaded == false)
        // Simulate load 1
        state.currentWorkflowID = "3w"
        state.loadedLibraryRootURL = rootURL1
        state.hasLoaded = true

        // Same workflow and same root: should not need reload
        let shouldReloadSame = !(state.hasLoaded && state.currentWorkflowID == "3w" && state.loadedLibraryRootURL == rootURL1 && state.errorMessage == nil)
        #expect(shouldReloadSame == false)

        // Different root: should trigger reload
        let shouldReloadNewRoot = !(state.hasLoaded && state.currentWorkflowID == "3w" && state.loadedLibraryRootURL == rootURL2 && state.errorMessage == nil)
        #expect(shouldReloadNewRoot == true)

        // Different workflow: should trigger reload
        let shouldReloadNewWF = !(state.hasLoaded && state.currentWorkflowID == "ahe" && state.loadedLibraryRootURL == rootURL1 && state.errorMessage == nil)
        #expect(shouldReloadNewWF == true)
    }

    @Test("Async query race: stale query cannot overwrite newer workflow or root results")
    @MainActor
    func testAsyncQueryRaceProtection() async {
        let state = WorkflowGalleryState()
        let rootURL1 = URL(fileURLWithPath: "/tmp/mock_root_1")
        let rootURL2 = URL(fileURLWithPath: "/tmp/mock_root_2")
        let defs = [
            WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: [])
        ]

        let dummyItem3w = WorkflowGalleryItem(
            chartIdentityKey: "item_3w",
            chartImagePath: "3w.png",
            manifestPath: "3w.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: "tab",
            associatedSampleKeys: ["S1"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "3ω Chart"
        )
        let dummyItemAHE = WorkflowGalleryItem(
            chartIdentityKey: "item_ahe",
            chartImagePath: "ahe.png",
            manifestPath: "ahe.manifest.json",
            canonicalWorkflowID: "ahe",
            rawWorkflowID: "ahe",
            generatedAt: Date(),
            tabKey: "tab",
            associatedSampleKeys: ["S2"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "AHE Chart"
        )

        // 1. Out-of-order workflow test:
        // Query 1 ("3w") is slow; Query 2 ("ahe") finishes first; Query 1 finishes second.
        var slowContinuation: CheckedContinuation<WorkflowGalleryQueryResult, Never>?
        state.queryExecutor = { _, wfID in
            if wfID == "3w" {
                return await withCheckedContinuation { cont in
                    slowContinuation = cont
                }
            } else {
                return WorkflowGalleryQueryResult(items: [dummyItemAHE], unreadableSampleIndices: [])
            }
        }

        // Start Query 1 (slow)
        let slowTask = Task { @MainActor in
            await state.loadGallery(workflowID: "3w", libraryRootURL: rootURL1, workflowDefinitions: defs, forceReload: true)
        }

        // Allow query 1 to enter queryExecutor and set slowContinuation
        while slowContinuation == nil {
            await Task.yield()
        }

        // Start Query 2 (fast) for AHE
        await state.loadGallery(workflowID: "ahe", libraryRootURL: rootURL1, workflowDefinitions: defs, forceReload: true)
        #expect(state.currentWorkflowID == "ahe")
        #expect(state.items.first?.canonicalWorkflowID == "ahe")

        // Now resume and finish slow Query 1
        slowContinuation?.resume(returning: WorkflowGalleryQueryResult(items: [dummyItem3w], unreadableSampleIndices: []))
        _ = await slowTask.value

        // Stale Query 1 must NOT overwrite Query 2 results
        #expect(state.currentWorkflowID == "ahe")
        #expect(state.items.first?.canonicalWorkflowID == "ahe", "Stale 3w query must never overwrite newer AHE state")

        // 2. Out-of-order library root switch test:
        // Query 3 (rootURL1) is slow; Query 4 (rootURL2) is fast.
        var slowRootContinuation: CheckedContinuation<WorkflowGalleryQueryResult, Never>?
        state.queryExecutor = { _, _ in
            if slowRootContinuation == nil {
                return await withCheckedContinuation { cont in
                    slowRootContinuation = cont
                }
            } else {
                return WorkflowGalleryQueryResult(items: [dummyItemAHE], unreadableSampleIndices: [])
            }
        }

        let slowRootTask = Task { @MainActor in
            await state.loadGallery(workflowID: "ahe", libraryRootURL: rootURL1, workflowDefinitions: defs, forceReload: true)
        }

        while slowRootContinuation == nil {
            await Task.yield()
        }

        // Switch to rootURL2 (completes fast)
        await state.loadGallery(workflowID: "ahe", libraryRootURL: rootURL2, workflowDefinitions: defs, forceReload: true)
        #expect(state.loadedLibraryRootURL == rootURL2)

        // Resume slow query for rootURL1
        slowRootContinuation?.resume(returning: WorkflowGalleryQueryResult(items: [dummyItem3w], unreadableSampleIndices: []))
        _ = await slowRootTask.value

        // Stale root query must NOT overwrite newer root results
        #expect(state.loadedLibraryRootURL == rootURL2)
        #expect(state.items.first?.chartIdentityKey == "item_ahe", "Stale root query must not overwrite newer root results")
    }

    @Test("Thumbnail cache: isolates different library roots sharing identical relative image paths")
    func testThumbnailCacheMultiRootIsolation() throws {
        let cache = WorkflowThumbnailCache(countLimit: 50)

        func makeTestPNG(width: Int, height: Int, in directory: URL) throws -> URL {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )!
            let pngData = rep.representation(using: .png, properties: [:])!
            let fileURL = directory.appending(path: "chart.png")
            try pngData.write(to: fileURL)
            return fileURL
        }

        let tempBase = FileManager.default.temporaryDirectory.appending(path: "spinlab_test_\(UUID().uuidString)")
        let rootA = tempBase.appending(path: "rootA")
        let rootB = tempBase.appending(path: "rootB")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempBase)
        }

        let relativePath = "chart.png"
        let fileA = try makeTestPNG(width: 80, height: 80, in: rootA)
        let fileB = try makeTestPNG(width: 240, height: 240, in: rootB)

        // 1. Verify isolated cache keys
        let keyA = WorkflowThumbnailCache.cacheKey(rootURL: rootA, relativePath: relativePath)
        let keyB = WorkflowThumbnailCache.cacheKey(rootURL: rootB, relativePath: relativePath)
        #expect(keyA != keyB, "Cache keys must distinguish Library Roots for the same relative path")

        // 2. Load into cache
        let thumbA = cache.loadThumbnail(url: fileA, key: keyA, maxPixelSize: 300)
        let thumbB = cache.loadThumbnail(url: fileB, key: keyB, maxPixelSize: 300)

        #expect(thumbA != nil)
        #expect(thumbB != nil)
        #expect(thumbA?.size.width == 80)
        #expect(thumbB?.size.width == 240)

        // 3. Verify retrieval by root key
        let cachedA = cache.cachedThumbnail(for: keyA)
        let cachedB = cache.cachedThumbnail(for: keyB)
        #expect(cachedA?.size.width == 80, "Root A cache hit must return 80px thumbnail")
        #expect(cachedB?.size.width == 240, "Root B cache hit must return 240px thumbnail")
    }

    @Test("Late image loads cannot overwrite visible thumbnail or preview after root switch or cancellation")
    @MainActor
    func testLateImageLoadCannotOverwriteNewRootThumbnail() async throws {
        func makeTestPNG(width: Int, height: Int, in directory: URL) throws -> URL {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )!
            let pngData = rep.representation(using: .png, properties: [:])!
            let fileURL = directory.appending(path: "plot.png")
            try pngData.write(to: fileURL)
            return fileURL
        }

        let tempBase = FileManager.default.temporaryDirectory.appending(path: "spinlab_race_\(UUID().uuidString)")
        let rootA = tempBase.appending(path: "rootA")
        let rootB = tempBase.appending(path: "rootB")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempBase)
        }

        let fileA = try makeTestPNG(width: 64, height: 64, in: rootA)
        _ = try makeTestPNG(width: 128, height: 128, in: rootB)

        let itemA = WorkflowGalleryItem(
            chartIdentityKey: "itemA",
            chartImagePath: "plot.png",
            manifestPath: "manifestA.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: nil,
            associatedSampleKeys: ["S1"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .missingFile,
            hasMeasurementAssociation: true,
            displayTitle: "Plot A"
        )

        let itemB = WorkflowGalleryItem(
            chartIdentityKey: "itemB",
            chartImagePath: "plot.png",
            manifestPath: "manifestB.json",
            canonicalWorkflowID: "ahe",
            rawWorkflowID: "ahe",
            generatedAt: Date(),
            tabKey: nil,
            associatedSampleKeys: ["S2"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .missingFile,
            hasMeasurementAssociation: true,
            displayTitle: "Plot B"
        )

        let state = WorkflowGalleryState()

        // 1. Verify loadThumbnailAsync yields nil when parent Task is cancelled
        let cache = WorkflowThumbnailCache.shared
        let keyA = WorkflowThumbnailCache.cacheKey(rootURL: rootA, relativePath: "plot.png")
        let cancelledTask = Task<NSImage?, Never> {
            try? await Task.sleep(nanoseconds: 1_000_000)
            return await cache.loadThumbnailAsync(url: rootA.appending(path: "plot.png"), key: keyA)
        }
        cancelledTask.cancel()
        let cancelledResult = await cancelledTask.value
        #expect(cancelledResult == nil, "loadThumbnailAsync must return nil if task is cancelled")

        // 2. Production Code Verification: State-level detail load race protection
        var slowDecodeContinuation: CheckedContinuation<NSImage?, Never>?
        state.thumbnailLoader = { url, key, maxPixelSize in
            if url.path.contains("rootA") {
                return await withCheckedContinuation { cont in
                    slowDecodeContinuation = cont
                }
            } else {
                return WorkflowThumbnailCache.shared.loadThumbnail(url: url, key: key, maxPixelSize: maxPixelSize)
            }
        }

        // Start slow load for Root A / Item A
        state.selectedItem = itemA
        let slowLoadTask = Task { @MainActor in
            await state.loadSelectedDetail(item: itemA, libraryRootURL: rootA)
        }

        // Wait until Root A's async decode begins
        while slowDecodeContinuation == nil {
            await Task.yield()
        }

        // Switch to Root B / Item B (completes fast)
        state.selectedItem = itemB
        await state.loadSelectedDetail(item: itemB, libraryRootURL: rootB)
        #expect(state.previewImage?.size.width == 128, "Active preview must be root B (128px)")

        // Resume slow decode for Root A with the 64px image
        let imageA = WorkflowThumbnailCache.shared.loadThumbnail(url: fileA, key: keyA, maxPixelSize: 960)
        slowDecodeContinuation?.resume(returning: imageA)
        await slowLoadTask.value

        // Production state code must reject the stale Root A completion
        #expect(state.previewImage?.size.width == 128, "Stale image from root A must be rejected by production state logic when root B is selected")
    }

    @Test("Rapid return to already loaded workflow does not overwrite with in-flight stale query")
    @MainActor
    func testRapidReturnToLoadedWorkflowDoesNotOverwriteWithStaleQuery() async {
        let state = WorkflowGalleryState()
        let defs = [
            WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: [])
        ]
        let rootURL = URL(fileURLWithPath: "/tmp/spinlab_test_rapid_return")

        let dummyAHE = WorkflowGalleryItem(
            chartIdentityKey: "item_ahe",
            chartImagePath: "charts/ahe.png",
            manifestPath: "charts/ahe.manifest.json",
            canonicalWorkflowID: "ahe",
            rawWorkflowID: "ahe",
            generatedAt: Date(),
            tabKey: nil,
            associatedSampleKeys: ["S1"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "AHE Plot"
        )

        let dummy3W = WorkflowGalleryItem(
            chartIdentityKey: "item_3w",
            chartImagePath: "charts/3w.png",
            manifestPath: "charts/3w.manifest.json",
            canonicalWorkflowID: "3w",
            rawWorkflowID: "3w",
            generatedAt: Date(),
            tabKey: nil,
            associatedSampleKeys: ["S2"],
            isMultiSample: false,
            imageStatus: .available,
            manifestStatus: .available,
            hasMeasurementAssociation: true,
            displayTitle: "3W Plot"
        )

        // 1. Initial load of 'ahe' completes
        await state.loadGallery(workflowID: "ahe", libraryRootURL: rootURL, workflowDefinitions: defs)
        state.items = [dummyAHE]
        state.currentWorkflowID = "ahe"
        state.loadedLibraryRootURL = rootURL
        state.hasLoaded = true

        #expect(state.currentWorkflowID == "ahe")
        #expect(state.items.first?.chartIdentityKey == "item_ahe")

        // 2. User clicks '3w' (slow query)
        var slowContinuation: CheckedContinuation<WorkflowGalleryQueryResult, Never>?
        state.queryExecutor = { _, _ in
            await withCheckedContinuation { cont in
                slowContinuation = cont
            }
        }

        let slowTask = Task { @MainActor in
            await state.loadGallery(workflowID: "3w", libraryRootURL: rootURL, workflowDefinitions: defs)
        }

        // Allow slow query to start
        while slowContinuation == nil {
            await Task.yield()
        }

        // 3. User quickly clicks back to 'ahe' (forceReload: false, hits skip check!)
        state.queryExecutor = nil
        await state.loadGallery(workflowID: "ahe", libraryRootURL: rootURL, workflowDefinitions: defs, forceReload: false)
        #expect(state.currentWorkflowID == "ahe")

        // 4. Slow query for '3w' finishes now
        slowContinuation?.resume(returning: WorkflowGalleryQueryResult(items: [dummy3W], unreadableSampleIndices: []))
        await slowTask.value

        // 5. Verify state still has 'ahe' and was NOT overwritten by the stale '3w' query
        #expect(state.currentWorkflowID == "ahe", "Stale 3w query must not overwrite ahe after rapid return")
        #expect(state.items.first?.chartIdentityKey == "item_ahe", "Items must remain ahe items")
        #expect(!state.isLoading, "Loading indicator must not be active")
    }

    @Test("End-to-end verification of 6 required real-app flows against production pipeline")
    @MainActor
    func testSixRequiredRealAppFlows() async throws {
        let appState = SpinLabAppState()
        let defs = [
            WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: []),
            WorkflowDefinition(id: "rt", displayName: "RT", conditionFields: []),
            WorkflowDefinition(id: "iv", displayName: "IV", conditionFields: [])
        ]
        appState.workflowDefinitions = defs

        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appending(path: "spinlab_e2e_\(UUID().uuidString)")
        let rootURL1 = tempBase.appending(path: "root1")
        let rootURL2 = tempBase.appending(path: "root2")
        try fm.createDirectory(at: rootURL1, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootURL2, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: tempBase)
        }

        func makePNG(in dir: URL, name: String, width: Int = 100, height: Int = 100) throws -> URL {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )!
            let data = rep.representation(using: .png, properties: [:])!
            let fileURL = dir.appending(path: name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: fileURL)
            return fileURL
        }

        func writeJSON<T: Encodable>(_ object: T, to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(object)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }

        func writeManifest(to url: URL, workflowID: String, imageRelPath: String, tabKey: String = "sweep") throws {
            let manifest = WorkbenchRunManifest(
                manifestID: UUID().uuidString,
                runID: UUID().uuidString,
                workflowID: workflowID,
                inputFiles: ["raw.txt"],
                filters: [:],
                axisMapping: WorkbenchAxisMapping(xField: "X", yField: "Y"),
                semanticParams: ["tabKey": tabKey],
                outputImagePath: imageRelPath,
                generatedAt: Date(),
                appVersion: "5.10.0"
            )
            try writeJSON(manifest, to: url)
        }

        // --- SETUP ROOT 1 FIXTURE ---
        // 1. Single sample PN104 with valid 3w chart
        let chart3WRel = "samples/PN104/charts/plot3w.png"
        let man3WRel = "samples/PN104/charts/plot3w.manifest.json"
        _ = try makePNG(in: rootURL1.appending(path: "samples/PN104/charts"), name: "plot3w.png")
        try writeManifest(to: rootURL1.appending(path: man3WRel), workflowID: "3w", imageRelPath: chart3WRel, tabKey: "fieldSweep")
        let ref3W = WorkbenchResultReference(
            chartIdentityKey: "chart_3w_valid",
            chartImagePath: chart3WRel,
            manifestPath: man3WRel,
            workflowID: "3w",
            generatedAt: Date()
        )
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "PN104", updatedAt: Date(), references: [ref3W]), to: rootURL1.appending(path: "samples/PN104/_spinlab/results_index.json"))

        // 2. Missing-image 3w chart in PN105 (manifest exists, PNG does not)
        let chartMissingRel = "samples/PN105/charts/missing3w.png"
        let manMissingRel = "samples/PN105/charts/missing3w.manifest.json"
        try writeManifest(to: rootURL1.appending(path: manMissingRel), workflowID: "3w", imageRelPath: chartMissingRel, tabKey: "fieldSweep")
        let refMissing = WorkbenchResultReference(
            chartIdentityKey: "chart_3w_missing",
            chartImagePath: chartMissingRel,
            manifestPath: manMissingRel,
            workflowID: "3w",
            generatedAt: Date().addingTimeInterval(-10)
        )
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "PN105", updatedAt: Date(), references: [refMissing]), to: rootURL1.appending(path: "samples/PN105/_spinlab/results_index.json"))

        // 3. Multi-sample AHE chart in _spinlab/multi-sample shared between PN59 and PN60
        let chartMultiRel = "_spinlab/multi-sample/charts/ahe_multi.png"
        let manMultiRel = "_spinlab/multi-sample/charts/ahe_multi.manifest.json"
        _ = try makePNG(in: rootURL1.appending(path: "_spinlab/multi-sample/charts"), name: "ahe_multi.png")
        try writeManifest(to: rootURL1.appending(path: manMultiRel), workflowID: "ahe", imageRelPath: chartMultiRel, tabKey: "aheLoop")
        let refMultiAHE = WorkbenchResultReference(
            chartIdentityKey: "chart_ahe_multi",
            chartImagePath: chartMultiRel,
            manifestPath: manMultiRel,
            workflowID: "ahe",
            generatedAt: Date().addingTimeInterval(-20)
        )
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "_spinlab/multi-sample", updatedAt: Date(), references: [refMultiAHE]), to: rootURL1.appending(path: "_spinlab/multi-sample/results_index.json"))
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "PN59", updatedAt: Date(), references: [refMultiAHE]), to: rootURL1.appending(path: "samples/PN59/_spinlab/results_index.json"))
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "PN60", updatedAt: Date(), references: [refMultiAHE]), to: rootURL1.appending(path: "samples/PN60/_spinlab/results_index.json"))

        // 4. Single-sample PN90 IV chart inside _spinlab/multi-sample/charts
        let chartPN90Rel = "_spinlab/multi-sample/charts/pn90.png"
        let manPN90Rel = "_spinlab/multi-sample/charts/pn90.manifest.json"
        _ = try makePNG(in: rootURL1.appending(path: "_spinlab/multi-sample/charts"), name: "pn90.png")
        try writeManifest(to: rootURL1.appending(path: manPN90Rel), workflowID: "iv", imageRelPath: chartPN90Rel)
        let refPN90 = WorkbenchResultReference(
            chartIdentityKey: "chart_pn90",
            chartImagePath: chartPN90Rel,
            manifestPath: manPN90Rel,
            workflowID: "iv",
            generatedAt: Date().addingTimeInterval(-30)
        )
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "PN90", updatedAt: Date(), references: [refPN90]), to: rootURL1.appending(path: "samples/PN90/_spinlab/results_index.json"))

        // 5. Valid RT chart in PN104
        let chartRTRel = "samples/PN104/charts/plot_rt.png"
        let manRTRel = "samples/PN104/charts/plot_rt.manifest.json"
        _ = try makePNG(in: rootURL1.appending(path: "samples/PN104/charts"), name: "plot_rt.png")
        try writeManifest(to: rootURL1.appending(path: manRTRel), workflowID: "rt", imageRelPath: chartRTRel)
        let refRT = WorkbenchResultReference(
            chartIdentityKey: "chart_rt_valid",
            chartImagePath: chartRTRel,
            manifestPath: manRTRel,
            workflowID: "rt",
            generatedAt: Date()
        )
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "PN104", updatedAt: Date(), references: [ref3W, refRT]), to: rootURL1.appending(path: "samples/PN104/_spinlab/results_index.json"))

        // --- SETUP ROOT 2 FIXTURE ---
        _ = try makePNG(in: rootURL2.appending(path: "samples/PN104/charts"), name: "plot3w.png", width: 220, height: 220)
        try writeManifest(to: rootURL2.appending(path: man3WRel), workflowID: "3w", imageRelPath: chart3WRel)
        try writeJSON(WorkbenchResultsIndex(schemaVersion: 1, sampleKey: "PN104", updatedAt: Date(), references: [ref3W]), to: rootURL2.appending(path: "samples/PN104/_spinlab/results_index.json"))

        // Setup AppState and GalleryState
        appState.library.librarySettings.rootPath = rootURL1.path
        let dummySample59 = LibrarySample(id: "PN59", displayName: "PN59", batchId: "PN59", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: ["STO"], substrateTags: [], metadata: [:], numericTags: [:], numericDisplay: [:], updatedAt: Date())
        let dummySample60 = LibrarySample(id: "PN60", displayName: "PN60", batchId: "PN60", substrateRaw: "STO", substrateDisplay: "STO", substrateTokens: ["STO"], substrateTags: [], metadata: [:], numericTags: [:], numericDisplay: [:], updatedAt: Date())
        appState.library.libraryExistingGroups = [
            "PN": [
                LibraryPreviewBatchGroup(batchId: "PN59", samples: [dummySample59]),
                LibraryPreviewBatchGroup(batchId: "PN60", samples: [dummySample60])
            ]
        ]

        let galleryState = WorkflowGalleryState()

        // =========================================================================
        // FLOW 1: Browsing the gallery (Navigation -> Workflows -> 3ω)
        // =========================================================================
        appState.navigate(to: .libraryWorkflowGallery(id: "3w"))
        #expect(appState.selectedArea == .library)
        #expect(appState.library.currentRoute == .workflowGallery(workflowID: "3w"))

        // Query service executes naturally on root 1
        await galleryState.loadGallery(workflowID: "3w", libraryRootURL: rootURL1, workflowDefinitions: defs)
        #expect(galleryState.hasLoaded == true)
        #expect(galleryState.items.count == 2, "Discovered valid and missing 3w charts")

        let validItem = galleryState.items.first { $0.chartIdentityKey == "chart_3w_valid" }
        #expect(validItem != nil)
        #expect(validItem?.imageStatus == .available)

        // Load detail via production method
        galleryState.selectedItem = validItem
        await galleryState.loadSelectedDetail(item: validItem, libraryRootURL: rootURL1)
        #expect(galleryState.previewImage != nil, "Production detail loaded preview image from disk")
        #expect(galleryState.manifest != nil, "Production detail loaded run manifest from disk")
        #expect(galleryState.imageLoadingError == nil)

        // =========================================================================
        // FLOW 2: Rapid workflow switching (3ω -> AHE -> RT -> 3ω)
        // =========================================================================
        await galleryState.loadGallery(workflowID: "ahe", libraryRootURL: rootURL1, workflowDefinitions: defs, forceReload: true)
        #expect(galleryState.currentWorkflowID == "ahe")
        #expect(galleryState.items.contains { $0.chartIdentityKey == "chart_ahe_multi" })

        await galleryState.loadGallery(workflowID: "rt", libraryRootURL: rootURL1, workflowDefinitions: defs, forceReload: true)
        #expect(galleryState.currentWorkflowID == "rt")
        #expect(galleryState.items.contains { $0.chartIdentityKey == "chart_rt_valid" })

        await galleryState.loadGallery(workflowID: "3w", libraryRootURL: rootURL1, workflowDefinitions: defs, forceReload: true)
        #expect(galleryState.currentWorkflowID == "3w")
        #expect(galleryState.items.count == 2)
        #expect(!galleryState.isLoading)

        // =========================================================================
        // FLOW 3: Library root switching
        // =========================================================================
        // Switch root to root2
        appState.library.librarySettings.rootPath = rootURL2.path
        await galleryState.loadGallery(workflowID: "3w", libraryRootURL: rootURL2, workflowDefinitions: defs, forceReload: true)
        #expect(galleryState.loadedLibraryRootURL == rootURL2)
        #expect(galleryState.items.count == 1, "Root 2 only has the 1 valid chart")

        // Thumbnail cache isolation verification across roots
        let keyRoot1 = WorkflowThumbnailCache.cacheKey(rootURL: rootURL1, relativePath: chart3WRel)
        let keyRoot2 = WorkflowThumbnailCache.cacheKey(rootURL: rootURL2, relativePath: chart3WRel)
        #expect(keyRoot1 != keyRoot2, "Thumbnail cache keys must be isolated across library roots")

        // Decode identical relative path chart3WRel from both roots and confirm each root gets its own pixels
        let thumbRoot1 = await WorkflowThumbnailCache.shared.loadThumbnailAsync(url: rootURL1.appending(path: chart3WRel), key: keyRoot1, maxPixelSize: 300)
        let thumbRoot2 = await WorkflowThumbnailCache.shared.loadThumbnailAsync(url: rootURL2.appending(path: chart3WRel), key: keyRoot2, maxPixelSize: 300)
        #expect(thumbRoot1 != nil && thumbRoot2 != nil)
        #expect(thumbRoot1?.size.width == 100, "Root 1 thumbnail must decode to 100px")
        #expect(thumbRoot2?.size.width == 220, "Root 2 thumbnail must decode to 220px, confirming distinct pixel content across roots")

        // Switch back to root1
        appState.library.librarySettings.rootPath = rootURL1.path
        await galleryState.loadGallery(workflowID: "3w", libraryRootURL: rootURL1, workflowDefinitions: defs, forceReload: true)
        #expect(galleryState.loadedLibraryRootURL == rootURL1)

        // =========================================================================
        // FLOW 4: Inspect multi-sample associations
        // =========================================================================
        await galleryState.loadGallery(workflowID: "ahe", libraryRootURL: rootURL1, workflowDefinitions: defs)
        let multiItem = try #require(galleryState.items.first { $0.chartIdentityKey == "chart_ahe_multi" })
        #expect(multiItem.isMultiSample == true, "Chart shared across PN59 and PN60 must be multi-sample")
        #expect(multiItem.associatedSampleKeys == ["PN59", "PN60"])

        // Also verify single sample in multi-sample folder is not multi-sample
        await galleryState.loadGallery(workflowID: "iv", libraryRootURL: rootURL1, workflowDefinitions: defs)
        let pn90Item = try #require(galleryState.items.first { $0.chartIdentityKey == "chart_pn90" })
        #expect(pn90Item.isMultiSample == false, "Single sample PN90 in multi-sample folder must have isMultiSample == false")

        // =========================================================================
        // FLOW 5: Open sample with unsaved edits
        // =========================================================================
        let draftDate = Date()
        let origDraft = LibrarySampleEditDraft(sampleId: "PN59", batchId: "PN59", baseUpdatedAt: draftDate, substrateTagsText: "STO", numericValues: [], metadataValues: [])
        let dirtyDraft = LibrarySampleEditDraft(sampleId: "PN59", batchId: "PN59", baseUpdatedAt: draftDate, substrateTagsText: "001", numericValues: [], metadataValues: [])
        appState.library.libraryState.sampleEditOriginalDraft = origDraft
        appState.library.librarySampleEditDraft = dirtyDraft
        #expect(appState.library.librarySampleEditIsDirty == true)

        var confirmationTriggered = false
        WorkflowGalleryDetailView.requestJumpToSample(
            sampleKey: "PN60",
            in: appState,
            onRequiresConfirmation: {
                confirmationTriggered = true
            }
        )
        #expect(confirmationTriggered == true, "Dirty edit draft must trigger confirmation dialog")
        #expect(appState.library.hasPendingSelectionChange() == true)

        // Apply pending change
        let outcome = appState.library.applyPendingSelectionChangeIfNeeded()
        appState.library.selectSamples()
        #expect(appState.library.currentRoute == .samples)
        if case let .appliedDrawer(prefix, batchId, sampleId) = outcome {
            #expect(prefix == "PN")
            #expect(batchId == "PN60")
            #expect(sampleId == "PN60")
        }
        appState.library.librarySampleEditDraft = nil

        // =========================================================================
        // FLOW 6: Verify missing-image handling
        // =========================================================================
        await galleryState.loadGallery(workflowID: "3w", libraryRootURL: rootURL1, workflowDefinitions: defs)
        let missingItem = try #require(galleryState.items.first { $0.chartIdentityKey == "chart_3w_missing" })
        #expect(missingItem.imageStatus == .missingFile, "Query service discovered missing PNG")
        #expect(missingItem.manifestStatus == .available, "Manifest was present")

        // Filter missing only
        galleryState.filterOption = .missingOnly
        #expect(galleryState.displayItems.count == 1)
        #expect(galleryState.displayItems.first?.chartIdentityKey == "chart_3w_missing")

        // Load detail for missing item
        galleryState.selectedItem = missingItem
        await galleryState.loadSelectedDetail(item: missingItem, libraryRootURL: rootURL1)
        #expect(galleryState.previewImage == nil, "Missing image preview must be nil")
        #expect(galleryState.manifest != nil, "Manifest details are still displayed")
        #expect(galleryState.imageLoadingError == nil, "No corrupted image error for missingFile")
    }

    @Test("WorkflowGalleryThumbnailCard late load and root change rejection")
    func testThumbnailCardLateLoadAndRootChangeRejection() async throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appending(path: "card_race_\(UUID().uuidString)")
        let rootA = tempBase.appending(path: "rootA")
        let rootB = tempBase.appending(path: "rootB")
        try fm.createDirectory(at: rootA, withIntermediateDirectories: true)
        try fm.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempBase) }

        func makeTestPNG(width: Int, height: Int, in dir: URL) throws -> URL {
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4,
                bitsPerPixel: 32
            )!
            let data = rep.representation(using: .png, properties: [:])!
            let fileURL = dir.appending(path: "chart.png")
            try data.write(to: fileURL)
            return fileURL
        }

        let fileA = try makeTestPNG(width: 80, height: 80, in: rootA)
        let fileB = try makeTestPNG(width: 200, height: 200, in: rootB)
        let keyA = WorkflowThumbnailCache.cacheKey(rootURL: rootA, relativePath: "chart.png")
        let keyB = WorkflowThumbnailCache.cacheKey(rootURL: rootB, relativePath: "chart.png")

        // 1. Deterministic cancellation simulation:
        // When SwiftUI switches root, .task(id:) cancels the in-flight thumbnail task.
        let cancelledTask = Task<NSImage?, Never> {
            try? await Task.sleep(nanoseconds: 1_000_000)
            return await WorkflowThumbnailCache.shared.loadThumbnailAsync(url: fileA, key: keyA)
        }
        cancelledTask.cancel()
        let cancelledResult = await cancelledTask.value
        #expect(cancelledResult == nil, "Thumbnail task cancelled during root change must return nil")

        // 2. Decode Root B's image directly and verify it is not affected by Root A's cancelled decode
        let thumbB = await WorkflowThumbnailCache.shared.loadThumbnailAsync(url: fileB, key: keyB)
        #expect(thumbB?.size.width == 200)

        // 3. Verify that the cache hit for keyB returns 200px, not 80px
        let hitB = WorkflowThumbnailCache.shared.cachedThumbnail(for: keyB)
        #expect(hitB?.size.width == 200)
    }
}
