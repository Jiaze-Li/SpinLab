import Foundation

extension RulesBootstrapper {

    static func migrateRulesBookIfNeeded(paths: RulesConfigPaths, internalPaths: AppInternalPaths) {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        let stateURL = internalPaths.migrationStateURL
        let failedURL = internalPaths.migrationFailedURL

        do {
            try fm.createDirectory(at: paths.configDirectoryURL, withIntermediateDirectories: true)
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: cannot create config directory", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        do {
            if fm.fileExists(atPath: stateURL.path) {
                let stateData = try Data(contentsOf: stateURL)
                let stateObj = try JSONSerialization.jsonObject(with: stateData)
                if let state = stateObj as? [String: Any],
                   let version = state["rules_schema_version"] as? Int,
                   version >= 7 {
                    // State says migrated to v7, but verify measuring_condition.json is actually at v7.
                    let measURL = paths.measuringConditionURL
                    let measFileVersion: Int
                    if let md = try? Data(contentsOf: measURL),
                       let mo = try? JSONSerialization.jsonObject(with: md) as? [String: Any],
                       let fv = mo["version"] as? Int {
                        measFileVersion = fv
                    } else {
                        measFileVersion = 0
                    }
                    if measFileVersion >= 7 {
                        AppLogger.shared.info(.import, "RulesBootstrapper migration skipped: already migrated", metadata: [
                            "rules_schema_version": String(version)
                        ])
                        return
                    }
                    AppLogger.shared.info(.import, "RulesBootstrapper: state=\(version) but measuring_condition.json version=\(measFileVersion); continuing migration")
                }
            }
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper migration state unreadable; continuing (\(error.localizedDescription))")
        }

        let measuringURL = paths.measuringConditionURL
        let sampleURL = paths.sampleIdentificationURL
        let workflowURL = paths.workflowURL
        let tokenizationURL = paths.filenameTokenizationURL

        guard fm.fileExists(atPath: measuringURL.path), fm.fileExists(atPath: sampleURL.path) else {
            AppLogger.shared.info(.import, "RulesBootstrapper migration skipped: runtime files incomplete", metadata: [
                "measuring_condition_exists": fm.fileExists(atPath: measuringURL.path) ? "true" : "false",
                "sample_identification_exists": fm.fileExists(atPath: sampleURL.path) ? "true" : "false"
            ])
            return
        }

        let sourceMeasuringData: Data
        let sourceSampleData: Data
        let sourceMeasuringJSON: [String: Any]
        let sourceSampleJSON: [String: Any]
        let tokenizationJSON: [String: Any]?
        let sourceWorkflowData: Data?
        let sourceWorkflowJSON: [String: Any]?
        do {
            sourceMeasuringData = try Data(contentsOf: measuringURL)
            sourceSampleData = try Data(contentsOf: sampleURL)

            let measuringObj = try JSONSerialization.jsonObject(with: sourceMeasuringData)
            let sampleObj = try JSONSerialization.jsonObject(with: sourceSampleData)
            guard let measuringDict = measuringObj as? [String: Any],
                  let sampleDict = sampleObj as? [String: Any] else {
                AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: root JSON is not object", metadata: [:])
                return
            }
            sourceMeasuringJSON = measuringDict
            sourceSampleJSON = sampleDict

            if fm.fileExists(atPath: tokenizationURL.path) {
                let tokenData = try Data(contentsOf: tokenizationURL)
                tokenizationJSON = try JSONSerialization.jsonObject(with: tokenData) as? [String: Any]
            } else {
                tokenizationJSON = nil
            }

            if fm.fileExists(atPath: workflowURL.path) {
                let wfData = try Data(contentsOf: workflowURL)
                sourceWorkflowData = wfData
                sourceWorkflowJSON = try JSONSerialization.jsonObject(with: wfData) as? [String: Any]
            } else {
                sourceWorkflowData = nil
                sourceWorkflowJSON = nil
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to read runtime json", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        let measuringVersion = (sourceMeasuringJSON["version"] as? Int) ?? 0
        let sampleVersion = (sourceSampleJSON["version"] as? Int) ?? 0
        let workflowVersion = (sourceWorkflowJSON?["version"] as? Int) ?? (sourceWorkflowJSON != nil ? 0 : Int.max)
        if measuringVersion >= 7, sampleVersion >= 5, workflowVersion >= 3 {
            var sourceHash: [String: String] = [
                "measuring_condition.json": sha256Hex(sourceMeasuringData),
                "sample_identification.json": sha256Hex(sourceSampleData)
            ]
            if let wfd = sourceWorkflowData {
                sourceHash["workflow.json"] = sha256Hex(wfd)
            }
            writeMigrationState(
                to: stateURL,
                sourceSHA: sourceHash,
                targetSHA: sourceHash,
                warnings: []
            )
            return
        }

        let timestamp = migrationTimestamp()
        let tmpDir = paths.configDirectoryURL.appendingPathComponent(".migration-tmp-\(timestamp)", isDirectory: true)
        let backupDir = paths.configDirectoryURL.appendingPathComponent(".backup-\(timestamp)", isDirectory: true)

        var warnings: [String] = []
        let migratedMeasuringJSON: [String: Any]
        let migratedSampleJSON: [String: Any]
        let migratedWorkflowJSON: [String: Any]?
        do {
            let v2MeasuringJSON = try migrateMeasuringConditionIfNeeded(json: sourceMeasuringJSON, warnings: &warnings)
            let v3MeasuringJSON = try migrateMeasuringConditionV2ToV3IfNeeded(json: v2MeasuringJSON, warnings: &warnings)
            let v4MeasuringJSON = try migrateMeasuringConditionV3ToV4IfNeeded(json: v3MeasuringJSON, warnings: &warnings)
            let v6MeasuringJSON = try migrateMeasuringConditionV5ToV6IfNeeded(json: v4MeasuringJSON, warnings: &warnings)
            migratedMeasuringJSON = try migrateMeasuringConditionV6ToV7IfNeeded(json: v6MeasuringJSON, warnings: &warnings)
            let v2SampleJSON = try migrateSampleIdentificationIfNeeded(json: sourceSampleJSON, warnings: &warnings)
            let v3SampleJSON = try migrateSampleIdentificationV2ToV3IfNeeded(
                json: v2SampleJSON,
                tokenizationJSON: tokenizationJSON,
                warnings: &warnings
            )
            let v4SampleJSON = try migrateSampleIdentificationV3ToV4IfNeeded(
                json: v3SampleJSON,
                warnings: &warnings
            )
            migratedSampleJSON = try migrateSampleIdentificationV4ToV5IfNeeded(
                json: v4SampleJSON,
                warnings: &warnings
            )
            if let wfJSON = sourceWorkflowJSON {
                let v2WorkflowJSON = try migrateWorkflowV1ToV2IfNeeded(json: wfJSON, warnings: &warnings)
                migratedWorkflowJSON = try migrateWorkflowV2ToV3IfNeeded(json: v2WorkflowJSON, warnings: &warnings)
            } else {
                migratedWorkflowJSON = nil
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: transform failed", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        let migratedMeasuringData: Data
        let migratedSampleData: Data
        let migratedWorkflowData: Data?
        do {
            migratedMeasuringData = try JSONSerialization.data(withJSONObject: migratedMeasuringJSON, options: [.prettyPrinted, .sortedKeys])
            migratedSampleData = try JSONSerialization.data(withJSONObject: migratedSampleJSON, options: [.prettyPrinted, .sortedKeys])
            if let wfJSON = migratedWorkflowJSON {
                migratedWorkflowData = try JSONSerialization.data(withJSONObject: wfJSON, options: [.prettyPrinted, .sortedKeys])
            } else {
                migratedWorkflowData = nil
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to encode migrated json", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            try migratedMeasuringData.write(to: tmpDir.appendingPathComponent("measuring_condition.json"), options: .atomic)
            try migratedSampleData.write(to: tmpDir.appendingPathComponent("sample_identification.json"), options: .atomic)
            if let wfd = migratedWorkflowData {
                try wfd.write(to: tmpDir.appendingPathComponent("workflow.json"), options: .atomic)
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to write tmp files", metadata: [
                "reason": error.localizedDescription
            ])
            return
        }

        do {
            _ = try decoder.decode(MigrationMeasuringConditionFile.self, from: migratedMeasuringData)
            _ = try decoder.decode(MigrationSampleIdentificationFile.self, from: migratedSampleData)
            if let wfd = migratedWorkflowData {
                _ = try decoder.decode(MigrationWorkflowFile.self, from: wfd)
            }
        } catch {
            writeMigrationFailed(
                to: failedURL,
                reason: "verify decode failed: \(error.localizedDescription)",
                warnings: warnings
            )
            cleanupTmpDirectory(tmpDir, fileManager: fm)
            return
        }

        let shouldWriteBackup = measuringVersion < 4 || sampleVersion < 5 || measuringVersion < 7
            || (sourceWorkflowData != nil && workflowVersion < 3)
        if shouldWriteBackup {
            do {
                try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                try sourceMeasuringData.write(to: backupDir.appendingPathComponent("measuring_condition.json"), options: .atomic)
                try sourceSampleData.write(to: backupDir.appendingPathComponent("sample_identification.json"), options: .atomic)
                if let wfd = sourceWorkflowData {
                    try wfd.write(to: backupDir.appendingPathComponent("workflow.json"), options: .atomic)
                }
            } catch {
                AppLogger.shared.error(.import, "RulesBootstrapper migration skipped: failed to write backup files", metadata: [
                    "reason": error.localizedDescription
                ])
                cleanupTmpDirectory(tmpDir, fileManager: fm)
                return
            }
        }

        do {
            try migratedMeasuringData.write(to: measuringURL, options: .atomic)
            try migratedSampleData.write(to: sampleURL, options: .atomic)
            if let wfd = migratedWorkflowData {
                try wfd.write(to: workflowURL, options: .atomic)
            }
        } catch {
            AppLogger.shared.error(.import, "RulesBootstrapper migration failed: atomic replace failed", metadata: [
                "reason": error.localizedDescription
            ])
            cleanupTmpDirectory(tmpDir, fileManager: fm)
            return
        }

        var sourceSHA: [String: String] = [
            "measuring_condition.json": sha256Hex(sourceMeasuringData),
            "sample_identification.json": sha256Hex(sourceSampleData)
        ]
        var targetSHA: [String: String] = [
            "measuring_condition.json": sha256Hex(migratedMeasuringData),
            "sample_identification.json": sha256Hex(migratedSampleData)
        ]
        if let wfSrc = sourceWorkflowData, let wfTgt = migratedWorkflowData {
            sourceSHA["workflow.json"] = sha256Hex(wfSrc)
            targetSHA["workflow.json"] = sha256Hex(wfTgt)
        }
        writeMigrationState(
            to: stateURL,
            sourceSHA: sourceSHA,
            targetSHA: targetSHA,
            warnings: warnings
        )

        do {
            if fm.fileExists(atPath: tmpDir.path) {
                try fm.removeItem(at: tmpDir)
            }
        } catch {
            AppLogger.shared.warning(.import, "RulesBootstrapper migration tmp cleanup failed (\(error.localizedDescription))")
        }
    }
}
