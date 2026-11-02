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

    @Test("WorkflowThumbnailCache downsamples image and enforces limits")
    func testWorkflowThumbnailCache() throws {
        let cache = WorkflowThumbnailCache()

        // Create a test 1000x1000 bitmap image
        let width = 1000
        let height = 1000
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

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            return
        }

        let tempURL = FileManager.default.temporaryDirectory.appending(path: "test_downsample_\(UUID().uuidString).png")
        try pngData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let thumbnail = cache.loadThumbnail(url: tempURL, key: tempURL.path, maxPixelSize: 300)
        #expect(thumbnail != nil)
        if let thumb = thumbnail {
            #expect(thumb.size.width <= 300)
            #expect(thumb.size.height <= 300)
        }

        // Cached lookup
        let cached = cache.cachedThumbnail(for: tempURL.path)
        #expect(cached != nil)
    }

    @Test("Full user journey: Navigation -> Gallery -> Select Chart -> Jump to Sample -> Return to Gallery")
    @MainActor
    func testFullUserJourneyNavigationAndSampleJump() {
        let appState = SpinLabAppState()
        appState.workflowDefinitions = [
            WorkflowDefinition(id: "3w", displayName: "3ω", conditionFields: []),
            WorkflowDefinition(id: "ahe", displayName: "AHE", conditionFields: []),
            WorkflowDefinition(id: "xy", displayName: "XY Rotation", conditionFields: [])
        ]

        let galleryState = WorkflowGalleryState()

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
            associatedSampleKeys: ["PN59|o|STO|111", "PN60|o|STO|111", "PN61|o|STO|111"],
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
        #expect(galleryState.selectedItem?.associatedSampleKeys.count == 3)

        // User opens full screen preview
        galleryState.openFullScreen()
        #expect(galleryState.isFullScreenPresented == true)
        galleryState.isFullScreenPresented = false

        // 4. User selects a specific target sample (PN60) to jump to
        let targetSample = "PN60|o|STO|111"
        appState.navigate(to: .libraryDrawer(prefix: "PN", batchId: "PN60", sampleId: targetSample))

        // Verifies user is now in Sample Library viewing PN60
        #expect(appState.selectedArea == .library)
        #expect(appState.library.currentRoute == .samples)
        #expect(appState.library.librarySelectedPrefix == "PN")
        #expect(appState.library.librarySelectedBatchId == "PN60")
        #expect(appState.library.librarySelectedSampleId == targetSample)

        // 5. User returns to Workflow Gallery via sidebar
        appState.navigate(to: .libraryWorkflowGallery(id: "3w"))
        #expect(appState.library.currentRoute == .workflowGallery(workflowID: "3w"))

        // Verifies previous sample drawer selection in Sample Library was NOT destroyed
        #expect(appState.library.librarySelectedPrefix == "PN")
        #expect(appState.library.librarySelectedBatchId == "PN60")
        #expect(appState.library.librarySelectedSampleId == targetSample)

        // Verifies Gallery's own selection state remains intact
        #expect(galleryState.selectedItem?.id == multiSampleItem.id)
    }
}
