// ============================================
// file: JarvisClient.swift  (HTTP only; no WebSocket)
// ============================================
import Foundation

struct JarvisClient {
    let baseURL: URL
    let bearer: String

    private func request(path: String, json body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        req.timeoutInterval = 30
        return req
    }

    struct APIError: LocalizedError {
        let code: Int
        let body: String
        var errorDescription: String? { "HTTP \(code): \(body)" }
    }

    // POST /ask -> { reply: String }
    func ask(prompt: String) async throws -> String {
        let req = try request(path: "/ask", json: ["prompt": prompt]) // <-- prompt key
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError(code: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let reply = obj?["reply"] as? String else { throw URLError(.cannotDecodeRawData) }
        return reply
    }

    // POST /speak -> MP3 bytes
    func speak(text: String, voice: String? = nil) async throws -> Data {
        var body: [String: Any] = ["text": text]
        if let voice { body["voice"] = voice }
        let req = try request(path: "/speak", json: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError(code: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }
        return data
    }
}

