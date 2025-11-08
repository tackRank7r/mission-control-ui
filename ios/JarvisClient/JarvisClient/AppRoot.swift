// =====================================
// File: JarvisClient/AppRoot.swift
// FINAL — routes to ContentView or WelcomeView
// =====================================
import SwiftUI

@main
struct JarvisClientApp: App {
    @StateObject private var auth = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isAuthenticated {
                    ContentView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Menu("Account") {
                                    if let profile = auth.profile {
                                        Text("Signed in as \(profile.username)").disabled(true)
                                        Divider()
                                    }
                                    NavigationLink(destination: PrivacySettingsView()) {
                                        Label("Privacy", systemImage: "lock.shield")
                                    }
                                    Button(role: .destructive) {
                                        auth.signOut()
                                    } label: {
                                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                }
                            }
                        }
                } else {
                    WelcomeView()   // real welcome screen with buttons
                }
            }
            .environmentObject(auth) // share AuthManager with all child views
        }
    }
}
