// File: ios/JarvisClient/JarvisClient/Message+UI.swift
// Action: CREATE new file
// Purpose: UI convenience for using `msg.text` even if the model stores `content`.

import Foundation

extension Message {
    /// Text used for display in chat bubbles.
    /// Adjust this if your model uses a different field name.
    var text: String {
        // Most of your earlier code used `content`, so bridge that.
        // If your Message already has `text`, this just returns it.
        // (If you later rename the stored property, update this one line.)
        // NOTE: If both `text` and `content` exist, prefer the real `text`.
        if let mirrorText = Mirror(reflecting: self).children
            .first(where: { $0.label == "text" })?.value as? String {
            return mirrorText
        }

        // Fallback to `content` if present.
        if let mirrorContent = Mirror(reflecting: self).children
            .first(where: { $0.label == "content" })?.value as? String {
            return mirrorContent
        }

        // Last-ditch fallback so we never crash.
        return ""
    }
}
