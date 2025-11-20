// FILE: ios/JarvisClient/JarvisClient/AuthManager+header.swift

import Foundation

extension AuthManager {
    /// Returns the Authorization header as a single optional `(key, value)` tuple.
    /// Prefers `Secrets.backendBearer`, then falls back to `Secrets.authToken`.
    /// Returns `nil` if no usable token is available.
    func authHeader() -> (String, String)? {
        if !Secrets.backendBearer.isEmpty {
            return ("Authorization", "Bearer \(Secrets.backendBearer)")
        }

        if let token = Secrets.authToken, !token.isEmpty {
            return ("Authorization", "Bearer \(token)")
        }

        // No token configured
        return nil
    }
}

