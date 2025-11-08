// File: JarvisClient/MenuSheet.swift
// =====================================
import SwiftUI

struct MenuSheet: View {
    @ObservedObject var store: ChatStore
    var openHistory: () -> Void
    var openEmail: () -> Void
    var logout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { openHistory() } label: {
                        Label("Chat History", systemImage: "clock")
                    }
                    Button { openEmail() } label: {
                        Label("Send Email", systemImage: "envelope")
                    }
                    Button(role: .destructive) { logout() } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Menu")
        }
    }
}
