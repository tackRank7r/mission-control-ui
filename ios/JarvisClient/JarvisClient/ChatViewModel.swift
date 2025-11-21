// File: ios/JarvisClient/JarvisClient/ChatViewModel.swift
// Purpose: Chat view model with:
//  - Local ChatMessage model for UI
//  - Agent name (user-renamable, default "SideKick")
//  - READY_TO_CALL → CallService hook
//  - Safe stubbed sendToBackend (no JSON / no network)

import Foundation
import SwiftUI

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case me
        case bot
        case system
    }

    let id: UUID
    let role: Role
    var text: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = .init()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isSending: Bool = false

    /// Current assistant / agent display name (shown in the header).
    @Published var agentName: String

    /// Optional: email to send summaries to; can be set from login/profile.
    var userEmail: String?

    private let agentNameKey = "agentName"

    init(userEmail: String? = nil) {
        self.userEmail = userEmail

        let stored = UserDefaults.standard
            .string(forKey: agentNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let stored, !stored.isEmpty {
            self.agentName = stored
        } else {
            self.agentName = "SideKick"
        }
    }

    // MARK: - Agent name

    /// Update the agent name and persist it.
    /// Empty / whitespace-only values snap back to the default "SideKick".
    func updateAgentName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = trimmed.isEmpty ? "SideKick" : trimmed
        agentName = final
        UserDefaults.standard.set(final, forKey: agentNameKey)
    }

    // MARK: - Sending

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(role: .me, text: trimmed)
        messages.append(userMessage)
        isSending = true

        sendToBackend(prompt: trimmed) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.isSending = false

                switch result {
                case .success(let replyText):
                    self.handleAssistantReply(replyText, originalUserText: trimmed)

                case .failure(let error):
                    let errorMessage = ChatMessage(
                        role: .bot,
                        text: "Sorry, something went wrong: \(error.localizedDescription)"
                    )
                    self.messages.append(errorMessage)
                }
            }
        }
    }

    // MARK: - Assistant reply handling

    private func handleAssistantReply(_ replyText: String, originalUserText: String) {
        // 1) First, see if this is telling us to start a call.
        if handleCallIntentIfPresent(in: replyText, originalUserText: originalUserText) {
            return
        }

        // 2) Otherwise, treat as a normal bot message.
        let botMessage = ChatMessage(role: .bot, text: replyText)
        messages.append(botMessage)
    }

    /// Looks for a READY_TO_CALL marker and phone number in the assistant text.
    /// If found, starts the backend Twilio call and posts a friendly message instead
    /// of the raw control text.
    private func handleCallIntentIfPresent(
        in rawText: String,
        originalUserText: String
    ) -> Bool {
        guard rawText.uppercased().contains("READY_TO_CALL") else {
            return false
        }

        // Very forgiving parse: search for a line containing "Number:" or "Phone:"
        // and collect digits / optional +.
        let lines = rawText.components(separatedBy: .newlines)
        var phoneCandidate: String?

        for line in lines {
            let lower = line.lowercased()
            if lower.contains("number:") || lower.contains("phone:") {
                if let idx = line.firstIndex(of: ":") {
                    let afterColon = line[line.index(after: idx)...]
                    let digits = afterColon.filter { $0.isNumber || $0 == "+" }
                    if !digits.isEmpty {
                        phoneCandidate = String(digits)
                        break
                    }
                }
            }
        }

        guard let rawNumber = phoneCandidate else {
            // We saw READY_TO_CALL but couldn't find a number – surface a clear message.
            let fallback = ChatMessage(
                role: .bot,
                text: """
                      I tried to start the call, but I couldn't parse a phone number \
                      from this response:

                      \(rawText)
                      """
            )
            messages.append(fallback)
            return true
        }

        let friendly = ChatMessage(
            role: .bot,
            text: "I’m calling now and will email you a summary of the conversation once it’s finished."
        )
        messages.append(friendly)

        // Fire-and-forget backend call; we don’t block the UI on this.
        CallService.shared.startCall(
            phoneNumber: rawNumber,
            instructions: originalUserText,
            userEmail: userEmail
        ) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                switch result {
                case .success:
                    // Optional: append a subtle “call started” marker if you want.
                    break

                case .failure(let error):
                    let errorMessage = ChatMessage(
                        role: .bot,
                        text: "I tried to start the call, but there was an error: \(error.localizedDescription)"
                    )
                    self.messages.append(errorMessage)
                }
            }
        }

        return true
    }

    // MARK: - Backend wiring (temporary stub)

    /// TEMP: Stubbed backend so we *never* hit JSONSerialization here.
    /// Replace this later with your real API client once everything is stable.
    private func sendToBackend(
        prompt: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Simulate a short network delay and return a canned response.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            completion(.success("Stub reply from backend – replace sendToBackend in ChatViewModel.swift."))
        }
    }
}
