import Foundation
import Testing
@testable import SpinLabApp

/// WP2 (Task 11 batch A): table Dataset codec, the three adapters, and the independent
/// standardize step (own commit/recovery, typed refusal, retries). Synthetic fixtures only.
@Suite("WP2 standardization")
struct WP2StandardizationTests {
    typealias T = AssetTestSupport
    typealias I = WP1SourceIngestTests

    static let ppms = """
    [Header]
    TITLE,synthetic
    [Data]
    Comment,Time Stamp (sec),Temperature (K),Magnetic Field (Oe),Bridge 1 Resistance (Ohms),Bridge 2 Resistance (Ohms)
    ,1,300,100,5.5,6.5
    ,2,299.9,200,5.6,not-a-number
    ,3,299.8,300,5.7
    ,4,299.7,400,5.8,6.8,extra
    """
    static let lvmRow = "0.001\t0.01\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100"
    static let lvm = "double header\n\nTableau:\n\(lvmRow)\n\(lvmRow)\n"
    static let rsm = "H K L Detector\n1.0 2.0 3.0 100\n1.1 2.1 3.1 110\n"

    private func bits(_ m: LoadedMeasurement) -> [[UInt64]] { m.signals.map { $0.values.map(\.bitPattern) } }

    private func roundTrip(_ measurement: LoadedMeasurement) throws -> LoadedMeasurement {
        let content = try MeasurementTableCodec.encode(measurement)
        #expect(content.format == "measurement_table_v1")
        var files: [String: Data] = [:]
        for file in content.files { files[file.name] = file.data }
        return try MeasurementTableCodec().decode(files: files)
    }

    private func load(_ text: String, name: String, with: (URL) throws -> LoadedMeasurement) throws -> LoadedMeasurement {
        try with(try I.writeFile(Data(text.utf8), name: name))
    }

    // MARK: AC6 — codec round trips

    @Test("PPMS: values (incl. NaN), order, labels, units, quantity tags and diagnostics round-trip exactly")
    func ppmsRoundTrip() throws {
        let original = try load(Self.ppms, name: "run.dat") { try PPMSDATLoader().load(fileURL: $0) }
        #expect(original.diagnostics.count == 2)   // padded + truncated row
        let decoded = try roundTrip(original)
        #expect(bits(decoded) == bits(original) && decoded.rowCount == original.rowCount && decoded.format == .ppmsDAT)
        #expect(decoded.signals.map(\.stableSourceKey) == original.signals.map(\.stableSourceKey))
        #expect(decoded.signals.map(\.rawLabel) == original.signals.map(\.rawLabel))
        #expect(decoded.signals.map(\.sourceUnit) == original.signals.map(\.sourceUnit))
        #expect(decoded.signals.map(\.physicalQuantityID) == original.signals.map(\.physicalQuantityID))
        #expect(decoded.signals.map(\.sourceColumnIndex) == original.signals.map(\.sourceColumnIndex))
        #expect(decoded.diagnostics == original.diagnostics)
        #expect(decoded.signals.contains { $0.values.contains { $0.isNaN } })
    }

    @Test("LVM and RSM round-trip bit for bit")
    func lvmRsmRoundTrip() throws {
        let lvm = try load(Self.lvm, name: "a.lvm") { try ZurichLVMLoader().load(fileURL: $0) }
        let rsm = try load(Self.rsm, name: "a.txt") { try RSMTextLoader().load(fileURL: $0) }
        for original in [lvm, rsm] {
            let decoded = try roundTrip(original)
            #expect(bits(decoded) == bits(original) && decoded.format == original.format)
            #expect(decoded.signals.map(\.rawLabel) == original.signals.map(\.rawLabel))
            #expect(decoded.signals.map(\.physicalQuantityID) == original.signals.map(\.physicalQuantityID))
        }
    }

    @Test("A NaN payload and ±Inf survive the codec bit for bit")
    func nanBitPattern() throws {
        let custom = Double(bitPattern: 0x7FF8_0000_0000_1234)
        let column = MeasurementColumn(stableSourceKey: "c", rawLabel: "c", sourceColumnIndex: 0, values: [custom, .infinity, -.infinity, -0.0], sourceUnit: .raw("V"))
        let decoded = try roundTrip(LoadedMeasurement(sourceFilePath: "x", format: .ppmsDAT, signals: [column], rowCount: 4))
        #expect(decoded.signals[0].values.map(\.bitPattern) == column.values.map(\.bitPattern))
        #expect(decoded.signals[0].sourceUnit == .raw("V"))
    }

    @Test("Unknown unit names, truncated values and unknown versions fail instead of reading as 'undeclared'")
    func decodeFailsClosed() throws {
        let column = MeasurementColumn(stableSourceKey: "c", rawLabel: "c", sourceColumnIndex: 0, values: [1, 2], sourceUnit: .temperature(.kelvin))
        let content = try MeasurementTableCodec.encode(LoadedMeasurement(sourceFilePath: "x", format: .ppmsDAT, signals: [column], rowCount: 2))
        var files = Dictionary(uniqueKeysWithValues: content.files.map { ($0.name, $0.data) })
        let json = String(decoding: files["columns.json"]!, as: UTF8.self)
        var bad = files
        bad["columns.json"] = Data(json.replacingOccurrences(of: "\"kelvin\"", with: "\"rankine\"").utf8)
        #expect(throws: MeasurementTableCodec.CodecError.self) { try MeasurementTableCodec().decode(files: bad) }
        bad = files; bad["values.bin"] = files["values.bin"]!.dropLast()
        #expect(throws: MeasurementTableCodec.CodecError.self) { try MeasurementTableCodec().decode(files: bad) }
        bad = files; bad["columns.json"] = Data(json.replacingOccurrences(of: "\"codecVersion\" : 1", with: "\"codecVersion\" : 9").utf8)
        #expect(throws: MeasurementTableCodec.CodecError.self) { try MeasurementTableCodec().decode(files: bad) }
        files.removeValue(forKey: "values.bin")
        #expect(throws: MeasurementTableCodec.CodecError.self) { try MeasurementTableCodec().decode(files: files) }
    }

    @Test("Reordered DAT columns only change the column mapping, not the values per label")
    func columnReorder() throws {
        let reordered = """
        [Data]
        Comment,Bridge 1 Resistance (Ohms),Magnetic Field (Oe),Temperature (K)
        ,5.5,100,300
        ,5.6,200,299.9
        """
        let m = try load(reordered, name: "r.dat") { try PPMSDATLoader().load(fileURL: $0) }
        let decoded = try roundTrip(m)
        let byLabel = Dictionary(uniqueKeysWithValues: decoded.signals.compactMap { c in c.rawLabel.map { ($0, c.values) } })
        #expect(byLabel["Magnetic Field (Oe)"] == [100, 200] && byLabel["Bridge 1 Resistance (Ohms)"] == [5.5, 5.6])
        #expect(decoded.signals.first { $0.rawLabel == "Magnetic Field (Oe)" }?.sourceColumnIndex == 2)
    }

    // MARK: AC6 — adapters

    @Test("LVM: a dropped data row refuses the Dataset; truncation and non-numeric fields are diagnostics only")
    func lvmPolicy() throws {
        let adapter = ZurichLVMStandardizationAdapter()
        let dropped = "double header\n\nTableau:\n0.001\t0.01\n\(Self.lvmRow)\n"
        #expect(throws: StandardizationRejected.self) { try adapter.standardize(sourceBytes: Data(dropped.utf8), originalFileName: "d.lvm") }
        do { _ = try adapter.standardize(sourceBytes: Data(dropped.utf8), originalFileName: "d.lvm") }
        catch let rejected as StandardizationRejected { #expect(rejected.code == "rows_dropped") }

        let lenient = "double header\n\nTableau:\n\(Self.lvmRow)\t7\t8\n\(Self.lvmRow)\n0.001\tbad\t0.001\t0.01\t5.7\t0.02\t0.002\t0.02\t5.7\t100\n"
        let items = try adapter.standardize(sourceBytes: Data(lenient.utf8), originalFileName: "l.lvm")
        let files = Dictionary(uniqueKeysWithValues: items[0].content.files.map { ($0.name, $0.data) })
        let decoded = try MeasurementTableCodec().decode(files: files)
        #expect(Set(decoded.diagnostics.map(\.code)).isSuperset(of: ["malformedRow.truncated", "field.nonNumeric"]))
        #expect(decoded.signals[1].values[2].isNaN)
    }

    @Test("Loader diagnostics for LVM never change the returned values")
    func lvmValuesUnchanged() throws {
        let text = "double header\n\nTableau:\n\(Self.lvmRow)\n0.5\t0.6\n\(Self.lvmRow)\n"
        let loaded = try load(text, name: "v.lvm") { try ZurichLVMLoader().load(fileURL: $0) }
        #expect(loaded.rowCount == 2 && loaded.diagnostics.map(\.code) == ["malformedRow.dropped"])
        #expect(loaded.signals[0].values == [0.001, 0.001])
    }

    @Test("Each adapter refuses with a typed reason instead of throwing technical errors")
    func typedRefusals() throws {
        do { _ = try RSMTextStandardizationAdapter().standardize(sourceBytes: Data("H K L Detector\n1 2 x 4\n".utf8), originalFileName: "b.txt") }
        catch let r as StandardizationRejected { #expect(r.code == "parse_error") }
        do { _ = try RSMTextStandardizationAdapter().standardize(sourceBytes: Data("hello".utf8), originalFileName: "b.txt") }
        catch let r as StandardizationRejected { #expect(r.code == "unsupported_layout") }
        do { _ = try PPMSDATStandardizationAdapter().standardize(sourceBytes: Data("hello".utf8), originalFileName: "b.dat") }
        catch let r as StandardizationRejected { #expect(r.code == "unsupported_layout") }
        do { _ = try ZurichLVMStandardizationAdapter().standardize(sourceBytes: Data("hello".utf8), originalFileName: "b.lvm") }
        catch let r as StandardizationRejected { #expect(r.code == "unsupported_layout") }
    }

    @Test("The registry picks by container; a confirmed MR classification vetoes, an unknown workflow does not")
    func registry() {
        #expect(StandardizationAdapterRegistry.adapter(fileName: "a.dat", confirmedWorkflowID: nil)?.adapterID == "ppms_dat@1")
        #expect(StandardizationAdapterRegistry.adapter(fileName: "a.DAT", confirmedWorkflowID: "AHE")?.adapterID == "ppms_dat@1")
        #expect(StandardizationAdapterRegistry.adapter(fileName: "a.lvm", confirmedWorkflowID: nil)?.adapterID == "zurich_lvm@1")
        #expect(StandardizationAdapterRegistry.adapter(fileName: "a.txt", confirmedWorkflowID: nil)?.adapterID == "rsm_text@1")
        #expect(StandardizationAdapterRegistry.adapter(fileName: "a.ibw", confirmedWorkflowID: "afm")?.adapterID == "afm_ibw_v5@1")
        #expect(StandardizationAdapterRegistry.adapter(fileName: "a.dat", confirmedWorkflowID: "MR") == nil)
        #expect(StandardizationAdapterRegistry.adapter(fileName: "a.xyz", confirmedWorkflowID: nil) == nil)
    }

    // MARK: AC3/AC4 — the service step

    private func ingested(_ s: T.Scenario, text: String, name: String, context: SourceContextInput = .unknown) throws -> SourceReceipt {
        try s.service.ingestSource(I.request(s, file: try I.writeFile(Data(text.utf8), name: name), context: context), rootURL: s.root)
    }

    @Test("Unknown workflow and unconfirmed channels do not stop standardization; the Dataset decodes through the codec")
    func unknownContextStandardizes() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try ingested(s, text: Self.ppms, name: "run.dat")
        let result = try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "std-1", rootURL: s.root)
        guard case let .standardized(ids, _) = result else { Issue.record("expected standardized"); return }
        let loaded = try s.service.loadDataset(datasetID: ids[0], codec: MeasurementTableCodec(), rootURL: s.root)
        #expect(loaded.dataset.rowCount == 4 && loaded.sourceAvailability == .available)
        #expect(try s.service.effectiveChannels(sourceID: receipt.sourceID, rootURL: s.root) == nil)
        let status = try #require(try s.service.sourceStatusSummaries(forSampleUID: s.uidA, rootURL: s.root).first)
        #expect(status.standardization == .standardized(adapterID: "ppms_dat@1") && status.datasetCount == 1)
    }

    @Test("Every refusal keeps the Source, makes no Dataset and records its reason; replay returns the same answer")
    func refusalIsSourceOnly() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let cases: [(String, String, (any AssetStandardizationAdapter)?, String)] = [
            (Self.ppms, "mr.dat", nil, "no_adapter"),
            ("H K L Detector\n1 2 x 4\n", "bad.txt", RSMTextStandardizationAdapter(), "parse_error"),
            ("double header\n\nTableau:\n0.001\t0.01\n\(Self.lvmRow)\n", "drop.lvm", ZurichLVMStandardizationAdapter(), "rows_dropped")
        ]
        for (index, item) in cases.enumerated() {
            let receipt = try ingested(s, text: item.0, name: item.1)
            let op = "std-\(index)"
            let result = try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: item.2, operationID: op, rootURL: s.root)
            guard case let .notStandardized(code, _) = result else { Issue.record("expected refusal for \(item.1)"); continue }
            #expect(code == item.3)
            #expect(try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: item.2, operationID: op, rootURL: s.root) == result)
            #expect(try s.service.readSource(sourceID: receipt.sourceID, rootURL: s.root).bytes == Data(item.0.utf8))
        }
        let statuses = try s.service.sourceStatusSummaries(forSampleUID: s.uidA, rootURL: s.root)
        #expect(statuses.count == 3 && statuses.allSatisfy { $0.datasetCount == 0 })
        #expect(throws: LibraryAssetError.self) {   // the same operation ID for another source is a different request
            try s.service.standardizeSource(sourceID: statuses[0].sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "std-0", rootURL: s.root)
        }
    }

    @Test("A crash while standardizing never touches the Source; the retry produces the Dataset for the same Source")
    func standardizeCrashes() throws {
        for point in [AssetFaultPoint.standardizeAfterWritten, .standardizeBeforeCommit] {
            let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
            let receipt = try ingested(s, text: Self.ppms, name: "run.dat")
            s.service.faultHook = { if $0 == point { throw T.Crash() } }
            #expect(throws: T.Crash.self) {
                try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "std", rootURL: s.root)
            }
            let restarted = LibraryAssetService(libraryStore: s.store)
            let status = try #require(try restarted.sourceStatusSummaries(forSampleUID: s.uidA, rootURL: s.root).first)
            #expect(status.sourceID == receipt.sourceID && status.standardization == .pending)   // 'pending' read does not recover yet
            let result = try restarted.standardizeSource(sourceID: receipt.sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "std", rootURL: s.root)
            #expect(result.datasetIDs.count == 1)
            #expect(try restarted.listAssets(forSampleUID: s.uidA, rootURL: s.root).count == 2)   // Source + exactly one Dataset
            let sources = try restarted.sourceStatusSummaries(forSampleUID: s.uidA, rootURL: s.root)
            #expect(sources.count == 1 && sources[0].sourceID == receipt.sourceID)
        }
    }

    @Test("Standardizing again with the same adapter is idempotent; a technical error writes no outcome")
    func idempotentAndTechnical() throws {
        struct Boom: Error {}
        struct BoomAdapter: AssetStandardizationAdapter {
            var adapterID: String { "boom@1" }
            func standardize(sourceBytes: Data, originalFileName: String) throws -> [StandardizedDatasetItem] { throw Boom() }
        }
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try ingested(s, text: Self.ppms, name: "run.dat")
        #expect(throws: Boom.self) {
            try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: BoomAdapter(), operationID: "t", rootURL: s.root)
        }
        #expect(try s.service.sourceStatusSummaries(forSampleUID: s.uidA, rootURL: s.root).first?.standardization == .pending)
        let first = try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "a", rootURL: s.root)
        let second = try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "b", rootURL: s.root)
        #expect(first == second && first.datasetIDs.count == 1)
    }

    @Test("A damaged Library copy is reported as unavailable and is not recorded as a refusal")
    func damagedCopy() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try ingested(s, text: Self.ppms, name: "run.dat")
        try Data("tampered".utf8).write(to: s.root.appending(path: "storage/\(receipt.sourceID)/payload.bin"))
        #expect(throws: LibraryAssetError.self) {
            try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "x", rootURL: s.root)
        }
        #expect(try s.service.sourceStatusSummaries(forSampleUID: s.uidA, rootURL: s.root).first?.standardization == .pending)
    }

    @Test("Standardization works from the Library copy after the external file is gone")
    func noExternalFileNeeded() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let file = try I.writeFile(Data(Self.lvm.utf8), name: "gone.lvm")
        let receipt = try s.service.ingestSource(I.request(s, file: file), rootURL: s.root)
        try FileManager.default.removeItem(at: file)
        let result = try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: ZurichLVMStandardizationAdapter(), operationID: "s", rootURL: s.root)
        #expect(result.datasetIDs.count == 1)
    }

    @Test("Deleting a Dataset's Source removes the outcome and the Dataset together under foreign keys")
    func deleteStandardizedSource() throws {
        let s = try T.makeScenario(); defer { try? FileManager.default.removeItem(at: s.root) }
        let receipt = try ingested(s, text: Self.ppms, name: "run.dat")
        _ = try s.service.standardizeSource(sourceID: receipt.sourceID, adapter: PPMSDATStandardizationAdapter(), operationID: "s", rootURL: s.root)
        let plan = try s.service.planAssetDeletion(target: .source(receipt.sourceID), rootURL: s.root)
        _ = try s.service.commitAssetDeletion(target: .source(receipt.sourceID), plan: plan, operationID: "d", rootURL: s.root)
        let db = try #require(try LibraryAssetDatabase.open(rootURL: s.root, createIfMissing: false))
        for table in ["assets", "standardization_outcome", "source_context", "asset_dependencies"] {
            #expect(try db.query("SELECT COUNT(*) AS n FROM \(table);").first?.int("n") == 0)
        }
    }
}
