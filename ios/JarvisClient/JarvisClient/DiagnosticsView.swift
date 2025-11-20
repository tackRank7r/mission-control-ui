import SwiftUI

struct DiagnosticsView: View {
    @State private var logs: [String] = ["Boot OK", "No issues detected"]

    var body: some View {
        List(logs, id: \.self) { log in
            Text(log)
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            Button("Add Log") { logs.append("Log \(logs.count + 1)") }
        }
    }
}

// NOTE: No PreviewProvider / #Preview blocks in this file.
