import Foundation
import Testing
@testable import SpinLabApp

@Suite("Phone Sample Pickup", .serialized)
struct PhoneSamplePickupTests {
    /// In-memory stand-in for the cloud list. Rows stay (marked received) like the real table.
    final class FakeTransport: PendingSampleTransport, @unchecked Sendable {
        var rows: [(id: String, fields: NewSampleFields?, received: Bool)]
        var failMark = false
        var markCalls: [String] = []

        init(_ rows: [(String, NewSampleFields?)]) {
            self.rows = rows.map { ($0.0, $0.1, false) }
        }

        func fetchPending() async throws -> [PendingPhoneSample] {
            rows.filter { !$0.received }.map { PendingPhoneSample(submissionId: $0.id, fields: $0.fields) }
        }

        func markReceived(submissionId: String) async throws {
            markCalls.append(submissionId)
            if failMark { throw PhonePickupTransportError.network("offline") }
            if let i = rows.firstIndex(where: { $0.id == submissionId }) { rows[i].received = true }
        }
    }

    private let choices = NativeSampleSubstrateChoices(
        treatments: ["o", "b"], materials: ["STO"], orientations: ["001"], defaultTreatment: "o"
    )

    private func fields(batch: String = "PN200") -> NewSampleFields {
        var f = NewSampleFields()
        f.batch = batch
        f.growthMaterial = "SRO"
        f.substrateMaterial = "STO"
        f.substrateOrientation = "001"
        f.temperature = 700
        f.pressure = 100
        return f
    }

    private func makeLibrary() throws -> (root: URL, store: LibraryStore) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spinlab-phone-pickup-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let store = LibraryStore()
        store.ensureRoot(at: url)
        return (url, store)
    }

    private func creator(_ root: URL, _ store: LibraryStore) -> (CreateNativeSampleDraft) -> CreateNativeSampleOutcome {
        { draft in
            NativeSampleCreationService().createSample(
                draft: draft, rootURL: root, libraryStore: store, settings: .default
            )
        }
    }

    private func sampleCount(_ root: URL, _ store: LibraryStore) throws -> Int {
        try store.readOnlyCompleteIndex(rootURL: root).samples.count
    }

    @Test("A submission with two substrates makes two samples in one batch, once")
    func multiSubstrateSubmission() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        var f = fields()
        f.extraSubstrates = [.init(treatment: "b", material: "STO", orientation: "001")]
        let transport = FakeTransport([("22222222-bbbb", f)])

        let first = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))
        #expect(first.created == 2)
        #expect(transport.markCalls == ["22222222-bbbb"])
        let index = try store.readOnlyCompleteIndex(rootURL: root)
        #expect(index.samples.count == 2)
        #expect(Set(index.samples.map(\.batchId)) == ["PN200"])

        transport.rows[0].received = false
        _ = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))
        #expect(try sampleCount(root, store) == 2)
    }

    @Test("If one substrate cannot be saved the submission stays waiting; a retry only makes the rest")
    func partialFailureKeepsSubmissionWaiting() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        var f = fields()
        f.extraSubstrates = [.init(treatment: "b", material: "STO", orientation: "001")]
        let transport = FakeTransport([("33333333-cccc", f)])
        let real = creator(root, store)
        var calls = 0
        let flaky: (CreateNativeSampleDraft) -> CreateNativeSampleOutcome = { draft in
            calls += 1
            if calls == 2 { return .failure(error: .invalidInput("disk full")) }
            return real(draft)
        }

        let first = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: flaky)
        #expect(first.created == 1)
        #expect(first.failed.count == 1)
        #expect(transport.markCalls.isEmpty)
        #expect(transport.rows[0].received == false)

        let retry = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: real)
        #expect(retry.failed.isEmpty)
        #expect(try sampleCount(root, store) == 2)
        #expect(transport.rows[0].received)
    }

    @Test("The same submission collected twice makes one sample")
    func repeatedPickupMakesOneSample() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = FakeTransport([("11111111-aaaa", fields())])

        let first = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))
        #expect(first.created == 1)
        #expect(try sampleCount(root, store) == 1)

        // A late resend re-opens the row as waiting; the sample id check must skip it.
        transport.rows[0].received = false
        let second = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))
        #expect(try sampleCount(root, store) == 1)
        #expect(second.failed.isEmpty)
    }

    @Test("A collected sample is named 'batch - substrate', has tags with units, and frequency 2 Hz")
    func collectedSampleShape() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = FakeTransport([("22222222-bbbb", fields())])
        _ = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))

        let sample = try #require(store.readOnlyCompleteIndex(rootURL: root).samples.first)
        #expect(sample.id == "smp_22222222-bbbb")
        #expect(sample.sampleUID == "smp_22222222-bbbb")
        #expect(sample.displayName == "PN200 - o STO(001)")
        #expect(sample.numericDisplay["温度"] == "700 °C")
        #expect(sample.numericDisplay["氧压"] == "100 mT")
        #expect(sample.numericDisplay["频率"] == "2 Hz")
        #expect(transport.rows[0].received)
    }

    @Test("A failed save leaves the submission waiting, writes nothing, and does not stop the others")
    func failedSaveLeavesItWaiting() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        // A batch name that escapes the library fails inside creation; the second row is fine.
        let transport = FakeTransport([
            ("33333333-cccc", fields(batch: "../escape")),
            ("44444444-dddd", fields(batch: "PN201")),
        ])
        let summary = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))

        #expect(summary.failed.count == 1)
        #expect(summary.created == 1)
        #expect(!transport.rows[0].received)
        #expect(transport.rows[1].received)
        #expect(!transport.markCalls.contains("33333333-cccc"))
        #expect(try store.readOnlyCompleteIndex(rootURL: root).samples.map(\.id) == ["smp_44444444-dddd"])
        #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appending(path: "escape").path))
    }

    @Test("An unreadable library creates nothing and leaves every submission waiting")
    func unreadableLibraryLeavesAllWaiting() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "index"), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: root.appending(path: "index/library_index.json"))
        let transport = FakeTransport([("55555555-eeee", fields())])
        let summary = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))

        #expect(summary.created == 0)
        #expect(summary.failed.count == 1)
        #expect(transport.markCalls.isEmpty)
        #expect(!transport.rows[0].received)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "smp_55555555-eeee").path))
    }

    @Test("An invalid submission stays waiting, is reported, and the others are still collected")
    func invalidSubmissionStaysWaiting() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        var noMaterial = fields()
        noMaterial.growthMaterial = ""
        let transport = FakeTransport([
            ("66666666-ffff", noMaterial),
            ("77777777-abab", nil),
            ("88888888-cdcd", fields(batch: "PN202")),
        ])
        let summary = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))

        #expect(summary.rejected.count == 2)
        #expect(summary.created == 1)
        #expect(summary.message.contains("66666666-ffff"))
        #expect(transport.rows.map(\.received) == [false, false, true])
    }

    @Test("When marking received fails the sample exists, and the next pickup skips it by id")
    func markFailureIsHarmless() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = FakeTransport([("99999999-efef", fields())])
        transport.failMark = true
        let first = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))
        #expect(first.created == 1)
        #expect(first.markFailures == 1)
        #expect(first.hasProblems)
        #expect(!transport.rows[0].received)

        transport.failMark = false
        _ = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))
        #expect(try sampleCount(root, store) == 1)
        #expect(transport.rows[0].received)
    }

    @Test("Existing samples are read exactly as before a pickup")
    func oldSamplesUnchanged() async throws {
        let (root, store) = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = CreateNativeSampleDraft(batchId: "PN100", substrateDescription: "STO(001)", displayName: "old one")
        guard case let .success(oldSample, _, _) = creator(root, store)(old) else {
            Issue.record("could not create the old sample")
            return
        }
        let before = try #require(store.readOnlyCompleteIndex(rootURL: root).samples.first { $0.id == oldSample.id })
        let transport = FakeTransport([("aaaaaaaa-1111", fields())])
        _ = try await PhoneSamplePickup.pickUp(transport: transport, choices: choices, create: creator(root, store))
        let after = try #require(store.readOnlyCompleteIndex(rootURL: root).samples.first { $0.id == oldSample.id })
        #expect(after == before)
        #expect(try sampleCount(root, store) == 2)
    }

    @Test("Phone fields that leave out unfilled keys still decode; a wrongly typed number does not")
    func lenientDecoding() throws {
        let ok = Data(#"{"batch":"PN1","growthMaterial":"SRO","substrateMaterial":"STO","substrateOrientation":"001","temperature":700}"#.utf8)
        let decoded = try JSONDecoder().decode(NewSampleFields.self, from: ok)
        #expect(decoded.batch == "PN1")
        #expect(decoded.temperature == 700)
        #expect(decoded.frequency == nil)
        let bad = Data(#"{"batch":"PN1","temperature":"hot"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(NewSampleFields.self, from: bad) }
    }
}

@MainActor
@Suite("Phone Sample Pickup Token", .serialized, .rulesGlobalState)
struct PhoneSamplePickupTokenTests {
    struct NoToken: PhoneAccessTokenProviding { func token() -> PhoneAccessToken? { nil } }
    struct MustNotBeUsed: PendingSampleTransport {
        func fetchPending() async throws -> [PendingPhoneSample] { Issue.record("transport used without a token"); return [] }
        func markReceived(submissionId: String) async throws {}
    }

    @Test("Without a token nothing is collected and a manual refresh says why")
    func missingTokenIsExplained() {
        let state = SpinLabAppState()
        state.library.librarySettings.rootPath = FileManager.default.temporaryDirectory.path
        state.library.libraryDrawerMessage = nil
        state.pickUpPhoneSamples(manual: false, tokenProvider: NoToken()) { _ in MustNotBeUsed() }
        #expect(state.library.libraryDrawerMessage == nil)
        state.pickUpPhoneSamples(manual: true, tokenProvider: NoToken()) { _ in MustNotBeUsed() }
        #expect(state.library.libraryDrawerMessage?.contains("token is not set up") == true)
    }
}

/// The real transport, with the network replaced by a stub.
@Suite("Phone Sample Pickup Transport", .serialized)
struct PhoneSamplePickupTransportTests {
    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = Self.handler else { return }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func transport() -> URLSessionPendingSampleTransport {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSessionPendingSampleTransport(
            siteURL: URL(string: "https://example.test")!,
            token: PhoneAccessToken(clientId: "id", clientSecret: "secret"),
            session: URLSession(configuration: config)
        )
    }

    private func reply(_ request: URLRequest, status: Int = 200, type: String = "application/json", host: String = "example.test", body: String) -> (HTTPURLResponse, Data) {
        let url = URL(string: "https://\(host)\(request.url!.path)")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": type])!
        return (response, Data(body.utf8))
    }

    @Test("Requests carry the Access token headers and the list is decoded")
    func sendsTokenAndDecodes() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            return reply(request, body: #"{"submissions":[{"submission_id":"abcd1234","created_at":"x","fields":{"batch":"PN1","growthMaterial":"SRO","substrateMaterial":"STO","substrateOrientation":"001"}},{"submission_id":"bad00001","created_at":"x","fields":null}]}"#)
        }
        let list = try await transport().fetchPending()
        #expect(seen?.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
        #expect(seen?.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "secret")
        #expect(seen?.httpMethod == "GET")
        #expect(list.map(\.submissionId) == ["abcd1234", "bad00001"])
        #expect(list[0].fields?.batch == "PN1")
        #expect(list[1].fields == nil)
    }

    @Test("A login page or a refused token is an error, never an empty list")
    func loginPageIsNotAnEmptyList() async {
        StubURLProtocol.handler = { request in reply(request, type: "text/html", host: "team.cloudflareaccess.com", body: "<html>login</html>") }
        await #expect(throws: PhonePickupTransportError.notAuthorized) { try await transport().fetchPending() }
        StubURLProtocol.handler = { request in reply(request, status: 403, body: "{}") }
        await #expect(throws: PhonePickupTransportError.notAuthorized) { try await transport().fetchPending() }
    }

    @Test("Marking received sends the submission id with PUT")
    func markReceivedBody() async throws {
        nonisolated(unsafe) var seen: URLRequest?
        StubURLProtocol.handler = { request in
            seen = request
            return reply(request, body: #"{"status":"received"}"#)
        }
        try await transport().markReceived(submissionId: "abcd1234")
        #expect(seen?.httpMethod == "PUT")
        let body = try #require(seen?.httpBody ?? seen?.httpBodyStream.map { stream -> Data in
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: 1024); if n <= 0 { break }; data.append(buf, count: n) }
            return data
        })
        #expect(String(data: body, encoding: .utf8)?.contains("abcd1234") == true)
    }
}
