import Foundation

/// RSM workflow pack state.
///
/// Stores only RSM-owned persisted state needed to re-open and re-parse the
/// source, then rebuild the heatmap path in later restore work.
/// This type intentionally omits derived render state, heatmap layout, PNG
/// bytes, and XY plot-preservation fields.
struct RSMPackState: Codable, Hashable, Sendable {

    static let currentSchemaVersion = 1

    var schemaVersion: Int

    /// Opaque source provenance token. May be a file identity, imported-file
    /// reference, or other stable lookup placeholder.
    var sourceFileIdentity: String?

    /// Raw detector column name used by the active source schema.
    var detectorColumnName: String

    /// Active 2D projection view for the canonical dataset.
    var activeView: RSMView

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        sourceFileIdentity: String? = nil,
        detectorColumnName: String,
        activeView: RSMView = .hl
    ) {
        self.schemaVersion = schemaVersion
        self.sourceFileIdentity = sourceFileIdentity
        self.detectorColumnName = detectorColumnName
        self.activeView = activeView
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sourceFileIdentity
        case importedFileReference
        case detectorColumnName
        case activeView
        case view
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        sourceFileIdentity = try c.decodeIfPresent(String.self, forKey: .sourceFileIdentity)
            ?? c.decodeIfPresent(String.self, forKey: .importedFileReference)
        detectorColumnName = try c.decodeIfPresent(String.self, forKey: .detectorColumnName) ?? ""

        let activeViewValue = try c.decodeIfPresent(String.self, forKey: .activeView)
            ?? c.decodeIfPresent(String.self, forKey: .view)
        activeView = RSMPackState.decodeView(activeViewValue)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(sourceFileIdentity, forKey: .sourceFileIdentity)
        try c.encode(detectorColumnName, forKey: .detectorColumnName)
        try c.encode(activeView.rawValue, forKey: .activeView)
    }

    private static func decodeView(_ rawValue: String?) -> RSMView {
        guard let rawValue, let view = RSMView(rawValue: rawValue.lowercased()) else {
            return .hl
        }
        return view
    }
}
