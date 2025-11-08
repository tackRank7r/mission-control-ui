//
//  ChatVM.swift
//  JarvisClient
//
 //

import Foundation
import Combine

enum Config {
    // <-- Replace with your real base URL (no trailing slash)
    static let baseURL = "https://YOUR-SERVER.com"
}

final class ChatVM: ObservableObject {
    @Published var isConnecting = false
    @Published var errorText: String?

    func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        errorText = nil

        guard let url = URL(string: "\(Config.baseURL)/api/chat/connect") else {
            self.errorText = "Bad URL. Check base URL."
            self.isConnecting = false
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["client":"ios"])

        URLSession.shared.dataTask(with: req) { _, resp, err in
            DispatchQueue.main.async {
                self.isConnecting = false
                if let err = err { self.errorText = err.localizedDescription; return }
                if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                    self.errorText = "Server error (404) — route missing: \(url.absoluteString)"
                }
            }
        }.resume()
    }
}
