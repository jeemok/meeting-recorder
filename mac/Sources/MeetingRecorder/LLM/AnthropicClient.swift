import Foundation

/// Minimal Anthropic Messages API client. Stateless; pass a system + user
/// prompt and get a string back. No streaming yet — we wait for the full
/// response since summaries are short and the realtime suggester polls
/// every 30 s anyway.
struct AnthropicClient {
    let apiKey: String
    let model: String
    let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    let session: URLSession

    init(apiKey: String, model: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func complete(system: String, user: String, maxTokens: Int = 1024) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [
                ["role": "user", "content": user],
            ],
        ]
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Anthropic", code: 0, userInfo: [NSLocalizedDescriptionKey: "no response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "<no body>"
            throw NSError(domain: "Anthropic", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else {
            throw NSError(domain: "Anthropic", code: 1, userInfo: [NSLocalizedDescriptionKey: "malformed response"])
        }
        let text = content.compactMap { $0["text"] as? String }.joined()
        return text
    }

    /// Read the API key from config, env (`ANTHROPIC_API_KEY`), or `.env`
    /// in the storage directory. nil if none configured.
    static func resolveAPIKey(from config: AppConfig) -> String? {
        if let k = config.llm.apiKey, !k.isEmpty { return k }
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty {
            return env
        }
        let dotenv = appSupportDir().appendingPathComponent(".env")
        if let raw = try? String(contentsOf: dotenv, encoding: .utf8) {
            for line in raw.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("ANTHROPIC_API_KEY=") {
                    return String(trimmed.dropFirst("ANTHROPIC_API_KEY=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                }
            }
        }
        return nil
    }
}
