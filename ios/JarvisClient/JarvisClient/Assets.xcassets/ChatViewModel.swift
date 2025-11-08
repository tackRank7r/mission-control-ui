////File: JarvisClient/ChatViewModel.swift
// ==========================
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = [Message(role: .system, content: "How can I help you today?")]
    @Published var isSending = false
    @Published var errorBanner: String? = nil

    private let api: APIClient

    init(api: APIClient) { self.api = api }

    func send(text: String) async {
        guard !isSending else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSending = true
        messages.append(Message(role: .user, content: trimmed))
        do {
            let reply = try await api.sendChat(userText: trimmed, history: messages)
            messages.append(Message(role: .assistant, content: reply))
        } catch {
            errorBanner = (error as NSError).localizedDescription
            messages.append(Message(role: .assistant, content: "Sorry—\(errorBanner ?? "something went wrong")."))
        }
        isSending = false
    }

    func dismissError() { errorBanner = nil }
}

// ==========================
// File: JarvisClient/AudioMonitor.swift
// ==========================
import Foundation
import AVFoundation

final class MicMonitor: NSObject, ObservableObject {
    @Published var level: CGFloat = 0.0                   // 0…1
    @Published var isListening: Bool = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let threshold: CGFloat = 0.12                 // tweak sensitivity

    func start() {
        Task { @MainActor in
            let ok = await requestPermission()
            guard ok else { print("Mic permission denied"); return }
            configureSession()
            startMetering()
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        self.level = 0; self.isListening = false
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func startMetering() {
        // write to /dev/null (why: metering without keeping files)
        let url = URL(fileURLWithPath: "/dev/null")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.prepareToRecord()
        recorder?.record()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            // Convert dB (-160..0) to 0..1
            let minDb: Float = -50
            let clamped = max(r.averagePower(forChannel: 0), minDb)
            let norm = (clamped - minDb) / -minDb
            DispatchQueue.main.async {
                self.level = CGFloat(max(0, min(1, norm)))
                self.isListening = self.level > self.threshold
            }
        }
    }
}
