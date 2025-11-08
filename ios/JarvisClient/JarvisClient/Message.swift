// ==========================
// Path: JarvisClient/Message.swift
// (single source of truth for chat messages)
// ==========================
import Foundation

enum MessageRole: String, Codable {
    case user, assistant, system
}

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = .init()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
