// File: JarvisClient/String+EmojiStrip.swift
// Strips emoji and markdown from text before sending to TTS engines.

import Foundation

extension String {
    /// Removes emoji and symbol characters that TTS engines read as garbage ("hash hash hash").
    /// Keeps all regular text, punctuation, numbers, and whitespace intact.
    var strippingEmoji: String {
        unicodeScalars.filter { scalar in
            // Reject characters that have Emoji_Presentation property
            if scalar.properties.isEmojiPresentation {
                return false
            }
            // Reject emoji modifiers and components (skin tones, joiners)
            if scalar.properties.isEmojiModifier || scalar.properties.isEmojiModifierBase {
                return false
            }
            // Reject variation selectors that force emoji rendering
            if scalar.value == 0xFE0F { return false }
            // Reject zero-width joiner used in compound emoji
            if scalar.value == 0x200D { return false }
            // Reject miscellaneous symbols & dingbats ranges
            if (0x2600...0x27BF).contains(scalar.value) { return false }
            // Reject supplemental symbols (most emoji live here)
            if (0x1F000...0x1FFFF).contains(scalar.value) { return false }
            // Reject enclosed alphanumeric supplement (circled numbers, etc.)
            if (0x1F100...0x1F1FF).contains(scalar.value) { return false }
            return true
        }
        .map(String.init)
        .joined()
        // Clean up extra whitespace left by removed emoji
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespaces)
    }

    /// Strips markdown formatting AND emoji so TTS reads clean natural text.
    /// Removes: **bold**, *italic*, # headings, [links](url), `code`, bullet markers, etc.
    var strippingForTTS: String {
        var text = self

        // Remove markdown bold/italic: **text** -> text, *text* -> text
        // Must handle ** before * to avoid leaving stray asterisks
        text = text.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#, with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\*(.+?)\*"#, with: "$1",
            options: .regularExpression
        )

        // Remove markdown headings: ### Heading -> Heading
        text = text.replacingOccurrences(
            of: #"#{1,6}\s*"#, with: "",
            options: .regularExpression
        )

        // Remove markdown links: [text](url) -> text
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1",
            options: .regularExpression
        )

        // Remove inline code backticks: `code` -> code
        text = text.replacingOccurrences(
            of: #"`([^`]+)`"#, with: "$1",
            options: .regularExpression
        )

        // Remove bullet markers at line start
        text = text.replacingOccurrences(
            of: #"(?m)^[\s]*[•\-]\s*"#, with: "",
            options: .regularExpression
        )

        // Remove numbered list markers: 1. 2. etc.
        text = text.replacingOccurrences(
            of: #"(?m)^\s*\d+\.\s*"#, with: "",
            options: .regularExpression
        )

        // Remove citation markers like [1], [2]
        text = text.replacingOccurrences(
            of: #"\[\d+\]"#, with: "",
            options: .regularExpression
        )

        // Now strip emoji
        return text.strippingEmoji
    }
}
