import Foundation
import Network

enum EmailDeliveryError: LocalizedError {
    case notConfigured
    case connectionFailed(String)
    case authenticationFailed
    case sendFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configure SMTP in Settings → Email to send automatically."
        case .connectionFailed(let detail):
            return "Could not connect to the mail server. \(detail)"
        case .authenticationFailed:
            return "SMTP sign-in failed. Check your username and app password."
        case .sendFailed(let detail):
            return "Email could not be sent. \(detail)"
        case .invalidResponse(let detail):
            return "Unexpected response from the mail server. \(detail)"
        }
    }
}

@MainActor
final class SMTPEmailDeliveryService {
    private let settings: SettingsService

    init(settings: SettingsService) {
        self.settings = settings
    }

    func send(_ payload: EmailPayload) async throws {
        guard settings.isAutomaticEmailConfigured,
              let password = settings.smtpPassword else {
            throw EmailDeliveryError.notConfigured
        }

        let client = SMTPClient(
            host: settings.smtpHost,
            port: settings.smtpPort,
            username: settings.smtpUsername,
            password: password,
            from: settings.smtpFromAddress
        )

        try await client.send(payload)
    }
}

private final class SMTPClient: @unchecked Sendable {
    private let host: String
    private let port: Int
    private let username: String
    private let password: String
    private let from: String
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.paperorg.notes.smtp")

    init(host: String, port: Int, username: String, password: String, from: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.from = from
    }

    func send(_ payload: EmailPayload) async throws {
        try await connect()

        do {
            try await expectCode(220)
            try await command("EHLO paperorgnotes.local")
            try await expectCode(250)

            try await command("AUTH LOGIN")
            try await expectCode(334)
            try await command(Data(username.utf8).base64EncodedString())
            try await expectCode(334)
            try await command(Data(password.utf8).base64EncodedString())
            do {
                try await expectCode(235)
            } catch {
                throw EmailDeliveryError.authenticationFailed
            }

            try await command("MAIL FROM:<\(from)>")
            try await expectCode(250)

            for recipient in payload.recipients {
                try await command("RCPT TO:<\(recipient)>")
                try await expectCode(250)
            }

            try await command("DATA")
            try await expectCode(354)
            try await sendRaw(buildMessage(payload: payload) + "\r\n.")
            try await expectCode(250)

            try await command("QUIT")
            try? await expectCode(221)
        } catch {
            try? await command("QUIT")
            throw error
        }

        await close()
    }

    private func connect() async throws {
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw EmailDeliveryError.connectionFailed("Invalid port.")
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: parameters
        )
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: EmailDeliveryError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: EmailDeliveryError.connectionFailed("Connection cancelled."))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func command(_ text: String) async throws {
        try await sendRaw(text + "\r\n")
    }

    private func sendRaw(_ text: String) async throws {
        guard let connection else {
            throw EmailDeliveryError.connectionFailed("Not connected.")
        }

        let data = Data(text.utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: EmailDeliveryError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func expectCode(_ expected: Int) async throws {
        let response = try await readResponse()
        guard response.code == expected else {
            if response.code == 535 || response.code == 534 {
                throw EmailDeliveryError.authenticationFailed
            }
            throw EmailDeliveryError.invalidResponse("\(response.code) \(response.message)")
        }
    }

    private struct SMTPResponse {
        let code: Int
        let message: String
    }

    private func readResponse() async throws -> SMTPResponse {
        var lines: [String] = []
        while true {
            let line = try await readLine()
            guard !line.isEmpty else { continue }
            lines.append(line)
            if line.count >= 4, line[line.index(line.startIndex, offsetBy: 3)] == " " {
                break
            }
        }

        guard let first = lines.first, let code = Int(first.prefix(3)) else {
            throw EmailDeliveryError.invalidResponse(lines.joined(separator: " "))
        }

        let message = lines.map { line in
            line.count > 4 ? String(line.dropFirst(4)) : ""
        }.joined(separator: " ")

        return SMTPResponse(code: code, message: message)
    }

    private func readLine() async throws -> String {
        guard let connection else {
            throw EmailDeliveryError.connectionFailed("Not connected.")
        }

        var buffer = Data()
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                if lineData.last == 0x0D {
                    return String(decoding: lineData.dropLast(), as: UTF8.self)
                }
                return String(decoding: lineData, as: UTF8.self)
            }

            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                    if let error {
                        continuation.resume(throwing: EmailDeliveryError.invalidResponse(error.localizedDescription))
                    } else {
                        continuation.resume(returning: data ?? Data())
                    }
                }
            }

            if chunk.isEmpty {
                throw EmailDeliveryError.invalidResponse("Connection closed.")
            }
            buffer.append(chunk)
        }
    }

    private func buildMessage(payload: EmailPayload) -> String {
        let outerBoundary = "PaperorgNotes-\(UUID().uuidString)"
        let altBoundary = "PaperorgNotes-alt-\(UUID().uuidString)"
        var parts: [String] = []

        parts.append("From: \(from)")
        parts.append("To: \(payload.recipients.joined(separator: ", "))")
        parts.append("Subject: \(encodeSubject(payload.subject))")
        parts.append("MIME-Version: 1.0")
        parts.append("Content-Type: multipart/mixed; boundary=\"\(outerBoundary)\"")
        parts.append("")

        parts.append("--\(outerBoundary)")
        parts.append("Content-Type: multipart/alternative; boundary=\"\(altBoundary)\"")
        parts.append("")

        parts.append("--\(altBoundary)")
        parts.append("Content-Type: text/plain; charset=\"UTF-8\"")
        parts.append("Content-Transfer-Encoding: 8bit")
        parts.append("")
        parts.append(escapeSMTPBody(payload.body))
        parts.append("")

        parts.append("--\(altBoundary)")
        parts.append("Content-Type: text/html; charset=\"UTF-8\"")
        parts.append("Content-Transfer-Encoding: 8bit")
        parts.append("")
        parts.append(escapeSMTPBody(payload.htmlBody))
        parts.append("")

        parts.append("--\(altBoundary)--")
        parts.append("")

        if let audioURL = payload.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path),
           let data = try? Data(contentsOf: audioURL) {
            parts.append(attachmentPart(
                boundary: outerBoundary,
                filename: audioURL.lastPathComponent,
                mimeType: "audio/m4a",
                data: data
            ))
        }

        if let pdfURL = payload.pdfURL,
           let data = try? Data(contentsOf: pdfURL) {
            parts.append(attachmentPart(
                boundary: outerBoundary,
                filename: pdfURL.lastPathComponent,
                mimeType: "application/pdf",
                data: data
            ))
        }

        if let markdownURL = payload.markdownURL,
           let data = try? Data(contentsOf: markdownURL) {
            parts.append(attachmentPart(
                boundary: outerBoundary,
                filename: markdownURL.lastPathComponent,
                mimeType: "text/markdown",
                data: data
            ))
        }

        parts.append("--\(outerBoundary)--")
        return parts.joined(separator: "\r\n")
    }

    private func attachmentPart(boundary: String, filename: String, mimeType: String, data: Data) -> String {
        """
        --\(boundary)
        Content-Type: \(mimeType); name="\(filename)"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="\(filename)"

        \(chunkedBase64(data))
        """
    }

    private func chunkedBase64(_ data: Data) -> String {
        let encoded = data.base64EncodedString()
        var chunks: [String] = []
        var index = encoded.startIndex
        while index < encoded.endIndex {
            let end = encoded.index(index, offsetBy: 76, limitedBy: encoded.endIndex) ?? encoded.endIndex
            chunks.append(String(encoded[index..<end]))
            index = end
        }
        return chunks.joined(separator: "\r\n")
    }

    private func encodeSubject(_ subject: String) -> String {
        guard subject.range(of: "[^\u{0000}-\u{007F}]", options: .regularExpression) != nil else {
            return subject
        }
        let encoded = Data(subject.utf8).base64EncodedString()
        return "=?UTF-8?B?\(encoded)?="
    }

    private func escapeSMTPBody(_ body: String) -> String {
        body
            .components(separatedBy: "\n")
            .map { line in
                line.hasPrefix(".") ? ".\(line)" : line
            }
            .joined(separator: "\r\n")
    }

    private func close() async {
        connection?.cancel()
        connection = nil
    }
}
