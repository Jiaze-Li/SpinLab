import Foundation
import Observation

/// The single pending-navigation record. A dirty Drawer draft defers either a
/// Drawer selection change (`selection`), a full navigation (`target`), or
/// both; there is never more than one waiting record.
struct LibraryPendingNavigation: Equatable {
    /// Drawer identity whose draft the user is being asked about.
    struct DraftBinding: Equatable {
        var prefix: String?
        var batchId: String?
        var sampleId: String?
    }

    let id: UUID
    var selection: LibraryPendingSelectionChange?
    var target: AppRoutePath?
    /// The Drawer draft this request was deferred for. Save/Discard act only if
    /// the live draft still has this identity; otherwise the request is stale.
    var boundDraft: DraftBinding?

    init(
        selection: LibraryPendingSelectionChange? = nil,
        target: AppRoutePath? = nil,
        boundDraft: DraftBinding? = nil
    ) {
        self.id = UUID()
        self.selection = selection
        self.target = target
        self.boundDraft = boundDraft
    }
}

@Observable
final class LibraryState {
    var sampleEditBaseSample: LibrarySample?
    var sampleEditOriginalDraft: LibrarySampleEditDraft?
    var pendingNavigation: LibraryPendingNavigation?

    /// Selection-level view of the pending record (kept for existing callers).
    var pendingSelectionChange: LibraryPendingSelectionChange? {
        get { pendingNavigation?.selection }
        set {
            if let newValue {
                pendingNavigation = LibraryPendingNavigation(selection: newValue, target: pendingNavigation?.target)
            } else if pendingNavigation?.target == nil {
                pendingNavigation = nil
            } else {
                pendingNavigation?.selection = nil
            }
        }
    }
}
