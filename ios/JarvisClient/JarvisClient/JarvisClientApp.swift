//
//  JarvisClientApp.swift
//

import SwiftUI
import Contacts

@main
struct JarvisClientApp: App {
    var body: some Scene {
        WindowGroup {
            RootShellView()
                .onAppear {
                    // Request contacts access on first launch so the app can
                    // look up phone numbers when scheduling calls.
                    ContactsManager.shared.requestAccessIfNeeded { _ in }
                }
        }
    }
}
