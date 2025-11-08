// =====================================
// File: JarvisClient/AuthViewModel.swift
// =====================================
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    static let shared = AuthViewModel()

    @Published var userToken: String? {
        didSet { persistToken(userToken) }
    }
    @Published var email: String = ""
    @Published var twilioNumber: String? = nil
    @Published var isAuthenticated: Bool = false
    @Published var lastError: String? = nil
    @Published var isBusy: Bool = false

    private let skipAuthRoutes = !Secrets.backendBearer.isEmpty

    private init() {
        self.userToken = Self.loadToken()
        if let token = userToken, !token.isEmpty {
            Secrets.authToken = token
        }
        if skipAuthRoutes {
            self.isAuthenticated = true
        } else {
            self.isAuthenticated = !(userToken ?? "").isEmpty
            Task { await refreshMeIfPossible() }
        }
    }

    // MARK: Public API
    func register(email: String, password: String) async -> Bool {
        clearError(); isBusy = true
        defer { isBusy = false }

        if skipAuthRoutes {
            markAuthenticated(email: email)
            return true
        }

        do {
            let url = Secrets.baseURL.appendingPathComponent("auth/register")
            let ok = try await postJSON(url: url, body: ["email": email, "password": password])
            guard (ok["ok"] as? Bool) == true else { throw SimpleError("Register failed.") }
            return true
        } catch {
            lastError = (error as NSError).localizedDescription
            return false
        }
    }

    func login(email: String, password: String) async -> Bool {
        clearError(); isBusy = true
        defer { isBusy = false }

        if skipAuthRoutes {
            markAuthenticated(email: email)
            return true
        }

        do {
            let url = Secrets.baseURL.appendingPathComponent("auth/login")
            let json = try await postJSON(url: url, body: ["email": email, "password": password])
            guard let token = json["token"] as? String else { throw SimpleError("Missing token.") }
            self.userToken = token
            self.email = (json["email"] as? String) ?? email
            self.twilioNumber = json["twilio_number"] as? String
            self.isAuthenticated = true
            return true
        } catch {
            lastError = (error as NSError).localizedDescription
            return false
        }
    }

    func logout() {
        userToken = nil
        email = ""
        twilioNumber = nil
        isAuthenticated = skipAuthRoutes ? true : false
        if skipAuthRoutes { lastError = nil }
    }

    func refreshMeIfPossible() async {
        if skipAuthRoutes { return }
        guard let token = userToken, !token.isEmpty else { return }
        clearError()
        do {
            let url = Secrets.baseURL.appendingPathComponent("me")
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue(token, forHTTPHeaderField: "X-User-Token")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) else { return }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.email = (json["email"] as? String) ?? self.email
                self.twilioNumber = json["twilioNumber"] as? String
                self.isAuthenticated = true
            }
        } catch {
            // stay silent; user can attempt login again
        }
    }

    // MARK: Helpers
    private func clearError() { lastError = nil }

    private static let tokenKey = "AuthViewModel.userToken"
    private func persistToken(_ token: String?) {
        let defaults = UserDefaults.standard
        Secrets.authToken = token
        if let t = token, !t.isEmpty { defaults.set(t, forKey: Self.tokenKey) }
        else { defaults.removeObject(forKey: Self.tokenKey) }
    }
    private static func loadToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    private func postJSON(url: URL, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SimpleHttpError(code: code, body: text)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SimpleError("Invalid JSON.")
        }
        return json
    }

    private func markAuthenticated(email: String) {
        self.userToken = nil
        self.email = email
        self.twilioNumber = nil
        self.isAuthenticated = true
        lastError = nil
    }

    struct SimpleError: LocalizedError { let message: String; init(_ m: String){message=m}; var errorDescription:String?{message} }
    struct SimpleHttpError: LocalizedError {
        let code: Int; let body: String
        var errorDescription: String? { "HTTP \(code): \(body)" }
    }
}
