// ==============================
// File: JarvisClient/ContentView.swift
// (voice mode: hides chat, shows spinning blue vortex + debug label)
// ==============================
import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif

// NOTE: These helpers (ErrorBanner, InfoBanner, MessageBubble, FallbackMailView)
// must be defined exactly once in the project. This file does NOT redeclare them.

// Define custom notification name for API client last path
extension Notification.Name {
    static let apiClientLastPath = Notification.Name("apiClientLastPath")
}

struct ContentView: View {
    // UI state
    @State private var showHistory = false
    @State private var showMenu = false
    @State private var showMail = false
    @State private var text: String = ""

    // Local info banner
    @State private var infoMessage: String? = nil

    // Debug last path used
    @State private var lastPathUsed: String = "—"

    // Models
    @StateObject private var store = ChatStore()
    @StateObject private var vm = ChatViewModel()
    @StateObject private var voice = VoiceChatManager()

    var body: some View {
        NavigationStack {
            ZStack {
                // MAIN CONTENT switches depending on voice.state
                if voice.state == .idle {
                    chatContent
                } else {
                    voiceContent
                }
            }
            .safeAreaInset(edge: .bottom) {
                if voice.state == .idle { bottomBar }
            }
            .navigationTitle("Jarvis")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Menu") { showMenu = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .accessibilityIdentifier("MenuButton")
                }
            }
            .sheet(isPresented: $showMenu) { menuSheet }
            .sheet(isPresented: $showHistory) { historySheet }
            .sheet(isPresented: $showMail) { mailSheet }
            .onAppear {
                vm.messages = store.currentSession.messages.isEmpty
                    ? [Message(role: .system, content: "Hello! You’re chatting with Jarvis.")]
                    : store.currentSession.messages
            }
            .onReceive(NotificationCenter.default.publisher(for: .apiClientLastPath)) { note in
                if let s = note.object as? String { lastPathUsed = s }
            }
        }
    }

    // MARK: - Chat content (when voice is idle)
    private var chatContent: some View {
        VStack(spacing: 0) {
            if let err = vm.error {
                ErrorBanner(text: err) { vm.error = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let info = infoMessage {
                InfoBanner(text: info) { infoMessage = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let vErr = voice.lastError {
                ErrorBanner(text: vErr) { voice.lastError = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Debug line: state + last backend route used
            HStack(spacing: 8) {
                Text("State: \(stateLabel(voice.state))")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.15)))
                Image(systemName: "antenna.radiowaves.left.and.right")
                Text("API: \(lastPathUsed)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.messages) { msg in
                        MessageBubble(message: msg)
                    }
                    if vm.isSending {
                        ProgressView().padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Voice content (when voice is active)
    private var voiceContent: some View {
        VStack(spacing: 18) {
            if let vErr = voice.lastError {
                ErrorBanner(text: vErr) { voice.lastError = nil }
            }

            Spacer()

            // Blue vortex visualizer (reacts to audio level)
            VortexView(level: voice.audioLevel, state: voice.state)
                .frame(width: 180, height: 180)
                .accessibilityIdentifier("VoiceVortex")

            if !voice.partialTranscript.isEmpty {
                Text(voice.partialTranscript)
                    .font(.title3)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

            Spacer()

            Button {
                voice.stopAll()
            } label: {
                Label("Exit Voice Chat", systemImage: "xmark.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.red.opacity(0.2)))
                    .overlay(Capsule().stroke(Color.red.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(inputBackground.ignoresSafeArea())
    }

    // MARK: - Bottom Bar (Voice controls + Text input)
    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Voice controls row
            HStack(spacing: 12) {
                Button {
                    if voice.state == .idle {
                        Task { await voice.requestAndStart() }   // <-- key change
                    } else {
                        voice.stopAll()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: iconForState(voice.state))
                        Text(labelForState(voice.state))
                    }
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(colorForState(voice.state))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderForState(voice.state), lineWidth: 1)
                    )
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                if !voice.partialTranscript.isEmpty {
                    Text(voice.partialTranscript)
                        .lineLimit(2)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }

            // Typed input row
            HStack(spacing: 10) {
                TextField("Type a message…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(vm.isSending || voice.state != .idle)
                    .opacity(voice.state == .idle ? 1 : 0.5)
                    .onSubmit { sendTyped() }

                Button(action: { sendTyped() }) {
                    Image(systemName: "paperplane.fill")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(
                                canSend ? Color.blue : Color.gray.opacity(0.35)
                            )
                        )
                        .foregroundColor(.white)
                        .accessibilityIdentifier("SendButton")
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(inputBackground)
        .shadow(radius: 2)
    }

    private var canSend: Bool {
        !vm.isSending
        && voice.state == .idle
        && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions
    private func sendTyped() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, voice.state == .idle else { return }
        let sendText = t
        text = ""
        Task {
            await vm.send(userText: sendText)
            store.updateCurrentMessages(vm.messages)
        }
    }

    // MARK: - Visual helpers (primary colors w/ contrast)
    private func stateLabel(_ s: VoiceChatManager.State) -> String {
        switch s {
        case .idle: "Idle"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        }
    }

    private func iconForState(_ s: VoiceChatManager.State) -> String {
        switch s {
        case .idle: return "waveform.circle"
        case .listening: return "waveform.circle.fill"
        case .thinking: return "bolt.circle"
        case .speaking: return "speaker.wave.3.fill"
        }
    }
    private func labelForState(_ s: VoiceChatManager.State) -> String {
        switch s {
        case .idle: return "Voice"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking…"
        }
    }
    private func colorForState(_ s: VoiceChatManager.State) -> Color {
        switch s {
        case .idle:      return Color.blue.opacity(0.28)
        case .listening: return Color.green.opacity(0.30)
        case .thinking:  return Color.orange.opacity(0.32)
        case .speaking:  return Color.red.opacity(0.28)
        }
    }
    private func borderForState(_ s: VoiceChatManager.State) -> Color {
        switch s {
        case .idle:      return Color.blue.opacity(0.60)
        case .listening: return Color.green.opacity(0.65)
        case .thinking:  return Color.orange.opacity(0.65)
        case .speaking:  return Color.red.opacity(0.60)
        }
    }

    private var inputBackground: some View {
        Group {
            if #available(iOS 15.0, *) { Color.clear.background(.ultraThinMaterial) }
            else { Color(.systemBackground).opacity(0.92) }
        }
    }

    // MARK: - Sheets
    private var menuSheet: some View {
        MenuSheet(
            store: store,
            openHistory: { showMenu = false; showHistory = true },
            openEmail: { showMenu = false; showMail = true },
            logout: {
                showMenu = false
                infoMessage = "Logged out."
                Haptics.success()
            }
        )
        .presentationDetents([.medium, .large])
    }

    private var historySheet: some View {
        HistoryView(
            store: store,
            onSelect: { s in
                store.setCurrent(s.id)
                vm.messages = store.currentSession.messages
            },
            onNew: {
                store.newSession()
                vm.messages = store.currentSession.messages
                infoMessage = "Started a new chat."
            }
        )
    }

    private var mailSheet: some View {
        Group {
            #if canImport(MessageUI)
            if MFMailComposeViewController.canSendMail() {
                MailComposer(
                    recipient: "support@jarvisapp.io",
                    subject: "Jarvis Feedback",
                    messageBody: "Hi Jarvis team,\n\nI’d like to share some feedback..."
                )
            } else {
                FallbackMailView(url: URL(string: "mailto:support@jarvisapp.io?subject=Jarvis%20Feedback")!)
            }
            #else
            FallbackMailView(url: URL(string: "mailto:support@jarvisapp.io?subject=Jarvis%20Feedback")!)
            #endif
        }
    }
}

// MARK: - Blue Vortex Visualizer (unique name, does not collide)
private struct VortexView: View {
    let level: CGFloat      // 0...1 from mic
    let state: VoiceChatManager.State

    @State private var rotate = false

    var body: some View {
        ZStack {
            // Base blue disc
            Circle()
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.65), Color.blue.opacity(0.35)],
                    startPoint: .top, endPoint: .bottom))
                .scaleEffect(1 + level * 0.12)

            // Concentric rings that rotate (vortex)
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.white.opacity(0.45 - Double(i)*0.07), lineWidth: 2)
                    .padding(CGFloat(i) * 12)
                    .rotationEffect(.degrees(rotate ? Double(360 * (i % 2 == 0 ? 1 : -1)) : 0))
                    .animation(.linear(duration: Double(8 - i)).repeatForever(autoreverses: false), value: rotate)
            }

            // Crosshair lines (subtle)
            VStack { Rectangle().fill(Color.white.opacity(0.25)).frame(width: 2) }
                .padding(.horizontal, 20)
            HStack { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 2) }
                .padding(.vertical, 20)
        }
        .onAppear { rotate = true }
        .onChange(of: state) { _ in rotate = (state != .idle) }
    }
}
