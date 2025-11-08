// Path: JarvisClient/ListeningIndicator.swift
import SwiftUI

struct ListeningIndicator: View {
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .stroke(AngularGradient(gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red]), center: .center))
            .frame(width: 50, height: 50)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}



