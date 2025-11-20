// File: SecretsExample.swift
// Action: CREATE new file
// Purpose: Safe template for configuring backend URL and bearer token.
//          This file is committed; real secrets live in Secrets.swift (ignored).

import Foundation

enum SecretsExample {
    /// Base URL of the deployed Flask backend (no trailing slash).
    /// Example: https://your-backend.onrender.com
    static let baseURL = URL(string: "https://your-backend-url-here")!

    /// Matches APP_BACKEND_BEARER on the Flask service. Leave empty if not used.
    static let backendBearer = "<YOUR_BACKEND_BEARER_HERE>"

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
}
