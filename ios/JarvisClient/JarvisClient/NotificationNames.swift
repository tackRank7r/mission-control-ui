// =====================================
// File: JarvisClient/NotificationNames.swift
// FINAL - Runbook Compliant Version
// =====================================

import Foundation

extension Notification.Name {
    // Authentication flow
    static let didStartSignIn = Notification.Name("didStartSignIn")
    static let didCompleteSignIn = Notification.Name("didCompleteSignIn")
    static let didFailSignIn = Notification.Name("didFailSignIn")
    static let didSignOut = Notification.Name("didSignOut")

    // Account management
    static let didStartSignUp = Notification.Name("didStartSignUp")
    static let didCompleteSignUp = Notification.Name("didCompleteSignUp")
    static let didRequestPasswordReset = Notification.Name("didRequestPasswordReset")
    static let didCompletePasswordReset = Notification.Name("didCompletePasswordReset")

    // Privacy & Settings
    static let didUpdatePrivacySettings = Notification.Name("didUpdatePrivacySettings")
    static let didSyncUserProfile = Notification.Name("didSyncUserProfile")

    // Miscellaneous app-level notifications
    static let didReceiveServerMessage = Notification.Name("didReceiveServerMessage")
    static let appDidEnterBackground = Notification.Name("appDidEnterBackground")
    static let appWillEnterForeground = Notification.Name("appWillEnterForeground")
}
