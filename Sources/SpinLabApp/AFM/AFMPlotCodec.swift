import Foundation

/// File encoding of a formal AFM Live Plot (`afm_plot_v1`): the rendered PNG, the processed matrix as
/// lossless Float64 little-endian (so numbers never depend on the PNG), and a manifest with
/// coordinates, unit, diagnostics, the effective science/display configuration and input identity.
/// PDF is never stored; it is redrawn from the matrix on export.
struct AFMPlotCodec {
    static let format = "afm_plot_v1"
    static let pngName = "plot.png"
    static let matrixName = "matrix.bin"
    static let manifestName = "manifest.json"

    struct Manifest: Codable, Equatable {
        struct Input: Codable, Equatable {
            let datasetID: String
            let datasetRevision: Int
            let channelID: String
        }
        let schemaVersion: Int
        let format: String
        let title: String
        let savedAt: Date
        let appVersion: String
        let scienceMethodID: String
        let input: Input
        let sampleUIDs: [String]
        let channelLabel: String
        let unit: String
        let xUnit: String
        let yUnit: String
        let nX: Int
        let nY: Int
        let xCoordinates: [Double]
        let yCoordinates: [Double]
        let nonFiniteCount: Int
        let warnings: [String]
        let processingConfiguration: AFMProcessingConfiguration
        let displayState: HeatmapTabRenderState
        let scaleBar: AFMScaleBarSetting
        /// Effective title drawn on the figure (template resolved), kept for reading back without a Dataset.
        let resolvedTitle: String
        let matrixSHA256: String
        let matrixByteLength: Int
        /// Task 7, all optional so older plots decode unchanged (they read as manual).
        /// "auto" when produced by the automatic runner; nil/absent means saved by hand.
        var origin: String? = nil
        /// The applied preset the automatic plot was made under.
        var presetVersionID: String? = nil
        /// Global plot style values actually used, frozen so read-back and PDF export reproduce the figure.
        var globalPlotDefaults: [String: String]? = nil

        var isAutomatic: Bool { origin == Self.automaticOrigin }
        static let automaticOrigin = "auto"
    }

    /// Provenance recorded on an automatic plot.
    struct AutomaticProvenance: Equatable, Sendable {
        let presetVersionID: String
    }

    struct StoredPlot {
        let manifest: Manifest
        let values: [[Double]]
        let png: Data
    }

    enum CodecError: Error, Equatable {
        case missingFile(String)
        case unsupportedManifest(String)
        case matrixMismatch
    }

    static func encode(
        candidate: AFMPlotComputation.Candidate, input: PlotInputRef, sampleUIDs: [String],
        title: String, displayState: HeatmapTabRenderState, savedAt: Date, appVersion: String,
        automatic: AutomaticProvenance? = nil
    ) throws -> StandardizedDatasetContent {
        let processed = candidate.processed
        var blob = Data()
        blob.reserveCapacity(processed.values.count * (processed.values.first?.count ?? 0) * 8)
        for row in processed.values {
            for value in row {
                var bits = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { blob.append(contentsOf: $0) }
            }
        }
        let manifest = Manifest(
            schemaVersion: 1, format: format, title: title, savedAt: savedAt, appVersion: appVersion,
            scienceMethodID: processed.scienceMethodID,
            input: .init(datasetID: input.datasetID, datasetRevision: input.revision, channelID: input.channelID),
            sampleUIDs: sampleUIDs, channelLabel: processed.displayLabel, unit: processed.unit,
            xUnit: CanonicalAFMDataset.xUnit, yUnit: CanonicalAFMDataset.yUnit,
            nX: processed.xCoordinates.count, nY: processed.yCoordinates.count,
            xCoordinates: processed.xCoordinates, yCoordinates: processed.yCoordinates,
            nonFiniteCount: processed.nonFiniteCount, warnings: processed.warnings,
            processingConfiguration: processed.configuration, displayState: displayState,
            scaleBar: candidate.display.scaleBar,
            resolvedTitle: candidate.display.displayState.titleOverride,
            matrixSHA256: AssetHashing.sha256Hex(blob), matrixByteLength: blob.count,
            origin: automatic == nil ? nil : Manifest.automaticOrigin,
            presetVersionID: automatic?.presetVersionID,
            globalPlotDefaults: automatic == nil ? nil : candidate.display.globalPlotDefaults
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return StandardizedDatasetContent(format: format, files: [
            StandardizedFile(name: pngName, data: candidate.imageData),
            StandardizedFile(name: matrixName, data: blob),
            StandardizedFile(name: manifestName, data: try encoder.encode(manifest)),
        ])
    }

    static func decodeManifest(_ data: Data) throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(Manifest.self, from: data)
        guard manifest.format == format, manifest.schemaVersion == 1 else {
            throw CodecError.unsupportedManifest("\(manifest.format) v\(manifest.schemaVersion)")
        }
        return manifest
    }

    static func decode(files: [String: Data]) throws -> StoredPlot {
        guard let manifestData = files[manifestName] else { throw CodecError.missingFile(manifestName) }
        guard let blob = files[matrixName] else { throw CodecError.missingFile(matrixName) }
        guard let png = files[pngName] else { throw CodecError.missingFile(pngName) }
        let manifest = try decodeManifest(manifestData)
        guard blob.count == manifest.matrixByteLength, blob.count == manifest.nX * manifest.nY * 8,
              AssetHashing.sha256Hex(blob) == manifest.matrixSHA256 else { throw CodecError.matrixMismatch }
        var values: [[Double]] = []
        values.reserveCapacity(manifest.nY)
        blob.withUnsafeBytes { raw in
            for y in 0..<manifest.nY {
                var row: [Double] = []
                row.reserveCapacity(manifest.nX)
                for x in 0..<manifest.nX {
                    let bits = raw.loadUnaligned(fromByteOffset: (y * manifest.nX + x) * 8, as: UInt64.self)
                    row.append(Double(bitPattern: UInt64(littleEndian: bits)))
                }
                values.append(row)
            }
        }
        return StoredPlot(manifest: manifest, values: values, png: png)
    }

    /// Redraws the figure from a stored matrix alone (no Dataset needed): used for PDF export.
    static func render(stored: StoredPlot, styleDefaults: [String: String]) throws -> HeatmapRenderPipeline.Output {
        let m = stored.manifest
        let channel = ProcessedAFMChannel(
            sourceChannelID: m.input.channelID, values: stored.values, canonicalUnit: m.unit,
            displayLabel: m.channelLabel, configuration: m.processingConfiguration, warnings: m.warnings
        )
        let dataset = CanonicalAFMDataset(
            sourceRef: "", title: m.title, xCoordinates: m.xCoordinates, yCoordinates: m.yCoordinates, channels: [],
            sourceMetadata: .init(sourceFilePath: "", waveName: "", sourceWidth: m.nX, sourceHeight: m.nY, rawNote: "")
        )
        var display = m.displayState
        display.titleOverride = m.resolvedTitle
        let payload = try AFMHeatmapPayloadBuilder.build(
            dataset: dataset, processed: channel, options: .init(workflowID: "afm", title: m.resolvedTitle, scaleBar: m.scaleBar)
        )
        return try HeatmapRenderPipeline.render(.init(
            payload: payload, colorScaleMode: display.colorScaleMode, zDomainState: display.zDomainState,
            chartStyle: WorkbenchChartStyle.from(styleParams: m.globalPlotDefaults ?? styleDefaults), showColorbar: display.showColorbar,
            showTitle: display.showTitle, interpolationMode: display.interpolationMode,
            colorbarTickStyleOverride: .zHeightTicks(unit: m.unit)
        ))
    }
}
