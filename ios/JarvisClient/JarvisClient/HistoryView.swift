// File: ios/JarvisClient/JarvisClient/HistoryView.swift
// Action: REPLACE entire file
// Purpose: Placeholder chat history screen with correct background (no black bars).

import SwiftUI

struct HistoryView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Chat history")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Your past conversations will be listed here in a future build.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 40)
        }
        .navigationTitle("SideKick360")
        .navigationBarTitleDisplayMode(.inline)
    }
}
