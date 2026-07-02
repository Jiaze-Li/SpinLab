import Foundation

struct IngestAHESelectionsUseCase {

    func execute(
        selections: [AHEPlotSelectionItem],
        numericDisplayBySample: [String: [String: String]] = [:],
        parseFile: (URL) throws -> PPMSParsedFile = { url in try AHEDataParser().parse(fileURL: url) }
    ) throws -> AHEIngestionResult {
        guard !selections.isEmpty else {
            return AHEIngestionResult(
                defaultAxisMapping: WorkbenchAxisMapping(
                    xField: AHEAxisDetector.semanticXField,
                    yField: AHEAxisDetector.semanticYField
                ),
                series: [],
                sourceFiles: [],
                warnings: []
            )
        }

        // Collect unique file paths in selection order
        var seenPaths = Set<String>()
        var orderedPaths: [String] = []
        for s in selections where seenPaths.insert(s.sourceFilePath).inserted {
            orderedPaths.append(s.sourceFilePath)
        }

        // Parse each unique file exactly once
        var parsedFiles: [String: PPMSParsedFile] = [:]
        var warnings: [String] = []

        for path in orderedPaths {
            let url = URL(fileURLWithPath: path)
            do {
                parsedFiles[path] = try parseFile(url)
            } catch {
                warnings.append("Parse failed [\(url.lastPathComponent)]: \(error.localizedDescription)")
            }
        }

        let detector = AHEAxisDetector()

        // Build one WorkbenchPlotSeries per selection
        var series: [WorkbenchPlotSeries] = []

        for selection in selections {
            guard let file = parsedFiles[selection.sourceFilePath] else {
                warnings.append(
                    "Skipped [\(selection.sampleKey) \(selection.channel.rawValue)]: file could not be parsed."
                )
                continue
            }

            let bridgeIndex = selection.channel.bridgeIndex

            guard let resolvedYCol = detector.yColumnName(from: file, bridgeIndex: bridgeIndex) else {
                warnings.append(
                    "Skipped [\(selection.sampleKey) \(selection.channel.rawValue)]: Bridge \(bridgeIndex) has no data in \(URL(fileURLWithPath: selection.sourceFilePath).lastPathComponent)."
                )
                continue
            }

            if resolvedYCol.contains("Resistivity") {
                warnings.append(
                    "[\(selection.sampleKey) \(selection.channel.rawValue)]: using Resistivity column '\(resolvedYCol)' — no unit conversion applied."
                )
            }

            let (rawXs, ys) = detector.pairedValues(
                from: file,
                xColumn: AHEAxisDetector.rawMagneticFieldColumn,
                yColumn: resolvedYCol
            )
            let xs = rawXs.map { $0 * 1e-4 }

            guard !xs.isEmpty else {
                warnings.append(
                    "Skipped [\(selection.sampleKey) \(selection.channel.rawValue)]: no valid paired data rows."
                )
                continue
            }

            let temperature = selection.conditions["temperature"]
            let label = temperature.map {
                "\(selection.sampleKey) | \(selection.channel.rawValue) | \($0)"
            } ?? "\(selection.sampleKey) | \(selection.channel.rawValue)"

            // Build metadata using the same logic as 3ω/XY for resolver compatibility.
            var meta: [String: String] = [:]
            if let t = selection.conditions["temperature"] { meta["temperature"] = t }
            if let d = selection.conditions["device"], !d.isEmpty { meta["device"] = d }
            if let descriptor = SampleSemanticDescriptor.fromSampleKey(selection.sampleKey) {
                let treatment = descriptor.processingTokens.sorted().joined(separator: "+")
                let material = descriptor.material ?? ""
                let orientation = descriptor.orientation ?? ""
                let parts = [treatment, material, orientation].filter { !$0.isEmpty }
                meta["substrate"] = parts.joined(separator: " ")
            } else if !selection.sampleSubstrate.isEmpty {
                meta["substrate"] = selection.sampleSubstrate
            }
            let nd = numericDisplayBySample[selection.sampleKey] ?? [:]
            for (chineseKey, value) in nd {
                let lower = chineseKey.lowercased()
                if lower.contains("能量") || lower.contains("energy") { meta["energy"] = value }
                else if lower.contains("氧压") || lower.contains("pressure") { meta["pressure"] = value }
                else if lower.contains("厚度") || lower.contains("thickness") { meta["thickness"] = value }
                else if lower.contains("温度") || lower.contains("temperature") { meta["growthTemperature"] = value }
            }
            meta["sampleKey"] = selection.sampleKey
            let seriesIdentityKey = WorkbenchSeriesIdentityMetadata.seriesIdentityKey(
                workflowID: selection.workflowID,
                tabKey: WorkbenchPlotSeriesIdentityTabKey.ahe,
                seriesRole: "channel-\(bridgeIndex)",
                stableSemanticID: selection.sourceFilePath
            )
            meta[WorkbenchSeriesOrderKeyResolver.seriesIdentityMetadataKey] = seriesIdentityKey

            series.append(WorkbenchPlotSeries(
                label: label,
                x: xs,
                y: ys,
                sourceRef: selection.sourceFilePath,
                sampleID: selection.sampleKey,
                metadata: meta
            ))
        }

        let defaultAxisMapping = detector.defaultAxisMapping()
        let sourceFiles = orderedPaths.filter { parsedFiles[$0] != nil }

        return AHEIngestionResult(
            defaultAxisMapping: defaultAxisMapping,
            series: series,
            sourceFiles: sourceFiles,
            warnings: warnings
        )
    }
}
