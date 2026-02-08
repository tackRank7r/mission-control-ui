// File: JarvisClient/AudioPlayback.swift
// Purpose: Audio playback engine with delegate support for chunked TTS and barge-in.

import Foundation
import AVFoundation

@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayback()

    @Published private(set) var isPlaying: Bool = false

    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?

    /// Plays audio data. Optionally calls onFinish when playback completes.
    func play(data: Data, onFinish: (() -> Void)? = nil) throws {
        self.onFinish = nil
        player?.stop()

        player = try AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        player?.play()
        isPlaying = true
        self.onFinish = onFinish
    }

    /// Stops any current playback immediately.
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        onFinish = nil
    }

    /// Current playback position in seconds.
    var currentTime: TimeInterval {
        player?.currentTime ?? 0
    }

    /// Total duration of current audio.
    var duration: TimeInterval {
        player?.duration ?? 0
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            let callback = self.onFinish
            self.onFinish = nil
            callback?()
        }
    }
}
