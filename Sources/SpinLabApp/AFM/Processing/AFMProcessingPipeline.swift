import Foundation

/// Deterministic AFM processing pipeline: source selected-channel matrix → Plane Level (if
/// enabled) → Line Flatten (if enabled) → Zero Reference (if enabled) → `ProcessedAFMChannel`.
///
/// Every call starts from the immutable `CanonicalAFMChannel` passed in — never from a previous
/// `ProcessedAFMChannel`. Callers (the AFM workspace store, Phase 4) must always pass the
/// original canonical channel, never chain a previous processed result back in; that is what
/// makes repeated toggling non-compounding.
enum AFMProcessingPipeline {
    static func process(
        channel: CanonicalAFMChannel,
        xCoordinates: [Double],
        yCoordinates: [Double],
        configuration: AFMProcessingConfiguration
    ) -> ProcessedAFMChannel {
        var matrix = channel.values
        var warnings: [String] = []

        if configuration.planeLevelEnabled {
            let result = AFMPlaneLevelProcessor.apply(to: matrix, xCoordinates: xCoordinates, yCoordinates: yCoordinates)
            matrix = result.values
            warnings.append(contentsOf: result.warnings)
        }

        if let degree = configuration.lineFlattenOrder.polynomialDegree {
            let result = AFMLineFlattenProcessor.apply(to: matrix, xCoordinates: xCoordinates, degree: degree)
            matrix = result.values
            warnings.append(contentsOf: result.warnings)
        }

        if configuration.zeroReference != .none {
            matrix = AFMZeroReferenceProcessor.apply(to: matrix, reference: configuration.zeroReference)
        }

        return ProcessedAFMChannel(
            sourceChannelID: channel.id,
            values: matrix,
            canonicalUnit: channel.canonicalUnit,
            displayLabel: channel.displayLabel,
            configuration: configuration,
            warnings: warnings
        )
    }
}
