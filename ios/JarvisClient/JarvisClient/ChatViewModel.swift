// File: ios/JarvisClient/JarvisClient/ChatViewModel.swift
// Purpose: Chat view model with:
//  - Local ChatMessage model for UI
//  - Agent name (user-renamable, default "SideKick")
//  - READY_TO_CALL → CallService hook
//  - Real backend via APIClient.ask()
//  - Source count tracking for citations

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

    /// Tracks which bot messages have their sources panel visible.
    @Published var sourcesVisible: Set<UUID> = []

    /// Optional: email to send summaries to; can be set from login/profile.
    var userEmail: String?

    private let api = APIClient()
    private let agentNameKey = "agentName"
    private var sourceCounts: [UUID: Int] = [:]

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

    /// Add a message from voice conversation (bypasses backend, messages come from VoiceChatManager)
    func addVoiceMessage(text: String, isUser: Bool) {
        let message = ChatMessage(role: isUser ? .me : .bot, text: text)
        messages.append(message)
    }

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
                case .success(let response):
                    let botMessage = ChatMessage(role: .bot, text: response.reply)
                    self.messages.append(botMessage)

                    // If the backend auto-scheduled a call, show confirmation
                    if let callInfo = response.call_scheduled {
                        let name = callInfo.target_name ?? "the number"
                        let confirmMessage = ChatMessage(
                            role: .bot,
                            text: "Your call to \(name) has been scheduled and will start shortly. I'll email you a summary when it's done."
                        )
                        self.messages.append(confirmMessage)
                    }

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

    // MARK: - Backend wiring

    private func sendToBackend(
        prompt: String,
        completion: @escaping (Result<AskResponse, Error>) -> Void
    ) {
        // Convert ChatMessage history to Message objects for the API
        var apiMessages: [Message] = messages.compactMap { msg in
            switch msg.role {
            case .me:    return Message(role: .user, content: msg.text)
            case .bot:   return Message(role: .assistant, content: msg.text)
            case .system: return Message(role: .system, content: msg.text)
            }
        }

        Task {
            // Enrich the last user message with contact info if a name is found
            if let match = await ContactsManager.shared.findContactInText(prompt) {
                if let lastIdx = apiMessages.lastIndex(where: { $0.role == .user }) {
                    let original = apiMessages[lastIdx].content
                    apiMessages[lastIdx] = Message(
                        role: .user,
                        content: "\(original)\n[Device found contact: \(match.name) — \(match.phone)]"
                    )
                }
            }

            do {
                let response = try await api.ask(messages: apiMessages)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Source tracking

    func toggleSources(for messageID: UUID) {
        if sourcesVisible.contains(messageID) {
            sourcesVisible.remove(messageID)
        } else {
            sourcesVisible.insert(messageID)
        }
    }

    func sourceCount(for messageID: UUID) -> Int {
        sourceCounts[messageID] ?? 0
    }

    func setSourceCount(_ count: Int, for messageID: UUID) {
        sourceCounts[messageID] = count
    }

    /// Count citation patterns like [1], [2], etc. in text.
    static func countSources(in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return 0 }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let uniqueNumbers = Set(matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        })
        return uniqueNumbers.count
    }
}
