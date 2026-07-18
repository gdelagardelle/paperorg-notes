import Foundation

@MainActor
final class ProBackendClient {
    private let settings: SettingsService
    private let keychain: KeychainService
    private let session: URLSession

    init(settings: SettingsService, keychain: KeychainService, session: URLSession = .shared) {
        self.settings = settings
        self.keychain = keychain
        self.session = session
    }

    var baseURL: URL {
        URL(string: settings.proBackendBaseURL)!
    }

    private var subscriptionBaseURL: URL {
        URL(string: settings.subscriptionBackendBaseURL)!
    }

    func ensureRegistered() async throws {
        if keychain.retrieve(for: .proAccessToken) != nil {
            return
        }
        _ = try await register()
    }

    @discardableResult
    func register() async throws -> ProUsageInfo {
        let deviceID = settings.deviceID
        var request = URLRequest(url: subscriptionBaseURL.appending(path: "/v1/auth/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // app_id is required by the Platform API and ignored by the legacy backend
        request.httpBody = try JSONEncoder().encode(["device_id": deviceID, "app_id": "notes"])

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let payload = try JSONDecoder().decode(RegisterResponse.self, from: data)
        try keychain.save(payload.accessToken, for: .proAccessToken)
        settings.cachedProUsage = payload.usageInfo
        if let userID = payload.userID {
            settings.platformUserID = userID
        }
        return payload.usageInfo
    }

    /// Sanitized server email status: who sends, from which address/host.
    func emailStatus() async throws -> BackendEmailStatus {
        try await ensureRegistered()
        var request = URLRequest(url: baseURL.appending(path: "/v1/email/status"))
        try authorize(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(BackendEmailStatus.self, from: data)
    }

    func refreshUsage() async throws -> ProUsageInfo {
        try await ensureRegistered()
        var request = URLRequest(url: usageURL())
        try authorize(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: data)
        settings.cachedProUsage = usage
        return usage
    }

    func verifySubscription(
        productID: String,
        transactionID: String?,
        signedTransactionInfo: String?
    ) async throws -> ProUsageInfo {
        try await ensureRegistered()
        var request = URLRequest(url: subscriptionBaseURL.appending(path: "/v1/subscription/verify"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)

        let body = VerifySubscriptionRequest(
            productID: productID,
            transactionID: transactionID,
            signedTransactionInfo: signedTransactionInfo
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: data)
        settings.cachedProUsage = usage
        return usage
    }

    func devActivatePro() async throws -> ProUsageInfo {
        if settings.usePlatformAuth {
            return try await verifySubscription(
                productID: SubscriptionProduct.proMonthly,
                transactionID: nil,
                signedTransactionInfo: nil
            )
        }

        // Fresh notes-api token (avoids stale Platform JWT after switching Debug config).
        keychain.delete(for: .proAccessToken)
        try await ensureRegistered()
        var request = URLRequest(url: baseURL.appending(path: "/v1/subscription/dev-activate"))
        request.httpMethod = "POST"
        try authorize(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let usage = try JSONDecoder().decode(ProUsageInfo.self, from: data)
        settings.cachedProUsage = usage
        return usage
    }

    func transcribeOpenAI(
        request transcriptionRequest: TranscriptionRequest,
        durationSeconds: TimeInterval
    ) async throws -> Data {
        try await ensureRegistered()
        let audioData = try AudioFileReader.readData(from: transcriptionRequest.audioURL)
        let boundary = UUID().uuidString
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        if let languageCode = transcriptionRequest.language.openAITranscriptionCode {
            appendField("language", languageCode)
        } else if transcriptionRequest.autoDetect {
            appendField("language", "auto")
        }
        appendField("duration_seconds", String(format: "%.2f", durationSeconds))
        if let prompt = transcriptionRequest.prompt, !prompt.isEmpty {
            appendField("prompt", String(prompt.prefix(900)))
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appending(path: "/v1/transcribe/openai"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        try authorize(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        _ = try? await refreshUsage()
        return data
    }

    func transcribeElevenLabs(
        request transcriptionRequest: TranscriptionRequest,
        durationSeconds: TimeInterval
    ) async throws -> Data {
        try await ensureRegistered()
        let audioData = try AudioFileReader.readData(from: transcriptionRequest.audioURL)
        let boundary = UUID().uuidString
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        if let languageCode = transcriptionRequest.language.elevenLabsCode {
            appendField("language_code", languageCode)
        } else if transcriptionRequest.autoDetect {
            appendField("language_code", "auto")
        }
        appendField("diarize", transcriptionRequest.enableDiarization ? "true" : "false")
        appendField("duration_seconds", String(format: "%.2f", durationSeconds))

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appending(path: "/v1/transcribe/elevenlabs"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        try authorize(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        _ = try? await refreshUsage()
        return data
    }

    func transcribeLuxASR(
        request transcriptionRequest: TranscriptionRequest,
        durationSeconds: TimeInterval
    ) async throws -> Data {
        try await ensureRegistered()
        let audioData = try AudioFileReader.readData(from: transcriptionRequest.audioURL)
        let boundary = UUID().uuidString
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("language", "lb")
        appendField("duration_seconds", String(format: "%.2f", durationSeconds))
        if let prompt = transcriptionRequest.prompt, !prompt.isEmpty {
            appendField("prompt", String(prompt.prefix(900)))
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appending(path: "/v1/transcribe/luxasr"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 300
        try authorize(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        _ = try? await refreshUsage()
        return data
    }

    func summarize(
        transcript: String,
        outputType: OutputType,
        language: AppLanguage,
        summaryLength: SummaryLength
    ) async throws -> Data {
        try await ensureRegistered()
        var request = URLRequest(url: baseURL.appending(path: "/v1/summarize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request)

        let body: [String: String] = [
            "transcript": transcript,
            "output_type": outputType.displayName,
            "language": language.displayName,
            "summary_length": summaryLength.rawValue
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    func sendEmail(_ payload: EmailPayload) async throws {
        try await ensureRegistered()
        let boundary = UUID().uuidString
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        func appendFile(_ name: String, filename: String, mimeType: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField("subject", payload.subject)
        appendField("body", payload.body)
        appendField("html_body", payload.htmlBody)
        if let recipientsData = try? JSONEncoder().encode(payload.recipients),
           let recipientsJSON = String(data: recipientsData, encoding: .utf8) {
            appendField("recipients", recipientsJSON)
        }

        if let audioURL = payload.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path),
           let audioData = try? Data(contentsOf: audioURL) {
            appendFile("audio", filename: audioURL.lastPathComponent, mimeType: "audio/m4a", data: audioData)
        }
        if let pdfURL = payload.pdfURL,
           let pdfData = try? Data(contentsOf: pdfURL) {
            appendFile("pdf", filename: pdfURL.lastPathComponent, mimeType: "application/pdf", data: pdfData)
        }
        if let markdownURL = payload.markdownURL,
           let markdownData = try? Data(contentsOf: markdownURL) {
            appendFile("markdown", filename: markdownURL.lastPathComponent, mimeType: "text/markdown", data: markdownData)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: baseURL.appending(path: "/v1/email/send"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120
        try authorize(&request)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
    }

    private func usageURL() -> URL {
        var components = URLComponents(
            url: subscriptionBaseURL.appending(path: "/v1/usage"),
            resolvingAgainstBaseURL: false
        )!
        if settings.usePlatformAuth {
            components.queryItems = [URLQueryItem(name: "app_id", value: "notes")]
        }
        return components.url!
    }

    private func authorize(_ request: inout URLRequest) throws {
        guard let token = keychain.retrieve(for: .proAccessToken) else {
            throw ProBackendError.notAuthenticated
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ProBackendError.serverError("Invalid server response.")
        }

        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
                ?? String(data: data, encoding: .utf8)
                ?? "HTTP \(http.statusCode)"
            switch http.statusCode {
            case 401:
                keychain.delete(for: .proAccessToken)
                throw ProBackendError.notAuthenticated
            case 402:
                throw ProBackendError.subscriptionRequired
            case 429:
                throw ProBackendError.usageLimitReached
            default:
                throw ProBackendError.serverError(message)
            }
        }
    }
}

private struct RegisterResponse: Decodable {
    let accessToken: String
    let userID: String?
    let usageInfo: ProUsageInfo

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case userID = "user_id"
        case usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        userID = try container.decodeIfPresent(String.self, forKey: .userID)
        // Platform nests the usage block; the legacy backend inlines it.
        if container.contains(.usage) {
            usageInfo = try container.decode(ProUsageInfo.self, forKey: .usage)
        } else {
            usageInfo = try ProUsageInfo(from: decoder)
        }
    }
}

struct BackendEmailStatus: Decodable, Sendable {
    let available: Bool
    let source: String
    let fromAddress: String?
    let fromName: String?
    let smtpHost: String?

    enum CodingKeys: String, CodingKey {
        case available
        case source
        case fromAddress = "from_address"
        case fromName = "from_name"
        case smtpHost = "smtp_host"
    }
}

private struct VerifySubscriptionRequest: Encodable {
    let productID: String
    let transactionID: String?
    let signedTransactionInfo: String?
    // required by the Platform API, ignored by the legacy backend
    let appID = "notes"

    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case transactionID = "transaction_id"
        case signedTransactionInfo = "signed_transaction_info"
        case appID = "app_id"
    }
}

private struct ErrorResponse: Decodable {
    let detail: String
}
