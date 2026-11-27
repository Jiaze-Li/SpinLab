import Foundation

/// Page-independent AFM analysis: standard matrix + explicit effective configuration -> candidate.
///
/// The single entry used by Analyze, reprocess/rerender, pack restore and (Task 7) headless callers.
/// It reads no UI state, no global "last used" configuration and no file; every input is a parameter,
/// so the same Dataset revision and configuration give the same matrix on every caller (Task 6 §2.6-C).
/// Display parameters only change the colour mapping; the processed matrix never depends on them.
enum AFMPlotComputation {

    /// Science identifier recorded with every candidate; bump only when the processing order or algorithms change.
    static let scienceMethodID = "afm_processing_v1"

    struct DisplayInput: Sendable {
        /// Display state with the title already resolved (template tokens applied).
        var displayState: HeatmapTabRenderState
        var scaleBar: AFMScaleBarSetting
        var globalPlotDefaults: [String: String]
        var workflowID: String

        init(
            displayState: HeatmapTabRenderState, scaleBar: AFMScaleBarSetting = .init(),
            globalPlotDefaults: [String: String] = [:], workflowID: String = "afm"
        ) {
            self.displayState = displayState
            self.scaleBar = scaleBar
            self.globalPlotDefaults = globalPlotDefaults
            self.workflowID = workflowID
        }
    }

    enum ComputationError: Error, Equatable, LocalizedError {
        case channelNotFound(String)
        case noUsableChannel

        var errorDescription: String? {
            switch self {
            case let .channelNotFound(id): return "Channel '\(id)' is not present in this dataset."
            case .noUsableChannel: return "The dataset has no usable AFM channel."
            }
        }
    }

    /// Scientific result: matrix, coordinates, unit and diagnostics. No display state.
    struct Processed: Sendable, Equatable {
        let channelID: String
        let values: [[Double]]
        let xCoordinates: [Double]
        let yCoordinates: [Double]
        let unit: String
        let displayLabel: String
        let configuration: AFMProcessingConfiguration
        let scienceMethodID: String
        let warnings: [String]
        let nonFiniteCount: Int
    }

    struct Candidate: Sendable {
        let processed: Processed
        let display: DisplayInput
        let imageData: Data
        let pdfData: Data
    }

    /// Resolves the channel for a fresh selection: keep the carried one if the dataset has it, otherwise
    /// the default resolver's choice (reported as a warning). An explicit run never falls back.
    static func resolveChannelID(
        preferred: String, in dataset: CanonicalAFMDataset
    ) throws -> (id: String, warning: String?) {
        if dataset.channels.contains(where: { $0.id == preferred }) { return (preferred, nil) }
        let resolution = AFMChannelResolver.resolveDefaultChannel(in: dataset.channels)
        guard let channel = resolution.channel else { throw ComputationError.noUsableChannel }
        return (channel.id, resolution.warning)
    }

    /// Scientific processing only. Throws if the explicit channel is missing; never substitutes another.
    static func process(
        dataset: CanonicalAFMDataset, configuration: AFMProcessingConfiguration
    ) throws -> Processed {
        guard let channel = dataset.channels.first(where: { $0.id == configuration.activeChannelID }) else {
            throw ComputationError.channelNotFound(configuration.activeChannelID)
        }
        let processed = AFMProcessingPipeline.process(
            channel: channel, xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates,
            configuration: configuration
        )
        let nonFinite = processed.values.reduce(0) { $0 + $1.reduce(0) { $0 + ($1.isFinite ? 0 : 1) } }
        return Processed(
            channelID: processed.sourceChannelID, values: processed.values,
            xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates,
            unit: processed.canonicalUnit, displayLabel: processed.displayLabel,
            configuration: processed.configuration, scienceMethodID: scienceMethodID,
            warnings: processed.warnings, nonFiniteCount: nonFinite
        )
    }

    static func run(
        dataset: CanonicalAFMDataset, configuration: AFMProcessingConfiguration, display: DisplayInput
    ) throws -> Candidate {
        let processed = try process(dataset: dataset, configuration: configuration)
        let output = try render(dataset: dataset, processed: processed, display: display)
        return Candidate(processed: processed, display: display, imageData: output.imageData, pdfData: output.pdfData)
    }

    /// Render from an already processed matrix (display-only changes and PDF export reuse the matrix).
    static func render(
        dataset: CanonicalAFMDataset, processed: Processed, display: DisplayInput
    ) throws -> HeatmapRenderPipeline.Output {
        let channel = ProcessedAFMChannel(
            sourceChannelID: processed.channelID, values: processed.values, canonicalUnit: processed.unit,
            displayLabel: processed.displayLabel, configuration: processed.configuration, warnings: processed.warnings
        )
        let payload = try AFMHeatmapPayloadBuilder.build(
            dataset: dataset, processed: channel,
            options: .init(
                workflowID: display.workflowID, title: display.displayState.titleOverride, scaleBar: display.scaleBar
            )
        )
        return try HeatmapRenderPipeline.render(.init(
            payload: payload,
            colorScaleMode: display.displayState.colorScaleMode,
            zDomainState: display.displayState.zDomainState,
            chartStyle: WorkbenchChartStyle.from(styleParams: display.globalPlotDefaults),
            showColorbar: display.displayState.showColorbar,
            showTitle: display.displayState.showTitle,
            interpolationMode: display.displayState.interpolationMode,
            colorbarTickStyleOverride: .zHeightTicks(unit: processed.unit)
        ))
    }
}
