//
//  RootShellView.swift
//  Shows animated splash on first launch and once per hour, then main chat UI.
//

import SwiftUI

struct RootShellView: View {
    @State private var showSplash: Bool

    private static let lastSplashKey = "lastSplashTimestamp"
    private static let splashIntervalSeconds: TimeInterval = 3600 // 1 hour

    init() {
        // Show splash on first launch or if more than 1 hour since last splash
        let lastSplash = UserDefaults.standard.double(forKey: Self.lastSplashKey)
        if lastSplash == 0 {
            // First launch ever
            _showSplash = State(initialValue: true)
        } else {
            let elapsed = Date().timeIntervalSince1970 - lastSplash
            _showSplash = State(initialValue: elapsed >= Self.splashIntervalSeconds)
        }
    }

    var body: some View {
        ZStack {
            if showSplash {
                Splashview()
                    .transition(.opacity)
            } else {
                ContentView()
                    .transition(.opacity)
            }
        }
        .onAppear {
            if showSplash {
                // Record this splash timestamp
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: Self.lastSplashKey
                )
                // Dismiss after 3.3 seconds (3s spin animation + brief pause)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.3) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
