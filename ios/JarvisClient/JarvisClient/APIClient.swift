// ==========================
// File: JarvisClient/APIClient.swift  (FULL REPLACEMENT – broad legacy compatibility)
// ==========================
import Foundation

// Single source of truth for the /ask payload/response
struct AskResponse: Codable, Equatable { let reply: String }

final class APIClient {
    enum BackendMode { case modern, legacy, unknown }

    private let urlSession: URLSession
    private var modeCache: (BackendMode, Date)?
    private let cacheTTL: TimeInterval = 600

    private(set) var lastPathUsed: String?
    private(set) var mode: BackendMode = .unknown

    init(session: URLSession = .shared) {
        self.urlSession = session
    }

    // MARK: - Public

    /// Sends chat using modern `/ask` or falls back to legacy `/api/chat`.
    func ask(messages: [Message]) async throws -> AskResponse {
        // Ensure final message is a non-empty user utterance
        guard let last = messages.last, last.role == .user else {
            throw error("Last message must be a user message.", code: 400, domain: "APIClient.ask")
        }
        let prompt = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw error("No non-empty user message to send.", code: 400, domain: "APIClient.ask")
        }

        try await ensureMode()

        // 1) Try modern /ask first when we believe it exists
        if mode != .legacy {
            if let ok = try? await askModern(messages: messages) {
                lastPathUsed = "modern:/ask (json)"
                mode = .modern
                modeCache = (.modern, Date())
                return ok
            }
        }

        // 2) Legacy compatibility ladder (stop on first success)
        // 2a) JSON
        if let ok = try? await legacyJSON(prompt: prompt, system: systemFrom(messages)) {
            lastPathUsed = "legacy:/api/chat (json)"
            mode = .legacy; modeCache = (.legacy, Date())
            return ok
        }
        // 2b) x-www-form-urlencoded
        if let ok = try? await legacyForm(prompt: prompt, system: systemFrom(messages)) {
            lastPathUsed = "legacy:/api/chat (form)"
            mode = .legacy; modeCache = (.legacy, Date())
            return ok
        }
        // 2c) multipart/form-data
        if let ok = try? await legacyMultipart(prompt: prompt, system: systemFrom(messages)) {
            lastPathUsed = "legacy:/api/chat (multipart)"
            mode = .legacy; modeCache = (.legacy, Date())
            return ok
        }
        // 2d) GET with query params (as a last resort)
        if let ok = try? await legacyGET(prompt: prompt, system: systemFrom(messages)) {
            lastPathUsed = "legacy:/api/chat (GET query)"
            mode = .legacy; modeCache = (.legacy, Date())
            return ok
        }

        throw error("All request shapes failed (ask/json, chat/json, chat/form, chat/multipart, chat/GET). See server logs for why.",
                    code: 400, domain: "APIClient")
    }

    /// POST /speak -> audio bytes (MP3/WAV)
    func speak(_ text: String) async throws -> Data {
        var req = URLRequest(url: Secrets.speakEndpoint)
        req.httpMethod = "POST"
        apply(headers: makeHeaders(json: true), to: &req)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text], options: [])

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw error("Bad status \(status). \(body)", code: status, domain: "APIClient.speak")
        }
        
        return data
    }

    // Legacy alias
    func sendChat(messages: [Message]) async throws -> AskResponse { try await ask(messages: messages) }

    // MARK: - Mode discovery

    private func ensureMode() async throws {
        if let (cached, at) = modeCache, Date().timeIntervalSince(at) < cacheTTL {
            mode = cached
            return
        }
        if let diag = try? await fetchDiagnostics(), diag.ok == true {
            mode = .modern
        } else if await routeLikelyExists(Secrets.askEndpoint) {
            mode = .modern
        } else {
            mode = .unknown
        }
        modeCache = (mode, Date())
    }

    private struct DiagnosticsResponse: Codable { let ok: Bool? }

    private func fetchDiagnostics() async throws -> DiagnosticsResponse {
        var req = URLRequest(url: Secrets.diagnosticsEndpoint)
        req.httpMethod = "GET"
        apply(headers: makeHeaders(json: false), to: &req)
        let (data, _) = try await urlSession.data(for: req)
        return try JSONDecoder().decode(DiagnosticsResponse.self, from: data)
    }

    private func routeLikelyExists(_ url: URL) async -> Bool {
        var req = URLRequest(url: url); req.httpMethod = "OPTIONS"
        apply(headers: makeHeaders(json: false), to: &req)
        do {
            let (_, resp) = try await urlSession.data(for: req)
            if let http = resp as? HTTPURLResponse {
                return (200..<400).contains(http.statusCode) || http.statusCode == 405
            }
        } catch {}
        return false
    }

    // MARK: - Modern /ask

    private func askModern(messages: [Message]) async throws -> AskResponse {
        var req = URLRequest(url: Secrets.askEndpoint)
        req.httpMethod = "POST"
        apply(headers: makeHeaders(json: true), to: &req)

        let payload = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        req.httpBody = try JSONSerialization.data(with: ["messages": payload])

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw error("ask failed \( (resp as? HTTPURLResponse)?.statusCode ?? -1): \(String(data: data, encoding: .utf8) ?? "")",
                        code: (resp as? HTTPURLResponse)?.statusCode ?? -1, domain: "APIClient.ask")
        }
        return try JSONDecoder().decode(AskResponse.self, from: data)
    }

    // MARK: - Legacy shapes

    // Common parse for legacy replies
    private func parseLegacy(_ data: Data) throws -> AskResponse {
        if let r = try? JSONDecoder().decode(AskResponse.self, from: data) { return r }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["reply","message","text","content","answer"] {
                if let s = obj[key] as? String, !s.isEmpty { return AskResponse(reply: s) }
            }
        }
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return AskResponse(reply: s)
        }
        throw error("Unparseable legacy body", code: -1, domain: "APIClient.legacy.parse")
    }

    private func addAuthAcceptHeaders(to req: inout URLRequest) {
        Secrets.headers(json: false).forEach { req.setValue($1, forHTTPHeaderField: $0) }
    }

    private func legacyJSON(prompt: String, system: String?) async throws -> AskResponse {
        var req = URLRequest(url: Secrets.chatEndpoint)
        req.httpMethod = "POST"
        addAuthAcceptHeaders(to: &req)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // send many aliases; server can pick what it wants
        var body: [String: Any] = [
            "user_text": prompt,
            "prompt": prompt,
            "text": prompt,
            "message": prompt,
            "query": prompt,
            "q": prompt,
            "input": prompt,
            "userText": prompt
        ]
        if let system {
            body["system"] = system
            body["system_prompt"] = system
        }
        req.httpBody = try JSONSerialization.data(with: body)

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw error("legacy json \( (resp as? HTTPURLResponse)?.statusCode ?? -1): \(String(data: data, encoding: .utf8) ?? "")",
                        code: (resp as? HTTPURLResponse)?.statusCode ?? -1, domain: "APIClient.legacy.json")
        }
        return try parseLegacy(data)
    }

    private func legacyForm(prompt: String, system: String?) async throws -> AskResponse {
        var req = URLRequest(url: Secrets.chatEndpoint)
        req.httpMethod = "POST"
        addAuthAcceptHeaders(to: &req)
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var items: [URLQueryItem] = [
            .init(name: "user_text", value: prompt),
            .init(name: "prompt", value: prompt),
            .init(name: "text", value: prompt),
            .init(name: "message", value: prompt),
            .init(name: "query", value: prompt),
            .init(name: "q", value: prompt),
            .init(name: "input", value: prompt),
            .init(name: "userText", value: prompt)
        ]
        if let system {
            items.append(.init(name: "system", value: system))
            items.append(.init(name: "system_prompt", value: system))
        }
        var comps = URLComponents(); comps.queryItems = items
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw error("legacy form \( (resp as? HTTPURLResponse)?.statusCode ?? -1): \(String(data: data, encoding: .utf8) ?? "")",
                        code: (resp as? HTTPURLResponse)?.statusCode ?? -1, domain: "APIClient.legacy.form")
        }
        return try parseLegacy(data)
    }

    private func legacyMultipart(prompt: String, system: String?) async throws -> AskResponse {
        var req = URLRequest(url: Secrets.chatEndpoint)
        req.httpMethod = "POST"
        addAuthAcceptHeaders(to: &req)

        // Build multipart/form-data
        let boundary = "----JarvisBoundary\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        func field(_ name: String, _ value: String) -> Data {
            var d = Data()
            d.append("--\(boundary)\r\n".data(using: .utf8)!)
            d.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            d.append("\(value)\r\n".data(using: .utf8)!)
            return d
        }

        var body = Data()
        for key in ["user_text","prompt","text","message","query","q","input","userText"] {
            body.append(field(key, prompt))
        }
        if let system {
            body.append(field("system", system))
            body.append(field("system_prompt", system))
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw error("legacy multipart \( (resp as? HTTPURLResponse)?.statusCode ?? -1): \(String(data: data, encoding: .utf8) ?? "")",
                        code: (resp as? HTTPURLResponse)?.statusCode ?? -1, domain: "APIClient.legacy.multipart")
        }
        return try parseLegacy(data)
    }

    private func legacyGET(prompt: String, system: String?) async throws -> AskResponse {
        var comps = URLComponents(url: Secrets.chatEndpoint, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "user_text", value: prompt),
            .init(name: "prompt", value: prompt),
            .init(name: "text", value: prompt),
            .init(name: "message", value: prompt),
            .init(name: "query", value: prompt),
            .init(name: "q", value: prompt),
            .init(name: "input", value: prompt),
            .init(name: "userText", value: prompt)
        ]
        if let system {
            items.append(.init(name: "system", value: system))
            items.append(.init(name: "system_prompt", value: system))
        }
        comps.queryItems = items

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        addAuthAcceptHeaders(to: &req)

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw error("legacy GET \( (resp as? HTTPURLResponse)?.statusCode ?? -1): \(String(data: data, encoding: .utf8) ?? "")",
                        code: (resp as? HTTPURLResponse)?.statusCode ?? -1, domain: "APIClient.legacy.get")
        }
        return try parseLegacy(data)
    }

    // MARK: - Helpers

    private func systemFrom(_ messages: [Message]) -> String? {
        messages.first(where: { $0.role == .system })?.content
    }

    private func makeHeaders(json: Bool) -> [String: String] {
        var h = Secrets.extraHeaders
        if json {
            h["Content-Type"] = "application/json"
            if h["Accept"] == nil { h["Accept"] = "application/json" }
        }
        if !Secrets.backendBearer.isEmpty {
            h["Authorization"] = "Bearer \(Secrets.backendBearer)"
        }
        return h
    }

    private func apply(headers: [String: String], to request: inout URLRequest) {
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
    }

    private func error(_ msg: String, code: Int = -1, domain: String = "APIClient") -> NSError {
        NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

// Tiny helper so JSONSerialization calls are concise
private extension JSONSerialization {
    static func data(with obj: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: obj, options: [])
    }
}
