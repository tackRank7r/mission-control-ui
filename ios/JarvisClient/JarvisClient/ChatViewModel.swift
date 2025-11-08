// ==========================
// Path: JarvisClient/ChatViewModel.swift
// ==========================
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isSending: Bool = false
    @Published var error: String? = nil  // why: simple user-facing error text

    private let api = APIClient()

    func send(userText: String) async {
        let text = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        error = nil
        isSending = true
        messages.append(Message(role: .user, content: text)) // uses your Message.init default timestamp
        do {
            let res = try await api.ask(messages: messages)
            messages.append(Message(role: .assistant, content: res.reply))
        } catch {
            self.error = (error as NSError).localizedDescription
        }
        isSending = false
    }
}

// Convenience inits matching your Message type
extension Message {
    init(role: MessageRole, content: String) {
        self.init(role: role, content: content, timestamp: Date())
    }
}
