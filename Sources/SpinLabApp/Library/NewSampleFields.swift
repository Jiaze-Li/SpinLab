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

    struct Substrate: Codable, Equatable, Sendable {
        var treatment: String = ""
        var material: String = ""
        var orientation: String = ""

        var isEmpty: Bool {
            [treatment, material, orientation].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    /// yyyy-MM-dd; empty means "not given".
    var date: String = ""
    var lab: String = ""
    var growthMaterial: String = ""
    var batch: String = ""
    var substrateTreatment: String = ""
    var substrateMaterial: String = ""
    var substrateOrientation: String = ""
    /// More substrates grown in the same run. The three fields above are the first substrate;
    /// each substrate becomes its own sample under the same batch with the same growth record.
    var extraSubstrates: [Substrate] = []
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

    /// Value of a number field by its schema key (`NewSampleFormSchema`); nil for an unknown key.
    func number(forKey key: String) -> Double? {
        switch key {
        case "temperature": return temperature
        case "pressure": return pressure
        case "sampleHeight": return sampleHeight
        case "frontEnergy": return frontEnergy
        case "laserVoltage": return laserVoltage
        case "laserOutputEnergy": return laserOutputEnergy
        case "prePulseCount": return prePulseCount
        case "growthPulseCount": return growthPulseCount
        case "frequency": return frequency
        default: return nil
        }
    }

    mutating func setNumber(_ value: Double?, forKey key: String) {
        switch key {
        case "temperature": temperature = value
        case "pressure": pressure = value
        case "sampleHeight": sampleHeight = value
        case "frontEnergy": frontEnergy = value
        case "laserVoltage": laserVoltage = value
        case "laserOutputEnergy": laserOutputEnergy = value
        case "prePulseCount": prePulseCount = value
        case "growthPulseCount": growthPulseCount = value
        case "frequency": frequency = value
        default: break
        }
    }

    func rheedValue(forKey key: String) -> Double? {
        switch key {
        case "grid": return rheed.grid
        case "focus": return rheed.focus
        case "x1": return rheed.x1
        case "y1": return rheed.y1
        case "y2": return rheed.y2
        case "x2": return rheed.x2
        default: return nil
        }
    }

    mutating func setRheed(_ value: Double?, forKey key: String) {
        switch key {
        case "grid": rheed.grid = value
        case "focus": rheed.focus = value
        case "x1": rheed.x1 = value
        case "y1": rheed.y1 = value
        case "y2": rheed.y2 = value
        case "x2": rheed.x2 = value
        default: break
        }
    }

    /// Numeric tag name and value for each number field, in schema order. Names with an entry in
    /// `LibraryRegistryParser.numericUnits` get their unit from there.
    private var numericValues: [(tag: String, value: Double?)] {
        NewSampleFormSchema.shared.numberFields.map { field in
            let value = number(forKey: field.key)
            return (field.tag, field.key == "frequency" ? (value ?? Double(RegistryGrowthPulseMapper.defaultHz)) : value)
        }
    }

    /// Sample id of the substrate at `index` (0 is the first). The first keeps `baseUID` unchanged, so a
    /// single-substrate submission is identical to before; later ones get a stable "-2", "-3" suffix
    /// so a repeated pickup finds every sample already there.
    static func sampleUID(base: String, index: Int) -> String {
        index == 0 ? base : "\(base)-\(index + 1)"
    }

    /// Validates and converts to the draft the creation service consumes (first substrate only).
    /// Batch, growth material and the substrate's material and orientation are required.
    func makeDraft(
        sampleUID: String,
        choices: NativeSampleSubstrateChoices,
        displayName: String? = nil
    ) -> Result<CreateNativeSampleDraft, CreateNativeSampleError> {
        makeDraft(
            substrate: Substrate(
                treatment: substrateTreatment, material: substrateMaterial, orientation: substrateOrientation
            ),
            sampleUID: sampleUID, choices: choices, displayName: displayName
        )
    }

    /// One draft per substrate, in order: the first substrate, then every non-empty extra one.
    /// A half-filled extra substrate is an error, not silently dropped. A custom display name only
    /// applies when there is exactly one substrate (it would otherwise name several samples alike).
    func makeDrafts(
        sampleUID: String,
        choices: NativeSampleSubstrateChoices,
        displayName: String? = nil
    ) -> Result<[CreateNativeSampleDraft], CreateNativeSampleError> {
        let first = Substrate(
            treatment: substrateTreatment, material: substrateMaterial, orientation: substrateOrientation
        )
        let extras = extraSubstrates.filter { !$0.isEmpty }
        var drafts: [CreateNativeSampleDraft] = []
        for (index, substrate) in ([first] + extras).enumerated() {
            let name = extras.isEmpty ? displayName : nil
            switch makeDraft(
                substrate: substrate,
                sampleUID: Self.sampleUID(base: sampleUID, index: index),
                choices: choices,
                displayName: name
            ) {
            case let .success(draft): drafts.append(draft)
            case let .failure(error): return .failure(error)
            }
        }
        return .success(drafts)
    }

    private func makeDraft(
        substrate: Substrate,
        sampleUID: String,
        choices: NativeSampleSubstrateChoices,
        displayName: String?
    ) -> Result<CreateNativeSampleDraft, CreateNativeSampleError> {
        let batchId = batch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !batchId.isEmpty else { return .failure(.invalidInput("Batch is required.")) }
        let material = growthMaterial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !material.isEmpty else { return .failure(.invalidInput("Growth material is required.")) }
        guard let substrateText = choices.composeDescription(
            material: substrate.material,
            orientation: substrate.orientation,
            treatment: substrate.treatment
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
        for field in NewSampleFormSchema.shared.rheedFields {
            if let value = rheedValue(forKey: field.key) { metadata[field.metadataKey] = Self.plain(value) }
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
            substrateDescription: substrateText,
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
        extraSubstrates = try c.decodeIfPresent([Substrate].self, forKey: .extraSubstrates) ?? []
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
