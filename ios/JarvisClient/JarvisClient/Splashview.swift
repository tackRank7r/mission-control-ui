//
//  Splashview.swift
//  SideKick360 animated splash
//

import SwiftUI

struct Splashview: View {
    @State private var scale: CGFloat = 0.9
    @State private var rotation: Double = 0
    static let primary = Color(red: 0.11, green: 0.36, blue: 0.95) // blue
    static let accent  = Color(red: 0.99, green: 0.25, blue: 0.20) // red

    var body: some View {
        ZStack {
            Color(red: 0.99, green: 0.25, blue: 0.20)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("SideKick360")
                    .font(.system(size: 28, weight: .bold))
                ZStack {
                    Image("SideKick360Splash")
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .scaleEffect(scale)
                        .clipShape(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                        )

                    Circle()
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 4)
                        .scaleEffect(1.05)
                        .rotationEffect(.degrees(rotation))
                        .blendMode(.plusLighter)
                }
                .padding(.horizontal, 40)
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
            ) {
                scale = 1.05
            }
            withAnimation(
                .linear(duration: 2.0)
                    .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}
