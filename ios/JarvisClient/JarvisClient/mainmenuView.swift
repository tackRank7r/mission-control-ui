// File: ios/JarvisClient/JarvisClient/MainMenuView.swift
// Action: REPLACE entire file
//
// Purpose:
// - SideKick360 main menu sheet
// - “View phone number” opens PhoneNumberView (fetches from Render backend)
// - “Make a phone call” calls onMakePhoneCall()
// - Other items are safe placeholders you can wire up later.

import SwiftUI

struct MainMenuView: View {
    let onDismiss: () -> Void
    let onMakePhoneCall: () -> Void

    @State private var showPhoneNumber = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Communication

                Section("Communication") {
                    Button {
                        showPhoneNumber = true
                    } label: {
                        Label("View phone number", systemImage: "phone.circle")
                    }

                    Button {
                        onMakePhoneCall()
                    } label: {
                        Label("Make a phone call", systemImage: "phone.arrow.up.right")
                    }

                    Button {
                        // TODO: send “schedule a meeting” intent into chat
                    } label: {
                        Label("Schedule a meeting", systemImage: "calendar.badge.plus")
                    }

                    Button {
                        // TODO: send “compose email” intent into chat
                    } label: {
                        Label("Send an email", systemImage: "envelope")
                    }
                }

                // MARK: - Help & context

                Section("Help & context") {
                    Button {
                        // TODO: show app context summary via chat
                    } label: {
                        Label("View app context", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        // TODO: start guided tour via chat messages or GuidedTourView
                    } label: {
                        Label("Guided tour", systemImage: "hand.point.right")
                    }
                }
            }
            .tint(AppTheme.primary)
            .navigationTitle("SideKick360")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .sheet(isPresented: $showPhoneNumber) {
                // This view should be defined in PhoneNumberView.swift
                PhoneNumberView()
            }
        }
    }
}
