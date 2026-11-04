import AppKit
import SwiftUI

struct WorkflowGalleryFullScreenView: View {
    let item: WorkflowGalleryItem
    let libraryRootURL: URL
    let onDismiss: () -> Void

    @State private var fullImage: NSImage?
    @State private var isLoading = true
    @State private var zoomScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.chartImagePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button("Close") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main image canvas
            ZStack {
                Color.black.opacity(0.85)

                if isLoading {
                    ProgressView("Loading full resolution image...")
                        .foregroundStyle(.white)
                } else if let fullImage {
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: fullImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(20)
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.orange)
                        Text("Image file could not be loaded from disk.")
                            .font(.callout)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            await loadFullImage()
        }
    }

    private func loadFullImage() async {
        let url = libraryRootURL.appending(path: item.chartImagePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            isLoading = false
            return
        }

        let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            return image
        }.value

        self.fullImage = image
        self.isLoading = false
    }
}
