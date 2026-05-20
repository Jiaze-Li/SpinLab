import Foundation

protocol LibraryAccessCapability {
    func loadIndex(from rootURL: URL) -> LibraryIndex?
}

extension LibraryStore: LibraryAccessCapability {}
