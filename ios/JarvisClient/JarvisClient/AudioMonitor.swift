// File: JarvisClient/AudioMonitor.swift
// =====================================
import Foundation
import AVFoundation
import CoreGraphics

/// Mic-backed meter; publishes active + level (0..1)
final class MicMonitor: NSObject, ObservableObject {
    @Published var level: CGFloat = 0
    @Published var isListening: Bool = false
    @Published var isActive: Bool = false   // why: keep ring visible while mic session is on

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let threshold: CGFloat = 0.12

    func start() {
        Task { @MainActor in
            let ok = await withCheckedContinuation { c in
                AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
            }
            guard ok else { print("Mic permission denied"); return }
            let s = AVAudioSession.sharedInstance()
            try? s.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try? s.setActive(true)

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
            isActive = true

            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
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

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false)
        level = 0; isListening = false; isActive = false
    }
}
