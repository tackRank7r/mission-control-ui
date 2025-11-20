// FILE: ios/JarvisClient/JarvisClient/GuidedTourView.swift
// Simple step-by-step guided tour of the five major Jarvis features.

import SwiftUI

struct GuidedTourView: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = AppContextCatalog.guidedTourItems
    @State private var currentIndex: Int = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 16)

                Text("Guided Tour")
                    .font(.largeTitle.bold())

                if currentIndex < steps.count {
                    let step = steps[currentIndex]

                    VStack(alignment: .leading, spacing: 12) {
                        Text(step.title)
                            .font(.title2.bold())

                        Text(step.description)
                            .font(.body)

                        HStack(alignment: .top, spacing: 8) {
                            Text("Where:")
                                .font(.subheadline.bold())
                            Text(step.location)
                                .font(.subheadline)
                        }

                        Text("Tip:")
                            .font(.subheadline.bold())
                        Text("Ask Jarvis things like “Show me how to use \(step.title.lowercased())”.")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                HStack {
                    Button {
                        if currentIndex > 0 {
                            currentIndex -= 1
                        }
                    } label: {
                        Text("Back")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if currentIndex < steps.count - 1 {
                            currentIndex += 1
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text(currentIndex < steps.count - 1 ? "Next" : "Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)

                Spacer(minLength: 12)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
