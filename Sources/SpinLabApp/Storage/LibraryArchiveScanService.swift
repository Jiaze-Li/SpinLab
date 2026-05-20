import Foundation

enum LibraryArchiveScanError: LocalizedError {
    case createDirectoryFailed(path: String, reason: String)
    case removeExistingRegistryFailed(path: String, reason: String)
    case copyRegistryFailed(source: String, destination: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .createDirectoryFailed(path, reason):
            return "Failed to create directory at \(path): \(reason)"
        case let .removeExistingRegistryFailed(path, reason):
            return "Failed to replace existing registry file at \(path): \(reason)"
        case let .copyRegistryFailed(source, destination, reason):
            return "Failed to copy registry from \(source) to \(destination): \(reason)"
        }
    }
}

final class LibraryArchiveScanService {
    private let fileManager = FileManager.default
    private let rootURL: URL

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(filePath: NSTemporaryDirectory(), directoryHint: .isDirectory)
            self.rootURL = appSupportURL.appending(path: "SpinLab", directoryHint: .isDirectory)
        }

        do {
            try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: registryDirectoryURL, withIntermediateDirectories: true)
        } catch {
            fputs("[LibraryArchiveScanService] Failed to create storage directories: \(error.localizedDescription)\n", stderr)
        }
    }

    var measurementsDirectoryURL: URL {
        rootURL.appending(path: "measurements", directoryHint: .isDirectory)
    }

    var registryDirectoryURL: URL {
        rootURL.appending(path: "registry", directoryHint: .isDirectory)
    }

    func isManagedMeasurementPath(_ path: String) -> Bool {
        normalizedPath(path).hasPrefix(measurementsDirectoryURL.standardizedFileURL.path + "/")
    }

    func clearManagedMeasurementCopies() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: measurementsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                fputs("[LibraryArchiveScanService] Failed to remove managed copy at \(url.lastPathComponent): \(error.localizedDescription)\n", stderr)
            }
        }
    }

    func installSampleRegistry(from url: URL) throws -> URL {
        let sanitizedName = url.lastPathComponent.replacingOccurrences(of: "/", with: "-")
        let destinationURL = registryDirectoryURL.appending(path: sanitizedName)

        do {
            try fileManager.createDirectory(at: registryDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw LibraryArchiveScanError.createDirectoryFailed(
                path: registryDirectoryURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
        } catch {
            throw LibraryArchiveScanError.removeExistingRegistryFailed(
                path: destinationURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            try fileManager.copyItem(at: url, to: destinationURL)
            return destinationURL
        } catch {
            throw LibraryArchiveScanError.copyRegistryFailed(
                source: url.path,
                destination: destinationURL.path,
                reason: error.localizedDescription
            )
        }
    }

    func currentSampleRegistryFileURL() -> URL? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: registryDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "xlsx" }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
            .first
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
