import AppKit
import SwiftUI

struct WorkflowGalleryDetailView: View {
    @Environment(SpinLabAppState.self) private var appState
    let workflowID: String
    @Bindable var galleryState: WorkflowGalleryState

    @State private var manifest: WorkbenchRunManifest?
    @State private var manifestLoadingError: String?
    @State private var previewImage: NSImage?
    @State private var imageLoadingError: String?
    @State private var isShowingUnsavedEditConfirmation: Bool = false

    private var libraryRootURL: URL? {
        guard let rootPath = appState.library.librarySettings.rootPath, !rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: rootPath)
    }

    var body: some View {
        ScrollView(.vertical) {
            if let item = galleryState.selectedItem {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Image Preview & Full Screen Button
                    previewHeader(for: item)

                    Divider()

                    // 2. Sample Navigation Section (Single vs Multi-Sample)
                    associatedSamplesSection(for: item)

                    Divider()

                    // 3. Experimental Parameters & Manifest Details
                    experimentalParametersSection(for: item)

                    Divider()

                    // 4. Input Measurement Files
                    inputFilesSection(for: item)

                    Divider()

                    // 5. File System Paths
                    filePathsSection(for: item)
                }
                .padding(16)
            } else {
                ContentUnavailableView(
                    "No Chart Selected",
                    systemImage: "photo.badge.plus",
                    description: Text("Select a chart from the gallery to view provenance, parameters, and associated samples.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .task(id: "\(libraryRootURL?.path ?? "")::\(galleryState.selectedItem?.id ?? "")") {
            await loadSelectedDetail()
        }
        .onChange(of: libraryRootURL) { _, _ in
            previewImage = nil
            manifest = nil
            manifestLoadingError = nil
            imageLoadingError = nil
        }
        .confirmationDialog(
            "Unsaved Edits",
            isPresented: $isShowingUnsavedEditConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save and Switch") {
                appState.saveAndContinuePendingLibrarySelectionChange()
                appState.library.selectSamples()
            }
            Button("Discard and Switch", role: .destructive) {
                appState.discardAndContinuePendingLibrarySelectionChange()
                appState.library.selectSamples()
            }
            Button("Cancel", role: .cancel) {
                appState.library.cancelPendingSelectionChange()
            }
        } message: {
            Text(appState.library.libraryPendingSelectionChangePrompt ?? "You have unsaved sample edits. Save before switching selection?")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func previewHeader(for item: WorkflowGalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if item.imageStatus == .missingFile {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text("Image File Missing on Disk")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        Text("The chart manifest and sample index entries exist, but the .png file is missing.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let error = imageLoadingError {
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                        Text("Failed to Load Image")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            galleryState.openFullScreen()
                        }
                } else {
                    ZStack {
                        Color(nsColor: .controlBackgroundColor)
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Title and Full Screen Button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.headline)
                    Text("Workflow: \(item.canonicalWorkflowID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if item.imageStatus == .available {
                    Button {
                        galleryState.openFullScreen()
                    } label: {
                        Label("View Full Size", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private func associatedSamplesSection(for item: WorkflowGalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Associated Samples", systemImage: "tray.full")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if item.isMultiSample {
                    Text("Multi-Sample (\(item.associatedSampleKeys.count))")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            if item.associatedSampleKeys.count > 1 {
                Text("This chart compares multiple samples. Select a sample below to open it in the Sample Library:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ForEach(item.associatedSampleKeys, id: \.self) { sampleKey in
                        HStack {
                            Text(sampleKey)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            if let _ = findDrawerInfo(for: sampleKey) {
                                Button {
                                    jumpToSample(sampleKey: sampleKey)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("Open Sample")
                                        Image(systemName: "arrow.right.circle")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            } else {
                                Text("(No drawer in Library)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if let singleSample = item.associatedSampleKeys.first {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(singleSample)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                        Text(findDrawerInfo(for: singleSample) != nil ? "Single sample plot" : "Drawer not found in Library")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let _ = findDrawerInfo(for: singleSample) {
                        Button {
                            jumpToSample(sampleKey: singleSample)
                        } label: {
                            HStack(spacing: 4) {
                                Text("Open in Library")
                                Image(systemName: "arrow.right.circle")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text("No sample key recorded for this chart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func experimentalParametersSection(for item: WorkflowGalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Experimental Parameters", systemImage: "slider.horizontal.3")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let manifest {
                VStack(spacing: 6) {
                    DetailRow(label: "Generated At", value: formattedDateTime(manifest.generatedAt))
                    if let tab = item.tabKey, !tab.isEmpty {
                        DetailRow(label: "Tab / Mode", value: tab)
                    }
                    DetailRow(label: "SpinLab Version", value: manifest.appVersion.isEmpty ? "Unknown" : manifest.appVersion)

                    // Semantic Params
                    if !manifest.semanticParams.isEmpty {
                        ForEach(manifest.semanticParams.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                            DetailRow(label: key, value: val)
                        }
                    }

                    // Filters
                    if !manifest.filters.isEmpty {
                        ForEach(manifest.filters.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                            DetailRow(label: "Filter: \(key)", value: val)
                        }
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if manifestLoadingError != nil {
                Text("Manifest file not found or corrupted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func inputFilesSection(for item: WorkflowGalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Input Measurements", systemImage: "doc.text")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if !item.hasMeasurementAssociation {
                    Text("Unlinked in Index")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }

            if let manifest, !manifest.inputFiles.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(manifest.inputFiles, id: \.self) { file in
                        HStack(spacing: 6) {
                            Image(systemName: "doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(file)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(item.hasMeasurementAssociation ? "No input files recorded in manifest." : "Derived/composite plot without direct measurement file link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func filePathsSection(for item: WorkflowGalleryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Repository File Paths", systemImage: "folder")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chart PNG:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(item.chartImagePath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Manifest JSON:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(item.manifestPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Navigation Action

    private func jumpToSample(sampleKey: String) {
        Self.requestJumpToSample(
            sampleKey: sampleKey,
            in: appState,
            onRequiresConfirmation: {
                isShowingUnsavedEditConfirmation = true
            }
        )
    }

    private func findDrawerInfo(for sampleKey: String) -> (prefix: String, batchId: String, sampleId: String)? {
        Self.findDrawerInfo(for: sampleKey, in: appState)
    }

    static func requestJumpToSample(
        sampleKey: String,
        in appState: SpinLabAppState,
        onRequiresConfirmation: () -> Void
    ) {
        // Look up drawer info strictly from existing groups
        guard let drawerInfo = findDrawerInfo(for: sampleKey, in: appState) else {
            // Incomplete provenance: never invent a fictitious drawer
            return
        }

        if appState.library.librarySampleEditIsDirty {
            // Guard dirty edit: defer selection change and trigger confirmation dialog
            _ = appState.library.selectExistingDrawer(
                prefix: drawerInfo.prefix,
                batchId: drawerInfo.batchId,
                sampleId: drawerInfo.sampleId
            )
            onRequiresConfirmation()
        } else {
            // Clean edit state: navigate directly
            appState.navigate(to: .libraryDrawer(
                prefix: drawerInfo.prefix,
                batchId: drawerInfo.batchId,
                sampleId: drawerInfo.sampleId
            ))
        }
    }

    static func findDrawerInfo(for sampleKey: String, in appState: SpinLabAppState) -> (prefix: String, batchId: String, sampleId: String)? {
        for (prefix, groups) in appState.library.libraryExistingGroups {
            for group in groups {
                if let sample = group.samples.first(where: { $0.id == sampleKey || $0.displayName == sampleKey }) {
                    return (prefix: prefix, batchId: group.batchId, sampleId: sample.id)
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func loadSelectedDetail() async {
        guard let item = galleryState.selectedItem else {
            manifest = nil
            previewImage = nil
            manifestLoadingError = nil
            imageLoadingError = nil
            return
        }

        guard let rootURL = libraryRootURL else {
            manifest = nil
            previewImage = nil
            manifestLoadingError = "Library root not configured"
            imageLoadingError = "Library root not configured"
            return
        }

        // Load preview image
        if item.imageStatus == .available {
            let requestedRoot = rootURL
            let requestedItemID = item.id
            let cacheKey = WorkflowThumbnailCache.cacheKey(rootURL: rootURL, relativePath: item.chartImagePath)
            let fullURL = rootURL.appending(path: item.chartImagePath)
            let image = await WorkflowThumbnailCache.shared.loadThumbnailAsync(
                url: fullURL,
                key: cacheKey,
                maxPixelSize: 960
            )

            // Late image load protection: ensure library root and selected item have not changed
            guard self.libraryRootURL == requestedRoot, self.galleryState.selectedItem?.id == requestedItemID else {
                return
            }

            self.previewImage = image
            if image == nil {
                self.imageLoadingError = "Image file is unreadable or corrupt on disk."
            } else {
                self.imageLoadingError = nil
            }
        } else if item.imageStatus == .missingFile {
            self.previewImage = nil
            self.imageLoadingError = nil
        } else {
            self.previewImage = nil
            self.imageLoadingError = "Image file is damaged or unreadable."
        }

        // Load manifest
        let manifestURL = rootURL.appending(path: item.manifestPath)
        if FileManager.default.fileExists(atPath: manifestURL.path),
           let data = try? Data(contentsOf: manifestURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(WorkbenchRunManifest.self, from: data) {
                self.manifest = decoded
                self.manifestLoadingError = nil
            } else {
                self.manifest = nil
                self.manifestLoadingError = "Corrupted manifest"
            }
        } else {
            self.manifest = nil
            self.manifestLoadingError = "Manifest not found"
        }
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
            Spacer()
        }
    }
}
