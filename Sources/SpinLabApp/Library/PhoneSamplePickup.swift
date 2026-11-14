import Foundation
import Security

/// Cloudflare Access service token the desktop uses to collect phone submissions.
struct PhoneAccessToken: Equatable, Sendable {
    var clientId: String
    var clientSecret: String
}

protocol PhoneAccessTokenProviding {
    /// nil when the token has not been set up (or cannot be read).
    func token() -> PhoneAccessToken?
}

/// Reads the token from the macOS Keychain (two generic passwords under one service name).
struct KeychainPhoneAccessTokenStore: PhoneAccessTokenProviding {
    static let service = "SpinLab.WebLibraryAccess"
    static let clientIdAccount = "client-id"
    static let clientSecretAccount = "client-secret"

    func token() -> PhoneAccessToken? {
        guard let id = read(account: Self.clientIdAccount),
              let secret = read(account: Self.clientSecretAccount),
              !id.isEmpty, !secret.isEmpty else { return nil }
        return PhoneAccessToken(clientId: id, clientSecret: secret)
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// One submission waiting in the cloud. `fields` is nil when the stored content cannot be read.
struct PendingPhoneSample: Equatable, Sendable {
    var submissionId: String
    var fields: NewSampleFields?
}

enum PhonePickupTransportError: LocalizedError, Equatable {
    case notAuthorized
    case unexpectedResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "The web library refused the pickup token (not signed in or token invalid)."
        case let .unexpectedResponse(reason):
            return "Unexpected response from the web library: \(reason)"
        case let .network(reason):
            return "Could not reach the web library: \(reason)"
        }
    }
}

protocol PendingSampleTransport {
    func fetchPending() async throws -> [PendingPhoneSample]
    func markReceived(submissionId: String) async throws
}

/// Talks to `/api/samples` on the web library through Cloudflare Access with the service token.
struct URLSessionPendingSampleTransport: PendingSampleTransport {
    static let defaultSiteURL = URL(string: "https://spinlab-web-library.pages.dev")!

    var siteURL: URL = Self.defaultSiteURL
    var token: PhoneAccessToken
    var session: URLSession = .shared

    private struct ListResponse: Decodable {
        struct Item: Decodable {
            var submissionId: String
            var fields: NewSampleFields?

            enum CodingKeys: String, CodingKey { case submissionId = "submission_id", fields }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                submissionId = try c.decode(String.self, forKey: .submissionId)
                fields = try? c.decode(NewSampleFields.self, forKey: .fields)
            }
        }
        var submissions: [Item]
    }

    func fetchPending() async throws -> [PendingPhoneSample] {
        let data = try await send(method: "GET", body: nil)
        do {
            let list = try JSONDecoder().decode(ListResponse.self, from: data)
            return list.submissions.map { PendingPhoneSample(submissionId: $0.submissionId, fields: $0.fields) }
        } catch {
            throw PhonePickupTransportError.unexpectedResponse("the pending list could not be read")
        }
    }

    func markReceived(submissionId: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["submission_id": submissionId])
        _ = try await send(method: "PUT", body: body)
    }

    private func send(method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: siteURL.appending(path: "api/samples"))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(token.clientId, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(token.clientSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PhonePickupTransportError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PhonePickupTransportError.unexpectedResponse("no HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PhonePickupTransportError.notAuthorized
        }
        // A refused token is redirected to the login page, which answers 200 with HTML: never trust that.
        let sameHost = http.url?.host == siteURL.host
        let isJSON = (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json")
        guard http.statusCode == 200, sameHost, isJSON else {
            if !sameHost { throw PhonePickupTransportError.notAuthorized }
            throw PhonePickupTransportError.unexpectedResponse("status \(http.statusCode)")
        }
        return data
    }
}

struct PhonePickupSummary: Equatable {
    var created = 0
    /// Submissions left waiting because their content is invalid (listed with the reason).
    var rejected: [String] = []
    /// Submissions left waiting because the sample could not be saved.
    var failed: [String] = []
    /// Samples that were saved but could not be marked received (picked up again next time, skipped by id).
    var markFailures = 0
    var lastIndex: LibraryIndex?

    var message: String {
        var parts: [String] = []
        if created > 0 { parts.append("Collected \(created) phone sample\(created == 1 ? "" : "s").") }
        if !rejected.isEmpty { parts.append("Left waiting (invalid): \(rejected.joined(separator: "; ")).") }
        if !failed.isEmpty { parts.append("Left waiting (not saved): \(failed.joined(separator: "; ")).") }
        if markFailures > 0 { parts.append("\(markFailures) could not be marked received; they will be skipped next time.") }
        return parts.isEmpty ? "No new phone samples." : parts.joined(separator: " ")
    }

    var hasProblems: Bool { !rejected.isEmpty || !failed.isEmpty || markFailures > 0 }
}

enum PhoneSamplePickup {
    /// The sample's permanent id is its submission id (random, made when the phone form opened) with
    /// the library's `smp_` prefix; nothing else is mixed in (K1, K2).
    static func sampleUID(forSubmission submissionId: String) -> String {
        "smp_" + submissionId.lowercased()
    }

    /// Collects every waiting submission. Each one goes through the same atomic creation path as the
    /// desktop New Sample window, with the submission id as the sample id (K1/K4), so a repeated
    /// pickup finds the sample already there and creates nothing. A submission is marked received
    /// only after its sample exists; any failure leaves it waiting and never blocks the others.
    static func pickUp(
        transport: any PendingSampleTransport,
        choices: NativeSampleSubstrateChoices,
        create: (CreateNativeSampleDraft) -> CreateNativeSampleOutcome
    ) async throws -> PhonePickupSummary {
        var summary = PhonePickupSummary()
        for item in try await transport.fetchPending() {
            guard let fields = item.fields else {
                summary.rejected.append("\(item.submissionId): content could not be read")
                continue
            }
            let draft: CreateNativeSampleDraft
            switch fields.makeDraft(sampleUID: sampleUID(forSubmission: item.submissionId), choices: choices) {
            case let .success(value):
                draft = value
            case let .failure(error):
                summary.rejected.append("\(item.submissionId): \(error.localizedDescription)")
                continue
            }
            switch create(draft) {
            case let .failure(error):
                summary.failed.append("\(item.submissionId): \(error.localizedDescription)")
            case let .success(_, _, index):
                summary.created += 1
                summary.lastIndex = index
                do {
                    try await transport.markReceived(submissionId: item.submissionId)
                } catch {
                    summary.markFailures += 1
                }
            }
        }
        return summary
    }
}
