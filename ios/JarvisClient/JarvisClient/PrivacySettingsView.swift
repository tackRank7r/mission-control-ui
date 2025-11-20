import SwiftUI

struct PrivacySettingsView: View {
    var body: some View {
        Form {
            Toggle("Share Analytics", isOn: .constant(false))
            Toggle("Crash Reports", isOn: .constant(true))
        }
        .navigationTitle("Privacy")
    }
}
