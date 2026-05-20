import Foundation

enum PendingTagReadiness {
    case notLibraryMatched
    case allGood
    case tagsMissing([String])
}
