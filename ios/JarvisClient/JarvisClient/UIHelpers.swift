import SwiftUI

// ---- Banners ----
struct ErrorBanner: View {
    let text: String
    var onClose: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).lineLimit(2)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
        }
        .font(.subheadline)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.4)))
        .padding([.horizontal, .top])
    }
}

struct InfoBanner: View {
    let text: String
    var onClose: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
            Text(text).lineLimit(2)
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
        }
        .font(.subheadline)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.4)))
        .padding([.horizontal])
    }
}

// ---- Chat bubble ----
struct MessageBubble: View {
    let message: Message
    var body: some View {
        let isUser = message.role == .user
        Text(message.content)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isUser ? Color.blue.opacity(0.2) : Color(.systemGray6))
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

// ---- Fallback mail view (used when MessageUI isn’t available/sending mail disabled) ----
struct FallbackMailView: View {
    let url: URL
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 16) {
            Text("Mail isn’t configured on this device.")
            Button("Open Mail") { openURL(url) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
