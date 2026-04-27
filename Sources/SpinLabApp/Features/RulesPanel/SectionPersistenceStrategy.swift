import Foundation

// MARK: - Post-load effect

enum PostLoadEffect {
    case none
    case updateConditionFieldIDs([String])
}

// MARK: - Cross-section context passed into validate / postLoad / postPersist

struct StoreContext {
    let dirtyMeasuringCondition: MeasuringConditionFileDraft?
    let dirtyWorkflow: WorkflowFileDraft?
    let loadMeasuringConditionFromDisk: () -> MeasuringConditionFileDraft?
    let loadWorkflowFromDisk: () -> WorkflowFileDraft?

    func resolvedMeasuringCondition() -> MeasuringConditionFileDraft? {
        dirtyMeasuringCondition ?? loadMeasuringConditionFromDisk()
    }

    func resolvedWorkflow() -> WorkflowFileDraft? {
        dirtyWorkflow ?? loadWorkflowFromDisk()
    }
}

// MARK: - Protocol

protocol SectionPersistenceStrategy<Draft> {
    associatedtype Draft: Codable
    var runtimeURL: URL { get }
    func validate(_ draft: Draft, context: StoreContext) -> [RulesPanelFieldError]
    func postLoad(_ draft: Draft, context: StoreContext) -> PostLoadEffect
    func postPersist(_ draft: Draft, context: StoreContext)
}

extension SectionPersistenceStrategy {
    func postLoad(_ draft: Draft, context: StoreContext) -> PostLoadEffect { .none }
    func postPersist(_ draft: Draft, context: StoreContext) {}
}

// MARK: - Shared regex helper

func validateRegexField(_ pattern: String, field: String, errors: inout [RulesPanelFieldError]) {
    guard !pattern.isEmpty else { return }
    do {
        _ = try NSRegularExpression(pattern: pattern, options: [])
    } catch {
        errors.append(.init(field: field, message: "Invalid regex '\(pattern)': \(error.localizedDescription)"))
    }
}

// MARK: - Import Filters

struct ImportFiltersStrategy: SectionPersistenceStrategy {
    let runtimeURL: URL

    func validate(_ draft: ImportFiltersFileDraft, context: StoreContext) -> [RulesPanelFieldError] {
        var errors: [RulesPanelFieldError] = []
        let allExts = draft.config.supportedFileExtensions + draft.config.ignoredFileExtensions
        for ext in allExts where ext.contains(" ") {
            errors.append(.init(field: "extensions", message: "Extension '\(ext)' must not contain spaces"))
        }
        for ext in allExts where ext.hasPrefix(".") {
            errors.append(.init(field: "extensions", message: "Extension '\(ext)' must not start with '.'"))
        }
        let supported = Set(draft.config.supportedFileExtensions)
        let ignored = Set(draft.config.ignoredFileExtensions)
        for ext in supported.intersection(ignored).sorted() {
            errors.append(.init(field: "extensions", message: "'\(ext)' is in both supported and ignored"))
        }
        return errors
    }
}

// MARK: - Filename Tokenization

struct FilenameTokenizationStrategy: SectionPersistenceStrategy {
    let runtimeURL: URL

    func validate(_ draft: FilenameTokenizationFileDraft, context: StoreContext) -> [RulesPanelFieldError] {
        var errors: [RulesPanelFieldError] = []
        if draft.tokenization.separators.isEmpty {
            errors.append(.init(field: "tokenization.separators", message: "Separators must not be empty"))
        }
        let allowedSources: Set<String> = ["file", "parent", "grandparent"]
        let deduped = Array(NSOrderedSet(array: draft.sources)) as? [String] ?? draft.sources
        if deduped.isEmpty {
            errors.append(.init(field: "sources", message: "Sources must contain at least one entry"))
        }
        for source in deduped where !allowedSources.contains(source) {
            errors.append(.init(field: "sources", message: "Unknown source '\(source)'; allowed: file, parent, grandparent"))
        }
        for (key, value) in draft.channel.aliases where key.isEmpty || value.isEmpty {
            errors.append(.init(field: "channel.aliases", message: "Alias key and value must not be empty"))
        }
        return errors
    }
}

// MARK: - Sample Identification

struct SampleIdentificationStrategy: SectionPersistenceStrategy {
    let runtimeURL: URL

    func validate(_ draft: SampleIdentificationFileDraft, context: StoreContext) -> [RulesPanelFieldError] {
        var errors: [RulesPanelFieldError] = []
        var seenMaterials: Set<String> = []
        for m in draft.substrate.materials {
            if m.displayName.isEmpty {
                errors.append(.init(field: "substrate.materials", message: "Material displayName must not be empty"))
            }
            if !seenMaterials.insert(m.displayName).inserted {
                errors.append(.init(field: "substrate.materials[\(m.displayName)]", message: "Duplicate material '\(m.displayName)'"))
            }
        }
        var seenTreatments: Set<String> = []
        for t in draft.substrate.treatments {
            if t.displayName.isEmpty {
                errors.append(.init(field: "substrate.treatments", message: "Treatment displayName must not be empty"))
            }
            if !seenTreatments.insert(t.displayName).inserted {
                errors.append(.init(field: "substrate.treatments[\(t.displayName)]", message: "Duplicate treatment '\(t.displayName)'"))
            }
        }
        var seenOrientations: Set<String> = []
        for o in draft.substrate.orientations {
            if o.displayName.isEmpty {
                errors.append(.init(field: "substrate.orientations", message: "Orientation displayName must not be empty"))
            }
            if !seenOrientations.insert(o.displayName).inserted {
                errors.append(.init(field: "substrate.orientations[\(o.displayName)]", message: "Duplicate orientation '\(o.displayName)'"))
            }
        }
        return errors
    }
}

// MARK: - Workflow

struct WorkflowStrategy: SectionPersistenceStrategy {
    let runtimeURL: URL

    func validate(_ draft: WorkflowFileDraft, context: StoreContext) -> [RulesPanelFieldError] {
        var errors: [RulesPanelFieldError] = []
        var seenIDs: Set<String> = []
        for w in draft.workflows {
            if w.id.isEmpty || w.id.contains(where: \.isWhitespace) {
                errors.append(.init(field: "workflows[\(w.id)].id",
                                    message: "Workflow ID must be non-empty and contain no whitespace"))
            }
            if !seenIDs.insert(w.id).inserted {
                errors.append(.init(field: "workflows[\(w.id)].id",
                                    message: "Duplicate workflow ID '\(w.id)'"))
            }
            if w.displayName.isEmpty {
                errors.append(.init(field: "workflows[\(w.id)].displayName",
                                    message: "Display name must not be empty"))
            }
            if w.matchRules.isEmpty {
                errors.append(.init(field: "workflows[\(w.id)].matchRules",
                                    message: "Workflow '\(w.id)' must have at least one match rule"))
            }
            for spec in w.matchRules where spec.type == "regex" {
                spec.matchValues.forEach {
                    validateRegexField($0, field: "workflows[\(w.id)].matchRules", errors: &errors)
                }
            }
        }
        let knownConditionIDs: Set<String>
        if let mc = context.resolvedMeasuringCondition() {
            knownConditionIDs = Set(mc.conditionDefinitions.map(\.id))
        } else {
            knownConditionIDs = []
        }
        for w in draft.workflows {
            for fieldID in w.conditionFieldIDs where !knownConditionIDs.contains(fieldID) {
                errors.append(.init(field: "workflows[\(w.id)].conditionFieldIDs",
                                    message: "Condition '\(fieldID)' not found in measuring_condition.json"))
            }
        }
        for rule in draft.measurementTagRules where rule.match.type == "regex" {
            rule.match.matchValues.forEach {
                validateRegexField($0, field: "measurementTagRules", errors: &errors)
            }
        }
        return errors
    }
}

// MARK: - Measuring Condition

struct MeasuringConditionStrategy: SectionPersistenceStrategy {
    let runtimeURL: URL

    func validate(_ draft: MeasuringConditionFileDraft, context: StoreContext) -> [RulesPanelFieldError] {
        var errors: [RulesPanelFieldError] = []
        var seenIDs: Set<String> = []
        for def in draft.conditionDefinitions {
            if !seenIDs.insert(def.id).inserted {
                errors.append(.init(field: "conditionDefinitions", message: "Duplicate condition ID '\(def.id)'"))
            }
            guard def.kind == "unit_suffix" || def.kind == "token_map" else {
                errors.append(.init(field: "conditionDefinitions[\(def.id)].kind",
                                    message: "Unknown kind '\(def.kind)'"))
                continue
            }
            if def.kind == "unit_suffix" {
                if def.tokenMap != nil {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "unit_suffix must not have tokenMap"))
                }
                let pattern = def.unitPattern ?? ""
                if pattern.isEmpty {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "unit_suffix requires a non-empty unitPattern"))
                } else {
                    validateRegexField(pattern, field: "conditionDefinitions[\(def.id)].unitPattern", errors: &errors)
                }
            } else {
                if def.unitPattern != nil {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "token_map must not have unitPattern"))
                }
                if def.tokenMap == nil {
                    errors.append(.init(field: "conditionDefinitions[\(def.id)]",
                                        message: "token_map requires tokenMap"))
                }
                for rule in def.tokenMap ?? [] where rule.match.type == "regex" {
                    rule.match.matchValues.forEach {
                        validateRegexField($0, field: "conditionDefinitions[\(def.id)].tokenMap", errors: &errors)
                    }
                }
            }
        }
        return errors
    }

    func postLoad(_ draft: MeasuringConditionFileDraft, context: StoreContext) -> PostLoadEffect {
        .updateConditionFieldIDs(draft.conditionDefinitions.map(\.id))
    }
}
