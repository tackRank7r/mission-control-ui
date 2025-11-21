//
//  RootShellView.swift
//  Hosts a 2s animated splash, then the main chat UI.
//

import SwiftUI

struct RootShellView: View {
    @State private var showSplash = true

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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.35)) {
                    showSplash = false
                }
            }
        }
    }
}
