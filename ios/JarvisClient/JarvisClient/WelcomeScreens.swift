// =====================================
// File: JarvisClient/WelcomeScreens.swift
// FINAL — single-sheet router + visible tap counters + namespaced logs
// =====================================

import SwiftUI
import Combine

// MARK: - Shared Auth access
private var AUTH: AuthManaging? { AuthManager.shared as? AuthManaging }
private func requireAuth(_ fn: StaticString) -> AuthManaging {
    guard let a = AUTH else {
        fatalError("AuthManager.shared does not conform to AuthManaging when calling \(fn).")
    }
    return a
}

// MARK: - Namespaced on-screen logging (no collisions)
extension Notification.Name { static let WSLogEvent = Notification.Name("WSLogEvent") }

private enum WSLog {
    static func post(_ line: String) {
        NotificationCenter.default.post(name: .WSLogEvent, object: line)
        print(line)
    }
    @discardableResult
    static func tap(_ text: String) -> String {
        let line = "[tap] \(text)"
        post(line); return line
    }
    @discardableResult
    static func measureAsync<T>(_ label: String, _ work: @escaping () async throws -> T)
        async rethrows -> (result: T, elapsedMs: Int)
    {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try await work()
        let end = DispatchTime.now().uptimeNanoseconds
        let ms = Int((end - start) / 1_000_000)
        post("[measure] \(label) took \(ms)ms")
        return (result, ms)
    }
}

// MARK: - Overlay UI
private final class WSLogStore: ObservableObject {
    static let shared = WSLogStore()
    @Published var lines: [String] = []
    func append(_ s: String) {
        Task { @MainActor in
            lines.append(s)
            if lines.count > 15 { lines.removeFirst() }
        }
    }
}

private struct DebugOverlay: View {
    @ObservedObject private var store = WSLogStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.lines.reversed(), id: \.self) {
                Text($0).font(.caption2).foregroundColor(.green)
            }
        }
        .padding(6)
        .background(.black.opacity(0.7))
        .cornerRadius(8)
        .frame(maxHeight: 120)
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .WSLogEvent)) { note in
            if let s = note.object as? String { store.append(s) }
        }
        .allowsHitTesting(false) // ← cannot block touches
    }
}

// MARK: - Single-sheet router (prevents multi-sheet gesture conflicts)
private enum ActiveSheet: Identifiable { case signIn, signUp, forgot
    var id: Int { hashValue }
}

// MARK: - Welcome (red) screen
public struct WelcomeView: View {
    @State private var activeSheet: ActiveSheet?
    @State private var tapCountNew = 0
    @State private var tapCountExisting = 0
    @State private var tapCountForgot = 0

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [Color(red: 0.92, green: 0.17, blue: 0.17),
                         Color(red: 0.80, green: 0.12, blue: 0.12)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                AppLogoView().frame(width: 160, height: 160).shadow(radius: 12)
                Text("Welcome to Jarvis")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Spacer()

                VStack(spacing: 12) {
                    Button {
                        WSLog.tap("Open SignUp sheet")
                        tapCountNew += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeSheet = .signUp
                    } label: {
                        Text("I’m new — Create account (\(tapCountNew))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white)
                            .foregroundColor(Color(red: 0.80, green: 0.12, blue: 0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(radius: 1, y: 1)
                    }
                    .contentShape(Rectangle())

                    Button {
                        WSLog.tap("Open SignIn sheet")
                        tapCountExisting += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeSheet = .signIn
                    } label: {
                        Text("I already have an account — Sign in (\(tapCountExisting))")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.15))
                            .foregroundColor(.white)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.5), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .contentShape(Rectangle())

                    Button {
                        WSLog.tap("Open Forgot sheet")
                        tapCountForgot += 1
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        activeSheet = .forgot
                    } label: {
                        Text("Forgot password? (\(tapCountForgot))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .underline()
                            .padding(.top, 2)
                    }
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, 22)

                Spacer(minLength: 24)
            }

            DebugOverlay()
        }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .signIn:  SignInView(mode: .existing)
            case .signUp:  SignInView(mode: .newUser)
            case .forgot:  ForgotPasswordView()
            }
        }
    }
}

// MARK: - Sign In / Sign Up
struct SignInView: View {
    enum Mode { case existing, newUser }
    enum Step { case credentials, verify }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var step: Step = .credentials
    @State private var info: String?
    @State private var error: String?
    @State private var isLoading = false

    private var title: String { mode == .existing ? "Sign In" : "Create Account" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(red: 0.92, green: 0.17, blue: 0.17),
                             Color(red: 0.80, green: 0.12, blue: 0.12)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 150)
                .overlay(AppLogoView().frame(width: 84, height: 84))
                .overlay(Text(title).font(.title2.bold()).foregroundColor(.white).padding(.top, 100), alignment: .top)
                .ignoresSafeArea(edges: .top)

                Form {
                    if let info { Section { Text(info).foregroundColor(.secondary) } }
                    if let error { Section { Text(error).foregroundColor(.red) } }

                    if step == .credentials {
                        Section(mode == .existing ? "Your account" : "Create your account") {
                            TextField("Username (email)", text: $username)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                            SecureField(mode == .existing ? "Password" : "Choose a password", text: $password)
                        }
                        Section {
                            Button { signInOrSignUp() } label: {
                                HStack { if isLoading { ProgressView() }; Text(mode == .existing ? "Continue" : "Create & Continue") }
                            }
                            .disabled(isLoading || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                        }
                    } else {
                        Section("Email passcode") {
                            Text("We sent a code to your email.").foregroundColor(.secondary)
                            TextField("6-digit code", text: $code).keyboardType(.numberPad)
                        }
                        Section {
                            Button { verifyCode() } label: {
                                HStack { if isLoading { ProgressView() }; Text("Verify and Sign In") }
                            }
                            .disabled(isLoading || code.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
    }

    private func signInOrSignUp() {
        guard !isLoading else { return }
        WSLog.tap(mode == .existing ? "SignIn Continue" : "SignUp Continue")
        isLoading = true; error = nil; info = nil

        Task {
            defer { Task { @MainActor in isLoading = false } }
            let auth = requireAuth(#function)
            do {
                if mode == .newUser {
                    let (res, _) = try await WSLog.measureAsync("startSignUp") {
                        try await withTimeout(seconds: 15) { try await auth.startSignUp(username: username, password: password) }
                    }
                    await MainActor.run {
                        if res.status == "OK" { info = res.message ?? "Account created." }
                        else { error = res.message ?? "Could not create account." }
                    }
                } else {
                    let (res, _) = try await WSLog.measureAsync("startSignIn") {
                        try await withTimeout(seconds: 15) { try await auth.startSignIn(username: username, password: password) }
                    }
                    await MainActor.run {
                        switch res.status {
                        case "OK": info = res.message ?? "Signed in."
                        case "VERIFY": info = res.message ?? "Enter the code sent to your email."; step = .verify
                        default: error = res.message ?? "Sign in failed."
                        }
                    }
                }
            } catch {
                await MainActor.run { self.error = (error as NSError).localizedDescription }
            }
        }
    }

    private func verifyCode() {
        guard !isLoading else { return }
        WSLog.tap("Verify Code")
        isLoading = true; error = nil; info = nil

        Task {
            defer { Task { @MainActor in isLoading = false } }
            let auth = requireAuth(#function)
            do {
                let (res, _) = try await WSLog.measureAsync("verifyCode") {
                    try await withTimeout(seconds: 15) { try await auth.verifyCode(username: username, code: code) }
                }
                await MainActor.run {
                    if res.status == "OK" { info = res.message ?? "Signed in." }
                    else { error = res.message ?? "Invalid code." }
                }
            } catch {
                await MainActor.run { self.error = (error as NSError).localizedDescription }
            }
        }
    }
}

// MARK: - Forgot Password
struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isSent = false
    @State private var error: String?
    @State private var isLoading = false
    @State private var localTapCount = 0 // visible on-screen

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundColor(.red) } }
                if isSent { Section { Text("Reset link sent!").foregroundColor(.green) } }

                Section("Account email") {
                    TextField("Username (email)", text: $username)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                }
                Section {
                    Button {
                        localTapCount += 1 // on-screen counter
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        WSLog.tap("ForgotPassword Button tapped (\(localTapCount))")
                        sendReset()
                    } label: {
                        HStack {
                            if isLoading { ProgressView() }
                            Text("Send reset link (\(localTapCount))")
                        }
                    }
                    .disabled(isLoading || username.isEmpty)
                }
            }
            .navigationTitle("Forgot Password")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        }
    }

    private func sendReset() {
        guard !isLoading else { return }
        isLoading = true; error = nil; isSent = false

        Task {
            defer { Task { @MainActor in isLoading = false } }
            let auth = requireAuth(#function)
            do {
                let (res, ms) = try await WSLog.measureAsync("requestPasswordReset") {
                    try await withTimeout(seconds: 15) { try await auth.requestPasswordReset(username: username) }
                }
                WSLog.post("[flow] requestPasswordReset -> \(res.status) in \(ms)ms")
                await MainActor.run {
                    if res.status == "OK" { isSent = true }
                    else { error = res.message ?? "Failed to send reset." }
                }
            } catch {
                await MainActor.run { self.error = (error as NSError).localizedDescription }
            }
        }
    }
}

// MARK: - Timeout helper
private func withTimeout<T>(seconds: TimeInterval, _ work: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Logo
struct AppLogoView: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let line: CGFloat = max(2, s * 0.035)
            ZStack {
                Circle().fill(LinearGradient(colors: [.blue.opacity(0.7), .blue],
                                             startPoint: .top, endPoint: .bottom))
                Circle().inset(by: s*0.12).stroke(Color.white.opacity(0.9), lineWidth: line)
                Circle().inset(by: s*0.24).stroke(Color.white.opacity(0.9), lineWidth: line)
                Circle().inset(by: s*0.36).stroke(Color.white.opacity(0.9), lineWidth: line)
                Circle().inset(by: s*0.43).fill(Color.white.opacity(0.9))
                Circle().stroke(Color.red, lineWidth: line*1.4)
                Rectangle().fill(Color.white.opacity(0.9)).frame(width: line, height: s*0.86)
                Rectangle().fill(Color.white.opacity(0.9)).frame(width: s*0.86, height: line)
            }
            .clipShape(Circle())
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

