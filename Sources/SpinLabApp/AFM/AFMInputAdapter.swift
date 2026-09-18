import Foundation

/// Converts a raw IBW byte decode (`IBWWave`) into an immutable, unit-explicit
/// `CanonicalAFMDataset`. This is the only place IBW units are interpreted and AFM channel
/// identity/semantics/provenance are derived — see
/// `docs/architecture/workbench/datasets/AFMDatasetContract.md`.
enum AFMInputAdapter {
    struct Output {
        let dataset: CanonicalAFMDataset
        /// Non-fatal warnings surfaced during adaptation (e.g. no Height channel found).
        let warnings: [String]
    }

    static func load(fileURL: URL) throws -> Output {
        let data = try Data(contentsOf: fileURL)
        return try build(from: data, sourceRef: fileURL.path)
    }

    static func build(from data: Data, sourceRef: String) throws -> Output {
        let wave = try IBWReader.read(data)

        let nX = wave.nDim[0]
        let nY = wave.nDim[1]
        let channelCount = wave.nDim[2] > 0 ? wave.nDim[2] : 1

        // X/Y calibration → µm. Blank dimension units default to meters, the IBW/instrument
        // convention for spatial dimensions — never guessed from filename or channel labels.
        let xUnitRaw = wave.dimUnits[0].isEmpty ? "m" : wave.dimUnits[0]
        let yUnitRaw = wave.dimUnits[1].isEmpty ? "m" : wave.dimUnits[1]
        guard let xMetersPerUnit = AFMLengthUnit.metersPerUnit(xUnitRaw),
              let yMetersPerUnit = AFMLengthUnit.metersPerUnit(yUnitRaw) else {
            throw IBWReadError.malformedDimensions
        }
        let xCoordinates = (0..<nX).map { i in
            (wave.sfA[0] * Double(i) + wave.sfB[0]) * xMetersPerUnit * 1e6
        }
        let yCoordinates = (0..<nY).map { j in
            (wave.sfA[1] * Double(j) + wave.sfB[1]) * yMetersPerUnit * 1e6
        }

        let channelLabels = wave.dimLabels[2]   // [0] = whole-dim label, [1...N] = per-channel
        let noteFields = AFMNoteFields(note: wave.note)

        // The wave's single data unit is shared by every channel (IBW carries no per-channel
        // unit); convert to nm only when it resolves to a recognized length unit.
        let sourceUnit = wave.dataUnit
        let metersPerSourceUnit = AFMLengthUnit.metersPerUnit(sourceUnit)
        let canonicalUnit = metersPerSourceUnit != nil ? "nm" : sourceUnit
        let toCanonicalScale = metersPerSourceUnit.map { $0 * 1e9 }

        var channels: [CanonicalAFMChannel] = []
        channels.reserveCapacity(channelCount)
        for c in 0..<channelCount {
            let sourceLabel = channelLabels.count > c + 1 ? channelLabels[c + 1] : "Channel\(c + 1)"

            var matrix = [[Double]](repeating: [Double](repeating: .nan, count: nX), count: nY)
            let channelOffset = c * nX * nY
            for y in 0..<nY {
                let rowOffset = channelOffset + y * nX
                for x in 0..<nX {
                    let raw = Double(wave.floatValues[rowOffset + x])
                    matrix[y][x] = toCanonicalScale.map { raw * $0 } ?? raw
                }
            }

            channels.append(CanonicalAFMChannel(
                id: "ch\(c)-\(sourceLabel)",
                sourceIndex: c,
                sourceLabel: sourceLabel,
                semanticTypeRaw: noteFields.channelDataType(index: c),
                displayLabel: sourceLabel,
                values: matrix,
                canonicalUnit: canonicalUnit,
                sourceUnit: sourceUnit,
                provenance: noteFields.provenance(index: c)
            ))
        }

        var warnings: [String] = []
        let resolution = AFMChannelResolver.resolveDefaultChannel(in: channels)
        if let warning = resolution.warning {
            warnings.append(warning)
        }

        let dataset = CanonicalAFMDataset(
            sourceRef: sourceRef,
            title: wave.waveName,
            xCoordinates: xCoordinates,
            yCoordinates: yCoordinates,
            channels: channels,
            sourceMetadata: AFMSourceProvenance(
                sourceFilePath: sourceRef,
                waveName: wave.waveName,
                sourceWidth: nX,
                sourceHeight: nY,
                rawNote: wave.note
            )
        )
        return Output(dataset: dataset, warnings: warnings)
    }
}
