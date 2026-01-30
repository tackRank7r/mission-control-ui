// =====================================================
// File: JarvisClient/VoiceChatManager.swift
// (tap-to-toggle, fast turn-taking voice conversation)
// + audioLevel for UI animation (safe, lightweight)
// + requestAndStart() => instant UI feedback on tap
// + /speak fallback to on-device AVSpeechSynthesizer if server TTS fails
// =====================================================
import Foundation
import AVFoundation
import Speech
import Accelerate
import CoreGraphics

@MainActor
final class VoiceChatManager: ObservableObject {
    enum State { case idle, listening, thinking, speaking }

    @Published private(set) var state: State = .idle
    @Published var partialTranscript: String = ""
    @Published var lastError: String?
    /// UI level 0...1 computed from mic buffers (animate vortex)
    @Published var audioLevel: CGFloat = 0.0

    /// Callback to add messages to chat when in conversation mode
    var onMessageReceived: ((String, Bool) -> Void)? // (text, isUser)

    private let api = APIClient()
    private let playback = AudioPlayback.shared
    private let localTTS = LocalTTS.shared

    // Speech
    private let recognizer = SFSpeechRecognizer(locale: Locale.current) // may be nil; fallback below
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // Turn-end detection
    private var lastSpeechAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let silenceMs: Double = 2000  // 2 seconds - allows natural pauses mid-sentence
    private var monitorTimer: Timer?

    // MARK: Public control

    /// Shows vortex immediately, then requests permissions and starts recognition.
    func requestAndStart() async {
        if state == .idle { state = .listening } // instant UI
        let granted = await Self.requestAuthorizations()
        guard granted else {
            lastError = "Microphone and Speech permissions are required."
            stopAll()
            return
        }
        await startListening()
    }

    func toggle() {
        switch state {
        case .idle: Task { await requestAndStart() }
        case .listening, .thinking, .speaking: stopAll()
        }
    }

    /// Alias for toggle() - used for voice conversation mode
    func toggleVoiceConversation() {
        toggle()
    }

    func stopAll() {
        stopRecognition()
        stopMonitoring()
        stopPlayback()
        localTTS.stop()
        state = .idle
        partialTranscript = ""
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Listening

    func startListening() async {
        state = .listening  // Always set to listening when we start
        do {
            try configureSession()
            try startRecognition()
            startMonitoring()
        } catch {
            lastError = (error as NSError).localizedDescription
            stopAll()
        }
    }

    // MARK: Setup
    private func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try s.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognition() throws {
        partialTranscript = ""
        audioLevel = 0

        // Build request
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 13.0, *) {
            if (recognizer?.supportsOnDeviceRecognition ?? SFSpeechRecognizer()?.supportsOnDeviceRecognition ?? false) {
                req.requiresOnDeviceRecognition = true
            }
        }
        request = req

        // Audio tap
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            self.updateLevel(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        lastSpeechAt = CFAbsoluteTimeGetCurrent()

        // Recognizer (fallback to default if locale is unsupported)
        let rec = recognizer ?? SFSpeechRecognizer()
        guard let request = request, let recognizerForTask = rec else {
            throw NSError(domain: "VoiceChatManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable for this locale."])
        }

        task = recognizerForTask.recognitionTask(with: request) { [weak self] result, err in
            guard let self else { return }
            if let r = result {
                self.partialTranscript = r.bestTranscription.formattedString
                if !self.partialTranscript.isEmpty {
                    self.lastSpeechAt = CFAbsoluteTimeGetCurrent()
                }
                if r.isFinal {
                    self.finishTurn(finalText: self.partialTranscript)
                }
            }
            if let err {
                // Ignore cancellation errors - these are expected when we stop listening
                let nsError = err as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // Error 216 = request was canceled, this is normal
                    return
                }
                self.lastError = err.localizedDescription
                self.finishTurn(finalText: self.partialTranscript)
            }
        }
    }

    /// Fast RMS-based mic level for UI (no effect on recognition).
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?.pointee else { return }
        let frameCount = Int(buffer.frameLength)
        if frameCount == 0 { return }

        var meanSquare: Float = 0
        vDSP_measqv(channel, 1, &meanSquare, vDSP_Length(frameCount))
        var rms = sqrtf(meanSquare)

        // Normalize for human speech; clamp to 0...1
        rms = (rms - 0.01) * 9.0
        let normalized = CGFloat(max(0, min(1, rms)))

        // Smooth peak hold & gentle decay
        let current = self.audioLevel
        let target = max(normalized, current * 0.86)

        Task { @MainActor in self.audioLevel = target }
    }

    private func stopRecognition() {
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: Silence monitor
    private func startMonitoring() {
        stopMonitoring()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, self.state == .listening else { return }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - self.lastSpeechAt) * 1000.0
            if elapsedMs >= self.silenceMs &&
                !self.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.finishTurn(finalText: self.partialTranscript)
            }
            if self.partialTranscript.isEmpty {
                self.audioLevel *= 0.92
            }
        }
        RunLoop.main.add(monitorTimer!, forMode: .common)
    }

    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    // MARK: Turn end → ask → speak
    private func finishTurn(finalText: String) {
        guard state == .listening else { return }
        stopRecognition()
        stopMonitoring()

        let utterance = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        partialTranscript = utterance

        // Nothing captured → resume quickly
        if utterance.isEmpty {
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                await self.startListening()
            }
            return
        }

        state = .thinking
        Task { await self.askAndSpeak(utterance) }
    }

    private func askAndSpeak(_ text: String) async {
        // Add user message to chat
        onMessageReceived?(text, true)

        do {
            var history: [Message] = [Message(role: .user, content: text)]
            let res = try await api.ask(messages: history)
            history.append(Message(role: .assistant, content: res.reply))

            // Add assistant response to chat
            onMessageReceived?(res.reply, false)

            // Try backend TTS first
            do {
                state = .speaking
                let audio = try await api.speak(res.reply)
                try await MainActor.run { try playback.play(data: audio) }

                // Resume listening shortly after playback begins (keep loop snappy)
                try? await Task.sleep(nanoseconds: 300_000_000)
                await startListening()
            } catch {
                // Fallback to on-device TTS
                state = .speaking
                await localTTS.speak(res.reply, language: Locale.current.identifier)
                await startListening()
            }
        } catch {
            lastError = (error as NSError).localizedDescription
            await startListening()
        }
    }

    private func stopPlayback() {
        // AudioPlayback is short-lived; new clips interrupt automatically.
    }

    // MARK: Permissions helper

    static func requestAuthorizations() async -> Bool {
        let micGranted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
        let speechGranted: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        return micGranted && speechGranted
    }

    /// Old callback-style for backward compatibility.
    static func ensureAuthorizations(completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { micGranted in
            SFSpeechRecognizer.requestAuthorization { status in
                let speechGranted = (status == .authorized)
                DispatchQueue.main.async { completion(micGranted && speechGranted) }
            }
        }
    }
}
