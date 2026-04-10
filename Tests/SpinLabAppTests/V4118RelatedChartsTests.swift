import Foundation
import Testing
@testable import SpinLabApp

@Suite("v4.1.18 Related Charts")
struct V4118RelatedChartsTests {

    // MARK: - InputFilesCanonicalKey

    @Test("canonical key is order-independent")
    func canonicalKeyOrderIndependent() {
        let a = InputFilesCanonicalKey.make(from: ["/data/file_b.dat", "/data/file_a.dat"])
        let b = InputFilesCanonicalKey.make(from: ["/data/file_a.dat", "/data/file_b.dat"])
        #expect(a == b)
    }

    @Test("canonical key uses full path, not lastPathComponent")
    func canonicalKeyUsesFullPath() {
        let a = InputFilesCanonicalKey.make(from: ["/dir1/file.dat"])
        let b = InputFilesCanonicalKey.make(from: ["/dir2/file.dat"])
        #expect(a != b, "Different directories with same filename must produce different keys")
    }

    @Test("canonical key empty input")
    func canonicalKeyEmpty() {
        let key = InputFilesCanonicalKey.make(from: [])
        #expect(key == "")
    }

    @Test("canonical key single file")
    func canonicalKeySingleFile() {
        let key = InputFilesCanonicalKey.make(from: ["/data/measurement.dat"])
        #expect(key == "/data/measurement.dat")
    }

    // MARK: - LoadRelatedChartsUseCase (structural, no disk)

    @Test("UseCase returns empty for nonexistent library root")
    func useCaseEmptyForBadRoot() {
        let uc = LoadRelatedChartsUseCase()
        let result = uc.execute(
            sampleKeys: ["sample1"],
            libraryRootURL: URL(fileURLWithPath: "/nonexistent_spinlab_test_path")
        )
        #expect(result.isEmpty)
    }

    @Test("UseCase returns empty for empty sampleKeys")
    func useCaseEmptyForNoSamples() {
        let uc = LoadRelatedChartsUseCase()
        let result = uc.execute(
            sampleKeys: [],
            libraryRootURL: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        #expect(result.isEmpty)
    }
}
