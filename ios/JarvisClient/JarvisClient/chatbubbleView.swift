// File: ios/JarvisClient/JarvisClient/chatbubbleView.swift
// Purpose: Single chat bubble view with action buttons for bot messages.

import SwiftUI

struct ChatBubbleView: View {
    enum Side {
        case me
        case bot
    }

    let side: Side
    let text: String

    // Action button callbacks (nil = don't show)
    var onCopy: (() -> Void)? = nil
    var onToggleSources: (() -> Void)? = nil
    var onSpeak: (() -> Void)? = nil
    var showingSources: Bool = false
    var sourceCount: Int = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if side == .bot {
                VStack(alignment: .leading, spacing: 6) {
                    bubble
                    if side == .bot && onCopy != nil {
                        actionButtons
                    }
                }
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
        let formatted: AttributedString =
            (try? AttributedString(markdown: text)) ?? AttributedString(text)

        return Text(formatted)
            .font(.body)
            .foregroundColor(AppTheme.text)
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(side == .me ? AppTheme.bubbleMe : AppTheme.bubbleBot)
            )
    }

    private var actionButtons: some View {
        HStack(spacing: 18) {
            // Copy button
            Button { onCopy?() } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            // Sources button with count badge
            Button { onToggleSources?() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "graduationcap")
                        .font(.system(size: 13))
                    if sourceCount > 0 {
                        Text("\(sourceCount)")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(showingSources ? AppTheme.primary : .secondary)
            }

            // Speak button
            Button { onSpeak?() } label: {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, 14)
    }
}
