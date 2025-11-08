// =========================================
/* File: JarvisClient/HistoryView.swift
   (contains search + rename sheet; depends on ChatStore/ChatSession) */
// =========================================
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: ChatStore
    var onSelect: (ChatSession) -> Void
    var onNew: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var renaming: ChatSession? = nil

    private var filtered: [ChatSession] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.sessions }
        return store.sessions.filter { s in
            s.title.localizedCaseInsensitiveContains(q)
            || s.messages.contains { $0.content.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onNew()
                        Haptics.success()
                        dismiss()
                    } label: { Label("New Chat", systemImage: "plus") }
                }
                Section("Chats") {
                    ForEach(filtered) { s in
                        Button {
                            onSelect(s)
                            Haptics.soft()
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title.isEmpty ? "Untitled" : s.title)
                                Text(s.createdAt, style: .date)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(allowsFullSwipe: false) {
                            Button("Rename") { renaming = s }.tint(.blue)
                        }
                    }
                    .onDelete(perform: store.delete)
                }
            }
            .navigationTitle("History")
            .toolbar { EditButton() }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search titles or messages")
            .sheet(item: $renaming) { s in
                RenameSessionSheet(
                    initial: s.title,
                    onCancel: {},
                    onSave: { name in store.rename(id: s.id, newTitle: name); Haptics.success() }
                )
            }
        }
    }
}

private struct RenameSessionSheet: View {
    @State private var name: String
    var onCancel: () -> Void
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initial: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        _name = State(initialValue: initial)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form { TextField("Title", text: $name).textInputAutocapitalization(.sentences) }
                .navigationTitle("Rename chat")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel(); dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { onSave(name); dismiss() }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
        }
    }
}
