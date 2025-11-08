
// ==========================
// Path: JarvisClient/ChatSession.swift
// (no Message/MessageRole here — just sessions)
// ==========================
import Foundation

struct ChatSession: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var messages: [Message]

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .init(),
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }
}

