import Foundation

enum Secrets {
    /// Base URL of the deployed Flask backend (no trailing slash).
    static let baseURL = URL(string: "https://cgptproject-v2.onrender.com")!

    /// Matches APP_BACKEND_BEARER on the Flask service. Leave empty if not used.
    static let backendBearer = "FEFEGTGT696969546TY54654745"

    /// Mutable copy of the current auth token (nil when using the backend bearer).
     static var authToken: String? = nil

    /// Extra headers shared across requests.
    static let extraHeaders: [String: String] = [
        "Accept": "application/json",
        "User-Agent": "JarvisClient/1.0 (iOS)"
    ]

    static var askEndpoint: URL { baseURL.appendingPathComponent("ask") }
    static var chatEndpoint: URL { baseURL.appendingPathComponent("api/chat") }

    static var speakEndpoint: URL { baseURL.appendingPathComponent("speak") }
    static var diagnosticsEndpoint: URL { baseURL.appendingPathComponent("diagnostics") }

    static func headers(json: Bool) -> [String: String] {
        var headers = extraHeaders
        if json { headers["Content-Type"] = "application/json" }

        if let token = authToken, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        } else if !backendBearer.isEmpty {
            headers["Authorization"] = "Bearer \(backendBearer)"
        }
        return headers
    }
}
