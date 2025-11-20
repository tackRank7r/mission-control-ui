import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Jarvis").font(.largeTitle).bold()
            Text("Tap continue to enter the app.").foregroundStyle(.secondary)
            Button("Continue") { auth.isAuthenticated = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
