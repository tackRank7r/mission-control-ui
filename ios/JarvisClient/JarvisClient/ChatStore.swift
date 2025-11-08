// =========================================
// File: JarvisClient/ChatStore.swift
// (renamed internal type to avoid colliding with your File.swift)
// =========================================
import Foundation

@MainActor
final class ChatStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentID: UUID?

    private let url: URL

    init(filename: String = "chat_store.json") {
        url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        load()
        if sessions.isEmpty { newSession() }
        if currentID == nil { currentID = sessions.first?.id }
    }

    var currentSession: ChatSession {
        get { sessions.first(where: { $0.id == currentID }) ?? sessions[0] }
        set {
            guard let idx = sessions.firstIndex(where: { $0.id == newValue.id }) else { return }
            sessions[idx] = newValue
            save()
        }
    }

    func newSession(initial: [Message]? = nil) {
        let seed = initial ?? [Message(role: .system, content: "Hello! You’re chatting with Jarvis.")]
        var title = seed.first(where: { $0.role == .user })?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty {
            title = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        }
        let s = ChatSession(title: String(title.prefix(40)), messages: seed)
        sessions.insert(s, at: 0)
        currentID = s.id
        save()
    }

    func setCurrent(_ id: UUID) {
        currentID = id
        save()
    }

    func updateCurrentMessages(_ messages: [Message]) {
        guard let id = currentID, let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].messages = messages
        if let firstUser = messages.first(where: { $0.role == .user })?.content, !firstUser.isEmpty {
            sessions[idx].title = String(firstUser.prefix(40))
        }
        save()
    }

    func rename(id: UUID, newTitle: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[idx].title = trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(40))
        save()
    }

    func delete(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        if sessions.isEmpty { newSession() }
        currentID = sessions.first?.id
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        struct StorageFile: Codable { var sessions: [ChatSession]; var currentID: UUID? }
        if let file = try? JSONDecoder().decode(StorageFile.self, from: data) {
            sessions = file.sessions
            currentID = file.currentID ?? sessions.first?.id
        }
    }

    private func save() {
        struct StorageFile: Codable { var sessions: [ChatSession]; var currentID: UUID? }
        let file = StorageFile(sessions: sessions, currentID: currentID)
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: url) }
    }
}
