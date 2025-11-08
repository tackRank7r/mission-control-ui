// =====================================
// File: JarvisClient/AudioPlayback.swift
// (unchanged if you already added it; included for completeness)
// =====================================
import Foundation
import AVFoundation

@MainActor
final class AudioPlayback: ObservableObject {
    static let shared = AudioPlayback()
    private var player: AVAudioPlayer?

    func play(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        player?.prepareToPlay()
        player?.play()
    }
}
