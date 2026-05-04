import Foundation

extension RulesBootstrapper {

    static func migrateWorkflowV1ToV2IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 2 else { return json }

        func stripScope(_ spec: [String: Any]) -> [String: Any] {
            var s = spec
            s.removeValue(forKey: "scope")
            return s
        }

        let rawWorkflows = (json["workflows"] as? [[String: Any]]) ?? []
        let migratedWorkflows: [[String: Any]] = rawWorkflows.map { wf in
            var w = wf
            if let matchRules = wf["matchRules"] as? [[String: Any]] {
                w["matchRules"] = matchRules.map(stripScope)
            }
            return w
        }

        let rawTagRules = (json["measurementTagRules"] as? [[String: Any]]) ?? []
        let migratedTagRules: [[String: Any]] = rawTagRules.map { rule in
            guard var match = rule["match"] as? [String: Any] else { return rule }
            match.removeValue(forKey: "scope")
            var r = rule
            r["match"] = match
            return r
        }

        var migrated = json
        migrated["version"] = 2
        migrated["workflows"] = migratedWorkflows
        migrated["measurementTagRules"] = migratedTagRules
        return migrated
    }

    static func migrateWorkflowV2ToV3IfNeeded(json: [String: Any], warnings: inout [String]) throws -> [String: Any] {
        let version = (json["version"] as? Int) ?? 0
        guard version < 3 else { return json }

        let rawWorkflows = (json["workflows"] as? [[String: Any]]) ?? []
        var migratedWorkflows: [[String: Any]] = []
        for wf in rawWorkflows {
            var w = wf
            let wfID = (wf["id"] as? String) ?? "?"
            if let legacyRules = wf["matchRules"] as? [[String: Any]] {
                var expandedRules: [[String: Any]] = []
                for (ruleIdx, rule) in legacyRules.enumerated() {
                    let label = "workflow: workflows[\(wfID)].matchRules[\(ruleIdx)]"
                    if let scopeStr = rule["scope"] as? String, scopeStr == "joined" {
                        warnings.append("\(label) legacy scope 'joined' was removed; rule is now token-scoped")
                    }
                    expandedRules.append(contentsOf: expandLegacyMatchSpec(rule, label: label, warnings: &warnings))
                }
                w["matchRules"] = expandedRules
            }
            migratedWorkflows.append(w)
        }

        let rawTagRules = (json["measurementTagRules"] as? [[String: Any]]) ?? []
        var migratedTagRules: [[String: Any]] = []
        for (ruleIdx, rule) in rawTagRules.enumerated() {
            guard let matchSpec = rule["match"] as? [String: Any] else { continue }
            let outputValue = (rule["value"] as? String) ?? ""
            let label = "workflow: measurementTagRules[\(ruleIdx)].match"
            if let scopeStr = matchSpec["scope"] as? String, scopeStr == "joined" {
                warnings.append("\(label) legacy scope 'joined' was removed; rule is now token-scoped")
            }
            let expanded = expandLegacyMatchSpec(matchSpec, label: label, warnings: &warnings)
            for newSpec in expanded {
                migratedTagRules.append(["match": newSpec, "value": outputValue])
            }
        }

        var migrated = json
        migrated["version"] = 3
        migrated["workflows"] = migratedWorkflows
        migrated["measurementTagRules"] = migratedTagRules
        return migrated
    }
}
