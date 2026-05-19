import Foundation
import os.log

private let logger = Logger(subsystem: AppPaths.logSubsystem, category: "OpenAIProtocolGenerator")

/// Generates meeting protocols via an OpenAI-compatible HTTP API (e.g. Ollama, LM Studio, llama.cpp).
struct OpenAIProtocolGenerator: ProtocolGenerating {
    let endpoint: URL
    let model: String
    let apiKey: String?
    let language: String
    let timeoutSeconds: TimeInterval
    let session: URLSession

    /// Default URLSession with TLS 1.2 minimum enforced.
    static let secureSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: config)
    }()

    init(
        endpoint: URL,
        model: String,
        language: String,
        apiKey: String? = nil,
        timeoutSeconds: TimeInterval = 600,
        session: URLSession? = nil,
    ) {
        self.endpoint = endpoint
        self.model = model
        self.language = language
        self.apiKey = apiKey
        self.timeoutSeconds = timeoutSeconds
        // Use a session with TLS 1.2 minimum by default; callers (e.g. tests) can inject their own.
        self.session = session ?? Self.secureSession
    }

    func generate(transcript: String, title _: String, diarized: Bool) async throws -> String {
        // Refuse to send the API key over a cleartext connection to a
        // non-loopback host — the key would be visible on the network.
        if endpoint.scheme?.lowercased() == "http",
           let host = endpoint.host {
            let lower = host.lowercased()
            // NOTE: This guard uses string-prefix matching and catches the most
            // common notations. Known limitation: exotic but valid forms such as
            // mixed octal/decimal like `0177.0.0.1` with non-standard segment
            // counts are not exhaustively covered. For a fully robust check,
            // resolve the hostname via getaddrinfo and inspect the resulting
            // sockaddr — that is intentionally out of scope here.
            let isPrivate = lower == "127.0.0.1"
                || lower.hasPrefix("127.")
                || lower == "0.0.0.0"
                || lower == "::1"
                || lower == "localhost"
                || lower.hasPrefix("fe80:")  // link-local IPv6
                || lower.hasPrefix("169.254.")  // link-local IPv4
                || lower.hasPrefix("10.")  // RFC-1918 class A
                || lower.hasPrefix("192.168.")  // RFC-1918 class C
                || (lower.hasPrefix("172.") && {  // RFC-1918 class B (172.16–31.x.x)
                    let parts = lower.split(separator: ".")
                    if parts.count >= 2, let second = Int(parts[1]) {
                        return second >= 16 && second <= 31
                    }
                    return false
                }())
                || lower.hasPrefix("fd")  // ULA IPv6 (fc00::/7, most common fd::/8)
                || lower.hasPrefix("fc")  // ULA IPv6
                // Octal loopback: 0177.0.0.1 → 127.0.0.1
                || lower.hasPrefix("0177.")
                // Hex loopback: 0x7f... → 127.x.x.x
                || lower.hasPrefix("0x7f")
                // Pure-decimal (dword) loopback: 2130706433 == 0x7F000001 == 127.0.0.1
                || (UInt32(lower) == 2_130_706_433)
            if !isPrivate {
                throw ProtocolError.connectionFailed(
                    "Endpoint uses http:// — API key would be transmitted in cleartext. Use https:// for remote endpoints."
                )
            }
        }
        let systemPrompt = ProtocolGenerator.buildSystemPrompt(diarized: diarized, language: language)

        // Wrap the transcript in <transcript> tags so the LLM can treat its
        // content as untrusted user input distinct from the system instructions,
        // reducing prompt-injection risk from instruction-like phrasing in meetings.
        let wrappedTranscript = "<transcript>\n" + transcript + "\n</transcript>"
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": wrappedTranscript],
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = bodyData
        request.timeoutInterval = timeoutSeconds

        logger.info("Generating protocol via OpenAI-compatible API (\(model))...")

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            logger.error(
                "openai_connection_failed endpoint=\(self.endpoint.absoluteString, privacy: .public) model=\(self.model, privacy: .public) error=\(error.localizedDescription, privacy: .public)",
            )
            throw ProtocolError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("openai_invalid_response endpoint=\(self.endpoint.absoluteString, privacy: .public)")
            throw ProtocolError.connectionFailed("Invalid response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            // Try to read error body
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            logger.error(
                "openai_http_error status=\(httpResponse.statusCode, privacy: .public) endpoint=\(self.endpoint.absoluteString, privacy: .public) body=\(errorBody, privacy: .public)",
            )
            throw ProtocolError.httpError(httpResponse.statusCode, errorBody)
        }

        var parts: [String] = []
        for try await line in bytes.lines {
            if let content = parseSSELine(line) {
                parts.append(content)
            }
        }

        let result = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else {
            throw ProtocolError.emptyProtocol
        }

        return result
    }

    /// Parse a single SSE line and extract the content delta.
    /// Returns `nil` for non-content lines (e.g. `data: [DONE]`, empty lines, comments).
    static func parseSSELine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("data: ") else { return nil }
        let payload = String(trimmed.dropFirst(6))

        if payload == "[DONE]" { return nil }

        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }

        return content
    }

    /// Test connection to the API by querying available models.
    /// Returns model names on success.
    static func testConnection(endpoint: String, model _: String, apiKey: String?, session: URLSession = .shared) async -> Result<[String], any Error> {
        // Derive models endpoint from chat completions endpoint
        guard let chatURL = URL(string: endpoint) else {
            return .failure(ProtocolError.connectionFailed("Invalid endpoint URL"))
        }
        guard let scheme = chatURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(ProtocolError.connectionFailed("Endpoint must use http or https scheme"))
        }
        // Apply the same cleartext + API-key guard used in generate(): refuse to
        // send credentials over plain HTTP to a non-loopback/non-private host.
        if scheme == "http", let host = chatURL.host, let apiKey, !apiKey.isEmpty {
            let lower = host.lowercased()
            let isPrivate = lower == "127.0.0.1" || lower.hasPrefix("127.")
                || lower == "0.0.0.0" || lower == "::1" || lower == "localhost"
                || lower.hasPrefix("fe80:") || lower.hasPrefix("169.254.")
                || lower.hasPrefix("10.") || lower.hasPrefix("192.168.")
                || lower.hasPrefix("fd") || lower.hasPrefix("fc")
                || (lower.hasPrefix("172.") && {
                    let parts = lower.split(separator: ".")
                    if parts.count >= 2, let second = Int(parts[1]) { return second >= 16 && second <= 31 }
                    return false
                }())
            if !isPrivate {
                return .failure(ProtocolError.connectionFailed(
                    "Endpoint uses http:// — API key would be transmitted in cleartext. Use https:// for remote endpoints."
                ))
            }
        }

        // Navigate from .../v1/chat/completions to .../v1/models
        let baseURL = chatURL.deletingLastPathComponent().deletingLastPathComponent()
        let modelsURL = baseURL.appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return .failure(ProtocolError.httpError(code, "Failed to fetch models"))
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelList = json["data"] as? [[String: Any]]
            else {
                return .success([])
            }

            let names = modelList.compactMap { $0["id"] as? String }.sorted()
            return .success(names)
        } catch {
            return .failure(ProtocolError.connectionFailed(error.localizedDescription))
        }
    }
}

// Private instance helper that delegates to the static method
private extension OpenAIProtocolGenerator {
    func parseSSELine(_ line: String) -> String? {
        Self.parseSSELine(line)
    }
}
