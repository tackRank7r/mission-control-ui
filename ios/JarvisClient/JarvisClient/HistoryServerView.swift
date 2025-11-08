// =====================================
// Path: JarvisClient/HistoryServerView.swift
// =====================================
import SwiftUI

struct HistoryServerView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var input: String = ""
    @FocusState private var focused: Bool
    @State private var showDiagnostics: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(vm.messages) { msg in
                                bubble(for: msg)
                                    .id(msg.id)
                            }
                            if vm.isSending {
                                ProgressView().padding(.vertical, 8)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { _ in
                        if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                Divider()
                inputBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDiagnostics = true
                    } label: {
                        Image(systemName: "waveform.path.ecg")
                    }
                    .accessibilityLabel("Diagnostics")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        vm.messages.removeAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(vm.messages.isEmpty)
                    .accessibilityLabel("Clear Chat")
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil },
                set: { if !$0 { vm.error = nil } }
            )) {
                Button("OK", role: .cancel) { vm.error = nil }
            } message: {
                Text(vm.error ?? "Unknown error")
            }
        }
    }

    @ViewBuilder
    private func bubble(for msg: Message) -> some View {
        HStack(alignment: .top) {
            if msg.role == .assistant { Spacer(minLength: 40) }
            Text(msg.content)
                .padding(10)
                .background(msg.role == .user ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            if msg.role == .user { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message…", text: $input)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .disabled(vm.isSending)
                .onSubmit { send() }

            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(vm.isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send() {
        let text = input
        input = ""
        focused = false
        Task { await vm.send(userText: text) }
    }
}

struct HistoryServerView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryServerView()
    }
}
