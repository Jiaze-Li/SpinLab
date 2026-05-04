import Foundation

final class LibraryStore {
    struct SidecarSnapshot: Equatable {
        var fileCount: Int
        var fingerprint: String

        static let empty = SidecarSnapshot(fileCount: 0, fingerprint: "")
    }

    struct BackfillSidecarsResult: Equatable {
        var scannedSampleCount: Int
        var scannedMeasurementFileCount: Int
        var createdSidecarCount: Int
        var updatedSidecarCount: Int
        var skippedExistingSidecarCount: Int
        var failedSidecarCount: Int
    }

    struct DirectoryEntriesCacheEntry {
        let modificationDate: Date?
        let entries: [URL]
    }

    struct DecodedBatchCacheEntry {
        let modificationDate: Date?
        let batch: LibraryBatch?
    }

    struct DecodedSampleCacheEntry {
        let modificationDate: Date?
        let sample: LibrarySample?
    }

    struct FileListCacheEntry {
        let modificationDate: Date?
        let files: [URL]
    }

    let fileManager = FileManager.default
    let logger = AppLogger.shared
    let xlsxSyncService = LibraryXLSXSyncService()
    var directoryEntriesCache: [String: DirectoryEntriesCacheEntry] = [:]
    var decodedBatchCache: [String: DecodedBatchCacheEntry] = [:]
    var decodedSampleCache: [String: DecodedSampleCacheEntry] = [:]
    var fileListCache: [String: FileListCacheEntry] = [:]
}
