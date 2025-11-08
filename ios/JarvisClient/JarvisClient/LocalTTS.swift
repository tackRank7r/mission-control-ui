// =====================================
// File: JarvisClient/LocalTTS.swift
// (simple on-device TTS fallback using AVSpeechSynthesizer)
// =====================================
import Foundation
import AVFoundation

@MainActor
final class LocalTTS: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = LocalTTS()

    private let synth = AVSpeechSynthesizer()
    private var didFinishContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Speaks the text out loud using AVSpeechSynthesizer.
    /// Returns when speech finishes or is cancelled.
    func speak(_ text: String,
               language: String = Locale.current.identifier,
               rate: Float = AVSpeechUtteranceDefaultSpeechRate) async {
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: language) ?? .init(language: "en-US")
        utt.rate  = rate
        utt.pitchMultiplier = 1.0

        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        synth.speak(utt)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.didFinishContinuation = cont
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        didFinishContinuation?.resume()
        didFinishContinuation = nil
    }

    // MARK: AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        didFinishContinuation?.resume()
        didFinishContinuation = nil
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        didFinishContinuation?.resume()
        didFinishContinuation = nil
    }
}
