//
//  Splashview.swift
//  SideKick360 animated splash with AirDrop-style loading ring
//

import SwiftUI

struct Splashview: View {
    // The logo rotates exactly 360 degrees in 3 seconds
    @State private var rotation: Double = 0
    // The blue arc fills from 0 to 1.0 (full circle) in the same 3 seconds
    @State private var progress: CGFloat = 0
    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: Double = 0

    static let brandBlue = Color(red: 0.11, green: 0.36, blue: 0.95)

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                ZStack {
                    // Background track circle (light gray)
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 5)
                        .frame(width: 180, height: 180)

                    // Blue progress arc that fills as the logo spins.
                    // Starts at 12 o'clock (-90 degrees) and the leading tip
                    // stays aligned with the logo's rotation.
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Splashview.brandBlue,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 180, height: 180)
                        .rotationEffect(.degrees(-90)) // start at 12 o'clock

                    // App icon / logo that spins
                    Image("SideKick360Splash")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .rotationEffect(.degrees(rotation))
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }

                VStack(spacing: 8) {
                    Text("SideKick360")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Your project & calls copilot")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .opacity(logoOpacity)
            }
        }
        .onAppear {
            // Fade in logo quickly
            withAnimation(.easeOut(duration: 0.3)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }

            // Logo spins exactly 360 degrees in 3 seconds
            withAnimation(.linear(duration: 3.0)) {
                rotation = 360
            }

            // Loading bar fills to a full circle in the same 3 seconds,
            // so the leading edge of the arc follows the logo's crosshair
            withAnimation(.linear(duration: 3.0)) {
                progress = 1.0
            }
        }
    }
}
