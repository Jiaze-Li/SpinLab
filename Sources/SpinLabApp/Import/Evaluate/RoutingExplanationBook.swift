import Foundation

struct RoutingExplanation {
    let message: String
    let reason: SpinLabDomain.RoutingWarningReason
}

enum RoutingExplanationBook {
    static func unresolvedChannelSampleSignal() -> RoutingExplanation {
        RoutingExplanation(
            message: "Channel sample signal exists but no filetoken was resolved.",
            reason: .channelSampleSignalWithoutToken
        )
    }

    static func nameConflictInLibrary() -> RoutingExplanation {
        RoutingExplanation(
            message: "Library drawer already contains a file with this name.",
            reason: .nameConflictInLibrary
        )
    }

    static func resolveScopeWarning(
        resolutionWarning: String?,
        matchedDrawer: String?
    ) -> RoutingExplanation? {
        if let resolutionWarning {
            return RoutingExplanation(
                message: resolutionWarning,
                reason: .upstreamResolutionWarning
            )
        }
        guard matchedDrawer == nil else {
            return nil
        }
        return RoutingExplanation(
            message: "No matching drawer found in Library.",
            reason: .noMatchingLibraryDrawer
        )
    }
}
