import AppKit
import SwiftUI

struct WorkflowGalleryThumbnailCard: View {
    let item: WorkflowGalleryItem
    let isSelected: Bool
    let libraryRootURL: URL
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isLoadingImage = false
    @State private var isDecodingFailed = false

    private let cardCornerRadius: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. Thumbnail Image or Missing Placeholder
            ZStack(alignment: .topTrailing) {
                imageContent
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))

                // Badges overlay
                HStack(spacing: 4) {
                    if item.isMultiSample {
                        Text("\(item.associatedSampleKeys.count) Samples")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    if !item.hasMeasurementAssociation {
                        Text("Unlinked")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(6)
            }

            // 2. Card Metadata Footer
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(sampleSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(formattedDate(item.generatedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius + 4)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius + 4)
                .strokeBorder(isSelected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.35), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onDoubleClick()
            }
        )
        .task(id: "\(libraryRootURL.path)::\(item.chartImagePath)") {
            await loadThumbnail()
        }
        .onChange(of: libraryRootURL) { _, _ in
            thumbnail = nil
            isDecodingFailed = false
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if item.imageStatus == .missingFile {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                Text("Image Missing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.orange.opacity(0.08))
        } else if isDecodingFailed || item.imageStatus == .unreadable {
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 24))
                    .foregroundStyle(.red)
                Text("Corrupt / Unreadable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.red.opacity(0.08))
        } else if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sampleSubtitle: String {
        if item.associatedSampleKeys.count > 1 {
            return "\(item.associatedSampleKeys.count) samples"
        }
        return item.associatedSampleKeys.first ?? "Unknown Sample"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func loadThumbnail() async {
        guard item.imageStatus == .available else { return }

        let requestedRoot = libraryRootURL
        let requestedPath = item.chartImagePath
        let cacheKey = WorkflowThumbnailCache.cacheKey(rootURL: libraryRootURL, relativePath: item.chartImagePath)
        let fullURL = libraryRootURL.appending(path: item.chartImagePath)

        if let cached = WorkflowThumbnailCache.shared.cachedThumbnail(for: cacheKey) {
            self.thumbnail = cached
            return
        }

        let loaded = await WorkflowThumbnailCache.shared.loadThumbnailAsync(
            url: fullURL,
            key: cacheKey,
            maxPixelSize: 480
        )

        // Late image load protection: ensure the card still represents the same library root and image path
        guard self.libraryRootURL == requestedRoot, self.item.chartImagePath == requestedPath else {
            return
        }

        self.thumbnail = loaded
        if loaded == nil {
            self.isDecodingFailed = true
        }
    }
}
