import Foundation

/// Lossless on-disk encoding of a `CanonicalAFMDataset`: a JSON manifest plus one IEEE-754
/// Float64 little-endian matrix blob (`values[y][x]`, row-major, channels in source order).
///
/// Non-finite values (`NaN`, `±Inf`) cannot go through `JSONEncoder`, so every matrix value lives
/// in the binary blob and round-trips bit-exactly. Identity (`dst_`/`src_` IDs, revision) is owned
/// by the asset database, never repeated in the manifest.
struct AFMDatasetCodec: DatasetPayloadCodec {
    typealias Dataset = CanonicalAFMDataset

    static let format = "afm_canonical_v1"
    static let manifestName = "manifest.json"
    static let matricesName = "matrices.bin"

    var datasetFormat: String { Self.format }

    enum CodecError: Error, Equatable {
        case emptyDataset
        case shapeMismatch(String)
        case nonFiniteCoordinate
        case unsupportedManifest(String)
        case matricesLengthMismatch(expected: Int, found: Int)
        case matricesHashMismatch
        case missingFile(String)
    }

    struct Manifest: Codable, Equatable {
        struct SourceMetadata: Codable, Equatable {
            let waveName: String
            let sourceWidth: Int
            let sourceHeight: Int
            let rawNote: String
            let historicalSourceRef: String
        }

        struct Channel: Codable, Equatable {
            let id: String
            let sourceIndex: Int
            let sourceLabel: String
            let semanticTypeRaw: String?
            let displayLabel: String
            let canonicalUnit: String
            let sourceUnit: String
            let provenance: AFMChannelProvenance
            let byteOffset: Int
            let byteLength: Int
            let dtype: String
            let nonFiniteCount: Int
        }

        let schemaVersion: Int
        let format: String
        let title: String
        let xUnit: String
        let yUnit: String
        let nX: Int
        let nY: Int
        let xCoordinates: [Double]
        let yCoordinates: [Double]
        let sourceMetadata: SourceMetadata
        let matricesSHA256: String
        let matricesByteLength: Int
        let channels: [Channel]
    }

    // MARK: Encode

    func encode(_ dataset: CanonicalAFMDataset) throws -> StandardizedDatasetContent {
        guard !dataset.channels.isEmpty else { throw CodecError.emptyDataset }
        let nX = dataset.xCoordinates.count
        let nY = dataset.yCoordinates.count
        guard nX > 0, nY > 0 else { throw CodecError.emptyDataset }
        guard dataset.xCoordinates.allSatisfy(\.isFinite), dataset.yCoordinates.allSatisfy(\.isFinite) else {
            throw CodecError.nonFiniteCoordinate
        }

        var blob = Data()
        if let perChannel = try? Self.safeChannelByteLength(nX: nX, nY: nY) {
            let (total, overflow) = dataset.channels.count.multipliedReportingOverflow(by: perChannel)
            if !overflow { blob.reserveCapacity(total) }
        }
        var channelManifests: [Manifest.Channel] = []
        for channel in dataset.channels {
            guard channel.values.count == nY, channel.values.allSatisfy({ $0.count == nX }) else {
                throw CodecError.shapeMismatch("channel '\(channel.id)' is not \(nY)×\(nX)")
            }
            let offset = blob.count
            var nonFinite = 0
            for row in channel.values {
                for value in row {
                    if !value.isFinite { nonFinite += 1 }
                    var bits = value.bitPattern.littleEndian
                    withUnsafeBytes(of: &bits) { blob.append(contentsOf: $0) }
                }
            }
            channelManifests.append(Manifest.Channel(
                id: channel.id, sourceIndex: channel.sourceIndex, sourceLabel: channel.sourceLabel,
                semanticTypeRaw: channel.semanticTypeRaw, displayLabel: channel.displayLabel,
                canonicalUnit: channel.canonicalUnit, sourceUnit: channel.sourceUnit, provenance: channel.provenance,
                byteOffset: offset, byteLength: blob.count - offset, dtype: "float64_le", nonFiniteCount: nonFinite
            ))
        }

        let manifest = Manifest(
            schemaVersion: 1, format: Self.format, title: dataset.title,
            xUnit: CanonicalAFMDataset.xUnit, yUnit: CanonicalAFMDataset.yUnit, nX: nX, nY: nY,
            xCoordinates: dataset.xCoordinates, yCoordinates: dataset.yCoordinates,
            sourceMetadata: Manifest.SourceMetadata(
                waveName: dataset.sourceMetadata.waveName, sourceWidth: dataset.sourceMetadata.sourceWidth,
                sourceHeight: dataset.sourceMetadata.sourceHeight, rawNote: dataset.sourceMetadata.rawNote,
                historicalSourceRef: dataset.sourceRef
            ),
            matricesSHA256: AssetHashing.sha256Hex(blob), matricesByteLength: blob.count, channels: channelManifests
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return StandardizedDatasetContent(format: Self.format, files: [
            StandardizedFile(name: Self.manifestName, data: try encoder.encode(manifest)),
            StandardizedFile(name: Self.matricesName, data: blob)
        ])
    }

    // MARK: Decode

    func decode(files: [String: Data]) throws -> CanonicalAFMDataset {
        guard let manifestData = files[Self.manifestName] else { throw CodecError.missingFile(Self.manifestName) }
        guard let blob = files[Self.matricesName] else { throw CodecError.missingFile(Self.matricesName) }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schemaVersion == 1, manifest.format == Self.format else {
            throw CodecError.unsupportedManifest("schemaVersion \(manifest.schemaVersion), format \(manifest.format)")
        }
        let nX = manifest.nX
        let nY = manifest.nY
        guard nX > 0, nY > 0, manifest.xCoordinates.count == nX, manifest.yCoordinates.count == nY else {
            throw CodecError.shapeMismatch("coordinates do not match \(nY)×\(nX)")
        }
        let perChannelBytes = try Self.safeChannelByteLength(nX: nX, nY: nY)
        let (expected, totalOverflow) = manifest.channels.count.multipliedReportingOverflow(by: perChannelBytes)
        guard !totalOverflow else {
            throw CodecError.unsupportedManifest("total matrices byte length overflow")
        }
        guard blob.count == expected, manifest.matricesByteLength == expected else {
            throw CodecError.matricesLengthMismatch(expected: expected, found: blob.count)
        }
        guard AssetHashing.sha256Hex(blob) == manifest.matricesSHA256 else { throw CodecError.matricesHashMismatch }

        var channels: [CanonicalAFMChannel] = []
        for meta in manifest.channels {
            let (channelEnd, offsetOverflow) = meta.byteOffset.addingReportingOverflow(meta.byteLength)
            guard meta.dtype == "float64_le", meta.byteLength == perChannelBytes,
                  meta.byteOffset >= 0, !offsetOverflow, channelEnd <= blob.count else {
                throw CodecError.unsupportedManifest("channel '\(meta.id)' layout")
            }
            var matrix = [[Double]](repeating: [Double](repeating: 0, count: nX), count: nY)
            blob.withUnsafeBytes { raw in
                for y in 0..<nY {
                    for x in 0..<nX {
                        let position = meta.byteOffset + (y * nX + x) * 8
                        let bits = raw.loadUnaligned(fromByteOffset: position, as: UInt64.self)
                        matrix[y][x] = Double(bitPattern: UInt64(littleEndian: bits))
                    }
                }
            }
            channels.append(CanonicalAFMChannel(
                id: meta.id, sourceIndex: meta.sourceIndex, sourceLabel: meta.sourceLabel,
                semanticTypeRaw: meta.semanticTypeRaw, displayLabel: meta.displayLabel, values: matrix,
                canonicalUnit: meta.canonicalUnit, sourceUnit: meta.sourceUnit, provenance: meta.provenance
            ))
        }
        return CanonicalAFMDataset(
            sourceRef: manifest.sourceMetadata.historicalSourceRef, title: manifest.title,
            xCoordinates: manifest.xCoordinates, yCoordinates: manifest.yCoordinates, channels: channels,
            sourceMetadata: AFMSourceProvenance(
                sourceFilePath: manifest.sourceMetadata.historicalSourceRef, waveName: manifest.sourceMetadata.waveName,
                sourceWidth: manifest.sourceMetadata.sourceWidth, sourceHeight: manifest.sourceMetadata.sourceHeight,
                rawNote: manifest.sourceMetadata.rawNote
            )
        )
    }

    private static func safeChannelByteLength(nX: Int, nY: Int) throws -> Int {
        let (cells, o1) = nX.multipliedReportingOverflow(by: nY)
        guard !o1 else { throw CodecError.unsupportedManifest("matrix dimensions overflow") }
        let (bytes, o2) = cells.multipliedReportingOverflow(by: 8)
        guard !o2 else { throw CodecError.unsupportedManifest("matrix byte length overflow") }
        return bytes
    }
}

/// First `AssetStandardizationAdapter`: Igor Binary Wave v5 → faithful canonical AFM dataset.
/// Reuses `IBWReader` + `AFMInputAdapter`; adds no scientific processing (K7).
struct AFMIBWStandardizationAdapter: AssetStandardizationAdapter {
    static let formatID = "ibw_v5"

    var sourceFormat: String { Self.formatID }

    func standardize(sourceFileURL: URL) throws -> StandardizedDatasetPayload {
        let bytes = try Data(contentsOf: sourceFileURL)
        let output = try AFMInputAdapter.build(from: bytes, sourceRef: sourceFileURL.path)
        let content = try AFMDatasetCodec().encode(output.dataset)
        return StandardizedDatasetPayload(
            sourceFormat: Self.formatID,
            originalFileName: sourceFileURL.lastPathComponent,
            originalSourcePath: sourceFileURL.path,
            sourceBytes: bytes,
            datasets: [
                StandardizedDatasetItem(
                    content: content,
                    signalLocators: output.dataset.channels.map(\.id)
                )
            ]
        )
    }
}
