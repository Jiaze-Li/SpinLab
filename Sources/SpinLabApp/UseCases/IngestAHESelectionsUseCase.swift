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
                    xField: AHEAxisDetector.displayXField,
                    yField: AHEAxisDetector.displayYField
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

            // Build resolver-compatible metadata via the shared builder (same path as
            // RT/IV/XY Rotation/3ω) so AHE stays in sync with sibling workflows, including batchID.
            var meta = WorkbenchSeriesMetadataBuilder.build(
                from: _searchHit(for: selection),
                numericDisplay: numericDisplayBySample[selection.sampleKey] ?? [:]
            )
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

    /// Adapts an AHE selection into the shape `WorkbenchSeriesMetadataBuilder` expects.
    /// Only `conditions`, `sampleKey`, `sampleSubstrate`, and `batchID` feed the built
    /// metadata; the remaining fields are populated from selection data but unused by the builder.
    private func _searchHit(for selection: AHEPlotSelectionItem) -> WorkflowMeasurementSearchHit {
        WorkflowMeasurementSearchHit(
            sidecarPath: selection.sourceFilePath,
            measurementFilePath: selection.sourceFilePath,
            sourceFilePath: selection.sourceFilePath,
            workflowID: selection.workflowID,
            workflowDisplayName: "AHE",
            workflowCanonicalID: selection.workflowID,
            batchID: selection.batchID,
            sampleKey: selection.sampleKey,
            sampleSubstrate: selection.sampleSubstrate,
            conditions: selection.conditions,
            channels: [selection.channel.rawValue],
            appliedAt: .distantPast
        )
    }
}
