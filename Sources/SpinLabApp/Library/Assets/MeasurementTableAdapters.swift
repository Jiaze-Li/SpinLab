import Foundation

// MARK: - WP2 — standardization adapters for the table loaders, and the container registry
//
// Adapters only wrap the existing loaders (no second parser): they hand the stored bytes to the
// loader through a private temporary file, then encode the loader's output with
// `MeasurementTableCodec`. A file the loader cannot read, or an LVM file whose data rows would
// be dropped, is a deliberate `StandardizationRejected` — the Source stays, no Dataset is made.

enum MeasurementTableAdapterSupport {
    /// Runs `body` with the bytes materialised as a file; the file never outlives the call.
    static func withTemporaryFile<T>(bytes: Data, originalFileName: String, _ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SpinLabStandardize-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let safeName = originalFileName.replacingOccurrences(of: "/", with: "_")
        let url = directory.appending(path: safeName.isEmpty ? "source.dat" : safeName, directoryHint: .notDirectory)
        try bytes.write(to: url)
        return try body(url)
    }

    static func item(from measurement: LoadedMeasurement) throws -> [StandardizedDatasetItem] {
        [StandardizedDatasetItem(content: try MeasurementTableCodec.encode(measurement), signalLocators: [])]
    }
}

/// PPMS `.dat`. Padded/truncated rows are kept with diagnostics, exactly as the loader reports them.
struct PPMSDATStandardizationAdapter: AssetStandardizationAdapter {
    var adapterID: String { "ppms_dat@1" }

    func standardize(sourceBytes: Data, originalFileName: String) throws -> [StandardizedDatasetItem] {
        let measurement: LoadedMeasurement
        do {
            measurement = try MeasurementTableAdapterSupport.withTemporaryFile(bytes: sourceBytes, originalFileName: originalFileName) {
                try PPMSDATLoader().load(fileURL: $0)
            }
        } catch let error as PPMSDATLoader.LoadError {
            throw StandardizationRejected(code: "unsupported_layout", detail: error.localizedDescription)
        }
        return try MeasurementTableAdapterSupport.item(from: measurement)
    }
}

/// Zurich `.lvm`. Any dropped data row refuses the Dataset (P1); truncation and non-numeric
/// fields are recorded as diagnostics only.
struct ZurichLVMStandardizationAdapter: AssetStandardizationAdapter {
    var adapterID: String { "zurich_lvm@1" }

    func standardize(sourceBytes: Data, originalFileName: String) throws -> [StandardizedDatasetItem] {
        let measurement: LoadedMeasurement
        do {
            measurement = try MeasurementTableAdapterSupport.withTemporaryFile(bytes: sourceBytes, originalFileName: originalFileName) {
                try ZurichLVMLoader().load(fileURL: $0)
            }
        } catch let error as ZurichLVMLoader.LoadError {
            throw StandardizationRejected(code: "unsupported_layout", detail: error.localizedDescription)
        }
        let dropped = measurement.diagnostics.filter { $0.code == "malformedRow.dropped" }
        guard dropped.isEmpty else {
            throw StandardizationRejected(
                code: "rows_dropped",
                detail: "\(dropped.count) data row(s) could not be read and would have been dropped; the original file is kept."
            )
        }
        return try MeasurementTableAdapterSupport.item(from: measurement)
    }
}

/// RSM text. The loader already throws on any malformed row, so nothing is silently lost.
struct RSMTextStandardizationAdapter: AssetStandardizationAdapter {
    var adapterID: String { "rsm_text@1" }

    func standardize(sourceBytes: Data, originalFileName: String) throws -> [StandardizedDatasetItem] {
        guard let text = String(data: sourceBytes, encoding: .utf8) else {
            throw StandardizationRejected(code: "unsupported_layout", detail: "the file is not UTF-8 text")
        }
        let measurement: LoadedMeasurement
        do {
            measurement = try RSMTextLoader.parseMeasurement(text: text, sourceFilePath: originalFileName)
        } catch let error as RSMTextLoader.LoadError {
            switch error {
            case .malformedRow:
                throw StandardizationRejected(code: "parse_error", detail: error.localizedDescription)
            case .empty, .missingRequiredColumns:
                throw StandardizationRejected(code: "unsupported_layout", detail: error.localizedDescription)
            }
        }
        return try MeasurementTableAdapterSupport.item(from: measurement)
    }
}

/// Chooses the adapter for a stored Source by *container format* (file suffix). The confirmed
/// workflow only matters to veto: an explicitly confirmed MR (or other adapter-less) classification
/// never gets a Dataset. An unknown workflow does not block faithful standardization.
enum StandardizationAdapterRegistry {
    /// Confirmed workflows for which no Dataset is made. MR keeps only the data classification.
    static let adapterlessWorkflows: Set<String> = ["mr"]

    static func adapter(fileName: String, confirmedWorkflowID: String?) -> (any AssetStandardizationAdapter)? {
        if let workflow = confirmedWorkflowID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           adapterlessWorkflows.contains(workflow) {
            return nil
        }
        switch (fileName as NSString).pathExtension.lowercased() {
        case "ibw": return AFMIBWStandardizationAdapter()
        case "dat": return PPMSDATStandardizationAdapter()
        case "lvm": return ZurichLVMStandardizationAdapter()
        case "txt": return RSMTextStandardizationAdapter()
        default: return nil
        }
    }
}
