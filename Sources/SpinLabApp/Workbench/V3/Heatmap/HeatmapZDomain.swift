import Foundation

enum HeatmapZDomainMode: String, Codable, CaseIterable, Sendable {
    case auto
    case manual
    case percentile
}

struct HeatmapZRangeDraft: Codable, Hashable, Sendable {
    var minText: String
    var maxText: String

    init(minText: String = "", maxText: String = "") {
        self.minText = minText
        self.maxText = maxText
    }
}

struct HeatmapPercentileClamp: Codable, Hashable, Sendable {
    var lowerPercent: Double
    var upperPercent: Double

    init(lowerPercent: Double, upperPercent: Double) {
        self.lowerPercent = lowerPercent
        self.upperPercent = upperPercent
    }

    var isValid: Bool {
        lowerPercent.isFinite &&
        upperPercent.isFinite &&
        lowerPercent >= 0 &&
        upperPercent <= 100 &&
        lowerPercent < upperPercent
    }
}

enum HeatmapPercentilePreset: String, Codable, CaseIterable, Sendable {
    case p0_5_99_5
    case p1_99
    case p2_98
    case p5_95
    case custom

    var displayTitle: String {
        switch self {
        case .p0_5_99_5: return "0.5% - 99.5%"
        case .p1_99:     return "1% - 99%"
        case .p2_98:     return "2% - 98%"
        case .p5_95:     return "5% - 95%"
        case .custom:    return "Custom"
        }
    }

    var clamp: HeatmapPercentileClamp? {
        switch self {
        case .p0_5_99_5:
            return HeatmapPercentileClamp(lowerPercent: 0.5, upperPercent: 99.5)
        case .p1_99:
            return HeatmapPercentileClamp(lowerPercent: 1, upperPercent: 99)
        case .p2_98:
            return HeatmapPercentileClamp(lowerPercent: 2, upperPercent: 98)
        case .p5_95:
            return HeatmapPercentileClamp(lowerPercent: 5, upperPercent: 95)
        case .custom:
            return nil
        }
    }
}

enum HeatmapZDomainValidationIssue: String, Codable, Hashable, Sendable {
    case manualMinMissing
    case manualMaxMissing
    case manualMinInvalid
    case manualMaxInvalid
    case manualRangeInverted
    case percentileInvalidClamp
    case percentileCollapsedDomain

    var message: String {
        switch self {
        case .manualMinMissing:        return "Enter a minimum Z value."
        case .manualMaxMissing:        return "Enter a maximum Z value."
        case .manualMinInvalid:        return "Minimum Z value must be a finite number."
        case .manualMaxInvalid:        return "Maximum Z value must be a finite number."
        case .manualRangeInverted:     return "Minimum Z must be less than maximum Z."
        case .percentileInvalidClamp:  return "Percentile clamp must stay within 0% to 100% and lower < upper."
        case .percentileCollapsedDomain: return "Percentile clamp collapses to an empty Z domain."
        }
    }
}

enum HeatmapZDomainResolution: Hashable, Sendable {
    case resolved(lowerBound: Double, upperBound: Double)
    case fallbackToAuto(reason: String)

    var resolvedBounds: (lowerBound: Double, upperBound: Double)? {
        switch self {
        case .resolved(let lowerBound, let upperBound):
            return (lowerBound, upperBound)
        case .fallbackToAuto:
            return nil
        }
    }
}

struct HeatmapZDomainState: Codable, Hashable, Sendable {
    var mode: HeatmapZDomainMode = .auto
    var manualRange: HeatmapZRangeDraft = .init()
    var percentilePreset: HeatmapPercentilePreset = .p1_99
    var percentileClamp: HeatmapPercentileClamp = .init(lowerPercent: 1, upperPercent: 99)

    init(
        mode: HeatmapZDomainMode = .auto,
        manualRange: HeatmapZRangeDraft = .init(),
        percentilePreset: HeatmapPercentilePreset = .p1_99,
        percentileClamp: HeatmapPercentileClamp = .init(lowerPercent: 1, upperPercent: 99)
    ) {
        self.mode = mode
        self.manualRange = manualRange
        self.percentilePreset = percentilePreset
        self.percentileClamp = percentileClamp
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case manualRange
        case percentilePreset
        case percentileClamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(HeatmapZDomainMode.self, forKey: .mode) ?? .auto
        manualRange = try container.decodeIfPresent(HeatmapZRangeDraft.self, forKey: .manualRange) ?? .init()
        percentilePreset = try container.decodeIfPresent(HeatmapPercentilePreset.self, forKey: .percentilePreset) ?? .p1_99
        percentileClamp = try container.decodeIfPresent(HeatmapPercentileClamp.self, forKey: .percentileClamp)
            ?? .init(lowerPercent: 1, upperPercent: 99)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(manualRange, forKey: .manualRange)
        try container.encode(percentilePreset, forKey: .percentilePreset)
        try container.encode(percentileClamp, forKey: .percentileClamp)
    }

    func validationIssue() -> HeatmapZDomainValidationIssue? {
        switch mode {
        case .auto:
            return nil
        case .manual:
            return Self.validationIssue(for: manualRange)
        case .percentile:
            let clamp = activePercentileClamp
            guard let clamp else { return .percentileInvalidClamp }
            guard clamp.isValid else { return .percentileInvalidClamp }
            return nil
        }
    }

    func validationIssue(rawValues: [Double]) -> HeatmapZDomainValidationIssue? {
        switch mode {
        case .auto:
            return nil
        case .manual:
            return Self.validationIssue(for: manualRange)
        case .percentile:
            let clamp = activePercentileClamp
            guard let clamp else { return .percentileInvalidClamp }
            guard clamp.isValid else { return .percentileInvalidClamp }
            guard Self.percentileDomain(for: clamp, rawValues: rawValues) != nil else {
                return .percentileCollapsedDomain
            }
            return nil
        }
    }

    func resolve(rawValues: [Double]) -> HeatmapZDomainResolution {
        switch mode {
        case .auto:
            return .resolved(lowerBound: Self.autoLowerBound(rawValues), upperBound: Self.autoUpperBound(rawValues))
        case .manual:
            guard let manualResolution = Self.resolvedManualDomain(from: manualRange) else {
                let issue = Self.validationIssue(for: manualRange) ?? .manualMinInvalid
                return .fallbackToAuto(reason: issue.message)
            }
            return .resolved(lowerBound: manualResolution.lowerBound, upperBound: manualResolution.upperBound)
        case .percentile:
            guard let clamp = activePercentileClamp, clamp.isValid else {
                return .fallbackToAuto(reason: HeatmapZDomainValidationIssue.percentileInvalidClamp.message)
            }
            guard let domain = Self.percentileDomain(for: clamp, rawValues: rawValues) else {
                return .fallbackToAuto(reason: HeatmapZDomainValidationIssue.percentileCollapsedDomain.message)
            }
            return .resolved(lowerBound: domain.lowerBound, upperBound: domain.upperBound)
        }
    }

    private var activePercentileClamp: HeatmapPercentileClamp? {
        switch percentilePreset {
        case .custom:
            return percentileClamp
        default:
            return percentilePreset.clamp
        }
    }

    private static func validationIssue(for draft: HeatmapZRangeDraft) -> HeatmapZDomainValidationIssue? {
        let minText = draft.minText.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxText = draft.maxText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !minText.isEmpty else { return .manualMinMissing }
        guard !maxText.isEmpty else { return .manualMaxMissing }

        guard let minValue = Self.parseFiniteDouble(minText) else { return .manualMinInvalid }
        guard let maxValue = Self.parseFiniteDouble(maxText) else { return .manualMaxInvalid }
        guard minValue < maxValue else { return .manualRangeInverted }
        return nil
    }

    private static func resolvedManualDomain(from draft: HeatmapZRangeDraft) -> (lowerBound: Double, upperBound: Double)? {
        let minText = draft.minText.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxText = draft.maxText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let minValue = parseFiniteDouble(minText), let maxValue = parseFiniteDouble(maxText), minValue < maxValue else {
            return nil
        }
        return (minValue, maxValue)
    }

    private static func parseFiniteDouble(_ text: String) -> Double? {
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func autoLowerBound(_ rawValues: [Double]) -> Double {
        finiteRawValues(from: rawValues).min() ?? 0
    }

    private static func autoUpperBound(_ rawValues: [Double]) -> Double {
        finiteRawValues(from: rawValues).max() ?? 1
    }

    private static func finiteRawValues(from rawValues: [Double]) -> [Double] {
        rawValues.filter { $0.isFinite }
    }

    private static func percentileDomain(
        for clamp: HeatmapPercentileClamp,
        rawValues: [Double]
    ) -> (lowerBound: Double, upperBound: Double)? {
        let values = finiteRawValues(from: rawValues).sorted()
        guard !values.isEmpty else { return nil }
        guard let lower = percentileValue(clamp.lowerPercent, in: values),
              let upper = percentileValue(clamp.upperPercent, in: values),
              lower.isFinite, upper.isFinite, lower < upper else {
            return nil
        }
        return (lower, upper)
    }

    private static func percentileValue(_ percentile: Double, in values: [Double]) -> Double? {
        guard percentile.isFinite, !values.isEmpty else { return nil }
        if values.count == 1 { return values[0] }

        let clamped = min(max(percentile, 0), 100)
        let position = (clamped / 100.0) * Double(values.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        let lowerValue = values[lowerIndex]
        let upperValue = values[upperIndex]

        if lowerIndex == upperIndex {
            return lowerValue
        }

        let fraction = position - Double(lowerIndex)
        return lowerValue + (upperValue - lowerValue) * fraction
    }
}

