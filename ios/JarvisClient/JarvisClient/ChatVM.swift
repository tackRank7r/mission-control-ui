// File: ios/JarvisClient/JarvisClient/ChatVM.swift
// Action: REPLACE entire file
// Purpose: Simple connectivity checker that posts to /api/chat/connect using the
//          same base URL as the main app (Secrets.baseURL).

import Foundation
import Combine

final class ChatVM: ObservableObject {
    @Published var isConnecting = false
    @Published var errorText: String?

    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        errorText = nil

        // Use the shared backend base URL (no trailing slash).
        let url = Secrets.baseURL.appendingPathComponent("api/chat/connect")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["client": "ios"],
            options: []
        )

        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                self.isConnecting = false

                if let err = err {
                    self.errorText = err.localizedDescription
                    return
                }

                if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                    self.errorText = "Server error (404) — route missing: \(url.absoluteString)"
                }
            }
        }.resume()
    }
}
