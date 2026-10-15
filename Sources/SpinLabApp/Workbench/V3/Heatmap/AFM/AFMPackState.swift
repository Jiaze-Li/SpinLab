import Foundation

/// AFM workflow pack state — persisted selected-channel identity and processing configuration
/// needed to restore an equivalent rendered state without re-parsing the source `.ibw` file
/// (the ingestion result itself is carried separately, in `AFMPackResult`).
struct AFMPackState: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// Opaque source provenance token (the source file path at analysis time).
    var sourceFileIdentity: String?
    var processingConfiguration: AFMProcessingConfiguration
    var scaleBar: AFMScaleBarSetting

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sourceFileIdentity: String? = nil,
        processingConfiguration: AFMProcessingConfiguration,
        scaleBar: AFMScaleBarSetting = .init()
    ) {
        self.schemaVersion = schemaVersion
        self.sourceFileIdentity = sourceFileIdentity
        self.processingConfiguration = processingConfiguration
        self.scaleBar = scaleBar
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sourceFileIdentity
        case processingConfiguration
        case scaleBar
    }

    /// Old/missing fields decode to V1 defaults (empty channel selection, all processing off)
    /// rather than failing to decode a legacy/partial pack.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        sourceFileIdentity = try c.decodeIfPresent(String.self, forKey: .sourceFileIdentity)
        processingConfiguration = try c.decodeIfPresent(AFMProcessingConfiguration.self, forKey: .processingConfiguration)
            ?? AFMProcessingConfiguration(activeChannelID: "")
        scaleBar = try c.decodeIfPresent(AFMScaleBarSetting.self, forKey: .scaleBar) ?? .init()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(sourceFileIdentity, forKey: .sourceFileIdentity)
        try c.encode(processingConfiguration, forKey: .processingConfiguration)
        try c.encode(scaleBar, forKey: .scaleBar)
    }
}
