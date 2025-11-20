// File: ios/JarvisClient/JarvisClient/mainmenuView.swift
// Action: REPLACE entire file

import SwiftUI

struct MainMenuView: View {
    let onDismiss: () -> Void
    let onMakePhoneCall: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Communication") {
                    Button {
                        // TODO: have Jarvis explain your phone number / Twilio status in chat
                    } label: {
                        Label("Phone Number Info", systemImage: "phone.circle")
                    }

                    Button {
                        // TODO: send "schedule a meeting" intent into chat
                    } label: {
                        Label("Schedule a Meeting", systemImage: "calendar.badge.plus")
                    }

                    Button {
                        onMakePhoneCall()
                    } label: {
                        Label("Make a Phone Call", systemImage: "phone.arrow.up.right")
                    }

                    Button {
                        // TODO: send "compose email" intent into chat
                    } label: {
                        Label("Send an Email", systemImage: "envelope")
                    }
                }

                Section("Help & Context") {
                    Button {
                        // TODO: show app context summary via chat
                    } label: {
                        Label("View App Context", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        // TODO: start guided tour via chat messages
                    } label: {
                        Label("Guided Tour", systemImage: "hand.point.right")
                    }
                }
            }
            .tint(AppTheme.primary)
            .navigationTitle("Jarvis Menu")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}
