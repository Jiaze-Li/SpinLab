import Foundation
import Testing
@testable import SpinLabApp

@Suite("V3.4.3 Measurement Data Read Model")
struct V343MeasurementDataReadModelTests {

    // MARK: - Helpers

    private func makeFixture() throws -> (resolver: LibraryPathResolver, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "v343-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (LibraryPathResolver(libraryRootURL: root), root)
    }

    private func cleanup(_ root: URL) { try? FileManager.default.removeItem(at: root) }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private func writeStore(
        _ store: WorkbenchMeasurementDataStore,
        sampleKey: String,
        root: URL
    ) throws {
        let dir = root
            .appending(path: "samples/\(sampleKey)/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.encoder.encode(store).write(to: dir.appending(path: "measurement_data.json"))
    }

    private func makeRecord(
        sampleKey: String,
        metric: String = "Hc",
        value: Double = 0.05,
        conditions: [String: String] = [:],
        overrideInfo: WorkbenchMetricOverrideInfo? = nil
    ) -> WorkbenchMetricRecord {
        WorkbenchMetricRecord(
            recordID: UUID().uuidString,
            sampleKey: sampleKey,
            displayKey: sampleKey,
            workflowID: "AHE",
            metric: metric,
            value: value,
            canonicalUnit: "T",
            conditions: conditions,
            generatedAt: Date(timeIntervalSince1970: 1_712_146_400),
            runID: UUID().uuidString,
            overrideInfo: overrideInfo
        )
    }

    // MARK: - Missing file → nil

    @Test("use case returns nil when measurement_data.json is absent")
    func missingFileReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let result = LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK-MISSING")
        #expect(result == nil)
    }

    // MARK: - Valid store → both entries in latestIndex

    @Test("valid store with two records produces two latestIndex entries")
    func validStoreTwoRecords() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        var store = WorkbenchMeasurementDataStore()
        store.append(makeRecord(sampleKey: "SK-A", metric: "Hc", value: 0.05, conditions: ["temperature": "80K"]))
        store.append(makeRecord(sampleKey: "SK-A", metric: "Hc", value: 0.06, conditions: ["temperature": "300K"]))
        try writeStore(store, sampleKey: "SK-A", root: root)

        let loaded = LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK-A")
        #expect(loaded != nil)
        #expect(loaded?.latestIndex.count == 2)
        #expect(loaded?.records.count == 2)
    }

    // MARK: - Schema version mismatch → nil

    @Test("use case returns nil when schemaVersion is not 1")
    func schemaMismatchReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        var store = WorkbenchMeasurementDataStore()
        store.append(makeRecord(sampleKey: "SK-B"))
        var encoded = try Self.encoder.encode(store)
        if var str = String(data: encoded, encoding: .utf8) {
            str = str.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
            encoded = str.data(using: .utf8)!
        }
        let dir = root.appending(path: "samples/SK-B/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoded.write(to: dir.appending(path: "measurement_data.json"))

        #expect(LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK-B") == nil)
    }

    // MARK: - Corrupt JSON → nil, no crash (Adj-10)

    @Test("use case returns nil for corrupt JSON without crashing")
    func corruptJSONReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let dir = root.appending(path: "samples/SK-C/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{bad json%%%".utf8).write(to: dir.appending(path: "measurement_data.json"))

        #expect(LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK-C") == nil)
    }

    // MARK: - Truncated file → nil, no crash (Adj-10)

    @Test("use case returns nil for truncated file without crashing")
    func truncatedFileReturnsNil() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        var store = WorkbenchMeasurementDataStore()
        store.append(makeRecord(sampleKey: "SK-D"))
        let full = try Self.encoder.encode(store)
        let dir = root.appending(path: "samples/SK-D/_spinlab", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try full.prefix(full.count / 2).write(to: dir.appending(path: "measurement_data.json"))

        #expect(LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK-D") == nil)
    }

    // MARK: - Override marker logic

    @Test("override record has non-nil overrideInfo; non-override record has nil")
    func overrideInfoPresentWhenOverridden() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let now = Date(timeIntervalSince1970: 1_712_146_400)
        let overrideInfo = WorkbenchMetricOverrideInfo(
            oldValue: 0.05, newValue: 0.08, reason: "Corrected",
            source: .manual, at: now
        )
        let overriddenRecord = makeRecord(sampleKey: "SK-E", metric: "Hc", value: 0.08, overrideInfo: overrideInfo)
        let plainRecord = makeRecord(sampleKey: "SK-E", metric: "Hc", value: 0.05,
                                     conditions: ["temperature": "300K"], overrideInfo: nil)

        var store = WorkbenchMeasurementDataStore()
        store.append(overriddenRecord)
        store.append(plainRecord)
        try writeStore(store, sampleKey: "SK-E", root: root)

        let loaded = try #require(LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK-E"))
        let recordsByID = Dictionary(uniqueKeysWithValues: loaded.records.map { ($0.recordID, $0) })

        // The overridden pointer's record must have overrideInfo; the plain pointer's must not.
        let overriddenPointer = loaded.latestIndex.values.first(where: { recordsByID[$0.recordID]?.overrideInfo != nil })
        let plainPointer = loaded.latestIndex.values.first(where: { recordsByID[$0.recordID]?.overrideInfo == nil })
        #expect(overriddenPointer != nil)
        #expect(plainPointer != nil)
    }

    // MARK: - Alias book: present → display label with alias badge

    @Test("alias book present: displayLabel returns canonical with alias annotation")
    func aliasBookPresentDisplaysLabel() throws {
        let aliasConfigJSON = """
        {
          "schemaVersion": 1,
          "conditionAliases": {
            "temperature": ["temp", "T"]
          }
        }
        """.data(using: .utf8)!
        let book = try ConditionAliasConfigLoader().load(from: aliasConfigJSON)

        // "temp" is an alias for "temperature"
        let label = book.displayLabel(for: "temp")
        #expect(label.contains("temperature"))
        #expect(label.contains("temp"))
    }

    // MARK: - Alias book: absent → plain key, no crash

    @Test("alias book absent: condition key shown plain without crash")
    func aliasBookAbsentPlainKey() {
        // No alias book — displayLabel falls back to the raw key
        let book: ConditionAliasBook? = nil
        let key = "temperature"
        let label = book?.displayLabel(for: key) ?? key
        #expect(label == "temperature")
    }

    // MARK: - Store projection trigger timing

    @Test("loadMeasurementDataForCurrentSelection populates measurementData when selection and root are set")
    @MainActor
    func storeProjectionPopulatesOnLoad() throws {
        let (_, root) = try makeFixture()
        defer { cleanup(root) }

        var store = WorkbenchMeasurementDataStore()
        store.append(makeRecord(sampleKey: "SK-F"))
        try writeStore(store, sampleKey: "SK-F", root: root)

        let featureStore = LibraryFeatureStore()
        featureStore.librarySelectedSampleId = "SK-F"
        featureStore.librarySettings.rootPath = root.path

        featureStore.loadMeasurementDataForCurrentSelection()

        #expect(featureStore.measurementData != nil)
        #expect(featureStore.measurementData?.records.count == 1)
    }

    @Test("loadMeasurementDataForCurrentSelection yields nil when no sample selected")
    @MainActor
    func storeProjectionNilWhenNoSample() {
        let featureStore = LibraryFeatureStore()
        featureStore.librarySelectedSampleId = nil
        featureStore.librarySettings.rootPath = "/some/path"

        featureStore.loadMeasurementDataForCurrentSelection()

        #expect(featureStore.measurementData == nil)
        #expect(featureStore.conditionAliasBook == nil)
    }

    @Test("conditionAliasBook is nil when alias config file is absent (non-fatal)")
    @MainActor
    func aliasBookNilWhenConfigAbsent() throws {
        let (_, root) = try makeFixture()
        defer { cleanup(root) }

        var store = WorkbenchMeasurementDataStore()
        store.append(makeRecord(sampleKey: "SK-G"))
        try writeStore(store, sampleKey: "SK-G", root: root)
        // No _spinlab/condition_aliases.json written

        let featureStore = LibraryFeatureStore()
        featureStore.librarySelectedSampleId = "SK-G"
        featureStore.librarySettings.rootPath = root.path

        featureStore.loadMeasurementDataForCurrentSelection()

        #expect(featureStore.measurementData != nil)
        #expect(featureStore.conditionAliasBook == nil)  // absent config → nil, no crash
    }

    // MARK: - Empty state condition

    @Test("nil measurementData satisfies empty-state rendering condition")
    func nilMeasurementDataEmptyState() throws {
        let (resolver, root) = try makeFixture()
        defer { cleanup(root) }

        let result = LoadMeasurementDataUseCase(pathResolver: resolver).execute(sampleKey: "SK-NONE")
        #expect(result == nil)
    }

    // MARK: - Formatted string output (Issue-2: direct text assertions)

    @Test("measurementValueText appends * for overridden value and omits it for plain")
    func overrideMarkerInFormattedText() {
        let overridden = measurementValueText(value: 1.05, unit: "T", isOverridden: true)
        let plain      = measurementValueText(value: 0.05, unit: "T", isOverridden: false)
        #expect(overridden == "1.05 T *")
        #expect(plain      == "0.05 T")
    }

    @Test("conditionDisplayLabel returns canonical with alias annotation when book present")
    func aliasLabelTextWithBook() throws {
        let aliasConfigJSON = """
        {
          "schemaVersion": 1,
          "conditionAliases": {
            "temperature": ["temp"]
          }
        }
        """.data(using: .utf8)!
        let book = try ConditionAliasConfigLoader().load(from: aliasConfigJSON)

        // "temp" is an alias → label shows canonical (alias: temp)
        let aliasLabel    = conditionDisplayLabel(key: "temp", aliasBook: book)
        // "temperature" is already canonical → label is just "temperature"
        let canonicalLabel = conditionDisplayLabel(key: "temperature", aliasBook: book)

        #expect(aliasLabel == "temperature (alias: temp)")
        #expect(canonicalLabel == "temperature")
    }

    @Test("conditionDisplayLabel returns plain key when book is nil")
    func aliasLabelTextWithoutBook() {
        let label = conditionDisplayLabel(key: "temperature", aliasBook: nil)
        #expect(label == "temperature")
    }
}
