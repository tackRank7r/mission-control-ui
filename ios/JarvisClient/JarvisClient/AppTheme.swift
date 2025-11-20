// File: ios/JarvisClient/JarvisClient/AppTheme.swift
// Action: REPLACE or CREATE new file
// Purpose: Central colors + tokens reused by chat UI & menus.

import SwiftUI

enum AppTheme {
    // Core palette
    static let primary = Color(red: 0.11, green: 0.36, blue: 0.95) // blue
    static let accent  = Color(red: 0.92, green: 0.12, blue: 0.20) // red

    // Back-compat aliases (used by other views you already have)
    static let blue = primary
    static let red  = accent

    // Tokens referenced by menus / context screens
    static let muted = Color.secondary
    static let card  = Color(UIColor.secondarySystemBackground)
    static let text  = Color.primary

    // Chat bubbles
    static let bubbleMe  = Color(UIColor.systemBlue).opacity(0.20)
    static let bubbleBot = Color(UIColor.secondarySystemBackground)
}
