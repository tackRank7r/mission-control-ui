// =====================================
// File: JarvisClient/PrivacySettingsView.swift
// =====================================
import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var auth = AuthManager.shared
    @State private var selection: MemoryPolicy = .off
    @State private var busy = false
    @State private var info: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Conversation Memory")) {
                    Picker("Policy", selection: $selection) {
                        ForEach(MemoryPolicy.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.inline)
                    Text(explainer(for: selection)).font(.footnote).foregroundColor(.secondary)
                }

                if let info {
                    Section { Text(info).foregroundColor(.secondary) }
                }

                Section {
                    Button("Save") {
                        Task {
                            busy = true
                            defer { busy = false }
                            await auth.updateMemoryPolicy(selection)
                            info = "Saved."
                        }
                    }.disabled(busy)
                }
            }
            .navigationTitle("Privacy")
            .onAppear {
                selection = auth.profile?.memoryPolicy ?? .off
            }
        }
    }

    private func explainer(for p: MemoryPolicy) -> String {
        switch p {
        case .off:   return "Jarvis will not retain information between chats."
        case .local: return "Jarvis stores memory securely on your device only."
        case .cloud: return "Jarvis stores memory on the server under your account."
        }
    }
}
