import AppKit
import SwiftUI

/// Popover panel shown on hover over a Measurements Done row.
/// Displays thumbnails of all charts that used the hovered measurement file.
///
/// Designed to be extended: add `onTitleEdit`, `onOpenInWorkbench`, etc. as needed.
/// Images are lazy-loaded in the background; empty state is shown when no plots exist.
struct MeasurementPlotPreviewPanel: View {
    let references: [WorkbenchResultReference]
    let libraryRootURL: URL?
    var onDelete: ((WorkbenchResultReference) -> Void)? = nil
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onDialogActiveChanged: ((Bool) -> Void)? = nil

    @State private var loadedImages: [String: NSImage] = [:]
    // v4.1.5.2 — delete chart confirmation
    @State private var pendingDeleteChart: WorkbenchResultReference? = nil
    @State private var isShowingDeleteChartConfirm = false

    var body: some View {
        Group {
            if references.isEmpty {
                Text("No plots yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 200, height: 80)
                    .padding()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(references, id: \.chartIdentityKey) { ref in
                            plotThumbnail(for: ref)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 340, height: min(CGFloat(references.count) * 200 + 16, 420))
            }
        }
        .onAppear {
            for ref in references { loadImageIfNeeded(ref) }
        }
        .onHover { isHovering in
            onHoverChanged?(isHovering)
        }
        .onChange(of: isShowingDeleteChartConfirm) { _, active in
            onDialogActiveChanged?(active)
        }
        .confirmationDialog(
            "Delete Chart?",
            isPresented: $isShowingDeleteChartConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Chart", role: .destructive) {
                if let ref = pendingDeleteChart {
                    onDelete?(ref)
                }
                pendingDeleteChart = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteChart = nil
            }
        } message: {
            Text("This will permanently delete the chart image and its manifest. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func plotThumbnail(for ref: WorkbenchResultReference) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = loadedImages[ref.chartIdentityKey] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 140)
                    .overlay(ProgressView().scaleEffect(0.7))
            }

            if onDelete != nil {
                Button {
                    pendingDeleteChart = ref
                    isShowingDeleteChartConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete chart")
                .padding(4)
                .help("Delete this chart and its files")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openChart(ref) }
        .help("Click to open in viewer")
    }

    private func openChart(_ ref: WorkbenchResultReference) {
        guard let rootURL = libraryRootURL else { return }
        let resolver = LibraryPathResolver(libraryRootURL: rootURL)
        guard let chartURL = try? resolver.absoluteURL(for: ref.chartImagePath) else { return }
        NSWorkspace.shared.open(chartURL)
    }

    private func loadImageIfNeeded(_ ref: WorkbenchResultReference) {
        guard loadedImages[ref.chartIdentityKey] == nil,
              let rootURL = libraryRootURL else { return }
        let chartPath = ref.chartImagePath
        let key = ref.chartIdentityKey
        Task {
            let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                let resolver = LibraryPathResolver(libraryRootURL: rootURL)
                guard let url = try? resolver.absoluteURL(for: chartPath) else { return nil }
                return NSImage(contentsOf: url)
            }.value
            if let image { loadedImages[key] = image }
        }
    }
}
