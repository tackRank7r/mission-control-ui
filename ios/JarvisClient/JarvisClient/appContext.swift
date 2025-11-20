// FILE: ios/JarvisClient/JarvisClient/AppContext.swift
// Static catalog describing what the Jarvis app can do and where features live.

import SwiftUI

struct AppContextItem: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let location: String
}

enum AppContextCatalog {
    static let items: [AppContextItem] = [
        AppContextItem(
            title: "Chat with Jarvis",
            description: "Ask questions, plan projects, and get multi-step answers in the main chat screen.",
            location: "Home > Chat"
        ),
        AppContextItem(
            title: "Voice dictation mic",
            description: "Tap the left mic above the keyboard to dictate a message instead of typing.",
            location: "Home > Chat > Input bar"
        ),
        AppContextItem(
            title: "Polly / voice response mic",
            description: "Tap the waveform mic to request a spoken response using your TTS backend.",
            location: "Home > Chat > Input bar"
        ),
        AppContextItem(
            title: "New Chat",
            description: "Start a fresh conversation, clearing current context while keeping history.",
            location: "Menu > Chats & Projects"
        ),
        AppContextItem(
            title: "Chat History",
            description: "Browse and reopen previous conversations.",
            location: "Menu > Chats & Projects"
        ),
        AppContextItem(
            title: "Projects",
            description: "Organize work into named projects and attach chat history, notes, and calls.",
            location: "Menu > Chats & Projects"
        ),
        AppContextItem(
            title: "New Project",
            description: "Create a new project and set its goal, owner, and timeline.",
            location: "Menu > Chats & Projects"
        ),
        AppContextItem(
            title: "Search Chats",
            description: "Search across past conversations for messages, tasks, or decisions.",
            location: "Menu > Chats & Projects"
        ),
        AppContextItem(
            title: "Phone Number Info",
            description: "View the Twilio phone numbers and routing rules configured for your account.",
            location: "Menu > Communication"
        ),
        AppContextItem(
            title: "Schedule a Meeting",
            description: "Ask Jarvis to set up a meeting and capture the details for your calendar.",
            location: "Menu > Communication"
        ),
        AppContextItem(
            title: "Make a Phone Call",
            description: "Initiate an outbound call using your integrated telephony provider.",
            location: "Menu > Communication"
        ),
        AppContextItem(
            title: "Send an Email",
            description: "Draft and send an email using your configured email account.",
            location: "Menu > Communication"
        ),
        AppContextItem(
            title: "Login / Account",
            description: "Sign in, manage your profile, and connect external services.",
            location: "Menu > Account"
        ),
        AppContextItem(
            title: "Guided Tour",
            description: "Walk through the five major features of the app with step-by-step instructions.",
            location: "Menu > Help & Context"
        )
    ]

    // A curated subset for the guided tour.
    static let guidedTourItems: [AppContextItem] = [
        items.first(where: { $0.title == "Chat with Jarvis" })!,
        items.first(where: { $0.title == "Voice dictation mic" })!,
        items.first(where: { $0.title == "Projects" })!,
        items.first(where: { $0.title == "Make a Phone Call" })!,
        items.first(where: { $0.title == "Send an Email" })!
    ]
}

// Simple view: list all context items so Jarvis can “explain itself” to the user.
struct AppContextView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(AppContextCatalog.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                        Text(item.description)
                            .font(.subheadline)
                        Text(item.location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Jarvis Context")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
    