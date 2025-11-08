// ==============================
// File: JarvisClient/APIClient+Speak.swift
// (stub to avoid duplicate 'speak'; safe to delete this file entirely)
// ==============================
import Foundation

extension APIClient {
    /// Convenience: generate TTS for the last assistant message (if any).
    /// Returns `nil` when there is no assistant message to speak.
    func speakAssistantReply(from messages: [Message]) async throws -> Data? {
        guard let last = messages.last, last.role == .assistant else { return nil }
        return try await speak(last.content) // calls the method defined in APIClient.swift
    }
}
