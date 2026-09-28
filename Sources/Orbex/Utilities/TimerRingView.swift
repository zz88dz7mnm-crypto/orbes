import SwiftUI

/// Anillo de vidrio que se vacía (informe §9.5). `progress` = lo que falta (1 → 0).
struct TimerRingView: View {
    var progress: Double
    var size: CGFloat
    var lineWidth: CGFloat = 5
    @Environment(\.orbexTheme) private var theme

    init(progress: Double, size: CGFloat, lineWidth: CGFloat = 5) {
        self.progress = progress
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        let p = min(1, max(0, progress))
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .stroke(
                    LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 0.6)
                .padding(-lineWidth / 2)
            Circle()
                .trim(from: 0, to: p)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: theme.accent.opacity(0.7), radius: lineWidth * 0.9)
                .animation(theme.reduceMotion ? nil : .linear(duration: 0.5), value: p)
        }
        .frame(width: size, height: size)
        .padding(lineWidth / 2)
    }
}
