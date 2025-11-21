// File: ios/JarvisClient/JarvisClient/PhoneNumberView.swift
// Action: CREATE file
// Purpose: Fetch the Twilio "from" number from /diagnostics on the backend
//          (using Secrets.diagnosticsEndpoint) and display it.

import SwiftUI

struct PhoneNumberView: View {
    @State private var isLoading = false
    @State private var phoneNumber: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading phone number…")
                        .padding()
                } else if let phone = phoneNumber {
                    VStack(spacing: 20) {
                        Text("Current call-from number")
                            .font(.headline)

                        Text(phone)
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )

                        Text("This number comes from the Twilio phone number configured on your Render backend.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Text("Couldn’t load phone number")
                            .font(.headline)
                        Text(error)
                            .font(.body)
                            .multilineTextAlignment(.center)
                        Button("Try again", action: load)
                    }
                    .padding()
                } else {
                    Text("No phone number available.")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Phone number")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: loadIfNeeded)
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        if phoneNumber == nil && !isLoading {
            load()
        }
    }

    private func load() {
        isLoading = true
        errorMessage = nil

        let url = Secrets.diagnosticsEndpoint
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // If your backend expects the bearer from APP_BACKEND_BEARER, send it.
        if !Secrets.backendBearer.isEmpty {
            request.setValue("Bearer \(Secrets.backendBearer)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self.errorMessage = "Empty response from /diagnostics."
                    return
                }

                self.phoneNumber = Self.extractPhoneNumber(from: data)
                if self.phoneNumber == nil {
                    self.errorMessage = "No phone number found in /diagnostics."
                }
            }
        }.resume()
    }

    // MARK: - Extremely forgiving JSON parse

    /// We don't assume a specific JSON field name — we just look for the
    /// first string in the /diagnostics JSON that *looks* like a phone number.
    private static func extractPhoneNumber(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []),
            let match = findPhone(in: json)
        else {
            return nil
        }
        return match
    }

    private static func findPhone(in any: Any) -> String? {
        if let dict = any as? [String: Any] {
            for value in dict.values {
                if let phone = findPhone(in: value) {
                    return phone
                }
            }
        } else if let array = any as? [Any] {
            for item in array {
                if let phone = findPhone(in: item) {
                    return phone
                }
            }
        } else if let s = any as? String {
            // Very simple heuristic: at least 7 digits.
            let digits = s.filter { $0.isNumber }
            if digits.count >= 7 {
                return s
            }
        }
        return nil
    }
}
