import SwiftUI

struct HistoryServerView: View {
    @State private var items: [String] = ["Session A", "Session B"]

    var body: some View {
        List(items, id: \.self) { item in
            Text(item)
        }
        .navigationTitle("History Server")
        .toolbar {
            Button("Refresh") {
                // TODO: hook to backend
            }
        }
    }
}

// NOTE: No PreviewProvider / #Preview blocks in this file.
