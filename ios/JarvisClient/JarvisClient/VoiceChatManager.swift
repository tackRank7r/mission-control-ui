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
import Combine
import AudioToolbox

@MainActor
final class VoiceChatManager: ObservableObject {
    enum State { case idle, listening, thinking, speaking }

    @Published private(set) var state: State = .idle
    @Published var partialTranscript: String = ""
    @Published var lastError: String?
    /// UI level 0...1 computed from mic buffers (animate vortex)
    @Published var audioLevel: CGFloat = 0.0

    /// Publisher for voice messages (text, isUser)
    let messagePublisher = PassthroughSubject<(String, Bool), Never>()

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

    // Thinking sound timer for continuous feedback during wait
    private var thinkingSoundTimer: Timer?

    // Conversation history for multi-turn context (persists across voice turns)
    private var conversationHistory: [Message] = []

    // Source count publisher (fires after audio starts, not before)
    let sourceCountPublisher = PassthroughSubject<(String, Int), Never>()

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
        case .idle:
            Task { await requestAndStart() }
        case .speaking:
            // Interrupt playback and resume listening immediately
            Task { await interruptAndListen() }
        case .listening, .thinking:
            stopAll()
        }
    }

    /// Alias for toggle() - used for voice conversation mode
    func toggleVoiceConversation() {
        toggle()
    }

    func stopAll() {
        stopRecognition()
        stopMonitoring()
        stopThinkingSoundLoop()
        stopPlayback()
        localTTS.stop()
        state = .idle
        partialTranscript = ""
        audioLevel = 0
        // Keep conversationHistory so context is maintained across sessions.
        // It resets naturally when a new conversation starts via the button tap.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Listening

    func startListening() async {
        state = .listening  // Always set to listening when we start

        // Retry once if the audio engine fails to start (common after playback)
        for attempt in 0..<2 {
            do {
                try configureSession()
                try startRecognition()
                startMonitoring()
                return // success
            } catch {
                #if DEBUG
                print("VoiceChatManager: startListening attempt \(attempt) failed: \(error)")
                #endif
                stopRecognition() // clean up partial state
                if attempt == 0 {
                    // Brief pause before retry
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if state != .listening { return }
                } else {
                    lastError = (error as NSError).localizedDescription
                    stopAll()
                }
            }
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

        // Build request — prefer on-device but allow server fallback on cellular
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Don't set requiresOnDeviceRecognition = true; it blocks recognition
        // entirely when the on-device model isn't available. Let iOS decide
        // the best path (on-device when available, server when not).
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
        messagePublisher.send((text, true))

        do {
            startThinkingSoundLoop()

            // Enrich message with contact phone number if a name is mentioned
            var enrichedText = text
            if let match = await ContactsManager.shared.findContactInText(text) {
                enrichedText = "\(text)\n[Device found contact: \(match.name) — \(match.phone)]"
            }

            // Append user message to persistent conversation history
            conversationHistory.append(Message(role: .user, content: enrichedText))
            let res = try await api.ask(messages: conversationHistory)
            conversationHistory.append(Message(role: .assistant, content: res.reply))

            messagePublisher.send((res.reply, false))

            stopThinkingSoundLoop()
            state = .speaking

            let cleanText = res.reply.strippingForTTS

            // Publish source count AFTER audio starts (don't block TTS)
            let sourceCount = ChatViewModel.countSources(in: res.reply)

            // Stop the audio engine during playback so the mic doesn't
            // pick up the speaker output and create a feedback loop.
            stopRecognition()

            // Try fast path: complete audio in <4 seconds
            let result = await speakWithTimeout(cleanText, timeout: 4.0)

            switch result {
            case .complete(let data):
                try await MainActor.run { try playback.play(data: data) }
                if sourceCount > 0 {
                    sourceCountPublisher.send((res.reply, sourceCount))
                }
                await waitForPlaybackEnd()
                guard state == .speaking else { return }
                await postPlaybackCooldownAndListen()

            case .timedOut:
                if sourceCount > 0 {
                    sourceCountPublisher.send((res.reply, sourceCount))
                }
                await speakChunked(cleanText)
                guard state == .speaking else { return }
                await postPlaybackCooldownAndListen()

            case .failed:
                state = .speaking
                await localTTS.speak(cleanText, language: Locale.current.identifier)
                guard state == .speaking else { return }
                await postPlaybackCooldownAndListen()
            }
        } catch {
            lastError = (error as NSError).localizedDescription
            stopThinkingSoundLoop()
            await startListening()
        }
    }

    // MARK: - Chunked TTS

    private enum SpeakResult {
        case complete(Data)
        case timedOut
        case failed
    }

    /// Races api.speak() against a timeout. Returns whichever finishes first.
    private func speakWithTimeout(_ text: String, timeout: TimeInterval) async -> SpeakResult {
        await withTaskGroup(of: SpeakResult.self) { group in
            group.addTask { [api] in
                do {
                    let data = try await api.speak(text)
                    return .complete(data)
                } catch {
                    return .failed
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timedOut
            }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
    }

    /// Splits text at sentence boundaries and plays each chunk sequentially,
    /// fetching the next chunk while the current one plays.
    private func speakChunked(_ text: String) async {
        let chunks = splitIntoThirds(text)
        guard chunks.count > 1 else {
            // Too short to split meaningfully — wait for full audio
            do {
                let data = try await api.speak(text)
                try await MainActor.run { try playback.play(data: data) }
                await waitForPlaybackEnd()
            } catch {
                await localTTS.speak(text, language: Locale.current.identifier)
            }
            return
        }

        for (index, chunk) in chunks.enumerated() {
            guard state == .speaking else { break }

            do {
                let data = try await api.speak(chunk)
                try await MainActor.run { try playback.play(data: data) }
                await waitForPlaybackEnd()
            } catch {
                // Speak remaining chunks with local TTS
                let remaining = chunks[index...].joined(separator: " ")
                await localTTS.speak(remaining, language: Locale.current.identifier)
                break
            }
        }
    }

    /// Split text into ~3 roughly equal parts at sentence boundaries.
    private func splitIntoThirds(_ text: String) -> [String] {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentences.count >= 3 else { return [text] }

        let third = sentences.count / 3
        let chunk1 = sentences[0..<third].joined(separator: ". ") + "."
        let chunk2 = sentences[third..<(2 * third)].joined(separator: ". ") + "."
        let chunk3 = sentences[(2 * third)...].joined(separator: ". ") + "."
        return [chunk1, chunk2, chunk3]
    }

    /// Waits until AudioPlayback finishes or state changes.
    private func waitForPlaybackEnd() async {
        while playback.isPlaying && state == .speaking {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms poll
        }
    }

    private func stopPlayback() {
        playback.stop()
    }

    // MARK: - Interrupt (barge-in via tap)

    /// Stops AI audio playback immediately and resumes listening for user speech.
    private func interruptAndListen() async {
        playback.stop()
        localTTS.stop()
        stopRecognition()

        // Brief pause to let audio output fully stop
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Reset audio session for recording
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try? await Task.sleep(nanoseconds: 100_000_000)
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("VoiceChatManager: interrupt audio session reset error: \(error)")
            #endif
        }

        await startListening()
    }

    // MARK: - Post-playback cooldown

    /// Waits a short time after audio playback ends before restarting
    /// speech recognition. This prevents the mic from picking up residual
    /// speaker output and interpreting it as user speech (echo loop).
    private func postPlaybackCooldownAndListen() async {
        // 600ms cooldown lets speaker audio fully dissipate
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard state == .speaking else { return }

        // Fully reset the audio session before restarting recognition.
        // After playback, the audio engine and session can be in a stale state
        // that causes startRecognition() to fail silently.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms settle
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // If audio session reset fails, try startListening anyway
            #if DEBUG
            print("VoiceChatManager: audio session reset error: \(error)")
            #endif
        }

        guard state == .speaking else { return }
        await startListening()
    }

    // MARK: Thinking sounds

    /// Starts a repeating soft sound to indicate the device is processing
    private func startThinkingSoundLoop() {
        stopThinkingSoundLoop() // Clean up any existing timer

        // Play first sound immediately
        AudioServicesPlayAlertSound(1103) // Soft "tink" sound

        // Repeat at ~100 BPM (0.6s interval) for a gentle rhythm
        thinkingSoundTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
            AudioServicesPlayAlertSound(1103)
        }
        RunLoop.main.add(thinkingSoundTimer!, forMode: .common)
    }

    /// Stops the thinking sound loop
    private func stopThinkingSoundLoop() {
        thinkingSoundTimer?.invalidate()
        thinkingSoundTimer = nil
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
