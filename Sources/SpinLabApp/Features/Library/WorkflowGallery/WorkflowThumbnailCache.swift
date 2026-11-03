import AppKit
import Foundation
import ImageIO

/// Thread-safe in-memory cache and downsampler for Workflow Gallery thumbnails.
///
/// Bounded decoding guarantees:
/// - Downsamples full-resolution PNGs during decode using ImageIO (`kCGImageSourceThumbnailMaxPixelSize`),
///   preventing unconstrained memory allocation.
/// - Limits memory cache to 150 items or ~80MB cost limit.
/// - Performs disk reads and decoding on background tasks off the main actor.
final class WorkflowThumbnailCache: @unchecked Sendable {
    static let shared = WorkflowThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private let queue = DispatchQueue(label: "com.spinlab.workflow-gallery.thumbnail-cache", qos: .userInitiated)

    init(countLimit: Int = 200, totalCostLimit: Int = 80 * 1024 * 1024) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    /// Computes an isolated cache key combining library root URL path and relative chart image path.
    static func cacheKey(rootURL: URL, relativePath: String) -> String {
        "\(rootURL.standardizedFileURL.path)::\(relativePath)"
    }

    /// Retrieves an already decoded thumbnail from cache if present.
    func cachedThumbnail(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    /// Loads and downsamples a thumbnail from the specified URL if not already cached.
    func loadThumbnail(url: URL, key: String, maxPixelSize: CGFloat = 512) -> NSImage? {
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let byteCost = cgImage.bytesPerRow * cgImage.height
        cache.setObject(image, forKey: key as NSString, cost: byteCost)
        return image
    }

    /// Loads and downsamples asynchronously off the main actor.
    func loadThumbnailAsync(url: URL, key: String, maxPixelSize: CGFloat = 512) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = cachedThumbnail(for: key) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = self.loadThumbnail(url: url, key: key, maxPixelSize: maxPixelSize)
                continuation.resume(returning: image)
            }
        }
    }

    /// Clears the in-memory cache.
    func clear() {
        cache.removeAllObjects()
    }
}
