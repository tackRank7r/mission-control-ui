//
//  InputBar.swift
//  JarvisClient
//
 //


// File: InputBar.swift
import SwiftUI

struct InputBar: View {
    @Binding var text: String
    var onSend: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button(action: { onSend(text) }) {
                Label("Send", systemImage: "paperplane.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray.opacity(0.3) : .blue))
                    .foregroundColor(.white)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("SendButton")
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
