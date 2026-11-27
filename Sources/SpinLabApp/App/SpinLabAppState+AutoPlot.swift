import Foundation

/// Task 7: user-facing automatic AFM plotting actions on the app state. Reads/writes go through
/// `LibraryAssetService`; slow work (it waits on the commit lock) never runs on the main actor.
extension SpinLabAppState {

    private var autoPlotAssetService: LibraryAssetService {
        LibraryAssetService(libraryStore: libraryFeatureStore.libraryStore)
    }

    /// Why the preset cannot be edited right now, or nil.
    var autoPlotUnavailableReason: String? {
        guard v2LibraryRootURL != nil else { return "Automatic plotting needs a standard (V2) Library." }
        if LibraryWriteLease.shared.isReadOnly { return LibraryWriteLease.readOnlyMessage }
        return nil
    }

    func loadAutoPlotPreset() async -> Result<AFMAutoPlotPresetLoad, Error> {
        guard let rootURL = v2LibraryRootURL else { return .success(.absent) }
        let service = autoPlotAssetService
        return await Task.detached { Result { try service.currentAutoPlotPreset(rootURL: rootURL).load } }.value
    }

    func applyAutoPlotPreset(_ draft: AFMAutoPlotPreset) async -> Result<AFMAutoPlotPreset, Error> {
        guard let rootURL = v2LibraryRootURL else { return .failure(AppError.state("No standard Library is open.")) }
        let service = autoPlotAssetService
        return await Task.detached { Result { try service.applyAutoPlotPreset(draft, rootURL: rootURL) } }.value
    }

    func setAutoPlotEnabled(_ enabled: Bool) async -> Result<AFMAutoPlotPreset, Error> {
        guard let rootURL = v2LibraryRootURL else { return .failure(AppError.state("No standard Library is open.")) }
        let service = autoPlotAssetService
        return await Task.detached { Result { try service.setAutoPlotEnabled(enabled, rootURL: rootURL) } }.value
    }

    /// A draft built from what the AFM Workbench shows right now. Not applied until the user applies it.
    func autoPlotDraftFromWorkbench() -> AFMAutoPlotPreset? {
        let afm = workbench.afmWorkspace
        guard let channel = afm.activeChannel else { return nil }
        var display = afm.heatmapDisplayState
        display.titleOverride = ""
        display.titleTemplate = ""
        return AFMAutoPlotPreset(
            enabled: false, presetVersionID: "",
            channelRule: .init(semanticType: channel.semanticTypeRaw, sourceLabel: channel.sourceLabel),
            surfaceLevel: afm.processingConfiguration.surfaceLevel,
            lineFlattenOrder: afm.processingConfiguration.lineFlattenOrder,
            zeroReference: afm.processingConfiguration.zeroReference,
            displayState: display, scaleBar: afm.scaleBar, globalPlotDefaults: afm.globalPlotDefaults
        )
    }

    /// Explicit one-Dataset run with the applied preset; the result appears in `afmAutoPlotRunner.reports`.
    func runAutoPlot(datasetID: String) {
        guard let rootURL = v2LibraryRootURL else { return }
        afmAutoPlotRunner.rerun(datasetID: datasetID, rootURL: rootURL, libraryStore: libraryFeatureStore.libraryStore)
    }
}

enum AutoPlotText {
    static func describe(_ result: AutoPlotRunResult) -> String {
        switch result {
        case .published: return "Plot saved automatically."
        case .alreadyPublished: return "An automatic plot was already saved for this measurement."
        case let .skipped(reason): return "Skipped: \(reason)"
        case let .failed(reason, _): return "Failed: \(reason)"
        case let .cancelled(reason): return "Not made: \(reason)"
        }
    }
}
