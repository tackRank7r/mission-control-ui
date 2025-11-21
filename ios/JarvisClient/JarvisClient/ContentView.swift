//
//  ContentView.swift
//  SideKick360 / JarvisClient
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()

    @State private var inputText: String = ""
    @State private var showMenu = false
    @State private var showHistory = false

    @FocusState private var isInputFocused: Bool

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTyping: Bool {
        !trimmedInput.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Fill background to eliminate black bars.
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    Divider().opacity(0.0)
                    chatList
                    inputBar
                }
            }
            .sheet(isPresented: $showMenu) {
                MainMenuView(
                    onDismiss: { showMenu = false },
                    onMakePhoneCall: {
                        showMenu = false
                        inputText = "Make a phone call"
                        isInputFocused = true
                    }
                )
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    HistoryView()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                showMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 22, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                // Agent name ~80% of the old huge title.
                Text(vm.agentName)
                    .font(.system(size: 22, weight: .semibold))
                Text("Your project & calls copilot")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                // You can wire this to a help view if you like.
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22, weight: .semibold))
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Chat list

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(vm.messages) { msg in
                        ChatBubbleView(
                            side: msg.role == .me ? .me : .bot,
                            text: msg.text
                        )
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: vm.messages.count) { _ in
                if let lastID = vm.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            Button {
                handleSend()
            } label: {
                Text("Send")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isTyping && !vm.isSending
                                  ? Color.accentColor
                                  : Color.gray.opacity(0.3))
                    )
                    .foregroundColor(.white)
            }
            .disabled(!isTyping || vm.isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    // MARK: - Actions

    private func handleSend() {
        let text = trimmedInput
        guard !text.isEmpty else { return }

        // Clear UI immediately so it doesn't "stick" in the field.
        inputText = ""
        isInputFocused = false

        vm.send(text)
    }
}
