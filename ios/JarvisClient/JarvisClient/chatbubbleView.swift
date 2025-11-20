// File: ios/JarvisClient/JarvisClient/chatbubbleView.swift
// Action: REPLACE entire file
// Purpose: Single chat bubble view matching JarvisClientClean theme,
//          with good readability for long, multi-step answers.

import SwiftUI

struct ChatBubbleView: View {
    enum Side {
        case me
        case bot
    }

    let side: Side
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if side == .bot {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var bubble: some View {
        // Use Markdown so the bot can send **bold** headings and numbered lists.
        let formatted: AttributedString =
            (try? AttributedString(markdown: text)) ?? AttributedString(text)

        return Text(formatted)
            .font(.body)
            .foregroundColor(AppTheme.text)
            .multilineTextAlignment(.leading)
            .lineSpacing(4) // nicer spacing for multi-step answers
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(side == .me ? AppTheme.bubbleMe : AppTheme.bubbleBot)
            )
    }
}
