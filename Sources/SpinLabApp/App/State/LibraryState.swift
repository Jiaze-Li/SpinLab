import Foundation
import Observation

@Observable
final class LibraryState {
    var sampleEditBaseSample: LibrarySample?
    var sampleEditOriginalDraft: LibrarySampleEditDraft?
    var pendingSelectionChange: LibraryPendingSelectionChange?
}
