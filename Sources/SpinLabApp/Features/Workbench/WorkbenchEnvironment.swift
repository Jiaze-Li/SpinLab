import Foundation

struct WorkbenchEnvironment {
    var fileManager: FileManager = .default
    var libraryAccess: any LibraryAccessCapability = LibraryStore()

    static let live = WorkbenchEnvironment()
}
