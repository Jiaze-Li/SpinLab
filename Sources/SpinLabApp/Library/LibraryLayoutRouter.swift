import Foundation

enum LibraryLayoutVersion: Int, Codable, Equatable, Sendable {
    case v1 = 1
    case v2 = 2
}

struct LibraryLayoutMarker: Codable, Equatable, Sendable {
    var version: Int
}

enum LibraryLayoutError: LocalizedError, Equatable, Sendable {
    case missingVersionMarkerForRecords
    case unknownVersion(Int)
    case corruptVersionMarker(String)
    case mixedLayouts(String)
    case layoutMismatch(String)
    case v2UnsupportedOperation(String)
    case duplicateSampleUID(String)
    case invalidV2SampleRecord(String)

    var errorDescription: String? {
        switch self {
        case .missingVersionMarkerForRecords:
            return "Library contains 'records/' without '_spinlab/layout_version.json'. Refusing write (fail-closed)."
        case let .unknownVersion(version):
            return "Unsupported Library layout version \(version) in '_spinlab/layout_version.json'. Refusing write (fail-closed)."
        case let .corruptVersionMarker(reason):
            return "Corrupt '_spinlab/layout_version.json': \(reason). Refusing write (fail-closed)."
        case let .mixedLayouts(reason):
            return "Mixed V1/V2 Library layout detected: \(reason). Refusing write (fail-closed)."
        case let .layoutMismatch(reason):
            return "Library layout mismatch: \(reason). Refusing write (fail-closed)."
        case let .v2UnsupportedOperation(operation):
            return "Operation '\(operation)' is not yet supported on Storage v2 libraries and was refused to prevent writing to V1 paths."
        case let .duplicateSampleUID(uid):
            return "Duplicate sampleUID '\(uid)' detected in Storage v2 library. Refusing write (fail-closed)."
        case let .invalidV2SampleRecord(reason):
            return "Invalid Storage v2 sample record: \(reason). Refusing write (fail-closed)."
        }
    }
}

enum LibraryLayoutResolution: Equatable, Sendable {
    case v1
    case v2
    case uninitialized
    case invalid(LibraryLayoutError)

    var isV2: Bool {
        if case .v2 = self { return true }
        return false
    }

    var isInvalid: Bool {
        if case .invalid = self { return true }
        return false
    }

    var error: LibraryLayoutError? {
        if case let .invalid(err) = self { return err }
        return nil
    }
}

enum LibraryLayoutRouter {
    static let markerRelativePath = "_spinlab/layout_version.json"

    static func markerURL(at rootURL: URL) -> URL {
        rootURL.appending(path: markerRelativePath)
    }

    static func resolve(rootURL: URL, fileManager: FileManager = .default) -> LibraryLayoutResolution {
        var isRootDir: ObjCBool = false
        let rootExists = fileManager.fileExists(atPath: rootURL.path, isDirectory: &isRootDir)
        if rootExists && !isRootDir.boolValue {
            return .invalid(.layoutMismatch("Library root '\(rootURL.path)' is not a directory."))
        }
        guard rootExists else {
            return .uninitialized
        }

        let markerFile = markerURL(at: rootURL)
        let batchesExists = fileManager.fileExists(atPath: rootURL.appending(path: "batches").path)
        let recordsExists = fileManager.fileExists(atPath: rootURL.appending(path: "records").path)
        let indexExists = fileManager.fileExists(atPath: rootURL.appending(path: "index").path)

        if fileManager.fileExists(atPath: markerFile.path) {
            let data: Data
            do {
                data = try Data(contentsOf: markerFile)
            } catch {
                return .invalid(.corruptVersionMarker(error.localizedDescription))
            }
            let marker: LibraryLayoutMarker
            do {
                marker = try JSONDecoder().decode(LibraryLayoutMarker.self, from: data)
            } catch {
                return .invalid(.corruptVersionMarker(error.localizedDescription))
            }

            switch marker.version {
            case LibraryLayoutVersion.v2.rawValue:
                if batchesExists {
                    return .invalid(.mixedLayouts("layout_version is 2, but V1 'batches/' directory exists."))
                }
                if !recordsExists {
                    return .invalid(.layoutMismatch("layout_version is 2, but 'records/' directory is missing."))
                }
                return .v2
            case LibraryLayoutVersion.v1.rawValue:
                if recordsExists {
                    return .invalid(.mixedLayouts("layout_version is 1, but V2 'records/' directory exists."))
                }
                return .v1
            default:
                return .invalid(.unknownVersion(marker.version))
            }
        }

        // No layout_version.json marker on disk.
        if batchesExists && recordsExists {
            return .invalid(.mixedLayouts("Both V1 'batches/' and V2 'records/' directories exist without a layout marker."))
        }
        if recordsExists {
            return .invalid(.missingVersionMarkerForRecords)
        }
        if batchesExists || indexExists {
            return .v1
        }

        return .uninitialized
    }

    static func requireV1ArtifactWriteAllowed(
        rootURL: URL,
        operation: String,
        fileManager: FileManager = .default
    ) throws {
        switch resolve(rootURL: rootURL, fileManager: fileManager) {
        case .v1, .uninitialized:
            return
        case .v2:
            throw LibraryLayoutError.v2UnsupportedOperation(operation)
        case let .invalid(error):
            throw error
        }
    }

    static func writeV2Marker(at rootURL: URL, fileManager: FileManager = .default) throws {
        let url = markerURL(at: rootURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LibraryLayoutMarker(version: LibraryLayoutVersion.v2.rawValue))
        try data.write(to: url, options: .atomic)
    }
}
