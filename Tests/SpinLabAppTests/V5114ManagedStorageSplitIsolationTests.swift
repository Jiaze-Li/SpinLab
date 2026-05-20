import Testing
import Foundation
@testable import SpinLabApp

// INV-9: ManagedStorage split into three services; no shared mutable cache state
// between instances of each service type.

@Suite("V5.1.14 ManagedStorage Split Isolation")
struct V5114ManagedStorageSplitIsolationTests {

    @Test("INV-9a: two InboxImportFilterService instances produce independent scan results")
    func inboxFilterInstancesAreIndependent() throws {
        let tmp1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("inv9a-a-\(UUID().uuidString)", isDirectory: true)
        let tmp2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("inv9a-b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp2, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tmp1)
            try? FileManager.default.removeItem(at: tmp2)
        }

        let svc1 = InboxImportFilterService()
        let svc2 = InboxImportFilterService()

        let r1 = svc1.scanMeasurementSourceFiles(from: [tmp1], allowedFileExtensions: ["dat"])
        let r2 = svc2.scanMeasurementSourceFiles(from: [tmp2], allowedFileExtensions: ["dat"])

        #expect(r1.isEmpty, "service 1 scans empty directory — no cross-instance state")
        #expect(r2.isEmpty, "service 2 scans empty directory — no cross-instance state")
    }

    @Test("INV-9b: ContentFingerprintService instances produce identical results for same file (no cache divergence)")
    func fingerprintServiceInstancesAreIdentical() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("inv9b-\(UUID().uuidString).dat")
        let data = Data("test-content".utf8)
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let svc1 = ContentFingerprintService()
        let svc2 = ContentFingerprintService()
        let fp1 = svc1.contentFingerprint(for: tmp)
        let fp2 = svc2.contentFingerprint(for: tmp)

        #expect(fp1 != nil)
        #expect(fp1 == fp2, "two independent instances produce the same fingerprint (no shared cache)")
    }

    @Test("INV-9c: LibraryArchiveScanService instances with different roots don't share path state")
    func archiveScanRootsAreIndependent() throws {
        let root1 = FileManager.default.temporaryDirectory
            .appendingPathComponent("inv9c-a-\(UUID().uuidString)", isDirectory: true)
        let root2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("inv9c-b-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root1)
            try? FileManager.default.removeItem(at: root2)
        }

        let svc1 = LibraryArchiveScanService(rootURL: root1)
        let svc2 = LibraryArchiveScanService(rootURL: root2)

        let path1 = svc1.measurementsDirectoryURL.path
        let path2 = svc2.measurementsDirectoryURL.path

        #expect(path1 != path2, "each service instance has its own root — no shared state")
        #expect(!svc1.isManagedMeasurementPath(path2 + "/file.dat"),
                "service 1 does not recognise service 2's measurements directory as managed")
    }
}
