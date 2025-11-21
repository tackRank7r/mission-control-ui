// File: ios/JarvisClient/JarvisClient/Secrets.swift
// Action: REPLACE entire file
// Purpose: Match existing code expectations (baseURL as URL + headers(json:)).

import Foundation

enum Secrets {
    /// Base URL of the deployed backend (no trailing slash).
    /// Example: https://cgptproject-v2.onrender.com
    static let baseURL = URL(string: "https://cgptproject-v2.onrender.com")!

    /// Bearer token for the backend, if you use one.
    /// Leave empty if your backend doesn’t expect it.
    static let backendBearer = "FEFEGTGT696969546TY54654745"

    /// Mutable copy of the current auth token. If non-nil this wins over backendBearer.
    static var authToken: String? = nil

    /// Extra headers shared across requests.
    static let extraHeaders: [String: String] = [
        "Accept": "application/json",
        "User-Agent": "JarvisClient/1.0 (iOS)"
    ]

    /// Central helper used by MemoryStore, CallService, etc.
    /// If `json` is true, adds Content-Type: application/json.
    /// If authToken or backendBearer is set, adds Authorization: Bearer ...
    static func headers(json: Bool = true) -> [String: String] {
        var headers = extraHeaders

        if json {
            headers["Content-Type"] = "application/json"
        }

        if let token = authToken ?? (backendBearer.isEmpty ? nil : backendBearer) {
            headers["Authorization"] = "Bearer \(token)"
        }

        return headers
    }

    // Existing endpoints (kept as-is so the rest of the app keeps working).
    static var askEndpoint: URL { baseURL.appendingPathComponent("ask") }
    static var chatEndpoint: URL { baseURL.appendingPathComponent("api/chat") }
    static var speakEndpoint: URL { baseURL.appendingPathComponent("speak") }
    static var diagnosticsEndpoint: URL { baseURL.appendingPathComponent("diagnostics") }
}
