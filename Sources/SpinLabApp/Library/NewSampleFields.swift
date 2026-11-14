import Foundation

/// The raw values of one "new sample" form, exactly as entered (no unit conversion).
/// The desktop New Sample window and phone submissions (task 8) both produce this one shape,
/// and `makeDraft` is the only place that turns it into numeric tags, so every entrance
/// yields the same tags and units (units live in `LibraryRegistryParser.numericUnits`).
struct NewSampleFields: Codable, Equatable, Sendable {
    struct Rheed: Codable, Equatable, Sendable {
        var grid: Double?
        var focus: Double?
        var x1: Double?
        var y1: Double?
        var y2: Double?
        var x2: Double?

        var isEmpty: Bool { [grid, focus, x1, y1, y2, x2].allSatisfy { $0 == nil } }
    }

    /// yyyy-MM-dd; empty means "not given".
    var date: String = ""
    var lab: String = ""
    var growthMaterial: String = ""
    var batch: String = ""
    var substrateTreatment: String = ""
    var substrateMaterial: String = ""
    var substrateOrientation: String = ""
    var temperature: Double?
    var pressure: Double?
    var sampleHeight: Double?
    var frontEnergy: Double?
    var laserVoltage: Double?
    var laserOutputEnergy: Double?
    var hasAttenuator: Bool = false
    var prePulseCount: Double?
    var growthPulseCount: Double?
    /// Pulse frequency in Hz; nil means the confirmed default (`RegistryGrowthPulseMapper.defaultHz`).
    var frequency: Double?
    var purpose: String = ""
    var note: String = ""
    var rheed: Rheed = Rheed()

    /// Numeric tag name for each number field, in display order. Names with an entry in
    /// `LibraryRegistryParser.numericUnits` get their unit from there.
    private var numericValues: [(tag: String, value: Double?)] {
        [
            ("温度", temperature),
            ("氧压", pressure),
            ("样品高度", sampleHeight),
            ("镜前能量", frontEnergy),
            ("激光器电压", laserVoltage),
            ("激光器输出能量", laserOutputEnergy),
            ("预打次数", prePulseCount),
            ("生长次数", growthPulseCount),
            ("频率", frequency ?? Double(RegistryGrowthPulseMapper.defaultHz))
        ]
    }

    /// Validates and converts to the draft the creation service consumes.
    /// Batch, growth material and the substrate's material and orientation are required.
    func makeDraft(
        sampleUID: String,
        choices: NativeSampleSubstrateChoices,
        displayName: String? = nil
    ) -> Result<CreateNativeSampleDraft, CreateNativeSampleError> {
        let batchId = batch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !batchId.isEmpty else { return .failure(.invalidInput("Batch is required.")) }
        let material = growthMaterial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !material.isEmpty else { return .failure(.invalidInput("Growth material is required.")) }
        guard let substrate = choices.composeDescription(
            material: substrateMaterial,
            orientation: substrateOrientation,
            treatment: substrateTreatment
        ) else {
            return .failure(.invalidInput("Substrate material and orientation are required."))
        }

        var metadata: [String: String] = [:]
        func put(_ key: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { metadata[key] = trimmed }
        }
        put("date", date)
        put("lab", lab)
        put("material", material)
        put("purpose", purpose)
        put("note", note)
        if hasAttenuator { metadata["attenuator"] = "yes" }
        let rheedValues: [(String, Double?)] = [
            ("RHEED Grid", rheed.grid), ("RHEED Focus", rheed.focus), ("RHEED X1", rheed.x1),
            ("RHEED Y1", rheed.y1), ("RHEED Y2", rheed.y2), ("RHEED X2", rheed.x2)
        ]
        for (key, value) in rheedValues {
            if let value { metadata[key] = Self.plain(value) }
        }

        var numericTags: [String: Double] = [:]
        var numericDisplay: [String: String] = [:]
        for (tag, value) in numericValues {
            guard let value else { continue }
            numericTags[tag] = value
            numericDisplay[tag] = LibraryRegistryParser.numericDisplay(canonicalKey: tag, number: value)
        }

        return .success(CreateNativeSampleDraft(
            batchId: batchId,
            substrateDescription: substrate,
            displayName: displayName,
            metadata: metadata,
            sampleUID: sampleUID,
            numericTags: numericTags,
            numericDisplay: numericDisplay
        ))
    }

    /// Lab choices from the Rules Book (the single list shared by the desktop window and the phone page).
    static func labOptions(provider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) -> [String] {
        provider.registryRules()?.labOptions ?? []
    }

    /// Growth-material choices from the Rules Book.
    static func growthMaterialOptions(provider: any SpinLabRuleProviding = SpinLabRuleProvider.shared) -> [String] {
        provider.registryRules()?.growthMaterialOptions ?? []
    }

    private static func plain(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// Phone submissions leave out fields the user did not fill, so every key is optional on decode.
/// A value of the wrong type still fails the whole decode (the submission is then left waiting, not guessed).
extension NewSampleFields {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) throws -> String { try c.decodeIfPresent(String.self, forKey: key) ?? "" }
        date = try text(.date)
        lab = try text(.lab)
        growthMaterial = try text(.growthMaterial)
        batch = try text(.batch)
        substrateTreatment = try text(.substrateTreatment)
        substrateMaterial = try text(.substrateMaterial)
        substrateOrientation = try text(.substrateOrientation)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        pressure = try c.decodeIfPresent(Double.self, forKey: .pressure)
        sampleHeight = try c.decodeIfPresent(Double.self, forKey: .sampleHeight)
        frontEnergy = try c.decodeIfPresent(Double.self, forKey: .frontEnergy)
        laserVoltage = try c.decodeIfPresent(Double.self, forKey: .laserVoltage)
        laserOutputEnergy = try c.decodeIfPresent(Double.self, forKey: .laserOutputEnergy)
        hasAttenuator = try c.decodeIfPresent(Bool.self, forKey: .hasAttenuator) ?? false
        prePulseCount = try c.decodeIfPresent(Double.self, forKey: .prePulseCount)
        growthPulseCount = try c.decodeIfPresent(Double.self, forKey: .growthPulseCount)
        frequency = try c.decodeIfPresent(Double.self, forKey: .frequency)
        purpose = try text(.purpose)
        note = try text(.note)
        rheed = try c.decodeIfPresent(Rheed.self, forKey: .rheed) ?? Rheed()
    }
}
