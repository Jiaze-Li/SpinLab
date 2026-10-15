import Foundation

/// User-facing scale bar choice for an AFM map. Display-only: never touches scientific data.
struct AFMScaleBarSetting: Sendable, Equatable, Hashable, Codable {
    enum Mode: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        case off
        case auto
        case manual
    }

    var mode: Mode = .auto
    /// Manual bar length in µm. Only used when `mode == .manual`.
    var manualLengthMicrometers: Double = 1
    var color: HeatmapScaleBarColor = .white

    init(mode: Mode = .auto, manualLengthMicrometers: Double = 1, color: HeatmapScaleBarColor = .white) {
        self.mode = mode
        self.manualLengthMicrometers = manualLengthMicrometers
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .auto
        manualLengthMicrometers = try c.decodeIfPresent(Double.self, forKey: .manualLengthMicrometers) ?? 1
        color = try c.decodeIfPresent(HeatmapScaleBarColor.self, forKey: .color) ?? .white
    }

    /// Largest 1/2/5 × 10^k length that is at most `maxFraction` of the scan width.
    static func autoLengthMicrometers(scanWidthMicrometers: Double, maxFraction: Double = 0.25) -> Double? {
        let limit = scanWidthMicrometers * maxFraction
        guard limit.isFinite, limit > 0 else { return nil }
        let exponent = floor(log10(limit))
        for mantissa in [5.0, 2.0, 1.0] {
            let candidate = mantissa * pow(10, exponent)
            if candidate <= limit * (1 + 1e-12) { return candidate }
        }
        return nil
    }

    static func label(forMicrometers length: Double) -> String {
        if length < 1 {
            return "\(format(length * 1000)) nm"
        }
        return "\(format(length)) μm"
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }

    /// Resolves to a physical overlay for a scan of the given full width, or nil when the bar is
    /// off, unresolvable, or does not fit inside the scan.
    func overlay(scanWidthMicrometers: Double) -> HeatmapScaleBarOverlay? {
        let length: Double?
        switch mode {
        case .off: length = nil
        case .auto: length = Self.autoLengthMicrometers(scanWidthMicrometers: scanWidthMicrometers)
        case .manual: length = manualLengthMicrometers
        }
        guard let length, length.isFinite, length > 0, length < scanWidthMicrometers else { return nil }
        return HeatmapScaleBarOverlay(
            lengthInPoints: 0,
            label: Self.label(forMicrometers: length),
            physicalLength: length,
            color: color
        )
    }
}
