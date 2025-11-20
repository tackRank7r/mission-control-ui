// File: ios/JarvisClient/JarvisClient/contentView.swift
// Action: REPLACE entire file
// Purpose: Main chat UI with dual mic radar buttons, per Runbook v14.

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()

    @State private var inputText: String = ""
    @State private var showMenu = false
    @State private var showContext = false
    @State private var showGuidedTour = false

    @State private var isDictationActive = false
    @State private var isVoiceChatActive = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Full-screen background (inside safe area)
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    Divider().opacity(0.0)
                    chatList
                }
            }
            // Input bar pinned above the keyboard
            .safeAreaInset(edge: .bottom) {
                inputBar
                    .background(.thinMaterial)
            }
            // Jarvis Menu sheet
            .sheet(isPresented: $showMenu) {
                MainMenuView(
                    onDismiss: { showMenu = false },
                    onMakePhoneCall: {
                        showMenu = false
                        handleMakePhoneCallFromMenu()
                    }
                )
            }
            // App Context sheet
            .sheet(isPresented: $showContext) {
                AppContextView()
            }
            // Guided Tour sheet
            .sheet(isPresented: $showGuidedTour) {
                GuidedTourView()
            }
        }
        // Hide nav chrome; Jarvis header hugs the safe-area top
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Hamburger → Jarvis Menu
            Button {
                showMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 24, weight: .semibold))
                    .padding(10)
                    .foregroundColor(AppTheme.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Jarvis")
                    .font(.system(size: 34, weight: .bold))

                Text("Your project & comms assistant")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Question mark → Guided Tour
            Button {
                showGuidedTour = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .padding(10)
                    .foregroundColor(AppTheme.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)   // slightly tighter than before
        .padding(.bottom, 4)
    }

    // MARK: - Chat list

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(vm.messages) { message in
                        ChatBubbleView(
                            side: message.role == .user ? .me : .bot,
                            text: message.content
                        )
                        .id(message.id)
                    }
                }
                .padding(.vertical, 8)
            }
            // Tap anywhere in the conversation to dismiss keyboard
            .onTapGesture {
                UIApplication.shared.endEditing()
            }
            .onChange(of: vm.messages.count) { _ in
                guard let last = vm.messages.last else { return }
                withAnimation {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input bar (dual radar mics + Send)

    private var inputBar: some View {
        let canSend = !inputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        return HStack(spacing: 8) {
            // LEFT MIC – dictation radar
            MicRadarButton(
                systemName: "mic.fill",
                isActive: $isDictationActive
            ) {
                // TODO: hook into VoiceInputManager for dictation
                UIApplication.shared.endEditing()
            }

            // TEXT FIELD
            TextField("Message…", text: $inputText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(UIColor.systemGray4), lineWidth: 1)
                )
                .submitLabel(.send)
                .onSubmit {
                    sendCurrentMessage()
                }

            // RIGHT MIC – voice chat radar
            MicRadarButton(
                systemName: "waveform",
                isActive: $isVoiceChatActive
            ) {
                // TODO: present full-screen voice chat / spinning icon animation
                UIApplication.shared.endEditing()
            }

            // SEND BUTTON – blue when enabled
            Button(action: sendCurrentMessage) {
                Text("Send")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(canSend ? AppTheme.primary : Color(UIColor.systemGray4))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)   // slightly tighter than before
    }

    // MARK: - Actions

    private func sendCurrentMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let textToSend = trimmed
        inputText = ""

        Task {
            await vm.sendUserMessage(textToSend)
        }
    }

    private func handleMakePhoneCallFromMenu() {
        // Nudge into call-planning flow via ChatViewModel’s prompt.
        let helper = "I’d like to plan a phone call with someone. Please help me collect the details."
        Task {
            await vm.sendUserMessage(helper)
        }
    }
}

// MARK: - Radar mic button

struct MicRadarButton: View {
    let systemName: String
    @Binding var isActive: Bool
    let action: () -> Void

    @State private var sweep = false

    var body: some View {
        Button {
            isActive.toggle()
            action()
            if isActive {
                sweep = true
            } else {
                sweep = false
            }
        } label: {
            ZStack {
                // Base circle with red outline
                Circle()
                    .fill(Color.white)
                    .overlay(
                        Circle().stroke(AppTheme.accent, lineWidth: 2)
                    )
                    .frame(width: 44, height: 44)

                // Spinning radar arc
                Circle()
                    .trim(from: 0.0, to: 0.35)
                    .stroke(
                        AppTheme.accent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 32, height: 32)
                    .rotationEffect(Angle.degrees(sweep && isActive ? 360 : 0))
                    .animation(
                        isActive
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                        value: sweep && isActive
                    )

                // Mic / waveform icon
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.primary)
            }
        }
    }
}

// MARK: - Keyboard helper

private extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder),
                   to: nil, from: nil, for: nil)
    }
}
