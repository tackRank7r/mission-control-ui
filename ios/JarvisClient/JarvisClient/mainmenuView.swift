// File: ios/JarvisClient/JarvisClient/MainMenuView.swift
// Purpose: Full SideKick360 menu with all sections from the design spec.

import SwiftUI

struct MainMenuView: View {
    let onDismiss: () -> Void
    let onMakePhoneCall: () -> Void

    @State private var showPhoneNumber = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Top CTA
                    Button {
                        onMakePhoneCall()
                    } label: {
                        Label("Schedule a Phone Call", systemImage: "phone.arrow.up.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                    }
                    .padding(.horizontal)

                    // MARK: - Profile
                    menuSection(title: "Profile") {
                        menuRow(icon: "person", label: "Name", trailing: "Not Set")
                        Divider().padding(.leading, 44)
                        menuRow(icon: "phone", label: "Phone Number", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "envelope", label: "Email", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "location.north", label: "Location", trailing: nil)
                    }

                    // MARK: - Tools
                    menuSection(title: "Tools") {
                        menuRow(icon: "bell", label: "Reminders", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "checklist", label: "To-dos", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "doc.text", label: "Notes", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "newspaper", label: "Briefings", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "waveform", label: "Voice", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "alarm", label: "Wake Up Calls", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "calendar.badge.plus", label: "Cc to Schedule", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "envelope.badge", label: "Email Drafter", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "brain.head.profile", label: "Memory", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "person.2", label: "Additional Instructions", trailing: nil)
                    }

                    // MARK: - Integrations
                    menuSection(title: "Integrations") {
                        menuRow(icon: "calendar", label: "Calendar", trailing: "Not Connected")
                        Divider().padding(.leading, 44)
                        menuRow(icon: "envelope.fill", label: "Inbox", trailing: "Not Connected")
                        Divider().padding(.leading, 44)
                        menuRow(icon: "person.crop.circle", label: "Contacts", trailing: "Not Connected")
                        Divider().padding(.leading, 44)
                        menuRow(icon: "number.square", label: "Slack", trailing: "Business")
                        Divider().padding(.leading, 44)
                        menuRow(icon: "checklist", label: "Apple Reminders", trailing: "Beta")
                    }

                    // MARK: - About
                    menuSection(title: "About") {
                        menuRow(icon: "desktopcomputer", label: "Use on Web", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "questionmark.circle", label: "Help Center", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "lock.shield", label: "Privacy Policy", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "doc.plaintext", label: "Terms of Service", trailing: nil)
                        Divider().padding(.leading, 44)
                        menuRow(icon: "info.circle", label: "Contact Us", trailing: nil)
                    }

                    // MARK: - Account actions
                    VStack(spacing: 0) {
                        Button {
                            // TODO: wire log out
                        } label: {
                            Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .foregroundColor(.primary)

                        Divider().padding(.leading, 44)

                        Button(role: .destructive) {
                            // TODO: wire delete account with confirmation
                        } label: {
                            Label("Delete Account", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)

                    Spacer(minLength: 30)
                }
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("SideKick360")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    // MARK: - Reusable components

    @ViewBuilder
    private func menuSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func menuRow(icon: String, label: String, trailing: String?) -> some View {
        Button {
            // Placeholder — individual items will be wired later
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.primary)
                    .frame(width: 28)

                Text(label)
                    .foregroundColor(.primary)

                Spacer()

                if let trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.vertical, 12)
            .padding(.horizontal)
        }
    }
}
