// File: ios/JarvisClient/JarvisClient/ChatViewModel.swift
// Action: REPLACE entire file
// Purpose: Chat state + backend calls + call-planning prompt per Runbook v14.

import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []

    // Backend response: { "reply": "..." }
    private struct AskResponse: Decodable {
        let reply: String
    }

    private struct BackendAPIError: LocalizedError {
        let statusCode: Int
        let body: String

        var errorDescription: String? {
            "HTTP \(statusCode): \(body)"
        }
    }

    init() {
        if messages.isEmpty {
            let welcome = Message(
                role: .assistant,
                content: "Hi, I’m Jarvis. Tell me what you’re working on and I’ll help with planning, calls, and messages."
            )
            messages = [welcome]
        }
    }

    /// Entry point from ContentView.
    func sendUserMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1) Append user message to timeline
        let userMessage = Message(role: .user, content: trimmed)
        messages.append(userMessage)

        // 2) Build prompt from full history + call-planning rules
        let promptToSend = buildPromptFromConversation(latestUserText: trimmed)

        // 3) Call backend
        do {
            let replyText = try await askBackend(prompt: promptToSend)
            let replyMessage = Message(role: .assistant, content: replyText)
            messages.append(replyMessage)
        } catch {
            let friendly = "I hit a network error talking to the backend: \(error.localizedDescription)"
            let errorMessage = Message(role: .assistant, content: friendly)
            messages.append(errorMessage)
        }
    }

    // MARK: - Prompt helpers

    /// Builds a single prompt string from the whole conversation.
    /// This gives the backend context (numbers + “call it”, etc.).
    private func buildPromptFromConversation(latestUserText: String) -> String {
        // Turn messages into a readable transcript.
        let historyLines = messages.map { msg -> String in
            let roleLabel: String
            switch msg.role {
            case .user:      roleLabel = "User"
            case .assistant: roleLabel = "Assistant"
            case .system:    roleLabel = "System"
            @unknown default: roleLabel = "Other"
            }
            return "\(roleLabel): \(msg.content)"
        }.joined(separator: "\n")

        // Base Jarvis behavior
        var systemInstructions = """
        You are Jarvis, a project and communications assistant running inside an iOS app.
        Be concise, friendly, and practical. You see the full conversation transcript and
        should respond as the Assistant in plain text (no JSON).

        If the user is just chatting, respond normally with helpful answers.
        """

        // Extra call-planning behavior when relevant
        if shouldTriggerCallPlanning(for: latestUserText) {
            systemInstructions += """



            CALL-PLANNING MODE:

            The user may want to make a phone call. When you detect that:
            - Ask for WHO we are calling (name / company) and, if missing, their phone number.
            - Ask for the main GOAL of the conversation.
            - Ask WHEN they want the call (now, later today, specific time, etc.).
            - Ask for any KEY POINTS they want us to hit on the call.

            If the user types a phone number (e.g. 7819345422) and then later says
            "call it", "call that number", "call them", or similar, assume they
            mean the most recent phone number mentioned in the conversation.

            Once you have enough information and the user clearly confirms they are ready,
            summarize the call plan and include the exact phrase: READY_TO_CALL
            in your last sentence so the system knows the plan is complete.
            """
        }

        return """
        \(systemInstructions)

        ---
        Conversation so far:
        \(historyLines)

        Assistant (your next reply only):
        """
    }

    private func shouldTriggerCallPlanning(for text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("phone call")
            || lower.contains("call this person")
            || lower.contains("schedule a call")
            || lower.contains("schedule a phone call")
            || lower.contains("call it")
            || lower.contains("call them")
            || lower.hasPrefix("/call")
    }

    // MARK: - Backend call

    private func askBackend(prompt: String) async throws -> String {
        let url = Secrets.askEndpoint
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Headers from Secrets (includes Authorization + JSON content type)
        let headers = Secrets.headers(json: true)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body: [String: Any] = ["prompt": prompt]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw BackendAPIError(statusCode: http.statusCode, body: bodyString)
        }

        let decoded = try JSONDecoder().decode(AskResponse.self, from: data)
        return decoded.reply
    }
}
