// =====================================
// Path: JarvisClient/AudioPlayerView.swift
// =====================================
import SwiftUI
import AVFoundation

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isPlaying = false
    @Published var error: String?
    @Published var progress: Double = 0 // 0...1
    @Published var contentType: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func speak(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        error = nil
        isLoading = true
        defer { isLoading = false }

        do {
            var req = URLRequest(url: Secrets.speakEndpoint)
            req.httpMethod = "POST"
            Secrets.headers(json: true).forEach { req.addValue($1, forHTTPHeaderField: $0) }
            req.httpBody = try JSONSerialization.data(withJSONObject: ["text": trimmed], options: [])

            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "Audio.speak", code: code,
                              userInfo: [NSLocalizedDescriptionKey: "Bad status \(code). \(body)"])
            }

            contentType = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")

            // AVAudioPlayer handles MP3 & WAV; for OGG you'd need a 3rd-party decoder.
            player = try AVAudioPlayer(data: data)
            player?.prepareToPlay()
            play()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        progress = 0
        stopTimer()
        player = nil
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, p.duration > 0 else { return }
            self.progress = p.currentTime / p.duration
            if !p.isPlaying { self.isPlaying = false; self.stopTimer() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct AudioPlayerView: View {
    @StateObject private var vm = AudioPlayerViewModel()
    @State private var text: String = "Hello from the app!"

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("TTS (/speak)").font(.headline)
                Spacer()
                if let ct = vm.contentType {
                    Text(ct).font(.footnote).foregroundColor(.secondary)
                }
            }

            TextField("What should I say?", text: $text)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isLoading)

            HStack(spacing: 12) {
                Button {
                    Task { await vm.speak(text: text) }
                } label: {
                    Label("Speak", systemImage: "waveform")
                }
                .disabled(vm.isLoading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(vm.isPlaying ? "Pause" : "Play") {
                    vm.isPlaying ? vm.pause() : vm.play()
                }
                .disabled(vm.isLoading)

                Button("Stop") { vm.stop() }
                .disabled(vm.isLoading)
            }

            ProgressView(value: vm.progress)
                .progressViewStyle(.linear)

            if vm.isLoading { ProgressView("Loading audio…") }

            if let err = vm.error {
                Text(err).foregroundColor(.red).multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }
}

struct AudioPlayerView_Previews: PreviewProvider {
    static var previews: some View {
        AudioPlayerView()
    }
}
