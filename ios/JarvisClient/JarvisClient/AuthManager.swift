// =====================================
// File: JarvisClient/AuthManager.swift
// Conforms to AuthManaging expected by WelcomeScreens
// =====================================

import Foundation
import Combine
import UIKit

enum MemoryPolicy: String, Codable, CaseIterable {
    case off            = "Off (no memory)"
    case local          = "Local only (on device)"
    case cloud          = "Cloud (sync with server)"
}

struct UserProfile: Codable, Equatable {
    var userId: String
    var username: String
    var email: String
    var memoryPolicy: MemoryPolicy
}

@MainActor
final class AuthManager: ObservableObject, AuthManaging {
    static let shared = AuthManager()

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var profile: UserProfile?
    @Published var lastError: String?

    private let session = URLSession.shared
    private var skipAuthRoutes: Bool { !Secrets.backendBearer.isEmpty }
    private let fallbackId = "backend-bearer"
    private let fallbackEmail = "backend@jarvis"

    // Device id (you already used this)
    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }

    // Token storage
    private let tokenKey = "AuthToken"
    private var authToken: String? {
        get {
            if let cached = Secrets.authToken, !cached.isEmpty { return cached }
            return UserDefaults.standard.string(forKey: tokenKey)
        }
        set {
            Secrets.authToken = newValue
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
        }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: tokenKey), !stored.isEmpty {
            Secrets.authToken = stored
        }
        if skipAuthRoutes {
            applyBackendFallback()
        } else if authToken != nil {
            Task { await restore() }
        }
    }

    // MARK: - Lifecycle utilities

    func restore() async {
        if skipAuthRoutes {
            applyBackendFallback()
            return
        }
        guard let token = authToken, !token.isEmpty else {
            isAuthenticated = false
            profile = nil
            return
        }
        await refreshProfile()
    }

    func signOut() {
        authToken = nil
        profile = nil
        isAuthenticated = false
        if skipAuthRoutes {
            applyBackendFallback()
        }
    }

    // MARK: - AuthManaging (UI calls these)

    func startSignIn(username: String, password: String) async throws -> AuthResponse {
        lastError = nil
        if skipAuthRoutes {
            applyBackendFallback(using: username)
            return AuthResponse(status: "OK", message: "Signed in with backend bearer.")
        }

        do {
            var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/auth/start"))
            req.httpMethod = "POST"
            Secrets.headers(json: true).forEach { req.addValue($1, forHTTPHeaderField: $0) }
            let body: [String: Any] = [
                "username": username,
                "password": password,
                "device_id": deviceId
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, resp) = try await session.data(for: req)

            guard let http = resp as? HTTPURLResponse else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])
            }

            if http.statusCode == 200 {
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = obj["token"] as? String {
                    self.authToken = token
                    await refreshProfile()
                    return AuthResponse(status: "OK", message: "Signed in.")
                } else {
                    return AuthResponse(status: "VERIFY", message: "Enter the code sent to your email.")
                }
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "Login failed"
                throw NSError(domain: "Auth", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        } catch {
            lastError = (error as NSError).localizedDescription
            throw error
        }
    }

    func startSignUp(username: String, password: String) async throws -> AuthResponse {
        lastError = nil
        if skipAuthRoutes {
            applyBackendFallback(using: username)
            return AuthResponse(status: "OK", message: "Account ready—using backend bearer.")
        }

        func post(_ path: String) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: Secrets.baseURL.appendingPathComponent(path))
            req.httpMethod = "POST"
            Secrets.headers(json: true).forEach { req.addValue($1, forHTTPHeaderField: $0) }
            let body: [String: Any] = [
                "username": username,
                "password": password,
                "device_id": deviceId
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw NSError(domain: "Auth", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "No response"])
            }
            return (data, http)
        }

        do {
            do {
                let (data, http) = try await post("/auth/signup")
                if (200..<300).contains(http.statusCode) {
                    return AuthResponse(status: "VERIFY", message: "We sent a code to your email.")
                } else if http.statusCode == 404 {
                    // fall through
                } else {
                    let msg = String(data: data, encoding: .utf8) ?? "Sign up failed"
                    throw NSError(domain: "Auth", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: msg])
                }
            } catch let err as NSError where err.code == 404 {
                // ignore and fall through
            }

            let (data, http) = try await post("/auth/start")
            if (200..<300).contains(http.statusCode) {
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = obj["token"] as? String {
                    self.authToken = token
                    await refreshProfile()
                    return AuthResponse(status: "OK", message: "Account created and signed in.")
                }
                return AuthResponse(status: "VERIFY", message: "We sent a code to your email.")
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "Sign up failed"
                throw NSError(domain: "Auth", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        } catch {
            lastError = (error as NSError).localizedDescription
            throw error
        }
    }

    func verifyCode(username: String, code: String) async throws -> AuthResponse {
        lastError = nil
        if skipAuthRoutes {
            applyBackendFallback(using: username)
            return AuthResponse(status: "OK", message: "Signed in with backend bearer.")
        }

        do {
            var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/auth/verify"))
            req.httpMethod = "POST"
            Secrets.headers(json: true).forEach { req.addValue($1, forHTTPHeaderField: $0) }
            let body: [String: Any] = ["device_id": deviceId, "code": code]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, resp) = try await session.data(for: req)

            guard let http = resp as? HTTPURLResponse else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Verification failed"
                throw NSError(domain: "Auth", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }

            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = obj["token"] as? String {
                self.authToken = token
                await refreshProfile()
                return AuthResponse(status: "OK", message: "Signed in.")
            } else {
                throw NSError(domain: "Auth", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Missing token"])
            }
        } catch {
            lastError = (error as NSError).localizedDescription
            throw error
        }
    }

    func requestPasswordReset(username: String) async throws -> AuthResponse {
        lastError = nil
        if skipAuthRoutes {
            return AuthResponse(status: "OK", message: "Reset not required for backend bearer.")
        }

        do {
            var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/auth/reset"))
            req.httpMethod = "POST"
            Secrets.headers(json: true).forEach { req.addValue($1, forHTTPHeaderField: $0) }
            let body: [String: Any] = ["username": username, "device_id": deviceId]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (data, resp) = try await session.data(for: req)

            guard let http = resp as? HTTPURLResponse else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response"])
            }

            switch http.statusCode {
            case 200...299:
                return AuthResponse(status: "OK", message: "Reset link sent.")
            case 404:
                return AuthResponse(status: "OK",
                                    message: "Reset requested (server route missing; check backend).")
            default:
                let msg = String(data: data, encoding: .utf8) ?? "Reset failed"
                throw NSError(domain: "Auth", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: msg])
            }
        } catch {
            lastError = (error as NSError).localizedDescription
            throw error
        }
    }

    // MARK: - Server profile fetch

    private func refreshProfile() async {
        if skipAuthRoutes {
            applyBackendFallback()
            return
        }
        guard let authToken else {
            profile = nil
            isAuthenticated = false
            return
        }
        do {
            var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/me"))
            req.httpMethod = "GET"
            var headers = Secrets.headers(json: false)
            headers["Authorization"] = "Bearer \(authToken)"
            headers.forEach { req.addValue($1, forHTTPHeaderField: $0) }
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                throw NSError(domain: "Auth", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Profile fetch failed"])
            }
            let p = try JSONDecoder().decode(UserProfile.self, from: data)
            profile = p
            isAuthenticated = true
        } catch {
            authToken = nil
            profile = nil
            isAuthenticated = false
            lastError = (error as NSError).localizedDescription
        }
    }

    // MARK: - Headers for APIClient integration (unchanged)
    func authHeader() -> (String, String)? {
        if let token = authToken, !token.isEmpty {
            return ("Authorization", "Bearer \(token)")
        }
        if !Secrets.backendBearer.isEmpty {
            return ("Authorization", "Bearer \(Secrets.backendBearer)")
        }
        return nil
    }

    func beginSignIn(username: String, password: String) async {
        _ = try? await startSignIn(username: username, password: password)
    }

    func updateMemoryPolicy(_ policy: MemoryPolicy) async {
        lastError = nil
        if skipAuthRoutes {
            let currentName = profile?.username ?? "Jarvis Operator"
            let currentEmail = profile?.email ?? fallbackEmail
            profile = UserProfile(userId: profile?.userId ?? fallbackId,
                                  username: currentName,
                                  email: currentEmail,
                                  memoryPolicy: policy)
            return
        }
        guard let authToken else { return }
        do {
            var req = URLRequest(url: Secrets.baseURL.appendingPathComponent("/me/memory"))
            req.httpMethod = "POST"
            var headers = Secrets.headers(json: true)
            headers["Authorization"] = "Bearer \(authToken)"
            headers.forEach { req.addValue($1, forHTTPHeaderField: $0) }
            let body: [String: Any] = ["policy": policy.rawValue]
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            await refreshProfile()
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    // MARK: - Helpers

    private func applyBackendFallback(using username: String? = nil) {
        guard skipAuthRoutes else { return }
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenName = (trimmed?.isEmpty == false ? trimmed! : (profile?.username ?? "Jarvis Operator"))
        let chosenEmail = (trimmed?.isEmpty == false ? trimmed! : (profile?.email ?? fallbackEmail))
        profile = UserProfile(userId: fallbackId,
                              username: chosenName,
                              email: chosenEmail,
                              memoryPolicy: profile?.memoryPolicy ?? .cloud)
        isAuthenticated = true
        lastError = nil
    }
}
