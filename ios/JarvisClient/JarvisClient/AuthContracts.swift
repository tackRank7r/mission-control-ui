// =====================================
// File: JarvisClient/AuthContracts.swift
// Contracts used by WelcomeScreens + AuthManager
// =====================================

import Foundation

/// Uniform response the UI can reason about.
public struct AuthResponse: Sendable {
    public let status: String         // "OK", "VERIFY", "ERROR"
    public let message: String?

    public init(status: String, message: String? = nil) {
        self.status = status
        self.message = message
    }
}

/// What the UI needs from the auth layer.
/// AuthManager must conform to this.
public protocol AuthManaging: AnyObject {
    // Start a sign-in flow. On success either:
    //  - status "OK" (token already issued), or
    //  - status "VERIFY" (email code required).
    func startSignIn(username: String, password: String) async throws -> AuthResponse

    // Start a sign-up flow (server may email a code or provision an account).
    func startSignUp(username: String, password: String) async throws -> AuthResponse

    // Verify the emailed passcode; username provided for servers that need it.
    func verifyCode(username: String, code: String) async throws -> AuthResponse

    // Ask server to send password reset to username/email.
    func requestPasswordReset(username: String) async throws -> AuthResponse
}
