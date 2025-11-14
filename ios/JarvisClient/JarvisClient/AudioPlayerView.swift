import SwiftUI
import AVFoundation

struct AudioPlayerView: View {
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Audio Player").font(.title2).bold()
            Button(isPlaying ? "Pause" : "Play") {
                isPlaying.toggle()
                // TODO: wire to your real audio engine
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Audio Player")
    }
}

// NOTE: No PreviewProvider / #Preview blocks in this file.
