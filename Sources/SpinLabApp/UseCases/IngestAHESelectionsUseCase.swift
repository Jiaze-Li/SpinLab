import Foundation

struct IngestAHESelectionsUseCase {

    func execute(
        selections: [AHEPlotSelectionItem],
        xColumnOverride: String? = nil,
        yColumnOverride: String? = nil,
        parseFile: (URL) throws -> PPMSParsedFile = { url in try AHEDataParser().parse(fileURL: url) }
    ) throws -> AHEIngestionResult {
        guard !selections.isEmpty else {
            return AHEIngestionResult(
                candidateAxisFields: [],
                defaultAxisMapping: WorkbenchAxisMapping(
                    xField: "Magnetic Field (Oe)",
                    yField: "Bridge 1 Resistance (Ohms)"
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
        let allParsed = orderedPaths.compactMap { parsedFiles[$0] }

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

            let isRHRequest = yColumnOverride == "R_H (\u{03A9})"
            let resolvedYCol: String
            if let yOverride = yColumnOverride, !isRHRequest {
                resolvedYCol = yOverride
            } else {
                guard let col = detector.yColumnName(from: file, bridgeIndex: bridgeIndex) else {
                    warnings.append(
                        "Skipped [\(selection.sampleKey) \(selection.channel.rawValue)]: Bridge \(bridgeIndex) has no data in \(URL(fileURLWithPath: selection.sourceFilePath).lastPathComponent)."
                    )
                    continue
                }
                resolvedYCol = col
            }

            if resolvedYCol.contains("Resistivity") {
                warnings.append(
                    "[\(selection.sampleKey) \(selection.channel.rawValue)]: using Resistivity column '\(resolvedYCol)' — no unit conversion applied."
                )
            }

            let isTeslaRequest = xColumnOverride == "Magnetic Field (T)" || xColumnOverride == nil
            let xColumn = isTeslaRequest ? "Magnetic Field (Oe)" : (xColumnOverride ?? "Magnetic Field (Oe)")
            let (rawXs, ys) = detector.pairedValues(
                from: file,
                xColumn: xColumn,
                yColumn: resolvedYCol
            )
            let xs = isTeslaRequest ? rawXs.map { $0 * 1e-4 } : rawXs

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

            series.append(WorkbenchPlotSeries(
                label: label,
                x: xs,
                y: ys,
                sourceRef: selection.sourceFilePath
            ))
        }

        var candidateAxisFields = detector.candidateAxisFields(from: allParsed)
        if let oeIndex = candidateAxisFields.firstIndex(of: "Magnetic Field (Oe)") {
            candidateAxisFields.insert("Magnetic Field (T)", at: oeIndex + 1)
        }
        let defaultAxisMapping = detector.defaultAxisMapping(from: allParsed)
        let sourceFiles = orderedPaths.filter { parsedFiles[$0] != nil }

        return AHEIngestionResult(
            candidateAxisFields: candidateAxisFields,
            defaultAxisMapping: defaultAxisMapping,
            series: series,
            sourceFiles: sourceFiles,
            warnings: warnings
        )
    }
}
